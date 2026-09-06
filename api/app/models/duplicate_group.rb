class DuplicateGroup < ApplicationRecord
  REASON_CONTENT_HASH = "content_hash"
  REASON_GEOMETRY = "geometry"
  REASON_NAME_SIZE = "name_size"
  REASONS = [REASON_CONTENT_HASH, REASON_GEOMETRY, REASON_NAME_SIZE].freeze

  CONFIDENCE_EXACT = "exact"
  CONFIDENCE_GEOMETRY = "geometry"
  CONFIDENCE_LIKELY = "likely"
  CONFIDENCES = [CONFIDENCE_EXACT, CONFIDENCE_GEOMETRY, CONFIDENCE_LIKELY].freeze

  OPEN = "open"
  KEPT = "kept"
  DISMISSED = "dismissed"
  MERGED = "merged"
  STATUSES = [OPEN, KEPT, DISMISSED, MERGED].freeze
  TERMINAL = [KEPT, DISMISSED, MERGED].freeze

  belongs_to :library
  has_many :duplicate_group_members, dependent: :destroy
  has_many :assets, through: :duplicate_group_members
  has_many :duplicate_reviews, dependent: :destroy

  validates :reason, inclusion: { in: REASONS }
  validates :confidence, inclusion: { in: CONFIDENCES }
  validates :status, inclusion: { in: STATUSES }

  scope :open, -> { where(status: OPEN) }
  scope :terminal, -> { where(status: TERMINAL) }
  scope :recent, -> { order(updated_at: :desc, id: :desc) }

  def open?
    status == OPEN
  end

  def terminal?
    TERMINAL.include?(status)
  end

  def match_key
    self.class.match_key(reason: reason, digest: digest, assets: assets.to_a)
  end

  def self.match_key(reason:, digest:, assets: [])
    if digest.present?
      "#{reason}:#{digest}"
    else
      sample = Array(assets).min_by { |asset| [asset.filename.to_s.downcase, asset.byte_size.to_i, asset.id] }
      filename = sample&.filename.to_s.downcase
      size = sample&.byte_size.to_i
      "#{reason}:#{filename}:#{size}"
    end
  end

  def as_api(viewer: nil)
    records = duplicate_group_members.includes(asset: { vibe_model: VibeModel::CARD_INCLUDES }).to_a
    asset_rows = records.filter_map(&:asset)
    sample = asset_rows.min_by { |asset| [asset.vibe_model.title, asset.relative_path, asset.id] }
    models = asset_rows.map(&:vibe_model).uniq
    {
      id: id,
      library_id: library_id,
      reason: reason,
      confidence: confidence,
      digest: digest,
      status: status,
      filename: sample&.filename,
      byte_size: sample&.byte_size,
      assets: asset_rows.sort_by { |asset| [asset.vibe_model.title, asset.relative_path, asset.id] }.map { |asset| serialize_asset(asset) },
      models: VibeModel.card_payloads(models, viewer: viewer),
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def serialize_asset(asset)
    {
      id: asset.id,
      filename: asset.filename,
      relative_path: asset.relative_path,
      kind: asset.kind,
      byte_size: asset.byte_size,
      content_digest: asset.content_digest,
      geometry_digest: asset.geometry_digest,
      model_id: asset.vibe_model_id,
      model_title: asset.vibe_model.title,
      folder_name: asset.vibe_model.folder_name
    }
  end
end
