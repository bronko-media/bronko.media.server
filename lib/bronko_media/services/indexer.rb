# frozen_string_literal: true

module BronkoMedia
  class Indexer < Service
    def build_index(image_root, thumb_target, extensions)
      images.remove_files(thumb_target)
      folders.remove_folders
      thumbnails.remove_thumbs(thumb_target)
      folders.write_folders_to_db(folders.index_folders(image_root))
      images.index_files_to_db(image_root, extensions)
      duplicates.find_duplicates
    end

    def add_new_fields
      Parallel.each(Image.all, in_threads: settings.threads) do |image|
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
      Parallel.each(Image.all, in_threads: settings.threads) do |image|
        image.update_attribute(:file_mtime, File.mtime(image.file_path))
        image.update_attribute(:file_ctime, File.ctime(image.file_path))
      end
    end
  end
end
