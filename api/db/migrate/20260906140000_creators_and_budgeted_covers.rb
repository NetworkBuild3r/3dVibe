class CreatorsAndBudgetedCovers < ActiveRecord::Migration[8.0]
  def change
    create_table :creators do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :source
      t.timestamps
    end
    add_index :creators, :slug, unique: true
    add_index :creators, :name

    add_reference :vibe_models, :creator, foreign_key: true
    add_column :vibe_models, :cover_status, :string, null: false, default: "missing"
    add_column :vibe_models, :cover_url, :string
    add_column :vibe_models, :cover_placeholder, :boolean, null: false, default: true
    add_column :vibe_models, :cover_cache_key, :string
    add_column :vibe_models, :cover_asset_id, :bigint
    add_index :vibe_models, :cover_status
    add_index :vibe_models, :cover_cache_key
  end
end
