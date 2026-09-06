class DeepArchiveVisibility < ActiveRecord::Migration[8.0]
  def change
    add_column :archive_members, :content_type, :string
    add_column :archive_members, :parent_path, :string, default: "", null: false
    add_column :archive_members, :basename, :string, default: "", null: false
    add_column :archive_members, :preview_digest, :string
    add_column :archive_members, :listing_source, :string, default: "zip", null: false
    add_index :archive_members, %i[asset_id parent_path], name: "index_archive_members_on_asset_id_and_parent_path"
    add_index :archive_members, %i[asset_id basename], name: "index_archive_members_on_asset_id_and_basename"

    add_column :assets, :archive_truncated, :boolean, default: false, null: false
    add_column :assets, :archive_support, :string

    reversible do |dir|
      dir.up { backfill_archive_members }
    end
  end

  def backfill_archive_members
    say_with_time "backfill archive member path fields" do
      ArchiveMember.reset_column_information
      ArchiveMember.find_each do |member|
        path = member.internal_path.to_s.tr("\\", "/")
        parts = path.delete_suffix("/").split("/").reject(&:blank?)
        parent = parts.size > 1 ? "#{parts[0..-2].join("/")}/" : ""
        ext = File.extname(path).delete(".").downcase
        member.update_columns(
          parent_path: parent,
          basename: parts.last.to_s,
          content_type: ArchiveMember.content_type_for(ext),
          listing_source: member.listing_source.presence || "zip"
        )
      end
    end
  end
end
