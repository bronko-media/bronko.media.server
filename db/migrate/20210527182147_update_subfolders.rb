# frozen_string_literal: true

class UpdateSubfolders < ActiveRecord::Migration[6.1]
  def change
    change_column :folders, :folder_path, :text
    change_column :folders, :parent_folder, :text
    change_column :folders, :sub_folders, :text
    change_column :images, :file_path, :text
    change_column :images, :folder_path, :text
    change_column :images, :tags, :text
  end
end
