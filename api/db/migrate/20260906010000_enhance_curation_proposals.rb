class EnhanceCurationProposals < ActiveRecord::Migration[8.0]
  def change
    add_column :curation_proposals, :applied_at, :datetime
    add_column :curation_proposals, :apply_error, :text
    add_column :curation_proposals, :result, :jsonb, default: {}, null: false

    add_index :curation_proposals, %i[library_id sidecar_ref],
              unique: true,
              where: "sidecar_ref IS NOT NULL AND sidecar_ref <> ''",
              name: "index_curation_proposals_library_sidecar_ref"
  end
end
