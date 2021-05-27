def upload_image(files, file_target)
  files.each do |file|
    target   = "#{file_target}#{file[:filename]}"
    md5_path = Digest::MD5.hexdigest(target)

    File.open(target, 'wb') { |f| f.write file[:tempfile].read }

    Image.find_or_create_by(md5_path: md5_path) do |image|
      is_video = true if Settings.movie_extentions.include? File.extname(file[:filename]).delete('.')
      is_image = true if Settings.image_extentions.include? File.extname(file[:filename]).delete('.')

      image.file_path   = target
      image.folder_path = file_target
      image.image_name  = File.basename(file[:filename], '.*')
      image.md5_path    = md5_path
      image.is_image    = is_image
      image.is_video    = is_video
    end

    create_thumb(md5_path, Settings.thumb_target, Settings.thumb_res)

    ActiveRecord::Base.clear_active_connections!
  end
end

def move_image(new_file_path, md5)
  image         = Image.find_by(md5_path: md5)
  new_md5_path  = Digest::MD5.hexdigest(new_file_path)

  FileUtils.mv image.file_path, new_file_path

  Image.find_or_create_by(md5_path: new_md5_path) do |image_item|
    is_video = true if Settings.movie_extentions.include? File.extname(new_file_path).delete('.')
    is_image = true if Settings.image_extentions.include? File.extname(new_file_path).delete('.')

    image_item.file_path   = new_file_path
    image_item.folder_path = "#{File.dirname(new_file_path)}/"
    image_item.image_name  = File.basename(new_file_path, '.*')
    image_item.md5_path    = new_md5_path
    image_item.is_image    = is_image
    image_item.is_video    = is_video
  end

  create_thumb(new_md5_path, Settings.thumb_target, Settings.thumb_res)

  image.destroy
  ActiveRecord::Base.clear_active_connections!
end

def index_files_to_db(path, extensions)
  time = Time.now

  logger.info "Indexing started - #{time}"

  Dir.glob("#{path}/**/").each do |folder|
    logger.info "Indexing Images from Folder: #{folder}"
    folder_time = Time.now
    files       = Dir.entries(folder).reject { |f| File.directory?(f) }

    Parallel.each(files, in_threads: Settings.threads) do |file|
      extension = File.extname(file).delete('.')
      file_path = "#{folder}#{file}"
      md5_path  = Digest::MD5.hexdigest(file_path)

      next unless extensions.include?(extension)
      next if File.exist? "#{Settings.thumb_target}/#{md5_path}.png"

      logger.info "Indexing Image: #{file_path}"
      is_video = true if Settings.movie_extentions.include?(extension)

      if Settings.image_extentions.include?(extension)
        fingerprint = Phashion::Image.new(file_path).fingerprint
        is_image    = true
      end

      file_meta_hash = {
        file_path: file_path,
        folder_path: folder,
        image_name: File.basename(file, '.*'),
        md5_path: md5_path,
        fingerprint: fingerprint || false,
        is_video: is_video || false,
        is_image: is_image || false
      }

      write_file_to_db(file_meta_hash)
    end
    logger.info "Indexing Images from Folder took: #{Time.now - folder_time} seconds."
  end
  logger.info "Indexing took: #{Time.now - time} seconds."
end

def write_file_to_db(file)
  Image.find_or_create_by(md5_path: file[:md5_path]) do |image|
    image.file_path   = file[:file_path]
    image.fingerprint = file[:fingerprint]
    image.folder_path = file[:folder_path]
    image.image_name  = file[:image_name]
    image.is_image    = file[:is_image]
    image.is_video    = file[:is_video]
    image.md5_path    = file[:md5_path]
    image.save
  end

  ActiveRecord::Base.clear_active_connections!
end

def remove_file(thumb_target)
  Parallel.each(Image.all, in_threads: Settings.threads) do |image|
    thumb_target_path = "#{thumb_target}/#{image.md5_path}.png"

    next if File.file?(image.file_path)

    logger.info "Removing Image from DB: #{image.file_path}"
    image.destroy

    if File.file?(thumb_target_path)
      logger.info "Removing Thumb from FS: #{thumb_target_path}"
      File.delete(thumb_target_path)
    end

    ActiveRecord::Base.clear_active_connections!
  end
end
