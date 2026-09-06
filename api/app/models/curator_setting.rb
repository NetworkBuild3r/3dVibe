# Site-scoped owner curator settings (one row per install).
# Env vars remain compose/CI fallbacks; persisted values override when present.
class CuratorSetting < ApplicationRecord
  STUB = "stub"
  OLLAMA = "ollama"
  XAI = "xai"
  PROVIDERS = [STUB, OLLAMA, XAI].freeze
  SINGLETON_LOCK = 1

  encrypts :xai_api_key
  self.filter_attributes += %i[xai_api_key]

  validates :provider, inclusion: { in: PROVIDERS }
  validates :singleton_lock, uniqueness: true

  before_validation :normalize_fields
  before_validation :assign_singleton_lock

  def self.instance
    order(:id).first
  end

  def self.instance!
    instance || create!(provider: CuratorRuntime.env_provider, singleton_lock: SINGLETON_LOCK)
  end

  def xai_api_key_status
    xai_api_key.present? ? "set" : "missing"
  end

  def as_api
    {
      provider: provider,
      ollama_url: ollama_url,
      ollama_model: ollama_model,
      xai_api_key_status: xai_api_key_status
    }
  end

  def as_json(options = nil)
    super(options).except("xai_api_key", :xai_api_key).merge("xai_api_key_status" => xai_api_key_status)
  end

  private

  def normalize_fields
    self.provider = provider.to_s.strip.downcase
    self.ollama_url = ollama_url.to_s.strip.presence
    self.ollama_model = ollama_model.to_s.strip.presence
    self.xai_api_key = xai_api_key.to_s.strip.presence
  end

  def assign_singleton_lock
    self.singleton_lock = SINGLETON_LOCK
  end
end
