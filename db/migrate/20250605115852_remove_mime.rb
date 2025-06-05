# frozen_string_literal: true

class RemoveMime < ActiveRecord::Migration[8.0]
  def change
    remove_column :images, :mime_type, :text
  end
end
