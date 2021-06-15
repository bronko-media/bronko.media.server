class AddImageType < ActiveRecord::Migration[6.1]
  def change
    add_column :images, :extension, :string
  end
end
