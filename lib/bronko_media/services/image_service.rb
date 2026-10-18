# frozen_string_literal: true

module BronkoMedia
  class ImageService < Service
    def upload_image(files, file_target)
      raise InvalidOperation, 'No upload files supplied' unless files.is_a?(Array) && !files.empty?

      with_media_lock do
        folder = "#{paths.resolve(file_target)}/"
        raise InvalidOperation, 'Upload folder does not exist' unless File.directory?(folder)

        targets = files.map do |file|
          name = file[:filename] if file.is_a?(Hash)
          unless name.is_a?(String) && !name.empty? && name == File.basename(name) && !name.include?('\\') &&
                 file[:tempfile].respond_to?(:read)
            raise InvalidOperation, 'Invalid upload filename or file'
          end

          target = paths.resolve(File.join(folder, name), allow_root: false)
          paths.available!(target)
          raise PathConflict, 'Media is already indexed at the destination' if Image.exists?(file_path: target)

          target
        end
        raise PathConflict, 'Duplicate filenames in upload' unless targets.uniq.size == targets.size

        files.zip(targets).each { |file, target| store_upload(file, target, folder) }
      end
    end

    def store_upload(file, target, folder)
      created = false
      mini_magic = nil
      extension = File.extname(target).delete('.').downcase
      unless (settings.image_extentions + settings.movie_extentions).include?(extension)
        raise InvalidOperation, 'Unsupported media extension'
      end

      begin
        File.open(target, File::WRONLY | File::CREAT | File::EXCL, 0o644) do |output|
          created = true
          IO.copy_stream(file[:tempfile], output)
        end
        is_image = settings.image_extentions.include?(extension)
        mini_magic = MiniMagick::Image.open(target) if is_image
        md5 = Digest::MD5.hexdigest(target)
        Image.create!(md5_path: md5, dimensions: mini_magic&.dimensions, extension: extension,
                      file_path: target, folder_path: folder, image_name: File.basename(target, '.*'),
                      is_image: is_image, is_video: settings.movie_extentions.include?(extension),
                      signature: mini_magic&.signature, size: File.size(target),
                      file_mtime: File.mtime(target), file_ctime: File.ctime(target))
      rescue StandardError
        File.unlink(target) if created
        raise
      ensure
        mini_magic&.destroy!
      end
      thumbnails.create_thumb(md5, settings.thumb_target, settings.thumb_res)
    end
    private :store_upload

    def move_image(new_file_path, md5)
      with_media_lock { move_image_record(new_file_path, md5) }
    end

    def move_image_record(new_file_path, md5)
      image = Image.find_by(md5_path: md5)
      return unless image

      original_path = paths.resolve(image.file_path, allow_root: false)
      new_file_path = paths.resolve(new_file_path, allow_root: false)
      paths.available!(new_file_path)
      raise PathConflict, 'Media is already indexed at the destination' if Image.exists?(file_path: new_file_path)

      old_thumb = thumbnail_path(md5)
      new_md5_path = Digest::MD5.hexdigest(new_file_path)
      thumbnail_path(new_md5_path)
      move_file_without_overwrite(original_path, new_file_path)
      begin
        image.update!(file_path: new_file_path, folder_path: "#{File.dirname(new_file_path)}/",
                      image_name: File.basename(new_file_path, '.*'), md5_path: new_md5_path)
      rescue StandardError
        move_file_without_overwrite(new_file_path, original_path)
        raise
      end
      remove_if_present(old_thumb)
      thumbnails.create_thumb(new_md5_path, settings.thumb_target, settings.thumb_res)
    end
    private :move_image_record

    def multi_move_images(path, md5s)
      with_media_lock do
        folder = paths.resolve(path)
        raise InvalidOperation, 'Destination folder does not exist' unless File.directory?(folder)

        moves = Image.where(md5_path: md5s).map do |image|
          paths.resolve(image.file_path, allow_root: false)
          target = paths.resolve(File.join(folder, File.basename(image.file_path)), allow_root: false)
          paths.available!(target)
          raise PathConflict, 'Media is already indexed at the destination' if Image.exists?(file_path: target)

          [target, image.md5_path]
        end
        raise PathConflict, 'Selected files have the same destination' unless moves.map(&:first).uniq.size == moves.size

        moves.each { |target, md5| move_image_record(target, md5) }
      end
    end

    def multi_delete_images(md5s)
      with_media_lock do
        Image.where(md5_path: md5s).each do |image|
          paths.resolve(image.file_path, allow_root: false)
          thumbnail_path(image.md5_path)
        end
        md5s.each { |md5| delete_image_record(md5) }
      end
    end

    def index_files_to_db(path, extensions)
      path = paths.resolve(path)
      time = Time.now
      FileUtils.mkdir_p settings.thumb_target

      logger.info "Indexing started - #{time}"

      Dir.glob("#{path}/**/").each do |folder|
        logger.info "Indexing Images from Folder: #{folder}"
        folder_time = Time.now
        files       = Dir.entries(folder).reject { |f| File.directory?(File.join(folder, f)) }

        Parallel.each(files, in_threads: settings.threads) do |file|
          extension = File.extname(file).delete('.').downcase
          next unless extensions.include?(extension)

          begin
            file_path = paths.resolve("#{folder}#{file}")
          rescue InvalidOperation => e
            logger.warn "Skipping media: #{e.message}"
            next
          end
          md5_path = Digest::MD5.hexdigest(file_path)
          thumb_path = thumbnail_path(md5_path)

          next if File.exist?(thumb_path)

          logger.info "Indexing Image: #{file_path}"
          is_video = settings.movie_extentions.include?(extension)
          is_image = settings.image_extentions.include?(extension)
          signature = size = dimensions = nil

          if is_image
            begin
              mini_magic  = MiniMagick::Image.new(file_path)
              signature   = mini_magic.signature
              size        = mini_magic.size
              dimensions  = mini_magic.dimensions
            rescue StandardError => e
              logger.error "MiniMagick error (#{file_path}): #{e.class} - #{e.message}"
            ensure
              mini_magic&.destroy!
            end
          end

          file_meta_hash = {
            dimensions: dimensions,
            extension: extension,
            file_path: file_path,
            folder_path: folder,
            image_name: File.basename(file, '.*'),
            is_image: is_image,
            is_video: is_video,
            md5_path: md5_path,
            signature: signature,
            size: size,
            file_mtime: File.mtime(file_path),
            file_ctime: File.ctime(file_path)
          }

          write_file_to_db(file_meta_hash)

          if is_video
            thumbnails.create_vid_thumb(file_path, thumb_path, settings.thumb_res)
          elsif is_image
            thumbnails.create_img_thumb(file_path, thumb_path, settings.thumb_res)
          end
        end
        logger.info "Indexing Images from Folder took: #{Time.now - folder_time} seconds."
      end
      logger.info "Indexing took: #{Time.now - time} seconds."
    end

    def write_file_to_db(file)
      Image.find_or_create_by(md5_path: file[:md5_path]) do |image|
        image.attributes = {
          dimensions: file[:dimensions],
          extension: file[:extension],
          file_path: file[:file_path],
          folder_path: file[:folder_path],
          image_name: file[:image_name],
          is_image: file[:is_image],
          is_video: file[:is_video],
          signature: file[:signature],
          size: file[:size],
          file_mtime: file[:file_mtime],
          file_ctime: file[:file_ctime]
        }
        image.save
      end
    end

    def remove_files(_thumb_target, image_set = Image.all)
      with_media_lock do
        Parallel.each(image_set, in_threads: settings.threads) do |image|
          next if File.file?(image.file_path)

          thumb_target_path = thumbnail_path(image.md5_path)

          logger.info "Removing Image from DB: #{image.file_path}"
          image.destroy

          if File.file?(thumb_target_path)
            logger.info "Removing Thumb from FS: #{thumb_target_path}"
            File.delete(thumb_target_path)
          end
        end
      end
    end

    def update_favorite(md5, favorite)
      image = Image.find_by(md5_path: md5)
      image&.update_attribute(:favorite, favorite)
    end

    def delete_image(md5)
      with_media_lock { delete_image_record(md5) }
    end

    def delete_image_record(md5)
      image = Image.find_by(md5_path: md5)
      return unless image

      source = paths.resolve(image.file_path, allow_root: false)
      thumb = thumbnail_path(md5)
      staged = "#{source}.bronko-delete-#{SecureRandom.hex(16)}"
      moved = File.exist?(source)
      move_file_without_overwrite(source, staged) if moved
      begin
        image.destroy!
      rescue StandardError
        move_file_without_overwrite(staged, source) if moved
        raise
      end
      File.unlink(staged) if moved
      remove_if_present(thumb)
    end
    private :delete_image_record

    def tag_image(md5, tags_param)
      tags = tags_param.split(',').map(&:strip)
      tags.each { |tag| Tag.find_or_create_by(name: tag) }
      image = Image.find_by(md5_path: md5)
      image&.update_attribute(:tags, tags)
    end
  end
end
