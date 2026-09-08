# INIT-020/SPEC-003 — pack identity is library-relative Category/Pack.
# Unique (library_id, folder_name) already exists from Create3dvibeSchema.
# Up denormalizes category from the first path segment only; it does not invent pack rows.
class PackPathIdentity < ActiveRecord::Migration[8.0]
  def change
    add_column :vibe_models, :category, :string
    add_index :vibe_models, %i[library_id category], name: "index_vibe_models_on_library_id_and_category"

    add_column :libraries, :layout_mode, :string, null: false, default: "category_model"

    reversible do |dir|
      dir.up do
        say_with_time "denormalize vibe_models.category from folder_name first segment (no pack split)" do
          execute <<~SQL
            UPDATE vibe_models
            SET category = split_part(folder_name, '/', 1)
            WHERE category IS NULL
              AND folder_name IS NOT NULL
              AND btrim(folder_name) <> ''
          SQL
        end
        change_column_null :vibe_models, :category, false
      end
      dir.down do
        change_column_null :vibe_models, :category, true
      end
    end
  end
end
