# frozen_string_literal: true

def move_folder(md5, new_folder_path)
  folder = Folder.find_by(md5_path: md5)
  return unless folder

  old_parent_folder = folder.parent_folder
  new_folder_path   = "#{new_folder_path}/" unless new_folder_path.end_with?('/')
  new_md5_path      = Digest::MD5.hexdigest(new_folder_path)
  new_parent_folder = "#{File.dirname(new_folder_path.delete_suffix('/'))}/"

  begin
    FileUtils.mv folder.folder_path, new_folder_path
  rescue StandardError => e
    logger.error "Failed to move folder: #{e.class} - #{e.message}"
    return
  end

  folder.update(
    folder_path: new_folder_path,
    parent_folder: new_parent_folder,
    sub_folders: Dir.glob("#{new_folder_path}*/"),
    md5_path: new_md5_path
  )

  Folder.find_by(folder_path: old_parent_folder)&.update(sub_folders: Dir.glob("#{old_parent_folder}*/"))
  Folder.find_by(folder_path: new_parent_folder)&.update(sub_folders: Dir.glob("#{new_parent_folder}*/"))

  # Re-index moved folder
  new_folder_path_wo_suffix = new_folder_path.delete_suffix('/')
  write_folders_to_db(index_folders(new_folder_path_wo_suffix))
  index_files_to_db(new_folder_path_wo_suffix, Settings.image_extentions + Settings.movie_extentions)
end

def create_folder(add_folder)
  folder_path   = add_folder.end_with?('/') ? add_folder : "#{add_folder}/"
  md5_path      = Digest::MD5.hexdigest(folder_path)
  parent_folder = "#{File.dirname(folder_path.delete_suffix('/'))}/"
  parent_md5    = Digest::MD5.hexdigest(parent_folder)

  begin
    FileUtils.mkdir_p folder_path
  rescue StandardError => e
    logger.error "Failed to create folder: #{e.class} - #{e.message}"
    return
  end

  Folder.find_or_create_by(md5_path: md5_path) do |folder|
    folder.folder_path   = folder_path
    folder.parent_folder = parent_folder
    folder.sub_folders   = Dir.glob("#{folder_path}*/")
    folder.md5_path      = md5_path
  end

  Folder.find_by(md5_path: parent_md5)&.update(sub_folders: Dir.glob("#{parent_folder}*/"))
end

def remove_folders
  Parallel.each(Folder.all, in_threads: Settings.threads) do |folder|
    next if File.directory?(folder.folder_path)

    logger.info "Removing Folder from DB: #{folder.folder_path}"
    folder.destroy
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

  Parallel.each(folder_hash, in_threads: Settings.threads) do |folder_path|
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
