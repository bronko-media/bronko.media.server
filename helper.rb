# frozen_string_literal: true

require 'optparse'
require_relative 'config/boot'

logger = Logger.new($stdout)
ActiveRecord::Base.establish_connection(BronkoMedia::Database.options(Settings))
indexer = BronkoMedia::Indexer.new(settings: Settings, logger: logger)
images = BronkoMedia::ImageService.new(settings: Settings, logger: logger)
folders = BronkoMedia::FolderService.new(settings: Settings, logger: logger)
thumbnails = BronkoMedia::ThumbnailService.new(settings: Settings, logger: logger)
duplicates = BronkoMedia::DuplicateScanner.new(settings: Settings, logger: logger)

image_root   = Settings.originals_path
thumb_target = Settings.thumb_target
extensions   = Settings.image_extentions + Settings.movie_extentions

@options = {}

OptionParser.new do |opts|
  opts.banner = 'Usage: helper.rb [options]'

  opts.on('--clean-thumbs', TrueClass, 'Clean obsolete Thumbs') do |e|
    @options[:clean_thumbs] = e.nil? || e
  end

  opts.on('--clean-files', TrueClass, 'Clean obsolete Files') do |e|
    @options[:clean_files] = e.nil? || e
  end

  opts.on('--clean-folders', TrueClass, 'Clean obsolete Folders') do |e|
    @options[:clean_folders] = e.nil? || e
  end

  opts.on('--index', TrueClass, 'Start Indexing') do |e|
    @options[:index] = e.nil? || e
  end

  opts.on('--find-duplicates', TrueClass, 'Find Duplicates') do |e|
    @options[:find_duplicates] = e.nil? || e
  end

  opts.on('--ar-logger', TrueClass, 'Activate AcitveRecord Logger') do |e|
    @options[:ar_logger] = e.nil? || e
  end

  opts.on('--add_new_fields', TrueClass, 'add new fields') do |e|
    @options[:add_new_fields] = e.nil? || e
  end

  opts.on('--add_mtime_and_ctime', TrueClass, 'add mtime and ctime') do |e|
    @options[:add_mtime_and_ctime] = e.nil? || e
  end
end.parse!

ActiveRecord::Base.logger = nil unless @options[:ar_logger]

indexer.build_index(image_root, thumb_target, extensions) if @options[:index]
thumbnails.remove_thumbs(Settings.thumb_target) if @options[:clean_thumbs]
folders.remove_folders if @options[:clean_folders]
images.remove_files(Settings.thumb_target) if @options[:clean_files]
duplicates.find_duplicates if @options[:find_duplicates]

# temporary actions
indexer.add_new_fields               if @options[:add_new_fields]
indexer.add_mtime_and_ctime          if @options[:add_mtime_and_ctime]
