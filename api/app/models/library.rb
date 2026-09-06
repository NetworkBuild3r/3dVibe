class Library < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :vibe_models, dependent: :destroy
  has_many :creators, -> { distinct }, through: :vibe_models
  has_many :scan_cursors, dependent: :destroy
  has_many :scan_runs, dependent: :destroy
  has_many :invites, dependent: :destroy
  has_many :curation_proposals, dependent: :destroy
  has_many :library_uploads, dependent: :destroy
  has_many :printers, dependent: :destroy
  has_many :print_dispatches, dependent: :nullify
  has_many :model_merges, dependent: :destroy
  has_many :duplicate_groups, dependent: :destroy

  validates :name, presence: true
  validates :root_path, presence: true

  def owner
    memberships.find_by(role: Membership::OWNER)&.user
  end

  def latest_scan_run
    scan_runs.recent.first
  end

  def current_scan_run
    scan_runs.active.recent.first
  end

  def last_finished_scan_run
    scan_runs.where(status: [ScanRun::COMPLETED, ScanRun::FAILED]).recent.first
  end

  def scan_as_api
    latest_scan_run&.as_api || ScanRun.idle_as_api
  end

  def scan_status_as_api
    {
      scan: scan_as_api,
      current: current_scan_run&.as_api,
      last: last_finished_scan_run&.as_api
    }
  end

  def cover_backlog_as_api
    counts = vibe_models.group(:cover_status).count
    {
      pending: counts[VibeModel::COVER_PENDING].to_i,
      failed: counts[VibeModel::COVER_FAILED].to_i,
      missing: counts[VibeModel::COVER_MISSING].to_i
    }
  end

  def geometry_backlog_as_api
    {
      assets_missing: assets_missing_geometry_digest_count,
      archive_members_missing: archive_members_missing_geometry_digest_count
    }
  end

  def assets_missing_geometry_digest_count
    Asset.joins(:vibe_model)
         .where(vibe_models: { library_id: id })
         .where(kind: GeometryFingerprint::FINGERPRINT_KINDS)
         .where(geometry_digest: [nil, ""])
         .count
  end

  def archive_members_missing_geometry_digest_count
    suffixes = GeometryFingerprint::FINGERPRINT_KINDS.map { |kind| ".#{kind}" }
    ArchiveMember.joins(asset: :vibe_model)
                 .where(vibe_models: { library_id: id })
                 .where(directory: false)
                 .where.not(listing_source: "placeholder")
                 .where.not(internal_path: ArchiveMember::PLACEHOLDER_PATH)
                 .where(geometry_digest: [nil, ""])
                 .where("RIGHT(LOWER(internal_path), 4) IN (?)", suffixes)
                 .count
  end

  def record_curation_poll!(provider:, error: nil)
    update!(
      last_polled_at: Time.current,
      last_provider: provider.to_s.presence,
      last_error: error.present? ? error.to_s.truncate(2_000) : nil
    )
  end

  def curation_as_api
    {
      last_polled_at: last_polled_at,
      last_provider: last_provider,
      last_error: last_error
    }
  end
end
