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

ActiveRecord::Schema[8.1].define(version: 2026_08_07_005300) do
  create_table "active_storage_attachments", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "attachments", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.string "iv", null: false
    t.integer "page_no", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["document_id", "page_no"], name: "index_attachments_on_document_id_and_page_no"
  end

  create_table "documents", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "applying_from"
    t.datetime "created_at", null: false
    t.date "expires_on"
    t.text "identifier"
    t.date "issued_on"
    t.string "issuing_country", null: false
    t.string "kind", null: false
    t.string "label"
    t.bigint "member_id", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["expires_on"], name: "index_documents_on_expires_on"
    t.index ["member_id"], name: "index_documents_on_member_id"
  end

  create_table "households", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "plan", default: "free", null: false
    t.string "recovery_salt"
    t.datetime "recovery_used_at"
    t.text "recovery_wrapped_key"
    t.string "recovery_wrapped_key_iv"
    t.datetime "updated_at", null: false
    t.string "vault_salt"
    t.text "wrapped_key"
    t.string "wrapped_key_iv"
  end

  create_table "members", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "household_id", null: false
    t.string "name", null: false
    t.string "relationship"
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_members_on_household_id"
  end

  create_table "push_subscriptions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "auth_key", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", limit: 512, null: false
    t.datetime "expired_at"
    t.string "p256dh_key", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id", "endpoint"], name: "index_push_subscriptions_on_user_id_and_endpoint", unique: true, length: { endpoint: 191 }
  end

  create_table "reminders", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.string "kind", null: false
    t.date "scheduled_for", null: false
    t.datetime "sent_at"
    t.datetime "updated_at", null: false
    t.index ["document_id", "kind"], name: "index_reminders_on_document_id_and_kind", unique: true
  end

  create_table "sessions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "subscriptions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "canceled_at"
    t.datetime "created_at", null: false
    t.bigint "household_id", null: false
    t.datetime "last_event_at"
    t.string "paddle_customer_id"
    t.string "paddle_subscription_id", null: false
    t.string "price_id"
    t.date "renews_on"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_subscriptions_on_household_id", unique: true
    t.index ["paddle_subscription_id"], name: "index_subscriptions_on_paddle_subscription_id", unique: true
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.bigint "household_id", null: false
    t.string "name"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["household_id"], name: "index_users_on_household_id"
  end

  create_table "webhook_events", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at"
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "event_id"], name: "index_webhook_events_on_provider_and_event_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "attachments", "documents"
  add_foreign_key "documents", "members"
  add_foreign_key "members", "households"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "reminders", "documents"
  add_foreign_key "sessions", "users"
  add_foreign_key "subscriptions", "households"
  add_foreign_key "users", "households"
end
