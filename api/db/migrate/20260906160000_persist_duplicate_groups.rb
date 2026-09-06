class PersistDuplicateGroups < ActiveRecord::Migration[8.0]
  def change
    add_column :assets, :geometry_digest, :string
    add_index :assets, :geometry_digest

    create_table :duplicate_groups do |t|
      t.references :library, null: false, foreign_key: true
      t.string :reason, null: false
      t.string :confidence, null: false
      t.string :digest
      t.string :status, null: false, default: "open"
      t.timestamps
    end
    add_index :duplicate_groups, %i[library_id status]

    create_table :duplicate_group_members do |t|
      t.references :duplicate_group, null: false, foreign_key: true
      t.references :asset, null: false, foreign_key: true
      t.references :vibe_model, foreign_key: true
      t.timestamps
    end
    add_index :duplicate_group_members, %i[duplicate_group_id asset_id],
              unique: true, name: "idx_dup_group_members_on_group_and_asset"

    create_table :duplicate_reviews do |t|
      t.references :duplicate_group, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :decision, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
  end
end
