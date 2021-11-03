def build_index(image_root, thumb_target, extensions)
  remove_files(thumb_target)
  remove_folders
  remove_thumbs(thumb_target)
  write_folders_to_db(index_folders(image_root))
  index_files_to_db(image_root, extensions)
  find_duplicates
end

def find_duplicates
  logger.info 'finding duplicates ...'

  Image.select(:fingerprint).group(:fingerprint).having('count(*) > 1').each do |dupe|
    next if dupe.fingerprint == '0'

    Image.where(fingerprint: dupe.fingerprint).update(duplicate: true)
  end

  Image.select(:signature).group(:signature).having('count(*) > 1').each do |dupe|
    Image.where(signature: dupe.signature).update(duplicate: true)
  end
end

def octicon(name)
  Octicons::Octicon.new(name).to_svg
end

def add_new_fields
  Parallel.each(Image.all, in_threads: Settings.threads) do |image|
    mini_magic = MiniMagick::Image.new(image.file_path)
    image.update_attribute(:dimensions, mini_magic.dimensions) if image.dimensions.nil?
    image.update_attribute(:mime_type, mini_magic.mime_type) if image.mime_type.nil?
    image.update_attribute(:size, mini_magic.size) if image.size.nil?
    image.update_attribute(:signature, mini_magic.signature) if image.signature.nil?
  rescue StandardError => e
    logger.error "Error: #{e.message}"
  ensure
    mini_magic.destroy!
  end
end
