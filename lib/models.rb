# frozen_string_literal: true

class Image < ActiveRecord::Base
end

class Folder < ActiveRecord::Base
  serialize :sub_folders, Array
  serialize :dimensions, Array
end

class Tag < ActiveRecord::Base
end
