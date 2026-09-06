class NFSScanHardening < ActiveRecord::Migration[8.0]
  def change
    add_column :scan_cursors, :last_inode, :bigint
    add_column :scan_cursors, :last_nlink, :integer
    add_column :scan_cursors, :last_dir_mtime, :datetime
    add_column :scan_cursors, :last_file_count, :integer
    add_column :scan_cursors, :last_deep_scanned_at, :datetime
    add_column :scan_cursors, :resume_relative_path, :string

    add_column :assets, :inode, :bigint

    create_table :scan_runs do |t|
      t.references :library, null: false, foreign_key: true
      t.references :triggered_by, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "queued"
      t.string :trigger, null: false, default: "job"
      t.string :phase, null: false, default: "walk"
      t.string :path_prefix
      t.string :resume_after
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :folders_seen, default: 0, null: false
      t.integer :folders_indexed, default: 0, null: false
      t.integer :folders_skipped, default: 0, null: false
      t.integer :files_seen, default: 0, null: false
      t.integer :files_changed, default: 0, null: false
      t.integer :pruned_count, default: 0, null: false
      t.integer :error_count, default: 0, null: false
      t.integer :deep_walks, default: 0, null: false
      t.boolean :budget_exhausted, default: false, null: false
      t.text :last_error
      t.timestamps
    end
    add_index :scan_runs, %i[library_id started_at]
    add_index :scan_runs, %i[library_id status]
  end
end
