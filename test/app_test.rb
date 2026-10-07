# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'tmpdir'
require_relative '../config/boot'

# Never connect to the configured media database when running tests.
Settings.db_adapter = 'sqlite3'
Settings.db_name = ':memory:'
require_relative '../app'

ActiveRecord::Schema.define do
  create_table :images do |table|
    table.string :md5_path
    table.string :file_path
    table.string :folder_path
    table.string :image_name
    table.string :extension
    table.text :dimensions
    table.integer :size
    table.string :duplicate_of
    table.datetime :file_mtime
    table.datetime :file_ctime
    table.string :signature
    table.json :tags
    table.boolean :favorite, default: false
    table.boolean :duplicate, default: false
    table.boolean :is_image, default: false
    table.boolean :is_video, default: false
    table.timestamps
  end
  create_table :folders do |table|
    table.string :md5_path
    table.string :folder_path
    table.string :parent_folder
    table.text :sub_folders
    table.timestamps
  end
  create_table :tags do |table|
    table.string :name
  end
end

class AppTest < Minitest::Test
  TestSettings = Struct.new(:thumb_target, :threads, :movie_extentions, :image_extentions, :thumb_res,
                            keyword_init: true)

  def setup
    [Image, Folder, Tag].each(&:delete_all)
    @directory = Dir.mktmpdir('bronko-test')
    @settings = TestSettings.new(thumb_target: @directory, threads: 0, movie_extentions: [], image_extentions: [])
    @service = BronkoMedia::ImageService.new(settings: @settings, logger: Logger.new(File::NULL))
    @request = Rack::MockRequest.new(BronkoMediaServer)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def create_image(name = 'original')
    path = File.join(@directory, "#{name}.jpg")
    File.write(path, 'original contents')
    md5 = Digest::MD5.hexdigest(path)
    File.write(File.join(@directory, "#{md5}.png"), 'thumbnail')
    Image.create!(file_path: path, folder_path: "#{@directory}/", md5_path: md5,
                  image_name: name, extension: 'jpg', size: 17)
  end

  def test_single_delete_removes_original_thumbnail_and_record
    image = create_image
    @service.delete_image(image.md5_path)
    refute File.exist?(image.file_path)
    refute File.exist?(File.join(@directory, "#{image.md5_path}.png"))
    refute Image.exists?(image.id)
  end

  def test_batch_delete_uses_same_cleanup
    images = [create_image('first'), create_image('second')]
    @service.multi_delete_images(images.map(&:md5_path))
    assert_empty Dir.children(@directory)
    assert_empty Image.all
  end

  def test_delete_missing_image_is_harmless
    @service.delete_image('missing')
    assert_empty Image.all
  end

  def test_failed_move_restores_original_and_keeps_thumbnail
    image = create_image
    target = File.join(@directory, 'moved.jpg')
    Image.connection.execute(<<~SQL)
      CREATE TRIGGER reject_image_update BEFORE UPDATE ON images
      BEGIN SELECT RAISE(ABORT, 'update rejected'); END;
    SQL
    begin
      assert_raises(ActiveRecord::StatementInvalid) { @service.move_image(target, image.md5_path) }
    ensure
      Image.connection.execute('DROP TRIGGER reject_image_update')
    end
    assert_equal 'original contents', File.read(image.file_path)
    refute File.exist?(target)
    assert File.exist?(File.join(@directory, "#{image.md5_path}.png"))
    assert_equal image.file_path, image.reload.file_path
  end

  def test_move_updates_path_and_removes_old_thumbnail
    image = create_image
    old_path = image.file_path
    old_md5 = image.md5_path
    target = File.join(@directory, 'moved.jpg')
    @service.move_image(target, old_md5)
    assert_equal target, image.reload.file_path
    assert_equal Digest::MD5.hexdigest(target), image.md5_path
    assert_equal 'moved', image.image_name
    refute File.exist?(old_path)
    refute File.exist?(File.join(@directory, "#{old_md5}.png"))
    assert_equal 'original contents', File.read(target)
  end

  def test_missing_image_and_media_return_not_found
    assert_equal 404, @request.get('/image/missing').status
    assert_equal 404, @request.get('/media/info/missing').status
    assert_equal 404, @request.delete('/image/missing').status
  end

  def test_missing_batch_parameters_return_bad_request
    assert_equal 400, @request.post('/images/delete').status
    assert_equal 400, @request.post('/images/delete', params: { md5s: ', ,' }).status
    assert_equal 400, @request.post('/images/move', params: { md5s: 'abc' }).status
    assert_equal 400, @request.post('/image/upload').status
  end

  def test_missing_tags_return_bad_request_without_creating_tags
    image = create_image
    assert_equal 400, @request.post("/image/tag/#{image.md5_path}").status
    assert_empty Tag.all
  end

  def test_favorite_returns_empty_success_and_updates_record
    image = create_image
    response = @request.post("/favorite/#{image.md5_path}", params: { favorite: 'true' })
    assert_equal 204, response.status
    assert_empty response.body
    assert image.reload.favorite
  end

  def test_views_render_with_prepared_locals
    %w[/ /favorites /duplicates /search /folders /tags].each do |path|
      assert_equal 200, @request.get(path).status, path
    end
  end

  def test_search_and_info_render_existing_image
    image = create_image
    assert_equal 200, @request.get('/search?search=original').status
    assert_equal 200, @request.get("/media/info/#{image.md5_path}").status
    assert_equal 200, @request.get("/image/#{image.md5_path}").status
  end

  def test_folder_view_filters_images
    Folder.create!(folder_path: "#{@directory}/", parent_folder: '/', sub_folders: [], md5_path: 'folder')
    image = create_image
    image.update!(is_image: true)
    original_root = Settings.originals_path
    Settings.originals_path = @directory
    response = @request.get('/folders?media=images')
    assert_equal 200, response.status
    assert_includes response.body, image.md5_path
  ensure
    Settings.originals_path = original_root
  end

  def test_folder_delete_returns_parent_without_http_dependency
    parent = "#{@directory}/"
    child = "#{parent}child/"
    FileUtils.mkdir_p(child)
    Folder.create!(folder_path: parent, sub_folders: [child])
    Folder.create!(folder_path: child, parent_folder: parent, md5_path: 'child')
    service = BronkoMedia::FolderService.new(settings: @settings, logger: Logger.new(File::NULL))
    assert_equal parent, service.delete_folder('child')
    refute File.directory?(child)
    assert_empty Folder.find_by(folder_path: parent).sub_folders
  end

  def test_missing_thumbnail_can_be_recreated_without_creating_empty_records
    service = BronkoMedia::ThumbnailService.new(settings: @settings, logger: Logger.new(File::NULL))
    service.recreate_thumb('missing')
    assert_empty Image.all
  end

  def test_thumbnail_removal_errors_are_not_hidden
    service = BronkoMedia::ThumbnailService.new(settings: @settings, logger: Logger.new(File::NULL))
    FileUtils.mkdir_p(File.join(@directory, 'broken.png'))
    assert_raises(Errno::EPERM, Errno::EISDIR) { service.recreate_thumb('broken') }
  end

  def test_indexer_cleans_stale_records_and_thumbnails_and_indexes_folders
    image = create_image
    File.delete(image.file_path)
    Folder.create!(folder_path: "#{@directory}/missing/", md5_path: 'missing')
    root = File.join(@directory, 'collection')
    child = File.join(root, 'child')
    FileUtils.mkdir_p(child)
    service = BronkoMedia::Indexer.new(settings: @settings, logger: Logger.new(File::NULL))
    service.build_index(root, @directory, [])
    assert_empty Image.all
    refute File.exist?(File.join(@directory, "#{image.md5_path}.png"))
    refute Folder.exists?(md5_path: 'missing')
    assert Folder.exists?(folder_path: "#{child}/")
  end

  def test_debug_view_receives_selected_images
    image = create_image
    response = @request.post('/debug', params: { md5s: image.md5_path })
    assert_equal 200, response.status
    assert_includes response.body, image.md5_path
  end

  def test_folder_info_uses_folder_attributes
    Folder.create!(folder_path: "#{@directory}/", sub_folders: [], md5_path: 'folder')
    assert_equal 200, @request.get('/media/info/folder').status
  end

  def test_database_configuration_is_shared
    assert_equal 'localhost', BronkoMedia::Database.options(Settings, environment: 'development')[:host]
    assert_equal Settings.db_host, BronkoMedia::Database.options(Settings, environment: 'production')[:host]
  end
end
