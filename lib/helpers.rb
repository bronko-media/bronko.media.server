def index_files_to_db(path, extensions)
  time = Time.now

  logger.info "Indexing started - #{time}"

  Dir.glob("#{path}/**/").each do |folder|
    logger.info "Indexing Folder: #{folder}"
    files = Dir.entries(folder).reject { |f| File.directory?(f) }

    files.each do |file|
      next unless extensions.include? File.extname(file).delete('.')

      file_path = "#{folder}#{file}"

      logger.info "Indexing Image: #{file_path}"
      is_video = true if Settings.movie_extentions.include? File.extname(file).delete('.')

      if Settings.image_extentions.include? File.extname(file).delete('.')
        fingerprint = Phashion::Image.new(file_path).fingerprint
        is_image    = true
      end

      file_meta_hash = {
        file_path: file_path,
        folder_path: folder,
        image_name: File.basename(file, '.*'),
        md5_path: Digest::MD5.hexdigest(file_path),
        fingerprint: fingerprint || false,
        is_video: is_video || false,
        is_image: is_image || false
      }

      write_file_to_db(file_meta_hash)
    end
  end

  logger.info "Indexing took #{Time.now - time} seconds."
end

def index_folders(path)
  folder_list = []

  Dir.glob("#{path}/**/").each do |folder|
    folder_list << {
      md5_path: Digest::MD5.hexdigest(folder),
      folder_path: folder,
      parent_folder: "#{File.dirname(folder)}/",
      sub_folders: Dir.glob("#{folder}*/")
    }
  end

  folder_list
end

def write_file_to_db(file)
  Image.find_or_create_by(md5_path: file[:md5_path]) do |image|
    image.file_path    = file[:file_path]
    image.fingerprint  = file[:fingerprint]
    image.folder_path  = file[:folder_path]
    image.image_name   = file[:image_name]
    image.is_image     = file[:is_image]
    image.is_video     = file[:is_video]
    image.md5_path     = file[:md5_path]
    image.save
  end
end

def write_folders_to_db(folder_hash)
  logger.info 'Writing new Folders to DB ...'

  folder_hash.each do |folder_path|
    Folder.find_or_create_by(md5_path: folder_path[:md5_path]) do |folder|
      folder.folder_path   = folder_path[:folder_path]
      folder.parent_folder = folder_path[:parent_folder]
      folder.sub_folders   = folder_path[:sub_folders]
      folder.md5_path      = folder_path[:md5_path]
    end

    updates = Folder.find_by(md5_path: folder_path[:md5_path])

    if updates.sub_folders != folder_path[:sub_folders]
      updates.sub_folders = folder_path[:sub_folders]
      updates.save
    end
  end
end

def create_thumbs(thumb_target, size)
  FileUtils.mkdir_p thumb_target
  Image.all.each do |image|
    image_path = "#{thumb_target}/#{image.md5_path}.png"
    next if File.file?(image_path)

    if Settings.movie_extentions.include? File.extname(image.file_path).delete('.')
      begin
        movie = FFMPEG::Movie.new(image.file_path)
        movie.screenshot(
          image_path,
          { seek_time: 1, resolution: size[0...-1], quality: 3 },
          preserve_aspect_ratio: :hight
        )
        logger.info "Generating Thumb: #{image_path}"
      rescue StandardError => e
        logger.error "Error: #{e.message}"
      end
    end

    next unless Settings.image_extentions.include? File.extname(image.file_path).delete('.')

    begin
      convert = MiniMagick::Tool::Convert.new
      convert << image.file_path # input file
      convert.resize(size)
      convert.gravity('north')
      convert.extent(size)
      convert << image_path # output file
      convert.call
      logger.info "Generating Thumb: #{image_path}"
    rescue StandardError => e
      logger.error "Error: #{e.message}"
    end
  end
end

def create_thumb(md5, thumb_target, size)
  image      = Image.find_or_create_by(md5_path: md5)
  image_path = "#{thumb_target}/#{md5}.png"

  if Settings.movie_extentions.include? File.extname(image.file_path).delete('.')
    movie = FFMPEG::Movie.new(image.file_path)
    movie.screenshot(
      image_path,
      { seek_time: 1, resolution: size[0...-1], quality: 3 },
      preserve_aspect_ratio: :hight
    )
  end

  if Settings.image_extentions.include? File.extname(image.file_path).delete('.')
    convert = MiniMagick::Tool::Convert.new
    convert << image.file_path # input file
    convert.resize(size)
    convert.gravity('north')
    convert.extent(size)
    convert << image_path # output file
    convert.call
  end

  logger.info "Generating Thumb: #{image_path}"
end

def remove_file(thumb_target)
  Image.all.each do |image|
    image_path = image.file_path
    thumb_path = "#{thumb_target}/#{image.md5_path}.png"

    next if File.file?(image_path)

    logger.info "Removing Image from DB: #{image.file_path}"
    image.destroy

    if File.file?(thumb_path)
      logger.info "Removing Thumb from FS: #{thumb_path}"
      File.delete(thumb_path)
    end
  end
end

def remove_thumb(thumb_target)
  thumbs = Dir.entries(thumb_target).reject { |f| File.directory?(f) } if File.exist? thumb_target
  return if thumbs.nil?

  Image.all.each do |image|
    thumb = "#{image.md5_path}.png"
    logger.debug "Checking Thumb #{thumb}"
    thumbs.delete(thumb) if thumbs.include?(thumb)
  end

  thumbs.each do |t|
    logger.info "Removing Thumb: #{t}"
    File.delete("#{thumb_target}/#{t}")
  end
end

def remove_folder
  Folder.all.each do |folder|
    folder_path = folder.folder_path

    unless File.directory?(folder_path)
      logger.info "Removing Folder from DB: #{folder.folder_path}"
      folder.destroy
    end
  end
end

def build_index(image_root, thumb_target, thumb_size, extensions)
  remove_file(thumb_target)
  remove_folder
  remove_thumb(thumb_target)
  write_folders_to_db(index_folders(image_root))
  index_files_to_db(image_root, extensions)
  create_thumbs(thumb_target, thumb_size)
  find_duplicates
end

def find_duplicates
  logger.info 'finding duplicates ...'

  Image.find_each do |image|
    if image.is_image
      if image.fingerprint.nil?
        logger.info "genrating image fingerprint for #{image.file_path}"
        fingerprint       = Phashion::Image.new(image.file_path).fingerprint
        image.fingerprint = fingerprint
      end

      duplicates = Image.where(fingerprint: image.fingerprint)

      if duplicates.size > 1
        image.duplicate = true
        duplicates.each { |dupe| image.duplicate_of = dupe.file_path }
      else
        image.duplicate = false
      end

      image.save
    end
  end
end
