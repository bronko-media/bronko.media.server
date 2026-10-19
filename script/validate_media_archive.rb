# frozen_string_literal: true

require 'rubygems/package'
require 'zlib'

def validate_name(name)
  parts = name.delete_suffix('/').split('/')
  root = parts.take(2) == %w[data images] || parts.take(3) == %w[public images thumbs]
  return if root && !parts.intersect?(['', '.', '..'])

  raise "Unsafe archive entry: #{name.inspect}"
end

# Validate the complete archive before tar writes anything to a mounted directory.
Zlib::GzipReader.wrap($stdin) do |gzip|
  Gem::Package::TarReader.new(gzip) do |archive|
    long_name = nil
    archive.each do |entry|
      if entry.header.typeflag == 'L' # GNU/BusyBox tar uses this for long paths.
        raise 'Repeated archive long-name header' if long_name

        long_name = entry.read.delete_suffix("\0")
        validate_name(long_name)
        next
      end

      validate_name(long_name || entry.full_name)
      long_name = nil
      raise 'Archive contains a link or unsupported entry' unless entry.file? || entry.directory?
    end
    raise 'Unterminated archive long-name header' if long_name
  end
  gzip.read # Consume the gzip footer and verify its checksum.
end
