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

ActiveRecord::Schema[8.1].define(version: 0) do
  create_table "llama_bot_rails_releases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "emailed_at"
    t.text "notes"
    t.boolean "published", default: false, null: false
    t.datetime "released_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["released_at"], name: "index_llama_bot_rails_releases_on_released_at"
    t.index ["version"], name: "index_llama_bot_rails_releases_on_version", unique: true
  end
end
