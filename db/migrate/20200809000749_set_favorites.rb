# frozen_string_literal: true

class SetFavorites < ActiveRecord::Migration[6.0]
  def change
    change_column :images, :favorite, :boolean, default: false
  end
end
