# frozen_string_literal: true

class WidenMediaSize < ActiveRecord::Migration[8.0]
  def up
    change_column :images, :size, :bigint
  end

  def down
    if select_value('SELECT COUNT(*) FROM images WHERE size > 2147483647').to_i.positive?
      raise ActiveRecord::IrreversibleMigration, 'Media sizes exceed the 32-bit integer range'
    end

    change_column :images, :size, :integer
  end
end
