# frozen_string_literal: true

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

  image_signatures = Image.select(:signature).group(:signature).having('count(*) > 1')

  Parallel.each(image_signatures, in_threads: Settings.threads) do |dupe|
    Image.where(signature: dupe.signature).update(duplicate: true)
  end
end

def add_new_fields
  Parallel.each(Image.all, in_threads: Settings.threads) do |image|
    if image.dimensions.nil? || image.size.nil? || image.signature.nil?
      mini_magic = MiniMagick::Image.new(image.file_path)
      image.update_attribute(:dimensions, mini_magic.dimensions)
      image.update_attribute(:size, mini_magic.size)
      image.update_attribute(:signature, mini_magic.signature)
      mini_magic.destroy!
    end
  rescue StandardError => e
    logger.error "Error: #{e.message}"
  end
end

def add_mtime_and_ctime
  Parallel.each(Image.all, in_threads: Settings.threads) do |image|
    image.update_attribute(:file_mtime, File.mtime(image.file_path))
    image.update_attribute(:file_ctime, File.ctime(image.file_path))
  end
end
