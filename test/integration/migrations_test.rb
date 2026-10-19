# frozen_string_literal: true

require_relative 'test_helper'

class MigrationsIntegrationTest < MediaIntegrationTest
  def test_complete_migration_chain_builds_the_production_schema
    expected = IntegrationDatabase.migrations.migrations.map(&:version).sort
    assert_equal expected, IntegrationDatabase.migrations.get_all_versions.sort
    assert_equal :json, Image.columns_hash.fetch('tags').type
    assert_equal :text, Image.columns_hash.fetch('file_path').type
    assert_equal :text, Folder.columns_hash.fetch('sub_folders').type
    assert_match(/bigint/i, Image.columns_hash.fetch('size').sql_type)
    refute Image.column_names.include?('mime_type')
    refute Image.column_names.include?('fingerprint')
    image = Image.create!(file_path: 'a' * 300, tags: ['猫', 'a"b'], size: 5_000_000_000)
    assert_equal ['猫', 'a"b'], image.reload.tags
    assert_equal 300, image.file_path.size
    assert_equal 5_000_000_000, image.size
    refute image.favorite
    refute image.duplicate
  end

  def test_upgrade_preserves_existing_metadata_and_guards_lossy_rollback
    previous = 20_250_605_115_852
    IntegrationDatabase.migrate(previous)
    image = Image.create!(file_path: 'existing.jpg', tags: %w[keep 猫], favorite: true, size: 123)
    IntegrationDatabase.migrate
    assert_equal %w[keep 猫], image.reload.tags
    assert image.favorite
    assert_equal 123, image.size
    image.update!(size: 5_000_000_000)
    error = assert_raises(StandardError) { IntegrationDatabase.migrate(previous) }
    assert_kind_of ActiveRecord::IrreversibleMigration, error.cause
    assert_equal 5_000_000_000, image.reload.size
    assert_equal 20_261_019_000_000, IntegrationDatabase.migrations.current_version
    image.update!(size: 123)
    IntegrationDatabase.migrate(previous)
    IntegrationDatabase.migrate
    assert_equal %w[keep 猫], image.reload.tags
    assert_equal 123, image.size
  ensure
    Image.delete_all
    IntegrationDatabase.migrate
  end
end
