class Image < ActiveRecord::Base
  serialize :tags, Array
end

class Folder < ActiveRecord::Base
  serialize :sub_folders, Array
end
