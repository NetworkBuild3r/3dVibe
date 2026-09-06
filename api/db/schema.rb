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

ActiveRecord::Schema[8.0].define(version: 2026_09_06_160000) do
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
    t.string "content_type"
    t.string "parent_path", default: "", null: false
    t.string "basename", default: "", null: false
    t.string "preview_digest"
    t.string "listing_source", default: "zip", null: false
    t.index ["asset_id", "basename"], name: "index_archive_members_on_asset_id_and_basename"
    t.index ["asset_id", "internal_path"], name: "index_archive_members_on_asset_id_and_internal_path", unique: true
    t.index ["asset_id", "parent_path"], name: "index_archive_members_on_asset_id_and_parent_path"
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
    t.bigint "uploaded_by_id"
    t.boolean "archive_truncated", default: false, null: false
    t.string "archive_support"
    t.bigint "inode"
    t.string "geometry_digest"
    t.index ["content_digest"], name: "index_assets_on_content_digest"
    t.index ["geometry_digest"], name: "index_assets_on_geometry_digest"
    t.index ["uploaded_by_id"], name: "index_assets_on_uploaded_by_id"
    t.index ["vibe_model_id", "relative_path"], name: "index_assets_on_vibe_model_id_and_relative_path", unique: true
    t.index ["vibe_model_id"], name: "index_assets_on_vibe_model_id"
  end

  create_table "bookmark_folders", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_bookmark_folders_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_bookmark_folders_on_user_id"
  end

  create_table "bookmarks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "vibe_model_id", null: false
    t.bigint "bookmark_folder_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bookmark_folder_id", "vibe_model_id"], name: "index_bookmarks_on_bookmark_folder_id_and_vibe_model_id", unique: true
    t.index ["bookmark_folder_id"], name: "index_bookmarks_on_bookmark_folder_id"
    t.index ["user_id", "vibe_model_id"], name: "index_bookmarks_on_user_id_and_vibe_model_id"
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
    t.index ["vibe_model_id"], name: "index_bookmarks_on_vibe_model_id"
  end

  create_table "creators", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.string "source"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_creators_on_name"
    t.index ["slug"], name: "index_creators_on_slug", unique: true
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
    t.datetime "applied_at"
    t.text "apply_error"
    t.jsonb "result", default: {}, null: false
    t.index ["library_id", "sidecar_ref"], name: "index_curation_proposals_library_sidecar_ref", unique: true, where: "((sidecar_ref IS NOT NULL) AND ((sidecar_ref)::text <> ''::text))"
    t.index ["library_id", "status"], name: "index_curation_proposals_on_library_id_and_status"
    t.index ["library_id"], name: "index_curation_proposals_on_library_id"
    t.index ["reviewed_by_id"], name: "index_curation_proposals_on_reviewed_by_id"
  end

  create_table "duplicate_group_members", force: :cascade do |t|
    t.bigint "duplicate_group_id", null: false
    t.bigint "asset_id", null: false
    t.bigint "vibe_model_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_duplicate_group_members_on_asset_id"
    t.index ["duplicate_group_id", "asset_id"], name: "idx_dup_group_members_on_group_and_asset", unique: true
    t.index ["duplicate_group_id"], name: "index_duplicate_group_members_on_duplicate_group_id"
    t.index ["vibe_model_id"], name: "index_duplicate_group_members_on_vibe_model_id"
  end

  create_table "duplicate_groups", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.string "reason", null: false
    t.string "confidence", null: false
    t.string "digest"
    t.string "status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "status"], name: "index_duplicate_groups_on_library_id_and_status"
    t.index ["library_id"], name: "index_duplicate_groups_on_library_id"
  end

  create_table "duplicate_reviews", force: :cascade do |t|
    t.bigint "duplicate_group_id", null: false
    t.bigint "user_id", null: false
    t.string "decision", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["duplicate_group_id"], name: "index_duplicate_reviews_on_duplicate_group_id"
    t.index ["user_id"], name: "index_duplicate_reviews_on_user_id"
  end

  create_table "invites", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.bigint "invited_by_id", null: false
    t.bigint "redeemed_by_id"
    t.string "email"
    t.string "token", null: false
    t.string "role", default: "contributor", null: false
    t.datetime "expires_at"
    t.datetime "redeemed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "revoked_at"
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

  create_table "library_uploads", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.bigint "uploaded_by_id", null: false
    t.string "folder_name", null: false
    t.string "relative_path", null: false
    t.string "filename", null: false
    t.bigint "byte_size", null: false
    t.bigint "byte_offset", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "status"], name: "index_library_uploads_on_library_id_and_status"
    t.index ["library_id"], name: "index_library_uploads_on_library_id"
    t.index ["uploaded_by_id"], name: "index_library_uploads_on_uploaded_by_id"
  end

  create_table "likes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "vibe_model_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "vibe_model_id"], name: "index_likes_on_user_id_and_vibe_model_id", unique: true
    t.index ["user_id"], name: "index_likes_on_user_id"
    t.index ["vibe_model_id"], name: "index_likes_on_vibe_model_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "library_id", null: false
    t.string "role", default: "contributor", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id"], name: "index_memberships_on_library_id"
    t.index ["user_id", "library_id"], name: "index_memberships_on_user_id_and_library_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "model_merges", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.bigint "target_vibe_model_id", null: false
    t.bigint "performed_by_id"
    t.string "kind", null: false
    t.jsonb "parts", default: [], null: false
    t.jsonb "result", default: {}, null: false
    t.datetime "split_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "target_vibe_model_id"], name: "index_model_merges_on_library_id_and_target_vibe_model_id"
    t.index ["library_id"], name: "index_model_merges_on_library_id"
    t.index ["performed_by_id"], name: "index_model_merges_on_performed_by_id"
    t.index ["target_vibe_model_id"], name: "index_model_merges_on_target_vibe_model_id"
  end

  create_table "print_dispatches", force: :cascade do |t|
    t.bigint "vibe_model_id"
    t.bigint "asset_id"
    t.bigint "requested_by_id", null: false
    t.string "status", default: "queued", null: false
    t.string "printer_hint"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "library_id"
    t.bigint "printer_id"
    t.integer "progress", default: 0, null: false
    t.string "protocol_type"
    t.string "filename"
    t.string "remote_ref"
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.index ["asset_id"], name: "index_print_dispatches_on_asset_id"
    t.index ["library_id", "status"], name: "index_print_dispatches_on_library_id_and_status"
    t.index ["library_id"], name: "index_print_dispatches_on_library_id"
    t.index ["printer_id", "created_at"], name: "index_print_dispatches_on_printer_id_and_created_at"
    t.index ["printer_id"], name: "index_print_dispatches_on_printer_id"
    t.index ["requested_by_id"], name: "index_print_dispatches_on_requested_by_id"
    t.index ["vibe_model_id"], name: "index_print_dispatches_on_vibe_model_id"
  end

  create_table "printers", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.string "name", null: false
    t.string "host", null: false
    t.string "protocol_type", default: "mock", null: false
    t.boolean "enabled", default: true, null: false
    t.text "notes"
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "enabled"], name: "index_printers_on_library_id_and_enabled"
    t.index ["library_id", "name"], name: "index_printers_on_library_id_and_name", unique: true
    t.index ["library_id"], name: "index_printers_on_library_id"
  end

  create_table "scan_cursors", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.string "path_prefix", null: false
    t.datetime "last_mtime"
    t.bigint "last_byte_size"
    t.datetime "last_scanned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "last_inode"
    t.integer "last_nlink"
    t.datetime "last_dir_mtime"
    t.integer "last_file_count"
    t.datetime "last_deep_scanned_at"
    t.string "resume_relative_path"
    t.index ["library_id", "path_prefix"], name: "index_scan_cursors_on_library_id_and_path_prefix", unique: true
    t.index ["library_id"], name: "index_scan_cursors_on_library_id"
  end

  create_table "scan_runs", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.bigint "triggered_by_id"
    t.string "status", default: "queued", null: false
    t.string "trigger", default: "job", null: false
    t.string "phase", default: "walk", null: false
    t.string "path_prefix"
    t.string "resume_after"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "folders_seen", default: 0, null: false
    t.integer "folders_indexed", default: 0, null: false
    t.integer "folders_skipped", default: 0, null: false
    t.integer "files_seen", default: 0, null: false
    t.integer "files_changed", default: 0, null: false
    t.integer "pruned_count", default: 0, null: false
    t.integer "error_count", default: 0, null: false
    t.integer "deep_walks", default: 0, null: false
    t.boolean "budget_exhausted", default: false, null: false
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "started_at"], name: "index_scan_runs_on_library_id_and_started_at"
    t.index ["library_id", "status"], name: "index_scan_runs_on_library_id_and_status"
    t.index ["library_id"], name: "index_scan_runs_on_library_id"
    t.index ["triggered_by_id"], name: "index_scan_runs_on_triggered_by_id"
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
    t.bigint "uploaded_by_id"
    t.bigint "creator_id"
    t.string "cover_status", default: "missing", null: false
    t.string "cover_url"
    t.boolean "cover_placeholder", default: true, null: false
    t.string "cover_cache_key"
    t.bigint "cover_asset_id"
    t.index ["cover_cache_key"], name: "index_vibe_models_on_cover_cache_key"
    t.index ["cover_status"], name: "index_vibe_models_on_cover_status"
    t.index ["creator_id"], name: "index_vibe_models_on_creator_id"
    t.index ["library_id", "folder_name"], name: "index_vibe_models_on_library_id_and_folder_name", unique: true
    t.index ["library_id", "updated_at", "id"], name: "index_vibe_models_on_library_id_and_updated_at_and_id"
    t.index ["library_id"], name: "index_vibe_models_on_library_id"
    t.index ["uploaded_by_id"], name: "index_vibe_models_on_uploaded_by_id"
  end

  add_foreign_key "access_tokens", "users"
  add_foreign_key "archive_members", "assets"
  add_foreign_key "assets", "users", column: "uploaded_by_id"
  add_foreign_key "assets", "vibe_models"
  add_foreign_key "bookmark_folders", "users"
  add_foreign_key "bookmarks", "bookmark_folders"
  add_foreign_key "bookmarks", "users"
  add_foreign_key "bookmarks", "vibe_models"
  add_foreign_key "curation_proposals", "libraries"
  add_foreign_key "curation_proposals", "users", column: "reviewed_by_id"
  add_foreign_key "duplicate_group_members", "assets"
  add_foreign_key "duplicate_group_members", "duplicate_groups"
  add_foreign_key "duplicate_group_members", "vibe_models"
  add_foreign_key "duplicate_groups", "libraries"
  add_foreign_key "duplicate_reviews", "duplicate_groups"
  add_foreign_key "duplicate_reviews", "users"
  add_foreign_key "invites", "libraries"
  add_foreign_key "invites", "users", column: "invited_by_id"
  add_foreign_key "library_uploads", "libraries"
  add_foreign_key "library_uploads", "users", column: "uploaded_by_id"
  add_foreign_key "likes", "users"
  add_foreign_key "likes", "vibe_models"
  add_foreign_key "memberships", "libraries"
  add_foreign_key "memberships", "users"
  add_foreign_key "model_merges", "libraries"
  add_foreign_key "model_merges", "users", column: "performed_by_id"
  add_foreign_key "model_merges", "vibe_models", column: "target_vibe_model_id"
  add_foreign_key "print_dispatches", "assets"
  add_foreign_key "print_dispatches", "libraries"
  add_foreign_key "print_dispatches", "printers"
  add_foreign_key "print_dispatches", "users", column: "requested_by_id"
  add_foreign_key "print_dispatches", "vibe_models"
  add_foreign_key "printers", "libraries"
  add_foreign_key "scan_cursors", "libraries"
  add_foreign_key "scan_runs", "libraries"
  add_foreign_key "scan_runs", "users", column: "triggered_by_id"
  add_foreign_key "tag_assignments", "tags"
  add_foreign_key "vibe_models", "creators"
  add_foreign_key "vibe_models", "libraries"
  add_foreign_key "vibe_models", "users", column: "uploaded_by_id"
end
