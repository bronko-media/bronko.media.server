# frozen_string_literal: true

class AddNameToImagesTable < ActiveRecord::Migration[6.0]
  def change
    add_column :images, :image_name, :string
  end
end
