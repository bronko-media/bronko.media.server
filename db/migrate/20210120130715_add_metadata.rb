# frozen_string_literal: true

class AddMetadata < ActiveRecord::Migration[6.0]
  def change
    add_column :images, :fingerprint, :string
    add_column :images, :duplicate, :boolean, default: false
    add_column :images, :duplicate_of, :string
    add_column :images, :is_video, :boolean
    add_column :images, :is_image, :boolean
  end
end
