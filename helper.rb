require 'config'
require 'digest'
require 'fileutils'
require 'logger'
require 'mini_magick'
require 'phashion'
require 'sinatra/activerecord'
require 'streamio-ffmpeg'
require 'yaml'
require 'optparse'

require_relative 'lib/helpers'
require_relative 'lib/models'

Config.load_and_set_settings("#{File.dirname(__FILE__)}/config/settings.yml")
ActiveRecord::Base.logger = nil

def logger
  @logger ||= Logger.new($stdout)
end

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: Settings.db_path,
  pool: 5,
  timeout: 5000,
  options: Settings.db_options
)

image_root   = Settings.originals_path
thumb_target = Settings.thumb_target
thumb_size   = Settings.thumb_res
extensions   = Settings.image_extentions + Settings.movie_extentions

@options = {}

OptionParser.new do |opts|
  opts.banner = 'Usage: helper.rb [options]'

  opts.on('--clean-thumbs', TrueClass, 'Clean obsolete Thumbs') do |e|
    @options[:clean_thumbs] = e.nil? ? true : e
  end

  opts.on('--clean-files', TrueClass, 'Clean obsolete Files') do |e|
    @options[:clean_files] = e.nil? ? true : e
  end

  opts.on('--clean-folders', TrueClass, 'Clean obsolete Folders') do |e|
    @options[:clean_folders] = e.nil? ? true : e
  end

  opts.on('--index', TrueClass, 'Start Indexing') do |e|
    @options[:index] = e.nil? ? true : e
  end

  opts.on('--find-duplicates', TrueClass, 'Find Duplicates') do |e|
    @options[:find_duplicates] = e.nil? ? true : e
  end

  opts.on('--fix-database', TrueClass, 'Fix Database') do |e|
    @options[:fix_database] = e.nil? ? true : e
  end
end.parse!

build_index(image_root, thumb_target, thumb_size, extensions) if @options[:index]
remove_thumb(Settings.thumb_target) if @options[:clean_thumbs]
remove_folder                       if @options[:clean_folders]
remove_file(Settings.thumb_target)  if @options[:clean_files]
find_duplicates                     if @options[:find_duplicates]
fix_database                        if @options[:fix_database]
