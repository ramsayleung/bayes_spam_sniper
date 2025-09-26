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

ActiveRecord::Schema[8.0].define(version: 2025_09_26_045204) do
  create_table "banned_users", force: :cascade do |t|
    t.bigint "group_id"
    t.bigint "sender_chat_id"
    t.string "sender_user_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "spam_message"
    t.string "group_name"
    t.integer "message_id", default: 0, null: false
  end

  create_table "batch_processors", force: :cascade do |t|
    t.string "batch_key", null: false
    t.string "job_class", null: false
    t.text "shared_args_json", default: "{}"
    t.text "pending_items_json", default: "[]"
    t.integer "pending_count", default: 0
    t.integer "batch_size", default: 100
    t.integer "batch_window_in_seconds", default: 30
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_processed_at"
    t.index ["batch_key"], name: "index_batch_processors_on_batch_key", unique: true
    t.index ["updated_at"], name: "index_batch_processors_on_updated_at"
  end

  create_table "group_classifier_states", force: :cascade do |t|
    t.bigint "group_id"
    t.text "spam_counts"
    t.text "ham_counts"
    t.integer "total_spam_words"
    t.integer "total_ham_words"
    t.integer "total_spam_messages"
    t.integer "total_ham_messages"
    t.integer "vocabulary_size"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "group_name"
    t.index ["group_id"], name: "index_group_classifier_states_on_group_id", unique: true
  end

  create_table "trained_messages", force: :cascade do |t|
    t.bigint "group_id"
    t.text "message"
    t.integer "message_type"
    t.bigint "sender_chat_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sender_user_name"
    t.string "group_name"
    t.integer "training_target", default: 0, null: false
    t.integer "message_id", default: 0, null: false
    t.string "message_hash", limit: 64
    t.integer "source", default: 0, null: false
    t.index ["group_id"], name: "index_trained_messages_on_group_id"
    t.index ["message_hash"], name: "index_trained_messages_on_message_hash"
    t.index ["sender_chat_id"], name: "index_trained_messages_on_sender_chat_id"
  end
end
