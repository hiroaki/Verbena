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

ActiveRecord::Schema[7.1].define(version: 2026_01_08_090000) do
  create_table "delivery_responses", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "mail_queue_id", null: false
    t.datetime "responded_at"
    t.string "status"
    t.string "contents"
    t.string "message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["mail_queue_id", "responded_at"], name: "index_delivery_responses_on_mail_queue_id_and_responded_at"
    t.index ["mail_queue_id"], name: "index_delivery_responses_on_mail_queue_id"
  end

  create_table "eml_sources", charset: "utf8mb4", force: :cascade do |t|
    t.text "eml", size: :medium, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "mail_queues", charset: "utf8mb4", force: :cascade do |t|
    t.string "session_id"
    t.datetime "timer_at"
    t.string "envelope_from"
    t.string "envelope_to", null: false
    t.bigint "eml_source_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "claimed_at"
    t.index ["claimed_at"], name: "index_mail_queues_on_claimed_at"
    t.index ["eml_source_id"], name: "index_mail_queues_on_eml_source_id"
    t.index ["session_id", "claimed_at"], name: "index_mail_queues_on_session_id_and_claimed_at"
    t.index ["session_id"], name: "index_mail_queues_on_session_id"
    t.index ["timer_at", "session_id"], name: "index_mail_queues_on_timer_at_and_session_id"
    t.index ["timer_at"], name: "index_mail_queues_on_timer_at"
  end

  create_table "tokens", charset: "utf8mb4", force: :cascade do |t|
    t.string "label"
    t.string "key_digest_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "last_used_at"
    t.index ["expires_at"], name: "index_tokens_on_expires_at"
    t.index ["key_digest_hash"], name: "index_tokens_on_key_digest_hash", unique: true
    t.index ["label"], name: "index_tokens_on_label", unique: true
    t.index ["revoked_at"], name: "index_tokens_on_revoked_at"
  end

  add_foreign_key "delivery_responses", "mail_queues"
  add_foreign_key "mail_queues", "eml_sources"
end
