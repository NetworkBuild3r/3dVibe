class AccessToken < ApplicationRecord
  belongs_to :user

  has_secure_token :token

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end
