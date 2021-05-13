require 'action_view'
require 'config'
require 'digest'
require 'fileutils'
require 'logger'
require 'mini_magick'
require 'octicons'
require 'phashion'
require 'securerandom'
require 'sinatra/activerecord'
require 'sinatra/base'
require 'sinatra/custom_logger'
require 'streamio-ffmpeg'
require 'will_paginate'
require 'will_paginate/active_record'
require 'yaml'

require_relative 'lib/bootstrap_link_renderer'
require_relative 'lib/helpers'
require_relative 'lib/models'

class BronkoMedia < Sinatra::Base
  include ActionView::Helpers::TextHelper

  register Sinatra::ActiveRecordExtension
  register WillPaginate::Sinatra

  Config.load_and_set_settings "#{File.dirname(__FILE__)}/config/settings.yml"
  ActiveRecord::Base.logger = nil

  set :method_override, true
  set :logger, Logger.new($stdout)
  set :session_secret, SecureRandom.uuid
  set :database, {
    adapter: 'sqlite3',
    database: Settings.db_path,
    pool: 5,
    timeout: 5000,
    options: Settings.db_options
  }

  enable :sessions

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
    if params[:add_folder]
      folder_path   = params['add_folder']
      folder_path   = "#{params['add_folder']}/" if folder_path[-1, 1] != '/'
      md5_path      = Digest::MD5.hexdigest(folder_path)

      # cut slash  from folder_path to get parent and than add slash to parent,
      # because all pathes end with a slash
      parent_folder = "#{File.dirname(folder_path.delete_suffix('/'))}/"
      parent_md5    = Digest::MD5.hexdigest(parent_folder)

      FileUtils.mkdir_p folder_path

      Folder.find_or_create_by(md5_path: md5_path) do |folder|
        folder.folder_path   = folder_path
        folder.parent_folder = parent_folder
        folder.sub_folders   = Dir.glob("#{folder_path}*/")
        folder.md5_path      = md5_path
      end

      updates = Folder.find_by(md5_path: parent_md5)
      if updates.sub_folders != Dir.glob("#{parent_folder}*/")
        updates.sub_folders = Dir.glob("#{parent_folder}*/")
        updates.save
      end
    end

    redirect back
  end

  delete '/folder/delete/:md5' do
    folder        = Folder.find_by(md5_path: params[:md5])
    parent_folder = folder.parent_folder.to_s

    FileUtils.rm_r folder.folder_path if File.directory?(folder.folder_path)

    updates = Folder.find_by(folder_path: parent_folder)
    if updates.sub_folders != Dir.glob("#{parent_folder}*/")
      updates.sub_folders = Dir.glob("#{parent_folder}*/")
      updates.save
    end

    folder.destroy
    redirect "/folders/#{parent_folder}"
  end

  post '/folder/move/:md5' do
    folder            = Folder.find_by(md5_path: params[:md5])
    old_parent_folder = folder.parent_folder.to_s
    new_folder_path   = params['move_folder']
    new_md5_path      = Digest::MD5.hexdigest(new_folder_path)
    new_parent_folder = "#{File.dirname(new_folder_path.delete_suffix('/'))}/"

    FileUtils.mv folder.folder_path, new_folder_path

    Folder.find_or_create_by(md5_path: new_md5_path) do |folder_item|
      folder_item.folder_path   = new_folder_path
      folder_item.parent_folder = new_parent_folder
      folder_item.sub_folders   = Dir.glob("#{new_folder_path}*/")
      folder_item.md5_path      = new_md5_path
    end

    update_old_parent = Folder.find_by(folder_path: old_parent_folder)
    if update_old_parent.sub_folders != Dir.glob("#{old_parent_folder}*/")
      update_old_parent.sub_folders = Dir.glob("#{old_parent_folder}*/")
      update_old_parent.save
    end

    update_new_parent = Folder.find_by(folder_path: new_parent_folder)
    if update_new_parent.sub_folders != Dir.glob("#{new_parent_folder}*/")
      update_new_parent.sub_folders = Dir.glob("#{new_parent_folder}*/")
      update_new_parent.save
    end

    folder.destroy
    redirect "/folders/#{new_folder_path}"
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
    if params[:files]
      folder_path = params[:file_target].delete_suffix('/')

      params['files'].each do |file|
        target   = "#{folder_path}/#{file[:filename]}"
        md5_path = Digest::MD5.hexdigest(target)

        File.open(target, 'wb') { |f| f.write file[:tempfile].read }

        Image.find_or_create_by(md5_path: md5_path) do |image|
          is_video = true if Settings.movie_extentions.include? File.extname(file[:filename]).delete('.')
          is_image = true if Settings.image_extentions.include? File.extname(file[:filename]).delete('.')

          image.file_path   = target
          image.folder_path = folder_path
          image.image_name  = File.basename(file[:filename], '.*')
          image.md5_path    = md5_path
          image.is_image    = is_image
          image.is_video    = is_video
        end

        create_thumb(md5_path, Settings.thumb_target, Settings.thumb_res)
      end
    end

    redirect back
  end

  post '/image/move/:md5' do
    new_file_path = params[:file_path]
    image         = Image.find_by(md5_path: params[:md5])
    new_md5_path  = Digest::MD5.hexdigest(new_file_path)

    FileUtils.mv image.file_path, new_file_path

    Image.find_or_create_by(md5_path: new_md5_path) do |image_item|
      is_video = true if Settings.movie_extentions.include? File.extname(new_file_path).delete('.')
      is_image = true if Settings.image_extentions.include? File.extname(new_file_path).delete('.')

      image_item.file_path   = new_file_path
      image_item.folder_path = File.dirname(new_file_path)
      image_item.image_name  = File.basename(new_file_path, '.*')
      image_item.md5_path    = new_md5_path
      image_item.is_image    = is_image
      image_item.is_video    = is_video
    end

    create_thumb(new_md5_path, Settings.thumb_target, Settings.thumb_res)

    image.destroy
    redirect back
  end

  post '/image/recreate/:md5' do
    create_thumb(params[:md5], Settings.thumb_target, Settings.thumb_res)
    redirect back
  end

  get '/indexer' do
    build_index(
      Settings.originals_path,
      Settings.thumb_target,
      Settings.thumb_res,
      Settings.image_extentions + Settings.movie_extentions
    )
    erb :index, locals: { message: 'Index ready' }
  end
end
