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

ActiveRecord::Schema.define(version: 2021_06_03_184412) do

  create_table "folders", charset: "utf8mb4", collation: "utf8mb4_bin", force: :cascade do |t|
    t.string "md5_path"
    t.text "folder_path"
    t.text "parent_folder"
    t.text "sub_folders"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "images", charset: "utf8mb4", collation: "utf8mb4_bin", force: :cascade do |t|
    t.string "md5_path"
    t.text "file_path"
    t.text "folder_path"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "image_name"
    t.boolean "favorite", default: false
    t.string "fingerprint"
    t.boolean "duplicate", default: false
    t.string "duplicate_of"
    t.boolean "is_video"
    t.boolean "is_image"
    t.json "tags"
  end

  create_table "tags", charset: "utf8mb4", collation: "utf8mb4_bin", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

end
