# frozen_string_literal: true

class CreateFolders < ActiveRecord::Migration[6.0]
  def change
    create_table :folders do |t|
      t.string :md5_path
      t.string :folder_path
      t.string :parent_folder
      t.string :sub_folders
      t.datetime :created_at
      t.datetime :updated_at
    end
  end
end
