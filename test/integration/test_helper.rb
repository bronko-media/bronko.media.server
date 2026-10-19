# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
# Never let Sinatra's database extension inherit an application's database URL.
ENV.delete('DATABASE_URL')

require 'tmpdir'
require_relative '../../config/boot'

module IntegrationDatabase
  class << self
    attr_reader :options

    def prepare
      @directory = Dir.mktmpdir('bronko-integration-db')
      case ENV.fetch('BRONKO_TEST_ADAPTER', 'sqlite3')
      when 'sqlite3'
        @options = { adapter: 'sqlite3', database: File.join(@directory, 'test.sqlite3'), pool: 12, timeout: 5000 }
      when 'mysql2'
        require 'mysql2'
        @admin = Mysql2::Client.new(host: ENV.fetch('BRONKO_TEST_MYSQL_HOST', '127.0.0.1'),
                                    port: Integer(ENV.fetch('BRONKO_TEST_MYSQL_PORT', '3306')),
                                    username: ENV.fetch('BRONKO_TEST_MYSQL_USER', 'root'),
                                    password: ENV.fetch('BRONKO_TEST_MYSQL_PASSWORD'), connect_timeout: 5)
        @database = "bronko_integration_#{Process.pid}_#{SecureRandom.hex(8)}"
        @admin.query("CREATE DATABASE `#{@database}` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin")
        @created = true
        @options = { adapter: 'mysql2', database: @database, pool: 12,
                     host: ENV.fetch('BRONKO_TEST_MYSQL_HOST', '127.0.0.1'),
                     port: Integer(ENV.fetch('BRONKO_TEST_MYSQL_PORT', '3306')),
                     username: ENV.fetch('BRONKO_TEST_MYSQL_USER', 'root'),
                     password: ENV.fetch('BRONKO_TEST_MYSQL_PASSWORD'), encoding: 'utf8mb4', collation: 'utf8mb4_bin' }
      else
        raise ArgumentError, 'BRONKO_TEST_ADAPTER must be sqlite3 or mysql2'
      end

      # Initial app loading must also use an isolated database, even before its
      # connection is replaced with the chosen integration adapter and port.
      Settings.db_adapter = 'sqlite3'
      Settings.db_name = File.join(@directory, 'bootstrap.sqlite3')
    end

    def migrations
      ActiveRecord::MigrationContext.new(File.expand_path('../../db/migrate', __dir__))
    end

    def migrate(version = nil)
      ActiveRecord::Migration.suppress_messages { migrations.migrate(version) }
      [Image, Folder, Tag].each(&:reset_column_information)
    end

    def cleanup
      ActiveRecord::Base.connection_handler.clear_all_connections!
      @admin.query("DROP DATABASE `#{@database}`") if @created
      @admin&.close
    ensure
      FileUtils.remove_entry(@directory) if @directory && File.directory?(@directory)
    end
  end
end

# Registered before Minitest's autorun so cleanup also runs after failed tests.
at_exit { IntegrationDatabase.cleanup }
require 'minitest/autorun'
IntegrationDatabase.prepare
require_relative '../../app'
BronkoMediaServer.set :database, IntegrationDatabase.options
IntegrationDatabase.migrate
puts "Integration database: #{ActiveRecord::Base.connection.adapter_name} (real migrations)"

class MediaIntegrationTest < Minitest::Test
  def setup
    [Image, Folder, Tag].each(&:delete_all)
    @directory = Dir.mktmpdir('bronko-media-integration')
    @original_settings = Settings.to_h
    Settings.originals_path = File.join(@directory, 'media')
    Settings.thumb_target = File.join(@directory, 'thumbs')
    Settings.image_extentions = %w[png jpg gif]
    Settings.movie_extentions = ['mp4']
    Settings.thumb_res = '16x16^'
    Settings.threads = 3
    FileUtils.mkdir_p([Settings.originals_path, Settings.thumb_target])
    @logger = Logger.new(File::NULL)
    @images = BronkoMedia::ImageService.new(settings: Settings, logger: @logger)
    @folders = BronkoMedia::FolderService.new(settings: Settings, logger: @logger)
    @request = Rack::MockRequest.new(BronkoMediaServer)
  end

  def teardown
    ActiveRecord::Base.connection_handler.clear_active_connections!
    @original_settings.each { |key, value| Settings[key] = value }
    FileUtils.remove_entry(@directory)
  end

  def picture(name, color = 'red', size = '8x4')
    path = File.join(Settings.originals_path, name)
    FileUtils.mkdir_p(File.dirname(path))
    temporary = File.join(@directory, "fixture#{File.extname(name)}")
    MiniMagick.convert do |convert|
      convert.size(size)
      convert << "xc:#{color}"
      convert << temporary
    end
    FileUtils.mv(temporary, path)
    path
  end

  def video(name, color = 'red')
    path = File.join(Settings.originals_path, name)
    assert system('ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', "color=c=#{color}:s=16x16:d=0.5",
                  '-c:v', 'mpeg4', '-y', path), 'FFmpeg fixture generation failed'
    path
  end

  def scan
    BronkoMedia::Indexer.new(settings: Settings, logger: @logger)
                        .build_index(Settings.originals_path, Settings.thumb_target,
                                     Settings.image_extentions + Settings.movie_extentions)
  end

  def thumb(image)
    File.join(Settings.thumb_target, "#{image.md5_path}.png")
  end

  def assert_thumbnail(image)
    thumbnail = MiniMagick::Image.new(thumb(image))
    assert thumbnail.valid?
    assert_equal 'PNG', thumbnail.type
    assert_equal [16, 16], thumbnail.dimensions
  end

  def reject_database_write(name, table, operation)
    sql = if ActiveRecord::Base.connection.adapter_name == 'Mysql2'
            "CREATE TRIGGER #{name} BEFORE #{operation} ON #{table} FOR EACH ROW " \
              "SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'integration test rejection'"
          else
            "CREATE TRIGGER #{name} BEFORE #{operation} ON #{table} " \
              "BEGIN SELECT RAISE(ABORT, 'integration test rejection'); END"
          end
    ActiveRecord::Base.connection.execute(sql)
    yield
  ensure
    ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS #{name}")
  end
end
