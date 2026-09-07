# Site-scoped owner curator settings (one row per install).
# Env vars remain compose/CI fallbacks; persisted values override when present.
class CuratorSetting < ApplicationRecord
  STUB = "stub"
  OLLAMA = "ollama"
  XAI = "xai"
  OPENAI = "openai"
  ANTHROPIC = "anthropic"
  PROVIDERS = [STUB, OLLAMA, XAI, OPENAI, ANTHROPIC].freeze
  SECRET_ATTRIBUTES = %i[xai_api_key openai_api_key anthropic_api_key].freeze
  DEFAULT_PROVIDER = OLLAMA
  DEFAULT_OLLAMA_MODEL = "gemma4"
  SINGLETON_LOCK = 1

  encrypts :xai_api_key, :openai_api_key, :anthropic_api_key
  self.filter_attributes += SECRET_ATTRIBUTES

  validates :provider, inclusion: { in: PROVIDERS }
  validates :singleton_lock, uniqueness: true

  before_validation :normalize_fields
  before_validation :assign_singleton_lock
  before_validation :apply_create_defaults, on: :create

  def self.instance
    order(:id).first
  end

  def self.instance!
    instance || create!(singleton_lock: SINGLETON_LOCK)
  end

  # Seed / migrate helper: create the singleton, or fill blank fields only.
  def self.ensure_defaults!
    setting = instance
    return create!(
      provider: DEFAULT_PROVIDER,
      ollama_model: DEFAULT_OLLAMA_MODEL,
      singleton_lock: SINGLETON_LOCK
    ) if setting.nil?

    updates = {}
    updates[:provider] = DEFAULT_PROVIDER if setting.provider.blank?
    updates[:ollama_model] = DEFAULT_OLLAMA_MODEL if setting.ollama_model.blank?
    setting.update!(updates) if updates.any?
    setting
  end

  def xai_api_key_status
    secret_status(xai_api_key)
  end

  def openai_api_key_status
    secret_status(openai_api_key)
  end

  def anthropic_api_key_status
    secret_status(anthropic_api_key)
  end

  def as_api
    {
      provider: provider,
      ollama_url: ollama_url,
      ollama_model: ollama_model,
      xai_api_key_status: xai_api_key_status,
      openai_api_key_status: openai_api_key_status,
      anthropic_api_key_status: anthropic_api_key_status
    }
  end

  def as_json(options = nil)
    super(options)
      .except(*SECRET_ATTRIBUTES.map(&:to_s), *SECRET_ATTRIBUTES)
      .merge(
        "xai_api_key_status" => xai_api_key_status,
        "openai_api_key_status" => openai_api_key_status,
        "anthropic_api_key_status" => anthropic_api_key_status
      )
  end

  private

  def secret_status(value)
    value.present? ? "set" : "missing"
  end

  def normalize_fields
    self.provider = provider.to_s.strip.downcase
    self.ollama_url = ollama_url.to_s.strip.presence
    self.ollama_model = ollama_model.to_s.strip.presence
    SECRET_ATTRIBUTES.each do |attribute|
      self[attribute] = self[attribute].to_s.strip.presence
    end
  end

  def apply_create_defaults
    self.provider = DEFAULT_PROVIDER if provider.blank?
    self.ollama_model = DEFAULT_OLLAMA_MODEL if ollama_model.blank?
  end

  def assign_singleton_lock
    self.singleton_lock = SINGLETON_LOCK
  end
end
