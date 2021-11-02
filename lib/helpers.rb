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

def fix_database
  Parallel.each(Image.all, in_threads: Settings.threads) do |image|
    next if image.folder_path[-1] == '/'

    image.folder_path = "#{image.folder_path}/"
    image.save
  end
end

def fix_database2
  Parallel.each(Image.all, in_threads: Settings.threads) do |image|
    next unless image.extension.nil?

    image.extension = File.extname(image.file_path).delete('.')
    image.save
  end
end

def octicon(name)
  Octicons::Octicon.new(name).to_svg
end

def add_new_fields
  Parallel.each(Image.all, in_threads: Settings.threads) do |image|
    mini_magic = MiniMagick::Image.open(image.file_path)

    image.update_attribute(:dimensions, mini_magic.dimensions) if image.dimensions.nil?
    image.update_attribute(:mime_type, mini_magic.mime_type) if image.mime_type.nil?
    image.update_attribute(:signature, mini_magic.signature) if image.signature.nil?
    image.update_attribute(:size, mini_magic.size) if image.size.nil?
  end
end
