def upload_image(files, file_target)
  files.each do |file|
    target   = "#{file_target}#{file[:filename]}"
    md5_path = Digest::MD5.hexdigest(target)

    File.open(target, 'wb') { |f| f.write file[:tempfile].read }

    mini_magic  = MiniMagick::Image.open(target)
    fingerprint = Phashion::Image.new(target).fingerprint

    Image.find_or_create_by(md5_path: md5_path) do |image|
      is_video = true if Settings.movie_extentions.include? File.extname(file[:filename]).delete('.')
      is_image = true if Settings.image_extentions.include? File.extname(file[:filename]).delete('.')

      image.dimensions  = mini_magic.dimensions
      image.extension   = File.extname(file[:filename]).delete('.')
      image.file_path   = target
      image.fingerprint = fingerprint
      image.folder_path = file_target
      image.image_name  = File.basename(file[:filename], '.*')
      image.is_image    = is_image
      image.is_video    = is_video
      image.md5_path    = md5_path
      image.mime_type   = mini_magic.mime_type
      image.signature   = mini_magic.signature
      image.size        = mini_magic.size
    end

    create_thumb(md5_path, Settings.thumb_target, Settings.thumb_res)

    ActiveRecord::Base.clear_active_connections!
  end
end

def move_image(new_file_path, md5)
  image         = Image.find_by(md5_path: md5)
  new_md5_path  = Digest::MD5.hexdigest(new_file_path)

  FileUtils.mv image.file_path, new_file_path

  image.update_attribute(:file_path, new_file_path)
  image.update_attribute(:folder_path, "#{File.dirname(new_file_path)}/")
  image.update_attribute(:image_name, File.basename(new_file_path, '.*'))
  image.update_attribute(:md5_path, new_md5_path)

  # update thumb
  FileUtils.rm "#{Settings.thumb_target}/#{md5}.png"
  create_thumb(new_md5_path, Settings.thumb_target, Settings.thumb_res)
end

def index_files_to_db(path, extensions)
  time = Time.now
  FileUtils.mkdir_p Settings.thumb_target

  logger.info "Indexing started - #{time}"

  Dir.glob("#{path}/**/").each do |folder|
    logger.info "Indexing Images from Folder: #{folder}"
    folder_time = Time.now
    files       = Dir.entries(folder).reject { |f| File.directory?(f) }

    Parallel.each(files, in_threads: Settings.threads) do |file|
      extension = File.extname(file).delete('.')
      next unless extensions.include?(extension)

      file_path = "#{folder}#{file}"
      md5_path  = Digest::MD5.hexdigest(file_path)

      next if File.exist? "#{Settings.thumb_target}/#{md5_path}.png"

      logger.info "Indexing Image: #{file_path}"
      if Settings.movie_extentions.include?(extension)
        is_video = true
        is_image = false
      end

      if Settings.image_extentions.include?(extension)
        begin
          mini_magic  = MiniMagick::Image.new(file_path)
          fingerprint = Phashion::Image.new(file_path).fingerprint
          signature   = mini_magic.signature
          size        = mini_magic.size
          mime_type   = mini_magic.mime_type
          dimensions  = mini_magic.dimensions
        rescue StandardError => e
          logger.error "Error: #{e.message}"
        ensure
          mini_magic.destroy!
        end

        is_video = false
        is_image = true
      end

      file_meta_hash = {
        dimensions: dimensions,
        extension: extension,
        file_path: file_path,
        fingerprint: fingerprint || false,
        folder_path: folder,
        image_name: File.basename(file, '.*'),
        is_image: is_image || false,
        is_video: is_video || false,
        md5_path: md5_path,
        mime_type: mime_type,
        signature: signature,
        size: size
      }

      write_file_to_db(file_meta_hash)

      if Settings.movie_extentions.include?(extension)
        create_vid_thumb(file_path, "#{Settings.thumb_target}/#{md5_path}.png", Settings.thumb_res)
      end

      if Settings.image_extentions.include?(extension)
        create_img_thumb(file_path, "#{Settings.thumb_target}/#{md5_path}.png", Settings.thumb_res)
      end
    end
    logger.info "Indexing Images from Folder took: #{Time.now - folder_time} seconds."
  end
  logger.info "Indexing took: #{Time.now - time} seconds."
end

def write_file_to_db(file)
  Image.find_or_create_by(md5_path: file[:md5_path]) do |image|
    image.dimensions  = file[:dimensions]
    image.extension   = file[:extension]
    image.file_path   = file[:file_path]
    image.fingerprint = file[:fingerprint]
    image.folder_path = file[:folder_path]
    image.image_name  = file[:image_name]
    image.is_image    = file[:is_image]
    image.is_video    = file[:is_video]
    image.md5_path    = file[:md5_path]
    image.mime_type   = file[:mime_type]
    image.signature   = file[:signature]
    image.size        = file[:size]

    image.save
  end

  ActiveRecord::Base.clear_active_connections!
end

def remove_files(thumb_target)
  Parallel.each(Image.all, in_threads: Settings.threads) do |image|
    next if File.file?(image.file_path)

    thumb_target_path = "#{thumb_target}/#{image.md5_path}.png"

    logger.info "Removing Image from DB: #{image.file_path}"
    image.destroy

    if File.file?(thumb_target_path)
      logger.info "Removing Thumb from FS: #{thumb_target_path}"
      File.delete(thumb_target_path)
    end

    ActiveRecord::Base.clear_active_connections!
  end
end
