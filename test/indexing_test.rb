# frozen_string_literal: true

require_relative 'app_test'
require_relative '../db/migrate/20261019000000_widen_media_size'

class IndexingTest < Minitest::Test
  include MediaTestSupport

  def setup
    super
    @root = "#{@directory}/media[1]"
    Dir.mkdir(@root)
    @settings.originals_path = @root
    @settings.thumb_target = "#{@directory}/thumbs"
    @settings.image_extentions = ['ppm']
    @settings.movie_extentions = ['mp4']
    @settings.thumb_res = '16x16^'
    @indexer = BronkoMedia::Indexer.new(settings: @settings, logger: Logger.new(File::NULL))
  end

  def picture(name, color = '255 0 0', width = 1)
    path = "#{@root}/#{name}.ppm"
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "P3\n#{width} 1\n255\n#{([color] * width).join(' ')}\n")
    path
  end

  def scan
    @indexer.build_index(@root, @settings.thumb_target, %w[ppm mp4])
  end

  def thumbnail(image)
    "#{@settings.thumb_target}/#{image.md5_path}.png"
  end

  def test_rescan_updates_changed_original_and_keeps_user_metadata
    path = picture('photo')
    scan
    image = Image.find_by!(file_path: path)
    image.update!(favorite: true, tags: ['keep'])
    original_id = image.id
    signature = image.signature
    previous_thumb = File.binread(thumbnail(image))
    picture('photo', '0 255 0', 2)
    scan
    image.reload
    assert_equal original_id, image.id
    assert_equal ['keep'], image.tags
    assert image.favorite
    assert_equal File.size(path), image.size
    assert_equal '[2, 1]', image.dimensions
    refute_equal signature, image.signature
    refute_equal previous_thumb, File.binread(thumbnail(image))
    assert_equal 1, Image.count
  end

  def test_content_changes_with_same_size_and_mtime_are_detected
    path = picture('photo')
    scan
    image = Image.find_by!(file_path: path)
    signature = image.signature
    mtime = File.mtime(path)
    size = File.size(path)
    picture('photo', '0 255 0')
    File.utime(mtime, mtime, path)
    assert_equal size, File.size(path)
    scan
    refute_equal signature, image.reload.signature
  end

  def test_unchanged_scan_keeps_thumbnail_and_record_timestamps
    path = picture('photo')
    scan
    image = Image.find_by!(file_path: path)
    timestamp = image.updated_at
    thumb = thumbnail(image)
    sentinel = Time.at(1_600_000_000)
    File.utime(sentinel, sentinel, thumb)
    scan
    assert_equal sentinel, File.mtime(thumb)
    assert_equal timestamp, image.reload.updated_at
  end

  def test_missing_thumbnail_is_rebuilt_without_replacing_record
    path = picture('photo')
    scan
    image = Image.find_by!(file_path: path)
    image.update!(tags: ['keep'])
    File.unlink(thumbnail(image))
    scan
    assert File.file?(thumbnail(image))
    assert_equal ['keep'], image.reload.tags
    assert_equal 1, Image.count
  end

  def test_orphan_thumbnail_does_not_prevent_indexing
    path = picture('photo')
    FileUtils.mkdir_p(@settings.thumb_target)
    File.write("#{@settings.thumb_target}/#{Digest::MD5.hexdigest(path)}.png", 'stale')
    @service.index_files_to_db(@root, ['ppm'])
    image = Image.find_by!(file_path: path)
    assert_equal '[1, 1]', image.dimensions
    refute_equal 'stale', File.binread(thumbnail(image))
  end

  def test_corrupt_file_does_not_abort_scan_and_is_retried_after_repair
    path = picture('photo')
    picture('copy')
    scan
    image = Image.find_by!(file_path: path)
    image.update!(tags: ['keep'])
    assert image.duplicate
    File.write(path, 'broken image')
    scan
    assert_nil image.reload.signature
    refute image.duplicate
    refute Image.find_by!(image_name: 'copy').duplicate
    refute File.exist?(thumbnail(image))
    picture('photo')
    scan
    assert image.reload.duplicate
    assert_equal ['keep'], image.tags
    assert File.file?(thumbnail(image))
  end

  def test_failed_thumbnail_is_retried_after_configuration_is_repaired
    path = picture('photo')
    scan
    image = Image.find_by!(file_path: path)
    picture('photo', '0 255 0')
    @settings.thumb_res = 'invalid-geometry'
    scan
    refute File.exist?(thumbnail(image))
    @settings.thumb_res = '16x16^'
    scan
    assert File.file?(thumbnail(image))
    assert_empty Dir.glob("#{@settings.thumb_target}/.thumb-*")
  end

  def test_duplicate_flags_are_recomputed_after_change_and_removal
    first = picture('first')
    second = picture('second')
    scan
    assert_equal 2, Image.where(duplicate: true).count
    picture('second', '0 255 0')
    scan
    assert_empty Image.where(duplicate: true)
    picture('second')
    scan
    assert_equal 2, Image.where(duplicate: true).count
    File.unlink(second)
    scan
    assert_equal [first], Image.pluck(:file_path)
    refute Image.first.duplicate
  end

  def test_empty_signatures_are_never_duplicates_and_stale_references_are_cleared
    [nil, nil, '', '', ' ', ' ', "\t", "\t"].each_with_index do |signature, index|
      Image.create!(md5_path: index.to_s, signature: signature, duplicate: true, duplicate_of: 'old')
    end
    BronkoMedia::DuplicateScanner.new(settings: @settings, logger: Logger.new(File::NULL)).find_duplicates
    assert_empty Image.where(duplicate: true)
    assert_empty Image.where.not(duplicate_of: nil)
  end

  def test_folder_scan_removes_deleted_descendants_and_refreshes_duplicates
    picture('folder/nested/first')
    picture('outside')
    scan
    removed = Image.find_by!(image_name: 'first')
    FileUtils.remove_entry("#{@root}/folder/nested")
    folder = Folder.find_by!(folder_path: "#{@root}/folder/")
    BronkoMedia::FolderService.new(settings: @settings, logger: Logger.new(File::NULL)).scan_folder(folder.md5_path)
    refute Image.exists?(removed.id)
    refute File.exist?(thumbnail(removed))
    refute Folder.exists?(folder_path: "#{@root}/folder/nested/")
    assert_empty folder.reload.sub_folders
    assert_equal ['outside'], Image.pluck(:image_name)
    refute Image.first.duplicate
  end

  def test_missing_scan_root_does_not_clean_existing_index
    picture('photo')
    scan
    image = Image.first
    File.rename(@root, "#{@root}-offline")
    assert_raises(Errno::ENOENT) { scan }
    assert Image.exists?(image.id)
    assert File.file?(thumbnail(image))
  end

  def test_video_metadata_fingerprints_and_thumbnails_are_indexed
    path = "#{@root}/video.mp4"
    assert system('ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'color=c=red:s=16x16:d=0.5',
                  '-c:v', 'mpeg4', '-y', path)
    FileUtils.cp(path, "#{@root}/copy.mp4")
    scan
    image = Image.find_by!(file_path: path)
    assert_equal File.size(path), image.size
    assert_equal '[16, 16]', image.dimensions
    assert_equal "sha256:#{Digest::SHA256.file(path).hexdigest}", image.signature
    assert image.is_video
    assert image.duplicate
    assert File.file?(thumbnail(image))
  end

  def test_symlinks_and_thumbnail_directory_are_not_indexed
    picture('photo')
    File.symlink("#{@root}/photo.ppm", "#{@root}/link.ppm")
    @settings.thumb_target = "#{@root}/thumbs"
    FileUtils.mkdir_p(@settings.thumb_target)
    File.write("#{@settings.thumb_target}/ignored.ppm", 'not media')
    scan
    assert_equal ['photo'], Image.pluck(:image_name)
    refute Folder.exists?(folder_path: "#{@settings.thumb_target}/")
    assert_empty Folder.find_by!(folder_path: "#{@root}/").sub_folders
  end

  def test_large_file_sizes_survive_migration_and_block_lossy_rollback
    migration = WidenMediaSize.new
    migration.migrate(:up)
    image = Image.create!(size: 5_000_000_000)
    assert_equal 5_000_000_000, image.reload.size
    assert_raises(ActiveRecord::IrreversibleMigration) { migration.migrate(:down) }
    image.destroy!
    migration.migrate(:down)
    migration.migrate(:up)
  end

  def test_invalid_video_does_not_abort_other_files
    File.write("#{@root}/broken.mp4", 'invalid video')
    picture('photo')
    scan
    assert_equal ['photo'], Image.pluck(:image_name)
  end

  def test_file_changed_during_scan_is_invalidated_then_retried
    path = picture('photo')
    scan
    image = Image.first
    image.update!(favorite: true, tags: ['keep'])
    changing_service = Class.new(BronkoMedia::ImageService) do
      private

      def media_metadata(file, stat)
        result = super
        File.write(file, "P3\n2 1\n255\n0 255 0 0 255 0\n")
        result
      end
    end.new(settings: @settings, logger: Logger.new(File::NULL))
    changing_service.index_files_to_db(@root, ['ppm'])
    assert_nil image.reload.signature
    refute File.exist?(thumbnail(image))
    assert_equal ['keep'], image.tags
    scan
    assert_equal '[2, 1]', image.reload.dimensions
    assert_equal File.size(path), image.size
    assert image.favorite
  end

  def test_duplicate_recalculation_rolls_back_on_database_failure
    first = Image.create!(signature: 'same', duplicate: true)
    second = Image.create!(signature: 'same', duplicate: false)
    Image.connection.execute(<<~SQL)
      CREATE TRIGGER reject_duplicate BEFORE UPDATE ON images WHEN NEW.duplicate = 1
      BEGIN SELECT RAISE(ABORT, 'rejected'); END;
    SQL
    scanner = BronkoMedia::DuplicateScanner.new(settings: @settings, logger: Logger.new(File::NULL))
    assert_raises(ActiveRecord::StatementInvalid) { scanner.find_duplicates }
    assert first.reload.duplicate
    refute second.reload.duplicate
  ensure
    Image.connection.execute('DROP TRIGGER IF EXISTS reject_duplicate')
  end

  def test_empty_thumbnail_is_regenerated
    picture('photo')
    scan
    image = Image.first
    File.write(thumbnail(image), '')
    scan
    refute File.empty?(thumbnail(image))
  end
end
