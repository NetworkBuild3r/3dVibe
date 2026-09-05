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

ActiveRecord::Schema[8.0].define(version: 2026_09_05_220000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "access_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token", null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_access_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_access_tokens_on_user_id"
  end

  create_table "archive_members", force: :cascade do |t|
    t.bigint "asset_id", null: false
    t.string "internal_path", null: false
    t.bigint "compressed_size"
    t.bigint "uncompressed_size"
    t.boolean "directory", default: false, null: false
    t.datetime "mtime"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id", "internal_path"], name: "index_archive_members_on_asset_id_and_internal_path", unique: true
    t.index ["asset_id"], name: "index_archive_members_on_asset_id"
  end

  create_table "assets", force: :cascade do |t|
    t.bigint "vibe_model_id", null: false
    t.string "relative_path", null: false
    t.string "filename", null: false
    t.string "kind", default: "file", null: false
    t.string "content_digest"
    t.bigint "byte_size", default: 0, null: false
    t.datetime "mtime"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content_digest"], name: "index_assets_on_content_digest"
    t.index ["vibe_model_id", "relative_path"], name: "index_assets_on_vibe_model_id_and_relative_path", unique: true
    t.index ["vibe_model_id"], name: "index_assets_on_vibe_model_id"
  end

  create_table "curation_proposals", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.bigint "reviewed_by_id"
    t.string "kind", null: false
    t.string "status", default: "pending", null: false
    t.string "summary", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "sidecar_ref"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "status"], name: "index_curation_proposals_on_library_id_and_status"
    t.index ["library_id"], name: "index_curation_proposals_on_library_id"
    t.index ["reviewed_by_id"], name: "index_curation_proposals_on_reviewed_by_id"
  end

  create_table "invites", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.bigint "invited_by_id", null: false
    t.bigint "redeemed_by_id"
    t.string "email", null: false
    t.string "token", null: false
    t.string "role", default: "friend", null: false
    t.datetime "expires_at"
    t.datetime "redeemed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invited_by_id"], name: "index_invites_on_invited_by_id"
    t.index ["library_id"], name: "index_invites_on_library_id"
    t.index ["token"], name: "index_invites_on_token", unique: true
  end

  create_table "libraries", force: :cascade do |t|
    t.string "name", null: false
    t.string "root_path", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["root_path"], name: "index_libraries_on_root_path", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "library_id", null: false
    t.string "role", default: "friend", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id"], name: "index_memberships_on_library_id"
    t.index ["user_id", "library_id"], name: "index_memberships_on_user_id_and_library_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "print_dispatches", force: :cascade do |t|
    t.bigint "vibe_model_id"
    t.bigint "asset_id"
    t.bigint "requested_by_id", null: false
    t.string "status", default: "unavailable", null: false
    t.string "printer_hint"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_print_dispatches_on_asset_id"
    t.index ["requested_by_id"], name: "index_print_dispatches_on_requested_by_id"
    t.index ["vibe_model_id"], name: "index_print_dispatches_on_vibe_model_id"
  end

  create_table "scan_cursors", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.string "path_prefix", null: false
    t.datetime "last_mtime"
    t.bigint "last_byte_size"
    t.datetime "last_scanned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "path_prefix"], name: "index_scan_cursors_on_library_id_and_path_prefix", unique: true
    t.index ["library_id"], name: "index_scan_cursors_on_library_id"
  end

  create_table "tag_assignments", force: :cascade do |t|
    t.bigint "tag_id", null: false
    t.string "taggable_type", null: false
    t.bigint "taggable_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id"], name: "index_tag_assignments_on_tag_id"
    t.index ["taggable_type", "taggable_id", "tag_id"], name: "idx_tag_assignments_unique", unique: true
  end

  create_table "tags", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "display_name", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "vibe_models", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.string "folder_name", null: false
    t.string "title", null: false
    t.text "synopsis"
    t.integer "asset_count", default: 0, null: false
    t.bigint "byte_size", default: 0, null: false
    t.datetime "folder_mtime"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "folder_name"], name: "index_vibe_models_on_library_id_and_folder_name", unique: true
    t.index ["library_id", "updated_at", "id"], name: "index_vibe_models_on_library_id_and_updated_at_and_id"
    t.index ["library_id"], name: "index_vibe_models_on_library_id"
  end

  add_foreign_key "access_tokens", "users"
  add_foreign_key "archive_members", "assets"
  add_foreign_key "assets", "vibe_models"
  add_foreign_key "curation_proposals", "libraries"
  add_foreign_key "curation_proposals", "users", column: "reviewed_by_id"
  add_foreign_key "invites", "libraries"
  add_foreign_key "invites", "users", column: "invited_by_id"
  add_foreign_key "memberships", "libraries"
  add_foreign_key "memberships", "users"
  add_foreign_key "print_dispatches", "assets"
  add_foreign_key "print_dispatches", "users", column: "requested_by_id"
  add_foreign_key "print_dispatches", "vibe_models"
  add_foreign_key "scan_cursors", "libraries"
  add_foreign_key "tag_assignments", "tags"
  add_foreign_key "vibe_models", "libraries"
end
