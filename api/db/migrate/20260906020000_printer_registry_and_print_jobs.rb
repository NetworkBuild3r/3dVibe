class PrinterRegistryAndPrintJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :printers do |t|
      t.references :library, null: false, foreign_key: true
      t.string :name, null: false
      t.string :host, null: false
      t.string :protocol_type, null: false, default: "mock"
      t.boolean :enabled, null: false, default: true
      t.text :notes
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :printers, %i[library_id name], unique: true
    add_index :printers, %i[library_id enabled]

    change_table :print_dispatches do |t|
      t.references :library, foreign_key: true
      t.references :printer, foreign_key: true
      t.integer :progress, null: false, default: 0
      t.string :protocol_type
      t.string :filename
      t.string :remote_ref
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
    end
    add_index :print_dispatches, %i[library_id status]
    add_index :print_dispatches, %i[printer_id created_at]

    change_column_default :print_dispatches, :status, from: "unavailable", to: "queued"
  end
end
