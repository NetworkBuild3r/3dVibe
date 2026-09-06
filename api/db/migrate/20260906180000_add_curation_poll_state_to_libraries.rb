class AddCurationPollStateToLibraries < ActiveRecord::Migration[8.0]
  def change
    add_column :libraries, :last_polled_at, :datetime
    add_column :libraries, :last_provider, :string
    add_column :libraries, :last_error, :text
  end
end
