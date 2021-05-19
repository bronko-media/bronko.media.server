class AddTags < ActiveRecord::Migration[6.0]
  def change
    add_column :images, :tags, :string
  end
end
