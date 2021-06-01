def create_img_thumb(input_path, output_path, size)
  convert = MiniMagick::Tool::Convert.new
  convert << input_path
  convert.resize(size)
  convert.gravity('north')
  convert.extent(size)
  convert << output_path
  convert.call
  logger.info "Generating Thumb: #{output_path}"
rescue StandardError => e
  logger.error "Error: #{e.message}"
end

def create_vid_thumb(input_path, output_path, size)
  movie = FFMPEG::Movie.new(input_path)
  movie.screenshot(
    output_path,
    { seek_time: 1, resolution: size[0...-1], quality: 3 },
    preserve_aspect_ratio: :hight
  )

  logger.info "Generating Thumb: #{output_path}"
rescue StandardError => e
  logger.error "Error: #{e.message}"
end

def create_thumb(md5, thumb_target, size)
  image      = Image.find_or_create_by(md5_path: md5)
  image_path = "#{thumb_target}/#{md5}.png"
  extension  = File.extname(image.file_path).delete('.')

  create_vid_thumb(image.file_path, image_path, size) if Settings.movie_extentions.include?(extension)
  create_img_thumb(image.file_path, image_path, size) if Settings.image_extentions.include?(extension)
end

def remove_thumb(thumb_target)
  thumbs = Dir.entries(thumb_target).reject { |f| File.directory?(f) } if File.exist? thumb_target
  return if thumbs.nil?

  Parallel.each(Image.all, in_threads: Settings.threads) do |image|
    thumb = "#{image.md5_path}.png"
    logger.debug "Checking Thumb #{thumb}"
    thumbs.delete(thumb) if thumbs.include?(thumb)
  end

  Parallel.each(thumbs, in_threads: Settings.threads) do |t|
    logger.info "Removing Thumb: #{t}"
    File.delete("#{thumb_target}/#{t}")
  end
end
