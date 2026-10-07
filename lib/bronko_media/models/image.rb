# frozen_string_literal: true

class Image < ActiveRecord::Base
  def self.tagged_with(tag)
    if connection.adapter_name == 'SQLite'
      where("EXISTS (SELECT 1 FROM json_each(images.tags) WHERE json_each.type = 'text' AND json_each.value = ?)", tag)
    else
      where('JSON_CONTAINS(tags, ?)', [tag].to_json)
    end
  end
end
