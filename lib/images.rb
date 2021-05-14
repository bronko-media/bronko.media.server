def upload_image(files, file_target)
  if files
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
    end
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
end
