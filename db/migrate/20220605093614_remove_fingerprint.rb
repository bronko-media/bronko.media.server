class RemoveFingerprint < ActiveRecord::Migration[7.0]
  def change
    remove_column :images, :fingerprint
  end
end
