# frozen_string_literal: true

class AddFields < ActiveRecord::Migration[6.1]
  def change
    add_column :images, :signature, :text
    add_column :images, :mime_type, :text
    add_column :images, :dimensions, :text
    add_column :images, :size, :integer
  end
end
