# frozen_string_literal: true

require 'action_view'
require 'config'
require 'digest'
require 'fileutils'
require 'json'
require 'logger'
require 'mini_magick'
require 'pagy'
require 'pagy/extras/bootstrap'
require 'pagy/extras/pagy'
require 'parallel'
require 'rackup'
require 'rack/handler/puma'
require 'securerandom'
require 'sinatra/base'
require 'sinatra/activerecord'
require 'sinatra/custom_logger'
require 'streamio-ffmpeg'
require 'timeout'
require 'yaml'

require_relative 'lib/helpers'
require_relative 'lib/folders'
require_relative 'lib/thumbs'
require_relative 'lib/images'
require_relative 'lib/models'

module BronkoMedia
  VERSION = 'v0.9.0'
end

class BronkoMediaServer < Sinatra::Base
  include ActionView::Helpers::TextHelper
  include ActionView::Helpers::NumberHelper
  include Pagy::Backend
  include Pagy::Frontend

  register Sinatra::ActiveRecordExtension

  Config.load_and_set_settings "#{File.dirname(__FILE__)}/config/settings.yml"

  set :server, :puma
  set :method_override, true
  set :logger, Logger.new($stdout)
  set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
  set :database, {
    adapter: Settings.db_adapter,
    database: Settings.db_name,
    password: Settings.db_password,
    username: Settings.db_username,
    host: ENV['RACK_ENV'] == 'development' ? 'localhost' : Settings.db_host,
    encoding: Settings.db_ecnoding,
    collation: Settings.db_collation,
    pool: Settings.db_pool
  }

  enable :sessions
  enable :logging

  helpers do
    def redirect_back
      redirect request.referer || '/'
    end
  end

  before do
    content_type :html
  end

  # Root
  get('/') { erb :index, locals: { message: nil } }

  # Duplicates
  get('/duplicates') { erb :duplicates }
  get('/duplicate/scan') do
    find_duplicates
    erb :index, locals: { message: 'Duplicate Scan ready' }
  end

  # Favorites
  get('/favorites') { erb :favorites }
  post('/favorite/:md5') { update_favorite(params[:md5], params[:favorite]) }

  # Folders
  get('/folders') { erb :folders, locals: { folder_root: "#{Settings.originals_path}/" } }
  get('/folders/*') { |path| erb :folders, locals: { folder_root: path } }
  post('/folder/create') do
    create_folder(params[:add_folder])
    redirect_back
  end
  delete('/folder/delete/:md5') { delete_folder(params[:md5]) }
  post('/folder/move/:md5') do
    move_folder(params[:md5], params['move_folder'])
    redirect "/folders/#{params['move_folder']}"
  end
  post('/folder/scan/:md5') do
    scan_folder(params[:md5])
    redirect_back
  end

  # Images
  get('/image/:md5') { send_image(params[:md5]) }
  delete('/image/:md5') do
    delete_image(params[:md5])
    redirect_back
  end
  post('/image/upload') do
    upload_image(params[:files], params[:file_target])
    redirect_back
  end
  post('/image/move/:md5') do
    move_image(params[:file_path], params[:md5])
    redirect_back
  end
  post('/images/move') do
    multi_move_images(params[:path], params[:md5s].split(',').uniq)
    redirect_back
  end
  post('/images/delete') do
    multi_delete_images(params[:md5s].split(',').uniq)
    redirect_back
  end
  post('/image/tag/:md5') do
    tag_image(params[:md5], params[:tags])
    redirect_back
  end

  # Misc
  get('/search') { erb :search }
  get('/config') { erb :config }
  get('/media/info/:md5') { erb :info, locals: { md5: params[:md5] } }
  post('/thumb/recreate/:md5') do
    recreate_thumb(params[:md5])
    redirect_back
  end
  get('/tags') { erb :tags }
  post('/debug') { erb :debug, locals: { message: params } }
  get('/indexer') do
    build_index(Settings.originals_path, Settings.thumb_target, Settings.image_extentions + Settings.movie_extentions)
    erb :index, locals: { message: 'Index ready' }
  end
  get('/js/pagy.min.js') do
    content_type 'application/javascript'
    send_file Pagy.root.join('javascripts', 'pagy.min.js')
  end

  private

  def update_favorite(md5, favorite)
    image = Image.find_by(md5_path: md5)
    image&.update_attribute(:favorite, favorite)
  end

  def delete_folder(md5)
    folder = Folder.find_by(md5_path: md5)
    parent = folder&.parent_folder
    FileUtils.rm_r folder.folder_path if folder && File.directory?(folder.folder_path)
    Folder.find_by(folder_path: parent)&.update_attribute(:sub_folders, Dir.glob("#{parent}*/"))
    folder&.destroy
    redirect "/folders/#{parent}"
  end

  def scan_folder(md5)
    folder_path = Folder.find_by(md5_path: md5)&.folder_path
    return unless folder_path

    folder = folder_path.delete_suffix('/')
    extensions = Settings.image_extentions + Settings.movie_extentions
    logger.info "Starting Folder Scan of: #{folder}"
    write_folders_to_db(index_folders(folder))
    index_files_to_db(folder, extensions)
    remove_files(Settings.thumb_target, Image.where(folder_path:))
  end

  def send_image(md5)
    image = Image.find_by(md5_path: md5)
    send_file(image.file_path, disposition: 'inline') if image
  end

  def delete_image(md5)
    image = Image.find_by(md5_path: md5)
    FileUtils.rm_f image.file_path if image
    image&.destroy
  end

  def tag_image(md5, tags_param)
    tags = tags_param.split(',').map(&:strip)
    tags.each { |tag| Tag.find_or_create_by(name: tag) }
    image = Image.find_by(md5_path: md5)
    image&.update_attribute(:tags, tags)
  end

  def recreate_thumb(md5)
    begin
      File.delete("#{Settings.thumb_target}/#{md5}.png")
    rescue StandardError
      nil
    end
    create_thumb(md5, Settings.thumb_target, Settings.thumb_res)
  end
end
