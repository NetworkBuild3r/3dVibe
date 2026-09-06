class Creator < ApplicationRecord
  SOURCE_NFS = "nfs_hint"
  SOURCE_MANUAL = "manual"
  SOURCES = [SOURCE_NFS, SOURCE_MANUAL].freeze

  has_many :vibe_models, dependent: :nullify

  validates :slug, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  validates :source, inclusion: { in: SOURCES }, allow_nil: true

  before_validation :normalize_identity

  scope :ordered, -> { order(:name, :id) }

  def as_api(model_count: nil)
    payload = {
      id: id,
      slug: slug,
      name: name,
      source: source
    }
    payload[:model_count] = model_count unless model_count.nil?
    payload
  end

  def as_card
    { id: id, slug: slug, name: name }
  end

  private

  def normalize_identity
    self.slug = slug.to_s.strip.downcase
    self.name = name.to_s.strip
    self.source = source.to_s.strip.presence
  end
end
