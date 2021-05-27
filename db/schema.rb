# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2021_05_19_201429) do

  create_table "folders", force: :cascade do |t|
    t.string "md5_path"
    t.string "folder_path"
    t.string "parent_folder"
    t.string "sub_folders"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "images", force: :cascade do |t|
    t.string "md5_path"
    t.string "file_path"
    t.string "folder_path"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "image_name"
    t.boolean "favorite", default: false
    t.string "fingerprint"
    t.boolean "duplicate", default: false
    t.string "duplicate_of"
    t.boolean "is_video"
    t.boolean "is_image"
    t.string "tags"
  end

end
