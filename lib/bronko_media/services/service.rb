# frozen_string_literal: true

module BronkoMedia
  class Service
    def initialize(settings:, logger:)
      @settings = settings
      @logger = logger
    end

    private

    attr_reader :settings, :logger

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
