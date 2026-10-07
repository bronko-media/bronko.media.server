# frozen_string_literal: true

require_relative 'config/boot'
require_relative 'lib/bronko_media/web_helpers'

class BronkoMediaServer < Sinatra::Base
  include ActionView::Helpers::TextHelper
  include ActionView::Helpers::NumberHelper
  include Pagy::Method

  register Sinatra::ActiveRecordExtension

  set :server, :puma
  set :method_override, true
  set :logger, Logger.new($stdout)
  set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
  set :database, BronkoMedia::Database.options(Settings)

  enable :sessions
  enable :logging

  helpers BronkoMedia::WebHelpers

  before do
    content_type :html
  end

  # Root
  get('/') { erb :index, locals: { message: nil } }

  # Duplicates
  get('/duplicates') { erb :duplicates, locals: paginated_locals(Image.where(duplicate: true)) }
  get('/duplicate/scan') do
    duplicate_scanner.find_duplicates
    erb :index, locals: { message: 'Duplicate Scan ready' }
  end

  # Favorites
  get('/favorites') { erb :favorites, locals: paginated_locals(Image.where(favorite: true).order(image_name: :asc)) }
  post('/favorite/:md5') do
    find_image(params[:md5])
    image_service.update_favorite(params[:md5], required_param(:favorite))
    status 204
  end

  # Folders
  get('/folders') { erb :folders, locals: folder_locals("#{Settings.originals_path}/") }
  get('/folders/*') { |path| erb :folders, locals: folder_locals(path) }
  post('/folder/create') do
    folder_service.create_folder(required_param(:add_folder))
    redirect_back
  end
  delete('/folder/delete/:md5') do
    folder = find_folder(params[:md5])
    parent = folder_service.delete_folder(folder.md5_path)
    redirect "/folders/#{parent}"
  end
  post('/folder/move/:md5') do
    find_folder(params[:md5])
    folder_service.move_folder(params[:md5], required_param(:move_folder))
    redirect "/folders/#{required_param(:move_folder)}"
  end
  post('/folder/scan/:md5') do
    find_folder(params[:md5])
    folder_service.scan_folder(params[:md5])
    redirect_back
  end

  # Images
  get('/image/:md5') { send_file find_image(params[:md5]).file_path, disposition: 'inline' }
  delete('/image/:md5') do
    find_image(params[:md5])
    image_service.delete_image(params[:md5])
    redirect_back
  end
  post('/image/upload') do
    image_service.upload_image(required_param(:files), required_param(:file_target))
    redirect_back
  end
  post('/image/move/:md5') do
    find_image(params[:md5])
    image_service.move_image(required_param(:file_path), params[:md5])
    redirect_back
  end
  post('/images/move') do
    image_service.multi_move_images(required_param(:path), selected_md5s)
    redirect_back
  end
  post('/images/delete') do
    image_service.multi_delete_images(selected_md5s)
    redirect_back
  end
  post('/image/tag/:md5') do
    find_image(params[:md5])
    image_service.tag_image(params[:md5], required_param(:tags, allow_empty: true))
    redirect_back
  end

  # Misc
  get('/search') do
    locals = { search: nil }
    unless params[:search].nil?
      result = paginated_locals(Image.where('file_path LIKE ?', "%#{params[:search]}%"))
      locals = { search: result[:images], pagy: result[:pagy] }
    end
    erb :search, locals: locals
  end
  get('/config') { erb :config }
  get('/media/info/:md5') do
    media = Image.find_by(md5_path: params[:md5]) || find_folder(params[:md5])
    is_folder = media.is_a?(Folder)
    files = Dir["#{media.folder_path}*"].reject { |file| File.directory?(file) } if is_folder
    erb :info, locals: { media: media, is_folder: is_folder, files_in_folder: files }
  end
  post('/thumb/recreate/:md5') do
    find_image(params[:md5])
    thumbnail_service.recreate_thumb(params[:md5])
    redirect_back
  end
  get('/tags') do
    locals = { tags: Tag.order(:id), images: nil }
    unless params[:tag].nil?
      scope = Image.where('JSON_CONTAINS(tags, ?)', [params[:tag]].to_json)
      locals.merge!(paginated_locals(scope))
    end
    erb :tags, locals: locals
  end
  post('/debug') do
    images = Image.where(md5_path: selected_md5s)
    erb :debug, locals: { message: params, images: images }
  end
  get('/indexer') do
    indexer.build_index(Settings.originals_path, Settings.thumb_target,
                        Settings.image_extentions + Settings.movie_extentions)
    erb :index, locals: { message: 'Index ready' }
  end
  get('/js/pagy.min.js') do
    content_type 'application/javascript'
    send_file Pagy::ROOT.join('javascripts', 'pagy.min.js')
  end
end
