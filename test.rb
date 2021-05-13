require 'config'
require 'digest'
require 'fileutils'
require 'logger'
require 'mini_magick'
require 'phashion'
require 'sinatra/activerecord'
require 'streamio-ffmpeg'
require 'yaml'

require_relative 'lib/helpers'
require_relative 'lib/models'

Config.load_and_set_settings("#{File.dirname(__FILE__)}/config/settings.yml")

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

ActiveRecord::Base.logger = nil

time         = Time.now
image_root   = Settings.originals_path
extensions   = Settings.image_extentions + Settings.movie_extentions
thumb_target = Settings.thumb_target
thumb_size   = Settings.thumb_res

remove_file(thumb_target)
remove_folder
remove_thumb(thumb_target)
write_folders_to_db(index_folders(image_root))
index_files_to_db(image_root, extensions)
create_thumbs(thumb_target, thumb_size)
# find_duplicates

puts "search took #{Time.now - time}sec"
