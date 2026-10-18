# frozen_string_literal: true

require_relative 'app_test'
require 'stringio'

class FileSafetyTest < Minitest::Test
  include MediaTestSupport

  def folder_service
    BronkoMedia::FolderService.new(settings: @settings, logger: Logger.new(File::NULL))
  end

  def folder_tree
    parent = "#{@directory}/"
    child = "#{parent}child/"
    nested = "#{child}nested/"
    FileUtils.mkdir_p(nested)
    Folder.create!(folder_path: parent, sub_folders: [child])
    folder = Folder.create!(folder_path: child, parent_folder: parent, sub_folders: [nested],
                            md5_path: Digest::MD5.hexdigest(child))
    Folder.create!(folder_path: nested, parent_folder: child, sub_folders: [], md5_path: Digest::MD5.hexdigest(nested))
    image = create_image('child/nested/photo')
    image.update!(folder_path: nested, tags: ['keep'], favorite: true)
    [folder, image]
  end

  def test_paths_reject_outside_traversal_and_symlink_targets
    policy = BronkoMedia::PathPolicy.new(@directory)
    ["#{@directory}/../outside", "#{@directory}-other/file", '/tmp/outside', "bad\0path"].each do |path|
      assert_raises(BronkoMedia::InvalidOperation) { policy.resolve(path) }
    end
    Dir.mktmpdir do |outside|
      File.symlink(outside, "#{@directory}/link")
      assert_raises(BronkoMedia::InvalidOperation) { folder_service.create_folder("#{@directory}/link/child") }
      refute File.exist?("#{outside}/child")
    end
    File.symlink("#{@directory}/missing", "#{@directory}/dangling")
    assert_raises(BronkoMedia::InvalidOperation) { policy.resolve("#{@directory}/dangling") }
    assert_equal "#{@directory}/new", policy.resolve("#{@directory}/./new/")
  end

  def test_relative_root_uses_the_same_path_identity_for_absolute_input
    # A project-relative root without traversal, like the production configuration.
    Dir.mktmpdir do |working|
      Dir.chdir(working) do
        Dir.mkdir('media')
        policy = BronkoMedia::PathPolicy.new('media')
        assert_equal 'media/photo.jpg', policy.resolve("#{working}/media/photo.jpg")
        assert_equal 'media/photo.jpg', policy.resolve('media/./photo.jpg')
      end
    end
  end

  def test_move_does_not_overwrite_existing_file_or_directory
    image = create_image
    other = create_image('other')
    File.write(other.file_path, 'keep destination')
    [other.file_path, @directory].each do |destination|
      assert_raises(BronkoMedia::InvalidOperation) { @service.move_image(destination, image.md5_path) }
    end
    assert_equal 'keep destination', File.read(other.file_path)
    assert_equal 'original contents', File.read(image.file_path)
    assert_equal 2, Image.count
  end

  def test_batch_collision_is_rejected_before_moving_anything
    first = create_image('first')
    second = create_image('second')
    target = "#{@directory}/target"
    Dir.mkdir(target)
    File.write("#{target}/second.jpg", 'keep')
    assert_raises(BronkoMedia::PathConflict) do
      @service.multi_move_images(target, [first.md5_path, second.md5_path])
    end
    assert File.exist?(first.file_path)
    assert File.exist?(second.file_path)
    refute File.exist?("#{target}/first.jpg")
  end

  def test_upload_collision_and_invalid_filename_do_not_write
    image = create_image
    %w[original.jpg ../outside.jpg].each do |filename|
      assert_raises(BronkoMedia::InvalidOperation) do
        @service.upload_image([{ filename: filename, tempfile: StringIO.new('replacement') }], @directory)
      end
    end
    assert_equal 'original contents', File.read(image.file_path)
    assert_equal 1, Image.count
  end

  def test_failed_upload_removes_new_file
    @settings.image_extentions = ['jpg']
    assert_raises(MiniMagick::Error) do
      @service.upload_image([{ filename: 'invalid.jpg', tempfile: StringIO.new('not an image') }], @directory)
    end
    refute File.exist?("#{@directory}/invalid.jpg")
    assert_empty Image.all
  end

  def test_media_root_cannot_be_deleted_or_moved
    folder = Folder.create!(folder_path: "#{@directory}/", md5_path: 'root')
    assert_raises(BronkoMedia::InvalidOperation) { folder_service.delete_folder(folder.md5_path) }
    assert_raises(BronkoMedia::InvalidOperation) { folder_service.move_folder(folder.md5_path, "#{@directory}/new") }
    assert File.directory?(@directory)
  end

  def test_recursive_folder_delete_cleans_records_and_thumbnails_but_keeps_siblings
    folder, image = folder_tree
    sibling = create_image('sibling')
    folder_service.delete_folder(folder.md5_path)
    refute File.exist?(folder.folder_path)
    refute Image.exists?(image.id)
    refute File.exist?("#{@directory}/#{image.md5_path}.png")
    assert Image.exists?(sibling.id)
    assert File.exist?(sibling.file_path)
    assert_equal ["#{@directory}/"], Folder.pluck(:folder_path)
    assert_empty Folder.first.sub_folders
  end

  def test_folder_move_preserves_records_metadata_and_thumbnails
    folder, image = folder_tree
    old_path = image.file_path
    old_thumb = "#{@directory}/#{image.md5_path}.png"
    target = "#{@directory}/renamed[1]"
    assert_equal "#{target}/", folder_service.move_folder(folder.md5_path, target)
    assert_equal "#{target}/nested/photo.jpg", image.reload.file_path
    assert_equal ['keep'], image.tags
    assert image.favorite
    assert File.file?(image.file_path)
    refute File.exist?(old_path)
    refute File.exist?(old_thumb)
    assert_equal 'thumbnail', File.read("#{@directory}/#{image.md5_path}.png")
    assert_equal "#{target}/", folder.reload.folder_path
    assert_equal ["#{target}/nested/"], folder.sub_folders
    assert Folder.exists?(folder_path: "#{target}/nested/", parent_folder: "#{target}/")
    assert_equal ["#{target}/"], Folder.find_by(folder_path: "#{@directory}/").sub_folders
    assert_equal 1, Image.count
    assert_equal 3, Folder.count
  end

  def test_folder_move_rejects_existing_target_and_own_subtree
    folder, image = folder_tree
    target = "#{@directory}/existing"
    Dir.mkdir(target)
    [target, "#{folder.folder_path}nested/new"].each do |destination|
      assert_raises(BronkoMedia::InvalidOperation) { folder_service.move_folder(folder.md5_path, destination) }
    end
    assert File.exist?(image.file_path)
  end

  def test_folder_move_database_failure_restores_tree
    folder, image = folder_tree
    original = folder.folder_path
    Image.connection.execute(<<~SQL)
      CREATE TRIGGER reject_move BEFORE UPDATE ON images
      BEGIN SELECT RAISE(ABORT, 'rejected'); END;
    SQL
    assert_raises(ActiveRecord::StatementInvalid) do
      folder_service.move_folder(folder.md5_path, "#{@directory}/renamed")
    end
    assert File.exist?(image.file_path)
    assert_equal original, folder.reload.folder_path
    assert File.exist?("#{@directory}/#{image.md5_path}.png")
    refute File.exist?("#{@directory}/renamed")
  ensure
    Image.connection.execute('DROP TRIGGER IF EXISTS reject_move')
  end

  def test_folder_delete_database_failure_restores_tree
    folder, image = folder_tree
    Image.connection.execute(<<~SQL)
      CREATE TRIGGER reject_delete BEFORE DELETE ON folders
      BEGIN SELECT RAISE(ABORT, 'rejected'); END;
    SQL
    assert_raises(ActiveRecord::StatementInvalid) { folder_service.delete_folder(folder.md5_path) }
    assert Image.exists?(image.id)
    assert File.exist?(image.file_path)
    assert File.exist?("#{@directory}/#{image.md5_path}.png")
    assert_equal 3, Folder.count
  ensure
    Image.connection.execute('DROP TRIGGER IF EXISTS reject_delete')
  end

  def test_http_path_errors_return_actionable_client_status
    response = @request.post('/folder/create', params: { add_folder: '/tmp/outside' })
    assert_equal 422, response.status
    assert_includes response.body, 'inside the media directory'
    path = "#{@directory}/existing"
    Dir.mkdir(path)
    assert_equal 409, @request.post('/folder/create', params: { add_folder: path }).status
  end

  def test_config_get_never_writes_and_does_not_expose_credentials
    path = File.expand_path('../config/settings.yml', __dir__)
    original = File.read(path)
    body = @request.get('/config?images_per_page=99&db_password=secret').body
    assert_equal original, File.read(path)
    refute_includes body, 'name="db_password"'
    refute_includes body, 'name="originals_path"'
    assert_includes body, 'method="post"'
    assert_includes body, 'name="config_token"'
    assert_equal 403, @request.post('/config', params: { images_per_page: '99' }).status
  end

  def test_settings_validates_before_writing_and_preserves_credentials
    path = "#{@directory}/settings.yml"
    File.write(path, { 'db_password' => 'keep secret', 'images_per_page' => 30 }.to_yaml)
    service = BronkoMedia::SettingsService.new(path: path)
    original = File.read(path)
    [{ 'images_per_page' => '0' }, { 'threads' => '1000' }, { 'originals_path' => '/tmp' },
     { 'col_options' => '\"><script>' }, { 'thumb_res' => '@file' }, { 'sort_order' => 'INVALID' }].each do |values|
      assert_raises(BronkoMedia::InvalidOperation) { service.update(values) }
      assert_equal original, File.read(path)
    end
    service.update('images_per_page' => '60', 'image_extentions' => 'JPG, png', 'threads' => '4')
    result = YAML.safe_load_file(path)
    assert_equal 60, result['images_per_page']
    assert_equal %w[jpg png], result['image_extentions']
    assert_equal 'keep secret', result['db_password']
  end

  def test_configuration_post_requires_its_session_token_and_redirects_after_save
    previous_path = BronkoMediaServer.configuration_file
    previous_database = [Settings.db_adapter, Settings.db_name]
    path = "#{@directory}/settings.yml"
    FileUtils.cp(previous_path, path)
    BronkoMediaServer.set :configuration_file, path
    response = @request.get('/config')
    cookie = Array(response['set-cookie']).first.split(';').first
    token = response.body[/name="config_token" value="([^"]+)"/, 1]
    original = File.read(path)
    assert_equal 403, @request.post('/config', 'HTTP_COOKIE' => cookie,
                                               params: { config_token: 'wrong', images_per_page: '60' }).status
    assert_equal 403, @request.post('/config', params: { config_token: token, images_per_page: '60' }).status
    assert_equal original, File.read(path)
    assert_equal 422, @request.post('/config', 'HTTP_COOKIE' => cookie,
                                               params: { config_token: token, originals_path: '/tmp' }).status
    assert_equal original, File.read(path)
    saved = @request.post('/config', 'HTTP_COOKIE' => cookie,
                                     params: { config_token: token, images_per_page: '60' })
    assert_equal 303, saved.status
    assert_equal 'http://example.org/config', saved['location']
    assert_equal 60, YAML.safe_load_file(path)['images_per_page']
    assert_equal YAML.safe_load_file(previous_path)['db_password'], YAML.safe_load_file(path)['db_password']
  ensure
    BronkoMediaServer.set :configuration_file, previous_path
    Settings.db_adapter, Settings.db_name = previous_database
    Settings.originals_path = @directory
  end

  def test_delete_with_sql_wildcards_and_case_differences_keeps_other_folders
    root = "#{@directory}/"
    %w[a_% axx A_%].each do |name|
      folder_service.create_folder("#{root}#{name}")
      image = create_image("#{name}/photo")
      image.update!(folder_path: "#{root}#{name}/")
    end
    folder = Folder.find_by(folder_path: "#{root}a_%/")
    folder_service.delete_folder(folder.md5_path)
    assert_equal ["#{root}A_%/", "#{root}axx/"], Folder.order(:folder_path).pluck(:folder_path)
    assert_equal 2, Image.count
    assert File.exist?("#{root}A_%/photo.jpg")
    assert File.exist?("#{root}axx/photo.jpg")
  end

  def test_image_delete_database_failure_restores_original
    image = create_image
    Image.connection.execute(<<~SQL)
      CREATE TRIGGER reject_image_delete BEFORE DELETE ON images
      BEGIN SELECT RAISE(ABORT, 'rejected'); END;
    SQL
    assert_raises(ActiveRecord::StatementInvalid) { @service.delete_image(image.md5_path) }
    assert_equal 'original contents', File.read(image.file_path)
    assert Image.exists?(image.id)
    assert File.exist?("#{@directory}/#{image.md5_path}.png")
  ensure
    Image.connection.execute('DROP TRIGGER IF EXISTS reject_image_delete')
  end

  def test_read_and_delete_reject_symlink_originals
    image = create_image
    Dir.mktmpdir do |outside|
      target = "#{outside}/private.jpg"
      File.write(target, 'private')
      File.unlink(image.file_path)
      File.symlink(target, image.file_path)
      assert_equal 422, @request.get("/image/#{image.md5_path}").status
      assert_raises(BronkoMedia::InvalidOperation) { @service.delete_image(image.md5_path) }
      assert_equal 'private', File.read(target)
      assert Image.exists?(image.id)
    end
  end

  def test_successful_upload_creates_original_record_and_thumbnail
    @settings.image_extentions = ['ppm']
    @settings.thumb_res = '3x4^'
    contents = "P3\n1 1\n255\n255 0 0\n"
    @service.upload_image([{ filename: 'pixel.ppm', tempfile: StringIO.new(contents) }], @directory)
    image = Image.find_by!(file_path: "#{@directory}/pixel.ppm")
    assert_equal contents, File.read(image.file_path)
    assert_equal "#{@directory}/", image.folder_path
    assert image.is_image
    assert_equal contents.bytesize, image.size
    assert File.file?("#{@directory}/#{image.md5_path}.png")
  end

  def test_successful_folder_creation_updates_parent
    Folder.create!(folder_path: "#{@directory}/", sub_folders: [])
    folder_service.create_folder("#{@directory}/new")
    assert File.directory?("#{@directory}/new")
    assert Folder.exists?(folder_path: "#{@directory}/new/", parent_folder: "#{@directory}/")
    assert_equal ["#{@directory}/new/"], Folder.find_by(folder_path: "#{@directory}/").sub_folders
  end

  def test_folder_with_symlink_cannot_be_deleted
    folder, image = folder_tree
    Dir.mktmpdir do |outside|
      File.write("#{outside}/keep", 'keep')
      File.symlink(outside, "#{folder.folder_path}external")
      assert_raises(BronkoMedia::InvalidOperation) { folder_service.delete_folder(folder.md5_path) }
      assert File.exist?(image.file_path)
      assert_equal 'keep', File.read("#{outside}/keep")
      assert Image.exists?(image.id)
    end
  end
end
