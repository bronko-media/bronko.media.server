def build_index(image_root, thumb_target, extensions, duplicates: true)
  remove_file(thumb_target)
  remove_folder
  remove_thumbs(thumb_target)
  write_folders_to_db(index_folders(image_root))
  index_files_to_db(image_root, extensions)
  find_duplicates if duplicates
end

def find_duplicates
  logger.info 'finding duplicates ...'

  Parallel.each(Image.all, in_threads: Settings.threads) do |image|
    next unless image.is_image

    if image.fingerprint.nil?
      logger.info "generating image fingerprint for #{image.file_path}"
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

def fix_database
  Parallel.each(Image.all, in_threads: Settings.threads) do |image|
    next if image.folder_path[-1] == '/'

    image.folder_path = "#{image.folder_path}/"
    image.save
  end
end

def octicon(name)
  Octicons::Octicon.new(name).to_svg
end
