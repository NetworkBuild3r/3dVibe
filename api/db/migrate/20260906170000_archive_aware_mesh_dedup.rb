class ArchiveAwareMeshDedup < ActiveRecord::Migration[8.0]
  def change
    add_column :archive_members, :geometry_digest, :string
    add_index :archive_members, :geometry_digest

    change_column_null :duplicate_group_members, :asset_id, true
    add_reference :duplicate_group_members, :archive_member,
                  null: true,
                  foreign_key: { on_delete: :cascade }

    remove_index :duplicate_group_members, name: "idx_dup_group_members_on_group_and_asset"
    add_index :duplicate_group_members, %i[duplicate_group_id asset_id],
              unique: true,
              where: "asset_id IS NOT NULL",
              name: "idx_dup_group_members_on_group_and_asset"
    add_index :duplicate_group_members, %i[duplicate_group_id archive_member_id],
              unique: true,
              where: "archive_member_id IS NOT NULL",
              name: "idx_dup_group_members_on_group_and_member"

    add_check_constraint :duplicate_group_members,
                         "(asset_id IS NOT NULL AND archive_member_id IS NULL) OR (asset_id IS NULL AND archive_member_id IS NOT NULL)",
                         name: "dup_group_members_asset_xor_archive_member"
  end
end
