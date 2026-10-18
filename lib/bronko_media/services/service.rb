# frozen_string_literal: true

require 'find'

module BronkoMedia
  class Service
    def initialize(settings:, logger:)
      @settings = settings
      @logger = logger
    end

    private

    attr_reader :settings, :logger

    def paths
      @paths ||= PathPolicy.new(settings.originals_path)
    end

    # Serialize file mutations across web workers and the CLI on this media root.
    def with_media_lock
      root = File.realpath(settings.originals_path)
      locks = Thread.current[:bronko_media_locks] ||= {}
      return yield if locks[root]

      File.open(root, File::RDONLY) do |directory|
        directory.flock(File::LOCK_EX)
        locks[root] = true
        begin
          yield
        ensure
          locks.delete(root)
          directory.flock(File::LOCK_UN)
        end
      end
    end

    def media_entries(path)
      return enum_for(__method__, path) unless block_given?

      root = paths.resolve(path)
      raise InvalidOperation, 'Scan folder does not exist' unless File.directory?(root)

      thumb_root = File.expand_path(settings.thumb_target)
      Find.find(root, ignore_error: false) do |entry|
        if File.symlink?(entry) || (entry != root && File.basename(entry).start_with?('.')) ||
           (File.expand_path(entry) == thumb_root && entry != root)
          Find.prune
        end
        yield paths.resolve(entry)
      end
    end

    def thumbnail_path(md5)
      raise InvalidOperation, 'Invalid thumbnail identifier' unless md5.is_a?(String) && md5.match?(/\A[0-9a-f]{32}\z/)

      PathPolicy.new(settings.thumb_target).resolve(File.join(settings.thumb_target, "#{md5}.png"))
    end

    def remove_if_present(path)
      File.unlink(path)
    rescue Errno::ENOENT
      # A missing cached thumbnail or already removed file needs no cleanup.
    end

    def move_file_without_overwrite(source, target)
      raise InvalidOperation, 'Source must be a regular file' unless File.file?(source)

      created = false
      begin
        begin
          File.link(source, target)
          created = true
        rescue Errno::EXDEV
          File.open(target, File::WRONLY | File::CREAT | File::EXCL, File.stat(source).mode & 0o777) do |output|
            created = true
            File.open(source, 'rb') { |input| IO.copy_stream(input, output) }
            output.flush
            output.fsync
          end
          File.utime(File.atime(source), File.mtime(source), target)
        end
        File.unlink(source)
      rescue StandardError
        File.unlink(target) if created
        raise
      end
    rescue Errno::EEXIST
      raise PathConflict, 'The destination already exists'
    end

    def thumbnails
      @thumbnails ||= ThumbnailService.new(settings: settings, logger: logger)
    end

    def images
      @images ||= ImageService.new(settings: settings, logger: logger)
    end

    def folders
      @folders ||= FolderService.new(settings: settings, logger: logger)
    end

    def duplicates
      @duplicates ||= DuplicateScanner.new(settings: settings, logger: logger)
    end
  end
end
