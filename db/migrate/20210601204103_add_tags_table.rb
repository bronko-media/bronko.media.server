class AddTagsTable < ActiveRecord::Migration[6.1]
  def change
    create_table :tags do |t|
      t.string :name
      t.datetime :created_at
      t.datetime :updated_at
    end
  end
end
