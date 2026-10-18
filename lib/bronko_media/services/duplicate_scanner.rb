# frozen_string_literal: true

module BronkoMedia
  class DuplicateScanner < Service
    def find_duplicates
      with_media_lock do
        logger.info 'Finding duplicates ...'
        Image.transaction do
          Image.update_all(duplicate: false, duplicate_of: nil)
          signatures = Image.where.not(signature: [nil, '']).where("TRIM(signature) <> ''")
                            .group(:signature).having('COUNT(*) > 1').pluck(:signature)
          signatures.each do |signature|
            next if signature.strip.empty?

            Image.where(signature: signature).update_all(duplicate: true)
          end
        end
      end
    end
  end
end
