# frozen_string_literal: true

module BronkoMedia
  module WebHelpers
    def redirect_back
      redirect request.referer || '/'
    end

    def required_param(name, allow_empty: false)
      value = params[name]
      if value.nil? || (!allow_empty && value.respond_to?(:empty?) && value.empty?)
        halt 400,
             "Missing parameter: #{name}"
      end
      value
    end

    def selected_md5s
      md5s = required_param(:md5s).split(',').map(&:strip).reject(&:empty?).uniq
      halt 400, 'No images selected' if md5s.empty?
      md5s
    end

    def find_image(md5)
      Image.find_by(md5_path: md5) || halt(404, 'Image not found')
    end

    def find_folder(md5)
      Folder.find_by(md5_path: md5) || halt(404, 'Folder not found')
    end

    def image_service
      @image_service ||= ImageService.new(settings: Settings, logger: logger)
    end

    def folder_service
      @folder_service ||= FolderService.new(settings: Settings, logger: logger)
    end

    def thumbnail_service
      @thumbnail_service ||= ThumbnailService.new(settings: Settings, logger: logger)
    end

    def indexer
      @indexer ||= Indexer.new(settings: Settings, logger: logger)
    end

    def duplicate_scanner
      @duplicate_scanner ||= DuplicateScanner.new(settings: Settings, logger: logger)
    end

    def paginated_locals(scope)
      pagination, images = pagy(:offset, scope, limit: Settings.images_per_page, page: params[:page])
      { pagy: pagination, images: images }
    end

    def folder_locals(path)
      folder = Folder.find_by(folder_path: path)
      locals = { folder_root: path, current_folder: folder, folder: folder }
      return locals unless folder

      filter = { folder_path: path }
      filter[:is_video] = true if params[:media] == 'videos'
      filter[:is_image] = true if params[:media] == 'images'
      order = Settings.sort_order.to_s.upcase == 'ASC' ? :asc : :desc
      locals.merge(paginated_locals(Image.where(filter).order(created_at: order, image_name: :asc)))
            .merge(entry_point: folder.sub_folders, parent_folder: folder.parent_folder, this_folder: path)
    end
  end
end
