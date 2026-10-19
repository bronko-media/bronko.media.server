# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'rubygems/package'
require 'stringio'
require 'zlib'

class ArchiveValidationTest < Minitest::Test
  def validate_archive(name, link: false, corrupt: false)
    tar = StringIO.new
    Gem::Package::TarWriter.new(tar) do |writer|
      if link
        writer.add_symlink(name, '/etc/passwd', 0o777)
      else
        writer.add_file_simple(name, 0o600, 4) { |file| file.write('test') }
      end
    end
    compressed = StringIO.new
    Zlib::GzipWriter.wrap(compressed) { |gzip| gzip.write(tar.string) }
    data = compressed.string
    data = data[0...-8] if corrupt
    Open3.capture2e(RbConfig.ruby, File.expand_path('../script/validate_media_archive.rb', __dir__), stdin_data: data)
  end

  def test_accepts_media_and_thumbnail_files
    ['data/images/猫 % [1].jpg', 'public/images/thumbs/a.png'].each do |name|
      output, status = validate_archive(name)
      assert status.success?, output
    end
  end

  def test_rejects_paths_outside_media_roots_and_symlinks
    ['/etc/passwd', 'data/images/../../config/settings.yml', 'config/settings.yml'].each do |name|
      _output, status = validate_archive(name)
      refute status.success?, name
    end
    _output, status = validate_archive('data/images/link', link: true)
    refute status.success?
  end

  def test_rejects_truncated_gzip
    _output, status = validate_archive('data/images/image.jpg', corrupt: true)
    refute status.success?
  end
end
