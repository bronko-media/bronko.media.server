# frozen_string_literal: true

class CreateImagesTable < ActiveRecord::Migration[6.0]
  def change
    create_table :images do |t|
      t.string :md5_path
      t.string :file_path
      t.string :folder_path
      t.datetime :created_at
      t.datetime :updated_at
    end
  end
end
