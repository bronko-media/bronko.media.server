class Image < ActiveRecord::Base
end

class Folder < ActiveRecord::Base
  serialize :sub_folders, Array
end

class Tag < ActiveRecord::Base
end
