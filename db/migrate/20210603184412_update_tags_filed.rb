class UpdateTagsFiled < ActiveRecord::Migration[6.1]
  def change
    change_column :images, :tags, :json
  end
end
