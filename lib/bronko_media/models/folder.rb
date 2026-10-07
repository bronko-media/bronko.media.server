# frozen_string_literal: true

class Folder < ActiveRecord::Base
  serialize :sub_folders, type: Array
  serialize :dimensions, type: Array
end
