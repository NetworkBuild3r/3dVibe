class Create3dvibeSchema < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :display_name, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :access_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.datetime :expires_at
      t.timestamps
    end
    add_index :access_tokens, :token, unique: true

    create_table :libraries do |t|
      t.string :name, null: false
      t.string :root_path, null: false
      t.text :notes
      t.timestamps
    end
    add_index :libraries, :root_path, unique: true

    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :library, null: false, foreign_key: true
      t.string :role, null: false, default: "friend"
      t.timestamps
    end
    add_index :memberships, %i[user_id library_id], unique: true

    create_table :invites do |t|
      t.references :library, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.bigint :redeemed_by_id
      t.string :email, null: false
      t.string :token, null: false
      t.string :role, null: false, default: "friend"
      t.datetime :expires_at
      t.datetime :redeemed_at
      t.timestamps
    end
    add_index :invites, :token, unique: true

    create_table :vibe_models do |t|
      t.references :library, null: false, foreign_key: true
      t.string :folder_name, null: false
      t.string :title, null: false
      t.text :synopsis
      t.integer :asset_count, null: false, default: 0
      t.bigint :byte_size, null: false, default: 0
      t.datetime :folder_mtime
      t.timestamps
    end
    add_index :vibe_models, %i[library_id folder_name], unique: true
    add_index :vibe_models, %i[library_id updated_at id]

    create_table :assets do |t|
      t.references :vibe_model, null: false, foreign_key: true
      t.string :relative_path, null: false
      t.string :filename, null: false
      t.string :kind, null: false, default: "file"
      t.string :content_digest
      t.bigint :byte_size, null: false, default: 0
      t.datetime :mtime
      t.timestamps
    end
    add_index :assets, %i[vibe_model_id relative_path], unique: true
    add_index :assets, :content_digest

    create_table :archive_members do |t|
      t.references :asset, null: false, foreign_key: true
      t.string :internal_path, null: false
      t.bigint :compressed_size
      t.bigint :uncompressed_size
      t.boolean :directory, null: false, default: false
      t.datetime :mtime
      t.timestamps
    end
    add_index :archive_members, %i[asset_id internal_path], unique: true

    create_table :tags do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :tags, :name, unique: true

    create_table :tag_assignments do |t|
      t.references :tag, null: false, foreign_key: true
      t.string :taggable_type, null: false
      t.bigint :taggable_id, null: false
      t.timestamps
    end
    add_index :tag_assignments, %i[taggable_type taggable_id tag_id], unique: true, name: "idx_tag_assignments_unique"

    create_table :curation_proposals do |t|
      t.references :library, null: false, foreign_key: true
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.string :summary, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :sidecar_ref
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :curation_proposals, %i[library_id status]

    create_table :scan_cursors do |t|
      t.references :library, null: false, foreign_key: true
      t.string :path_prefix, null: false
      t.datetime :last_mtime
      t.bigint :last_byte_size
      t.datetime :last_scanned_at
      t.timestamps
    end
    add_index :scan_cursors, %i[library_id path_prefix], unique: true

    create_table :print_dispatches do |t|
      t.references :vibe_model, foreign_key: true
      t.references :asset, foreign_key: true
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "unavailable"
      t.string :printer_hint
      t.text :note
      t.timestamps
    end
  end
end
