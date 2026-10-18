# frozen_string_literal: true

require 'find'

module BronkoMedia
  class FolderService < Service
    def move_folder(md5, new_folder_path)
      with_media_lock do
        folder = Folder.find_by(md5_path: md5)
        return unless folder

        source = paths.resolve(folder.folder_path, allow_root: false)
        target = paths.resolve(new_folder_path, allow_root: false)
        paths.available!(target)
        raise InvalidOperation, 'Cannot move a folder into itself' if target.start_with?("#{source}/")
        raise InvalidOperation, 'Destination parent does not exist' unless File.directory?(File.dirname(target))

        validate_tree(source)
        old_prefix = "#{source}/"
        new_prefix = "#{target}/"
        records = descendants(Folder, :folder_path, old_prefix).to_a
        media = descendants(Image, :file_path, old_prefix).to_a
        if descendants(Folder, :folder_path, new_prefix).any? || descendants(Image, :file_path, new_prefix).any?
          raise PathConflict, 'The destination already contains indexed media'
        end

        thumb_moves = media.filter_map do |image|
          old_thumb = thumbnail_path(image.md5_path)
          new_path = image.file_path.sub(old_prefix, new_prefix)
          new_thumb = thumbnail_path(Digest::MD5.hexdigest(new_path))
          next unless File.exist?(old_thumb)

          paths.available!(new_thumb)
          [old_thumb, new_thumb]
        end
        relocate_folder(source, target, records, media, thumb_moves)
        new_prefix
      end
    end

    def create_folder(add_folder)
      with_media_lock do
        path = paths.resolve(add_folder, allow_root: false)
        paths.available!(path)
        raise PathConflict, 'Folder is already indexed' if Folder.exists?(folder_path: "#{path}/")
        raise InvalidOperation, 'Parent folder does not exist' unless File.directory?(File.dirname(path))

        Dir.mkdir(path)
        begin
          Folder.transaction do
            Folder.create!(folder_path: "#{path}/", parent_folder: "#{File.dirname(path)}/",
                           sub_folders: [], md5_path: Digest::MD5.hexdigest("#{path}/"))
            refresh_parent("#{File.dirname(path)}/")
          end
        rescue StandardError
          Dir.rmdir(path)
          raise
        end
      end
    end

    def remove_folders
      with_media_lock do
        Parallel.each(Folder.all, in_threads: settings.threads) do |folder|
          next if File.directory?(folder.folder_path)

          logger.info "Removing Folder from DB: #{folder.folder_path}"
          folder.destroy
        end
      end
    end

    def index_folders(path)
      Dir.glob("#{path}/**/").map do |folder|
        {
          md5_path: Digest::MD5.hexdigest(folder),
          folder_path: folder,
          parent_folder: "#{File.dirname(folder)}/",
          sub_folders: Dir.glob("#{folder}*/")
        }
      end
    end

    def write_folders_to_db(folder_hash)
      logger.info 'Writing new Folders to DB ...'

      Parallel.each(folder_hash, in_threads: settings.threads) do |folder_path|
        logger.info "Indexing Folder: #{folder_path[:folder_path]}"

        Folder.find_or_create_by(md5_path: folder_path[:md5_path]) do |folder|
          folder.folder_path   = folder_path[:folder_path]
          folder.parent_folder = folder_path[:parent_folder]
          folder.sub_folders   = folder_path[:sub_folders]
          folder.md5_path      = folder_path[:md5_path]
        end

        updates = Folder.find_by(md5_path: folder_path[:md5_path])
        if updates && updates.sub_folders != folder_path[:sub_folders]
          updates.update(sub_folders: folder_path[:sub_folders])
        end

        unless File.directory?(folder_path[:folder_path])
          logger.info "Removing Folder from DB: #{folder_path[:folder_path]}"
          updates&.destroy
        end
      end
    end

    def delete_folder(md5)
      with_media_lock do
        folder = Folder.find_by(md5_path: md5)
        return unless folder

        source = paths.resolve(folder.folder_path, allow_root: false)
        validate_tree(source) if File.exist?(source)
        prefix = "#{source}/"
        media = descendants(Image, :file_path, prefix).to_a
        thumbs = media.map { |image| thumbnail_path(image.md5_path) }
        staged = File.join(File.dirname(source), ".bronko-delete-#{SecureRandom.hex(16)}")
        moved = File.exist?(source)
        File.rename(source, staged) if moved
        begin
          Folder.transaction do
            media.each(&:destroy!)
            descendants(Folder, :folder_path, prefix).each(&:destroy!)
            refresh_parent(folder.parent_folder)
          end
        rescue StandardError
          File.rename(staged, source) if moved
          raise
        end
        FileUtils.rm_r(staged) if moved
        thumbs.each { |thumb| remove_if_present(thumb) }
        folder.parent_folder
      end
    end

    def scan_folder(md5)
      with_media_lock do
        folder_path = Folder.find_by(md5_path: md5)&.folder_path
        return unless folder_path

        paths.resolve(folder_path)
        folder = folder_path.delete_suffix('/')
        extensions = settings.image_extentions + settings.movie_extentions
        logger.info "Starting Folder Scan of: #{folder}"
        write_folders_to_db(index_folders(folder))
        images.index_files_to_db(folder, extensions)
        images.remove_files(settings.thumb_target, Image.where(folder_path:))
      end
    end

    private

    def descendants(model, column, prefix)
      pattern = "#{ActiveRecord::Base.sanitize_sql_like(prefix, '!')}%"
      model.where("#{column} LIKE ? ESCAPE '!'", pattern).select do |record|
        record.public_send(column).start_with?(prefix)
      end
    end

    def validate_tree(source)
      raise InvalidOperation, 'Source folder does not exist' unless File.directory?(source)

      Find.find(source) { |entry| paths.resolve(entry) }
    end

    def child_folders(path)
      Dir.children(path).sort.filter_map do |name|
        next if name.start_with?('.')

        child = File.join(path, name)
        "#{child}/" if File.directory?(child) && !File.symlink?(child)
      end
    end

    def refresh_parent(path)
      return unless path

      paths.resolve(path)
      Folder.find_by(folder_path: path)&.update!(sub_folders: child_folders(path))
    end

    def relocate_folder(source, target, records, media, thumb_moves)
      old_prefix = "#{source}/"
      new_prefix = "#{target}/"
      completed_thumbs = []
      File.rename(source, target)
      begin
        Folder.transaction do
          media.each do |image|
            new_path = image.file_path.sub(old_prefix, new_prefix)
            image.update!(file_path: new_path, folder_path: "#{File.dirname(new_path)}/",
                          md5_path: Digest::MD5.hexdigest(new_path))
          end
          records.each do |record|
            new_path = record.folder_path.sub(old_prefix, new_prefix)
            record.update!(folder_path: new_path, parent_folder: "#{File.dirname(new_path.delete_suffix('/'))}/",
                           sub_folders: child_folders(new_path), md5_path: Digest::MD5.hexdigest(new_path))
          end
          thumb_moves.each do |old_thumb, new_thumb|
            move_file_without_overwrite(old_thumb, new_thumb)
            completed_thumbs << [old_thumb, new_thumb]
          end
          refresh_parent("#{File.dirname(source)}/")
          refresh_parent("#{File.dirname(target)}/")
        end
      rescue StandardError
        completed_thumbs.reverse_each { |old_thumb, new_thumb| move_file_without_overwrite(new_thumb, old_thumb) }
        File.rename(target, source)
        raise
      end
    rescue Errno::EXDEV
      raise InvalidOperation, 'Folders can only be moved within the same filesystem'
    end
  end
end
