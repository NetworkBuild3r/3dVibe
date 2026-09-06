class CreateCuratorSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :curator_settings do |t|
      t.string :provider, null: false, default: "stub"
      t.string :ollama_url
      t.string :ollama_model
      t.text :xai_api_key
      t.integer :singleton_lock, null: false, default: 1
      t.timestamps
    end

    add_index :curator_settings, :singleton_lock, unique: true
  end
end
