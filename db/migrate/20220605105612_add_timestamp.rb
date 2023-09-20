# frozen_string_literal: true

class AddTimestamp < ActiveRecord::Migration[7.0]
  def change
    add_column :images, :file_mtime, :datetime
    add_column :images, :file_ctime, :datetime
  end
end
