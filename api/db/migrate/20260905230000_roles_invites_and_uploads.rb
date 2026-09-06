class RolesInvitesAndUploads < ActiveRecord::Migration[8.0]
  def change
    change_column_null :invites, :email, true
    change_column_default :invites, :role, from: "friend", to: "contributor"
    change_column_default :memberships, :role, from: "friend", to: "contributor"
    add_column :invites, :revoked_at, :datetime

    reversible do |dir|
      dir.up do
        execute "UPDATE memberships SET role = 'contributor' WHERE role = 'friend'"
        execute "UPDATE invites SET role = 'contributor' WHERE role = 'friend'"
      end
      dir.down do
        execute "UPDATE memberships SET role = 'friend' WHERE role = 'contributor'"
        execute "UPDATE invites SET role = 'friend' WHERE role = 'contributor'"
      end
    end

    add_reference :vibe_models, :uploaded_by, foreign_key: { to_table: :users }
    add_reference :assets, :uploaded_by, foreign_key: { to_table: :users }

    create_table :library_uploads do |t|
      t.references :library, null: false, foreign_key: true
      t.references :uploaded_by, null: false, foreign_key: { to_table: :users }
      t.string :folder_name, null: false
      t.string :relative_path, null: false
      t.string :filename, null: false
      t.bigint :byte_size, null: false
      t.bigint :byte_offset, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.datetime :completed_at
      t.timestamps
    end
    add_index :library_uploads, %i[library_id status]
  end
end
