# frozen_string_literal: true

module BronkoMedia
  class InvalidOperation < StandardError; end
  class PathConflict < InvalidOperation; end

  # Paths in the database retain the configured root's relative/absolute convention.
  # Symlinks beneath that trusted root are deliberately not followed.
  class PathPolicy
    def initialize(root)
      @root = File.expand_path(root)
      @absolute = Pathname.new(root).absolute?
    end

    def resolve(path, allow_root: true)
      unless path.is_a?(String) && !path.empty? && !path.include?("\0") && !path.split('/').include?('..')
        raise InvalidOperation, 'Invalid media path'
      end

      expanded = File.expand_path(path)
      unless expanded == @root || expanded.start_with?("#{@root}/")
        raise InvalidOperation, 'Path must be inside the media directory'
      end
      raise InvalidOperation, 'The media root cannot be changed or deleted' if !allow_root && expanded == @root

      relative = Pathname.new(expanded).relative_path_from(Pathname.new(@root))
      current = @root
      relative.each_filename do |part|
        current = File.join(current, part)
        raise InvalidOperation, 'Symbolic links are not supported for media operations' if File.symlink?(current)
      end
      @absolute ? expanded : Pathname.new(expanded).relative_path_from(Pathname.pwd).to_s
    end

    def available!(path)
      raise PathConflict, 'The destination already exists' if File.exist?(path) || File.symlink?(path)
    end
  end
end
