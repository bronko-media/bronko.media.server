# frozen_string_literal: true

module BronkoMedia
  class SettingsService
    EDITABLE = %w[images_per_page col_options sort_order threads video_do_loop thumb_res
                  image_extentions movie_extentions].freeze

    def initialize(path: File.expand_path('../../../config/settings.yml', __dir__))
      @path = path
    end

    def update(values)
      raise InvalidOperation, 'Unknown configuration setting' unless (values.keys - EDITABLE).empty?

      updates = values.to_h { |key, value| [key, validate(key, value)] }
      # Keep the inode: settings.yml may be a Docker bind mount.
      File.open(@path, 'r+') do |file|
        file.flock(File::LOCK_EX)
        original = file.read
        config = YAML.safe_load(original)
        serialized = config.merge(updates).to_yaml
        begin
          file.rewind
          file.write(serialized)
          file.truncate(file.pos)
          file.flush
          file.fsync
        rescue StandardError
          file.rewind
          file.write(original)
          file.truncate(file.pos)
          raise
        end
      end
    end

    private

    def validate(key, value)
      raise InvalidOperation, "Invalid value for #{key}" unless value.is_a?(String)

      valid = case key
              when 'images_per_page', 'threads'
                limit = key == 'threads' ? 32 : 500
                return value.to_i if value.match?(/\A\d+\z/) && (1..limit).cover?(value.to_i)
              when 'sort_order'
                %w[ASC DESC].include?(value)
              when 'video_do_loop'
                %w[true false].include?(value)
              when 'thumb_res'
                value.match?(/\A[1-9]\d{0,3}x[1-9]\d{0,3}\^?\z/)
              when 'col_options'
                classes = value.split
                !classes.empty? && classes.all? do |name|
                  name.match?(/\Acol(?:-(?:sm|md|lg|xl|xxl))?-(?:[1-9]|1[0-2])\z/)
                end
              when 'image_extentions', 'movie_extentions'
                extensions = value.split(',').map(&:strip).map(&:downcase).uniq
                return extensions if !extensions.empty? && extensions.all? { |ext| ext.match?(/\A[a-z0-9]+\z/) }
              end
      raise InvalidOperation, "Invalid value for #{key}" unless valid

      value
    end
  end
end
