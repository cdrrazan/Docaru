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

ActiveRecord::Schema[8.1].define(version: 2026_08_05_123405) do
  create_table "documents", force: :cascade do |t|
    t.string "applying_from"
    t.datetime "created_at", null: false
    t.date "expires_on", null: false
    t.text "identifier"
    t.date "issued_on"
    t.string "issuing_country", null: false
    t.string "kind", null: false
    t.string "label"
    t.integer "member_id", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["expires_on"], name: "index_documents_on_expires_on"
    t.index ["member_id"], name: "index_documents_on_member_id"
  end

  create_table "households", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "plan", default: "free", null: false
    t.datetime "updated_at", null: false
  end

  create_table "members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.string "name", null: false
    t.string "relationship"
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_members_on_household_id"
  end

  create_table "reminders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "document_id", null: false
    t.string "kind", null: false
    t.date "scheduled_for", null: false
    t.datetime "sent_at"
    t.datetime "updated_at", null: false
    t.index ["document_id", "kind"], name: "index_reminders_on_document_id_and_kind", unique: true
    t.index ["document_id"], name: "index_reminders_on_document_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.integer "household_id", null: false
    t.string "name"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["household_id"], name: "index_users_on_household_id"
  end

  add_foreign_key "documents", "members"
  add_foreign_key "members", "households"
  add_foreign_key "reminders", "documents"
  add_foreign_key "sessions", "users"
  add_foreign_key "users", "households"
end
