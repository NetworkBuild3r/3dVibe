class PersonalCatalogAndPrintPrivacy < ActiveRecord::Migration[8.0]
  def change
    create_table :likes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :vibe_model, null: false, foreign_key: true
      t.timestamps
    end
    add_index :likes, %i[user_id vibe_model_id], unique: true

    create_table :bookmark_folders do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :bookmark_folders, %i[user_id name], unique: true

    create_table :bookmarks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :vibe_model, null: false, foreign_key: true
      t.references :bookmark_folder, null: false, foreign_key: true
      t.timestamps
    end
    add_index :bookmarks, %i[bookmark_folder_id vibe_model_id], unique: true
    add_index :bookmarks, %i[user_id vibe_model_id]

    create_table :model_merges do |t|
      t.references :library, null: false, foreign_key: true
      t.references :target_vibe_model, null: false, foreign_key: { to_table: :vibe_models }
      t.bigint :performed_by_id
      t.string :kind, null: false
      t.jsonb :parts, default: [], null: false
      t.jsonb :result, default: {}, null: false
      t.datetime :split_at
      t.timestamps
    end
    add_index :model_merges, :performed_by_id
    add_index :model_merges, %i[library_id target_vibe_model_id]
    add_foreign_key :model_merges, :users, column: :performed_by_id
  end
end
