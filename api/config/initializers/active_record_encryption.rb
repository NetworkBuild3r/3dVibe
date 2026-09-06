# Active Record encryption for CuratorSetting#xai_api_key (and future secrets).
#
# Resolution:
#   1. VIBE_ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
#      VIBE_ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
#      VIBE_ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
#   2. Rails credentials: active_record_encryption.{primary_key,deterministic_key,key_derivation_salt}
#   3. Deterministic CI/dev keys (never use these in production)
#
# Generate production keys with `bin/rails db:encryption:init` and put them in
# credentials or compose secrets. Do not commit real keys.
module VibeActiveRecordEncryption
  TEST_PRIMARY_KEY = "vibe-ci-primary-key-32bytes0001"
  TEST_DETERMINISTIC_KEY = "vibe-ci-determ-key-32bytes0002"
  TEST_KEY_DERIVATION_SALT = "vibe-ci-derivation-salt-32b003"

  module_function

  def apply!
    keys = from_env
    keys = from_credentials if keys.values.any?(&:blank?)
    keys = test_defaults if keys.values.any?(&:blank?) && !Rails.env.production?

    Rails.application.config.active_record.encryption.primary_key = keys[:primary_key]
    Rails.application.config.active_record.encryption.deterministic_key = keys[:deterministic_key]
    Rails.application.config.active_record.encryption.key_derivation_salt = keys[:key_derivation_salt]
  end

  def from_env
    {
      primary_key: ENV["VIBE_ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence,
      deterministic_key: ENV["VIBE_ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence,
      key_derivation_salt: ENV["VIBE_ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence
    }
  end

  def from_credentials
    creds = Rails.application.credentials.active_record_encryption
    return { primary_key: nil, deterministic_key: nil, key_derivation_salt: nil } unless creds

    {
      primary_key: creds[:primary_key].presence,
      deterministic_key: creds[:deterministic_key].presence,
      key_derivation_salt: creds[:key_derivation_salt].presence
    }
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError
    { primary_key: nil, deterministic_key: nil, key_derivation_salt: nil }
  end

  def test_defaults
    {
      primary_key: TEST_PRIMARY_KEY,
      deterministic_key: TEST_DETERMINISTIC_KEY,
      key_derivation_salt: TEST_KEY_DERIVATION_SALT
    }
  end
end

VibeActiveRecordEncryption.apply!
