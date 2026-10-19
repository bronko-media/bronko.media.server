# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/multipart'

class MediaWorkflowIntegrationTest < MediaIntegrationTest
  def test_real_multipart_upload_and_collision_through_http
    fixture = picture('fixture.png')
    destination = File.join(Settings.originals_path, 'uploads')
    @folders.create_folder(destination)
    upload = Rack::Multipart::UploadedFile.new(fixture, 'image/png')
    response = @request.post('/image/upload', params: { 'files[]' => upload, 'file_target' => destination })
    assert_equal 303, response.status
    image = Image.find_by!(file_path: File.join(destination, 'fixture.png'))
    digest = Digest::SHA256.file(image.file_path).hexdigest
    assert_thumbnail(image)
    assert_equal 409,
                 @request.post('/image/upload', params: { 'files[]' => upload, 'file_target' => destination }).status
    assert_equal digest, Digest::SHA256.file(image.file_path).hexdigest
    assert_equal 1, Image.count
    assert_equal 204, @request.post("/favorite/#{image.md5_path}", params: { favorite: 'true' }).status
    assert_equal 303, @request.post("/image/tag/#{image.md5_path}", params: { tags: '猫,a"b' }).status
    assert_equal [image.id], Image.tagged_with('猫').pluck(:id)
    assert_equal [image.id], Image.tagged_with('a"b').pluck(:id)
    assert_empty Image.tagged_with('a')
    assert image.reload.favorite
  end

  def test_parallel_scan_and_rescan_of_real_image_formats
    %w[png jpg gif].each { |extension| picture("photo.#{extension}") }
    scan
    assert_equal 3, Image.count
    Image.find_each { |image| assert_thumbnail(image) }
    image = Image.find_by!(extension: 'png')
    image.update!(favorite: true, tags: ['keep'])
    previous_signature = image.signature
    timestamps = Image.order(:id).pluck(:updated_at)
    thumbnail_times = Image.order(:id).map { |record| File.mtime(thumb(record)) }
    scan
    assert_equal timestamps, Image.order(:id).pluck(:updated_at)
    assert_equal(thumbnail_times, Image.order(:id).map { |record| File.mtime(thumb(record)) })
    picture('photo.png', 'blue', '12x6')
    scan
    assert_equal '[12, 6]', image.reload.dimensions
    refute_equal previous_signature, image.signature
    assert_equal ['keep'], image.tags
    assert image.favorite
    assert_equal 3, Image.count
    assert_thumbnail(image)
  end

  def test_video_changes_refresh_metadata_duplicates_and_decodable_thumbnail
    path = video('first.mp4')
    FileUtils.cp(path, File.join(Settings.originals_path, 'second.mp4'))
    scan
    assert_equal 2, Image.where(duplicate: true).count
    image = Image.find_by!(file_path: path)
    signature = image.signature
    preview = Digest::SHA256.file(thumb(image)).hexdigest
    assert_equal File.size(path), image.size
    assert_thumbnail(image)
    video('first.mp4', 'blue')
    scan
    refute_equal signature, image.reload.signature
    refute_equal preview, Digest::SHA256.file(thumb(image)).hexdigest
    assert_empty Image.where(duplicate: true)
    assert_thumbnail(image)
  end

  def test_folder_move_rescan_and_recursive_delete_preserve_correct_records
    path = picture('a_%[1]/nested/photo.png')
    sibling = picture('A_%[1]/photo.png', 'blue')
    scan
    image = Image.find_by!(file_path: path)
    image.update!(favorite: true, tags: ['keep'])
    source = Folder.find_by!(folder_path: "#{Settings.originals_path}/a_%[1]/")
    target = "#{Settings.originals_path}/renamed[1]"
    @folders.move_folder(source.md5_path, target)
    scan
    assert_equal "#{target}/nested/photo.png", image.reload.file_path
    assert_equal ['keep'], image.tags
    assert image.favorite
    assert_thumbnail(image)
    @folders.delete_folder(source.reload.md5_path)
    refute Image.exists?(image.id)
    refute File.exist?(thumb(image))
    refute File.exist?(target)
    assert_equal [sibling], Image.pluck(:file_path)
    assert_empty Folder.where('folder_path LIKE ?', "#{target}/%")
  end

  def test_database_failures_restore_original_files_and_folder_records
    path = picture('folder/photo.png')
    scan
    image = Image.find_by!(file_path: path)
    folder = Folder.find_by!(folder_path: "#{Settings.originals_path}/folder/")
    digest = Digest::SHA256.file(path).hexdigest
    reject_database_write('reject_image_move', 'images', 'UPDATE') do
      assert_raises(ActiveRecord::StatementInvalid) { @images.move_image("#{Settings.originals_path}/new.png", image.md5_path) }
      assert_raises(ActiveRecord::StatementInvalid) { @folders.move_folder(folder.md5_path, "#{Settings.originals_path}/new") }
    end
    reject_database_write('reject_folder_delete', 'folders', 'DELETE') do
      assert_raises(ActiveRecord::StatementInvalid) { @folders.delete_folder(folder.md5_path) }
    end
    assert_equal path, image.reload.file_path
    assert_equal digest, Digest::SHA256.file(path).hexdigest
    assert Folder.exists?(folder.id)
    assert_thumbnail(image)
    assert_empty Dir.glob("#{Settings.originals_path}/.bronko-delete-*")
    refute File.exist?("#{Settings.originals_path}/new")
  end

  def test_concurrent_http_moves_do_not_overwrite_the_winning_file
    first_path = picture('first.png')
    second_path = picture('second.png', 'blue')
    scan
    originals = Image.order(:id).to_a
    target = "#{Settings.originals_path}/winner.png"
    start = Queue.new
    threads = originals.map do |image|
      Thread.new do
        start.pop
        ActiveRecord::Base.connection_pool.with_connection do
          Rack::MockRequest.new(BronkoMediaServer).post("/image/move/#{image.md5_path}",
                                                        params: { file_path: target }).status
        end
      end
    end
    threads.size.times { start << true }
    results = Timeout.timeout(20) { threads.map(&:value) }
    assert_equal [303, 409], results.sort
    assert_equal 2, Image.count
    assert_equal 1, Image.where(file_path: target).count
    assert_equal(1, [first_path, second_path].count { |path| File.file?(path) })
    Image.find_each { |image| assert File.file?(image.file_path) }
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    threads&.each(&:join)
  end
end
