# frozen_string_literal: true

module BronkoMedia
  class ThumbnailService < Service
    def create_img_thumb(input_path, output_path, size)
      ext = File.extname(input_path).delete('.').downcase
      source = ext == 'gif' ? "#{input_path}[0]" : input_path

      MiniMagick.convert do |convert|
        convert << source
        convert.resize(size)
        convert.gravity('north')
        convert.extent(size)
        convert << output_path
      end
      logger.info "Generated image thumb: #{output_path}"
    rescue StandardError => e
      logger.error "Image thumb error (#{input_path}): #{e.class} - #{e.message}"
    end

    def create_vid_thumb(input_path, output_path, size)
      movie = FFMPEG::Movie.new(input_path)
      movie.screenshot(
        output_path,
        { seek_time: 1, resolution: size[0...-1], quality: 3 },
        preserve_aspect_ratio: :height # fixed typo
      )
      logger.info "Generated video thumb: #{output_path}"
    rescue StandardError => e
      logger.error "Video thumb error (#{input_path}): #{e.class} - #{e.message}"
    end

    def create_thumb(md5, _thumb_target, size)
      image = Image.find_by(md5_path: md5)
      return unless image&.file_path && image.extension

      paths.resolve(image.file_path)
      image_path = thumbnail_path(md5)
      ext = image.extension.downcase

      if settings.movie_extentions.include?(ext)
        create_vid_thumb(image.file_path, image_path, size)
      elsif settings.image_extentions.include?(ext)
        create_img_thumb(image.file_path, image_path, size)
      else
        logger.warn "Unknown extension for thumb: #{ext} (#{image.file_path})"
      end
    end

    def remove_thumbs(thumb_target)
      with_media_lock do
        return unless File.exist?(thumb_target)

        thumbs = Dir.entries(thumb_target).reject { |f| File.directory?(File.join(thumb_target, f)) }
        return if thumbs.empty?

        used_thumbs = Image.pluck(:md5_path).map { |md5| "#{md5}.png" }
        unused_thumbs = thumbs - used_thumbs

        Parallel.each(unused_thumbs, in_threads: settings.threads) do |t|
          path = File.join(thumb_target, t)
          logger.info "Removing unused thumb: #{path}"
          FileUtils.rm_f(path)
        end
      end
    end

    def recreate_thumb(md5)
      with_media_lock do
        begin
          image = Image.find_by(md5_path: md5)
          return unless image

          paths.resolve(image.file_path)
          File.delete(thumbnail_path(md5))
        rescue Errno::ENOENT
          # A missing thumbnail is expected when creating it for the first time.
        end
        create_thumb(md5, settings.thumb_target, settings.thumb_res)
      end
    end
  end
end
