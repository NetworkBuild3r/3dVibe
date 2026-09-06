class EnablePgTrgmForGallerySearch < ActiveRecord::Migration[8.0]
  def change
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :vibe_models, :title, using: :gin, opclass: :gin_trgm_ops,
              name: "index_vibe_models_on_title_trgm"
    add_index :vibe_models, :folder_name, using: :gin, opclass: :gin_trgm_ops,
              name: "index_vibe_models_on_folder_name_trgm"
    add_index :vibe_models, :synopsis, using: :gin, opclass: :gin_trgm_ops,
              name: "index_vibe_models_on_synopsis_trgm"
    add_index :tags, :name, using: :gin, opclass: :gin_trgm_ops,
              name: "index_tags_on_name_trgm"
    add_index :creators, :name, using: :gin, opclass: :gin_trgm_ops,
              name: "index_creators_on_name_trgm"
    add_index :creators, :slug, using: :gin, opclass: :gin_trgm_ops,
              name: "index_creators_on_slug_trgm"
    add_index :users, :display_name, using: :gin, opclass: :gin_trgm_ops,
              name: "index_users_on_display_name_trgm"
    add_index :assets, :filename, using: :gin, opclass: :gin_trgm_ops,
              name: "index_assets_on_filename_trgm"
    add_index :assets, :relative_path, using: :gin, opclass: :gin_trgm_ops,
              name: "index_assets_on_relative_path_trgm"
    add_index :archive_members, :internal_path, using: :gin, opclass: :gin_trgm_ops,
              name: "index_archive_members_on_internal_path_trgm"
  end
end
