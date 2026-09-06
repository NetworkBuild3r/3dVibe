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

  MEMBER_INCLUDES = {
    asset: { vibe_model: VibeModel::CARD_INCLUDES },
    archive_member: { asset: { vibe_model: VibeModel::CARD_INCLUDES } }
  }.freeze

  belongs_to :library
  has_many :duplicate_group_members, dependent: :destroy
  has_many :assets, through: :duplicate_group_members
  has_many :archive_members, through: :duplicate_group_members
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
    records = duplicate_group_members.includes(MEMBER_INCLUDES).to_a
    members = records.map { |row| serialize_member(row) }.sort_by { |row| member_sort_key(row) }
    asset_rows = records.filter_map(&:asset)
    archive_rows = records.filter_map(&:archive_member)
    sample_asset = asset_rows.min_by { |asset| [asset.vibe_model.title, asset.relative_path, asset.id] }
    sample_member = archive_rows.min_by { |member| [member.asset.vibe_model.title, member.internal_path, member.id] }
    models = (asset_rows.map(&:vibe_model) + archive_rows.map { |member| member.asset.vibe_model }).uniq
    {
      id: id,
      library_id: library_id,
      reason: reason,
      confidence: confidence,
      digest: digest,
      status: status,
      filename: sample_asset&.filename || sample_member&.basename,
      byte_size: sample_asset&.byte_size || sample_member&.uncompressed_size,
      members: members,
      assets: asset_rows.sort_by { |asset| [asset.vibe_model.title, asset.relative_path, asset.id] }.map { |asset| serialize_asset(asset) },
      models: VibeModel.card_payloads(models, viewer: viewer),
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def serialize_member(row)
    if row.archive_member?
      serialize_archive_member(row.archive_member)
    else
      serialize_loose_member(row.asset)
    end
  end

  def serialize_loose_member(asset)
    model = asset.vibe_model
    {
      kind: "asset",
      mergeable: true,
      id: asset.id,
      asset_id: asset.id,
      archive_member_id: nil,
      filename: asset.filename,
      relative_path: asset.relative_path,
      member_path: nil,
      archive_path: nil,
      parent_asset_id: nil,
      parent_filename: nil,
      file_kind: asset.kind,
      byte_size: asset.byte_size,
      content_digest: asset.content_digest,
      geometry_digest: asset.geometry_digest,
      model_id: asset.vibe_model_id,
      model_title: model.title,
      folder_name: model.folder_name,
      cover_status: model.cover_status,
      cover_url: model.cover_url,
      cover_placeholder: model.cover_placeholder
    }
  end

  def serialize_archive_member(member)
    asset = member.asset
    model = asset.vibe_model
    {
      kind: "archive_member",
      mergeable: false,
      id: member.id,
      asset_id: asset.id,
      archive_member_id: member.id,
      filename: member.basename,
      relative_path: asset.relative_path,
      member_path: member.internal_path,
      archive_path: member.archive_path,
      parent_asset_id: asset.id,
      parent_filename: asset.filename,
      file_kind: member.extension,
      byte_size: member.uncompressed_size,
      content_digest: nil,
      geometry_digest: member.geometry_digest,
      model_id: model.id,
      model_title: model.title,
      folder_name: model.folder_name,
      cover_status: model.cover_status,
      cover_url: model.cover_url,
      cover_placeholder: model.cover_placeholder
    }
  end

  def member_sort_key(row)
    [
      row[:kind].to_s,
      row[:model_title].to_s,
      row[:archive_path].presence || row[:relative_path].to_s,
      row[:id].to_i
    ]
  end

  def serialize_asset(asset)
    {
      id: asset.id,
      filename: asset.filename,
      relative_path: asset.relative_path,
      kind: asset.kind,
      byte_size: asset.byte_size,
      content_digest: asset.content_digest,
      geometry_digest: asset.geometry_digest,
      mergeable: true,
      model_id: asset.vibe_model_id,
      model_title: asset.vibe_model.title,
      folder_name: asset.vibe_model.folder_name,
      cover_status: asset.vibe_model.cover_status,
      cover_url: asset.vibe_model.cover_url,
      cover_placeholder: asset.vibe_model.cover_placeholder
    }
  end
end
