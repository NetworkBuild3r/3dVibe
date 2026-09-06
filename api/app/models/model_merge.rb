class ModelMerge < ApplicationRecord
  KINDS = %w[models assets].freeze

  belongs_to :library
  belongs_to :target_vibe_model, class_name: "VibeModel"
  belongs_to :performed_by, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(split_at: nil) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def split?
    split_at.present?
  end

  def as_api
    {
      id: id,
      library_id: library_id,
      target_model_id: target_vibe_model_id,
      target_title: target_vibe_model&.title,
      kind: kind,
      parts: parts,
      result: result,
      split_at: split_at,
      performed_by: performed_by && { id: performed_by.id, display_name: performed_by.display_name },
      created_at: created_at
    }
  end
end
