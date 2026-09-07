class ExtendCuratorSettingsProviders < ActiveRecord::Migration[8.0]
  def change
    add_column :curator_settings, :openai_api_key, :text
    add_column :curator_settings, :anthropic_api_key, :text
    change_column_default :curator_settings, :provider, from: "stub", to: "ollama"
    change_column_default :curator_settings, :ollama_model, from: nil, to: "gemma4"

    reversible do |dir|
      dir.up do
        say_with_time "seed ollama/gemma4 defaults on blank curator_settings singleton" do
          execute <<~SQL
            UPDATE curator_settings
            SET
              provider = CASE
                WHEN provider IS NULL OR btrim(provider) = '' THEN 'ollama'
                ELSE provider
              END,
              ollama_model = CASE
                WHEN ollama_model IS NULL OR btrim(ollama_model) = '' THEN 'gemma4'
                ELSE ollama_model
              END
          SQL
        end
      end
    end
  end
end
