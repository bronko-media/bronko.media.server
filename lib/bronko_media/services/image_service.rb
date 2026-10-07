# frozen_string_literal: true

module BronkoMedia
  class ImageService < Service
    def upload_image(files, file_target)
      files.each do |file|
        target   = "#{file_target}#{file[:filename]}"
        md5_path = Digest::MD5.hexdigest(target)

        begin
          File.binwrite(target, file[:tempfile].read)
          mini_magic = MiniMagick::Image.open(target)
          extension = File.extname(file[:filename]).delete('.').downcase
          is_video = settings.movie_extentions.include?(extension)
          is_image = settings.image_extentions.include?(extension)

          Image.find_or_create_by(md5_path: md5_path) do |image|
            image.attributes = {
              dimensions: mini_magic.dimensions,
              extension: extension,
              file_path: target,
              folder_path: file_target,
              image_name: File.basename(file[:filename], '.*'),
              is_image: is_image,
              is_video: is_video,
              signature: mini_magic.signature,
              size: mini_magic.size,
              file_mtime: File.mtime(target),
              file_ctime: File.ctime(target)
            }
          end

          thumbnails.create_thumb(md5_path, settings.thumb_target, settings.thumb_res)
        rescue StandardError => e
          logger.error "Upload image error (#{file[:filename]}): #{e.class} - #{e.message}"
        ensure
          mini_magic&.destroy!
        end
      end
    end

    def move_image(new_file_path, md5)
      image = Image.find_by(md5_path: md5)
      return unless image

      original_path = image.file_path
      file_moved = false
      new_md5_path = Digest::MD5.hexdigest(new_file_path)

      begin
        FileUtils.mv image.file_path, new_file_path
        file_moved = true
        image.update!(
          file_path: new_file_path,
          folder_path: "#{File.dirname(new_file_path)}/",
          image_name: File.basename(new_file_path, '.*'),
          md5_path: new_md5_path
        )
      rescue StandardError => e
        if file_moved && File.exist?(new_file_path) && !File.exist?(original_path)
          FileUtils.mv(new_file_path, original_path)
        end
        logger.error "Move image error (#{image.file_path}): #{e.class} - #{e.message}"
        raise
      end

      FileUtils.rm_f "#{settings.thumb_target}/#{md5}.png"
      thumbnails.create_thumb(new_md5_path, settings.thumb_target, settings.thumb_res)
    end

    def multi_move_images(path, md5s)
      Parallel.each(md5s, in_threads: settings.threads) do |md5|
        image = Image.find_by(md5_path: md5)
        next unless image

        move_image(File.join(path, "#{image.image_name}.#{image.extension}"), md5)
      end
    end

    def multi_delete_images(md5s)
      Parallel.each(md5s, in_threads: settings.threads) { |md5| delete_image(md5) }
    end

    def index_files_to_db(path, extensions)
      time = Time.now
      FileUtils.mkdir_p settings.thumb_target

      logger.info "Indexing started - #{time}"

      Dir.glob("#{path}/**/").each do |folder|
        logger.info "Indexing Images from Folder: #{folder}"
        folder_time = Time.now
        files       = Dir.entries(folder).reject { |f| File.directory?(f) }

        Parallel.each(files, in_threads: settings.threads) do |file|
          extension = File.extname(file).delete('.').downcase
          next unless extensions.include?(extension)

          file_path = "#{folder}#{file}"
          md5_path  = Digest::MD5.hexdigest(file_path)
          thumb_path = "#{settings.thumb_target}/#{md5_path}.png"

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

    def remove_files(thumb_target, image_set = Image.all)
      Parallel.each(image_set, in_threads: settings.threads) do |image|
        next if File.file?(image.file_path)

        thumb_target_path = "#{thumb_target}/#{image.md5_path}.png"

        logger.info "Removing Image from DB: #{image.file_path}"
        image.destroy

        if File.file?(thumb_target_path)
          logger.info "Removing Thumb from FS: #{thumb_target_path}"
          File.delete(thumb_target_path)
        end
      end
    end

    def update_favorite(md5, favorite)
      image = Image.find_by(md5_path: md5)
      image&.update_attribute(:favorite, favorite)
    end

    def delete_image(md5)
      image = Image.find_by(md5_path: md5)
      FileUtils.rm_f image.file_path if image
      FileUtils.rm_f "#{settings.thumb_target}/#{md5}.png" if image
      image&.destroy!
    end

    def tag_image(md5, tags_param)
      tags = tags_param.split(',').map(&:strip)
      tags.each { |tag| Tag.find_or_create_by(name: tag) }
      image = Image.find_by(md5_path: md5)
      image&.update_attribute(:tags, tags)
    end
  end
end
