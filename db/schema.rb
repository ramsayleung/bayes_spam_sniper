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

ActiveRecord::Schema[8.0].define(version: 2025_08_24_060940) do
  create_table "trained_messages", force: :cascade do |t|
    t.integer "group_id"
    t.text "message"
    t.integer "message_type"
    t.integer "sender_chat_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id"], name: "index_trained_messages_on_group_id"
    t.index ["sender_chat_id"], name: "index_trained_messages_on_sender_chat_id"
  end
end
