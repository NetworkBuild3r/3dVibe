class Printer < ApplicationRecord
  MOCK = "mock"
  SDCP = "sdcp"
  PROTOCOL_TYPES = [MOCK, SDCP].freeze
  DEFAULT_SDCP_PORT = 3030
  HOST_PATTERN = /\A(?:(?:\d{1,3}\.){3}\d{1,3}|[A-Za-z0-9](?:[A-Za-z0-9_\-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9_\-]{0,61}[A-Za-z0-9])?)*|\[[0-9A-Fa-f:]+\])(?::([1-9]\d{0,4}))?\z/

  belongs_to :library
  has_many :print_dispatches, dependent: :nullify

  before_validation :normalize_printer

  validates :name, presence: true, uniqueness: { scope: :library_id }
  validates :host, presence: true
  validates :protocol_type, presence: true, inclusion: { in: PROTOCOL_TYPES }
  validates :enabled, inclusion: { in: [true, false] }
  validate :host_is_lan_endpoint
  validate :settings_shape

  scope :enabled, -> { where(enabled: true) }
  scope :by_name, -> { order(:name) }

  def mock?
    protocol_type == MOCK
  end

  def sdcp?
    protocol_type == SDCP
  end

  def endpoint_host
    parsed_host_and_port[0]
  end

  def endpoint_port
    setting = settings.is_a?(Hash) ? settings["port"].presence : nil
    return Integer(setting) if setting.present?

    parsed_host_and_port[1] || ENV.fetch("VIBE_SDCP_PORT", DEFAULT_SDCP_PORT.to_s).to_i
  end

  def sdcp_token
    from_settings = settings.is_a?(Hash) ? settings["token"].presence : nil
    from_settings || ENV["VIBE_SDCP_TOKEN"].presence
  end

  def sdcp_mainboard_id
    settings.is_a?(Hash) ? settings["mainboard_id"].to_s : ""
  end

  def sdcp_client_id
    from_settings = settings.is_a?(Hash) ? settings["client_id"].presence : nil
    from_settings || ENV["VIBE_SDCP_CLIENT_ID"].presence || "3dvibe-sdcp"
  end

  def sdcp_timeout(default = ENV.fetch("VIBE_PRINT_TIMEOUT", "15").to_i)
    from_settings = settings.is_a?(Hash) ? settings["timeout"].presence : nil
    return Integer(from_settings) if from_settings.present?

    ENV.fetch("VIBE_SDCP_TIMEOUT", default.to_s).to_i
  end

  def sdcp_stub?
    return false unless Rails.env.test?

    flag = settings.is_a?(Hash) ? settings["stub"] : nil
    ActiveModel::Type::Boolean.new.cast(flag) || ActiveModel::Type::Boolean.new.cast(ENV["VIBE_SDCP_STUB"])
  end

  private

  def normalize_printer
    self.name = name.to_s.strip
    self.host = host.to_s.strip
    self.protocol_type = protocol_type.to_s.strip.downcase
    self.enabled = true if enabled.nil?
    self.settings = {} if settings.nil?
  end

  def host_is_lan_endpoint
    value = host.to_s
    if value.match?(%r{\A(?:https?|wss?)://}i) || value.include?("/")
      errors.add(:host, "must be a hostname or IP (no URL)")
      return
    end
    unless value.match?(HOST_PATTERN)
      errors.add(:host, "must be a hostname or IP (no URL)")
      return
    end

    _name, port = parsed_host_and_port
    errors.add(:host, "port must be 1-65535") if port && !port.between?(1, 65_535)
  end

  def settings_shape
    unless settings.is_a?(Hash)
      errors.add(:settings, "must be an object")
      return
    end

    if settings.key?("port") && settings["port"].present?
      port = Integer(settings["port"], exception: false)
      errors.add(:settings, "port must be 1-65535") unless port&.between?(1, 65_535)
    end
    if settings.key?("timeout") && settings["timeout"].present?
      timeout = Float(settings["timeout"], exception: false)
      errors.add(:settings, "timeout must be a positive number") unless timeout&.positive?
    end
  end

  def parsed_host_and_port
    value = host.to_s.strip
    if value.start_with?("[") && value =~ /\A\[([0-9A-Fa-f:]+)\](?::(\d+))?\z/
      return [Regexp.last_match(1), Regexp.last_match(2)&.to_i]
    end
    if value =~ /\A(.+):(\d+)\z/ && !value.start_with?("[") && value.count(":") == 1
      return [Regexp.last_match(1), Regexp.last_match(2).to_i]
    end

    [value, nil]
  end
end
