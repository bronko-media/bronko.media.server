require 'action_view'
require 'config'
require 'digest'
require 'fileutils'
require 'json'
require 'logger'
require 'mini_magick'
require 'octicons'
require 'parallel'
require 'phashion'
require 'rack/handler/puma'
require 'securerandom'
require 'sinatra/base'
require 'sinatra/activerecord'
require 'sinatra/custom_logger'
require 'streamio-ffmpeg'
require 'timeout'
require 'will_paginate'
require 'will_paginate/active_record'
require 'yaml'

require_relative 'lib/bootstrap_link_renderer'
require_relative 'lib/helpers'
require_relative 'lib/folders'
require_relative 'lib/thumbs'
require_relative 'lib/images'
require_relative 'lib/models'

class BronkoMedia < Sinatra::Base
  include ActionView::Helpers::TextHelper

  register Sinatra::ActiveRecordExtension
  register WillPaginate::Sinatra

  Config.load_and_set_settings "#{File.dirname(__FILE__)}/config/settings.yml"

  set :server, :puma
  set :method_override, true
  set :logger, Logger.new($stdout)
  set :session_secret, SecureRandom.uuid
  set :database, {
    adapter: Settings.db_adapter,
    database: Settings.db_name,
    password: Settings.db_password,
    username: Settings.db_username,
    host: Settings.db_host,
    encoding: Settings.db_ecnoding,
    collation: Settings.db_collation,
    pool: Settings.db_pool
  }

  enable :sessions
  enable :logging

  get '/' do
    erb :index, locals: { message: nil }
  end

  get '/config' do
    erb :config
  end

  get '/duplicates' do
    erb :duplicates
  end

  get '/duplicate/scan' do
    find_duplicates

    erb :index, locals: { message: 'Duplicate Scan ready' }
  end

  get '/favorites' do
    erb :favorites
  end

  post '/favorite/:md5' do
    image = Image.find_by(md5_path: params[:md5])
    image.update_attribute(:favorite, params[:favorite])
  end

  get '/folders' do
    erb :folders, locals: { folder_root: "#{Settings.originals_path}/" }
  end

  get '/folders/*' do |path|
    erb :folders, locals: { folder_root: path }
  end

  post '/folder/create' do
    create_folder(params[:add_folder])

    redirect back
  end

  delete '/folder/delete/:md5' do
    delete_folder(params[:md5])

    redirect "/folders/#{parent_folder}"
  end

  post '/folder/move/:md5' do
    move_folder(params[:md5], params['move_folder'])

    redirect "/folders/#{params['move_folder']}"
  end

  post '/folder/scan/:md5' do
    folder     = Folder.find_by(md5_path: params[:md5]).folder_path.delete_suffix('/')
    extensions = Settings.image_extentions + Settings.movie_extentions

    logger.info "Starting Folder Scan of: #{folder}"

    write_folders_to_db(index_folders(folder))
    index_files_to_db(folder, extensions)

    redirect back
  end

  get '/image/:md5' do
    image = Image.find_by(md5_path: params[:md5])
    send_file(image.file_path.to_s, disposition: 'inline')
  end

  delete '/image/:md5' do
    image = Image.find_by(md5_path: params[:md5])
    File.delete(image.file_path) if File.exist?(image.file_path)
    image.destroy

    redirect back
  end

  post '/image/upload' do
    upload_image(params[:files], params[:file_target])

    redirect back
  end

  post '/image/move/:md5' do
    move_image(params[:file_path], params[:md5])

    redirect back
  end

  post '/thumb/recreate/:md5' do
    begin
      File.delete("#{Settings.thumb_target}/#{params[:md5]}.png")
    rescue StandardError => e
      logger.error "Error: #{e.message}"
    end
    create_thumb(params[:md5], Settings.thumb_target, Settings.thumb_res)
  end

  get '/tags' do
    erb :tags
  end

  post '/image/tag/:md5' do
    tags = params[:tags].split(',').collect(&:strip)
    tags.each { |tag| Tag.find_or_create_by(name: tag) }

    image = Image.find_by(md5_path: params[:md5])
    image.update_attribute(:tags, tags)

    redirect back
  end

  get '/indexer' do
    build_index(
      Settings.originals_path,
      Settings.thumb_target,
      Settings.image_extentions + Settings.movie_extentions
    )

    erb :index, locals: { message: 'Index ready' }
  end
end
