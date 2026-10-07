# frozen_string_literal: true

module BronkoMedia
  class DuplicateScanner < Service
    def find_duplicates
      logger.info 'finding duplicates ...'

      image_signatures = Image.select(:signature).group(:signature).having('count(*) > 1')

      Parallel.each(image_signatures, in_threads: settings.threads) do |dupe|
        Image.where(signature: dupe.signature).update(duplicate: true)
      end
    end
  end
end
