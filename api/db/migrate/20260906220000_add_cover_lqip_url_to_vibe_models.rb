class AddCoverLqipUrlToVibeModels < ActiveRecord::Migration[8.0]
  def change
    add_column :vibe_models, :cover_lqip_url, :string
  end
end
