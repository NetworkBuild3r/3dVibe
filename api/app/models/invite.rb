class Invite < ApplicationRecord
  belongs_to :library
  belongs_to :invited_by, class_name: "User"

  has_secure_token :token

  validates :role, inclusion: { in: Membership::INVITABLE_ROLES }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  ROLE_RANK = {
    Membership::VIEWER => 0,
    Membership::CONTRIBUTOR => 1,
    Membership::OWNER => 2
  }.freeze

  before_validation :normalize_email

  scope :pending, -> { where(redeemed_at: nil, revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def pending?
    redeemed_at.nil? && revoked_at.nil? && (expires_at.nil? || expires_at > Time.current)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def redeem!(user)
    raise "Invite already used" unless pending?

    transaction do
      membership = Membership.find_or_initialize_by(user: user, library: library)
      membership.role = self.class.higher_role(membership.role, role)
      membership.save!
      update!(redeemed_at: Time.current, redeemed_by_id: user.id)
    end
  end

  # Existing members keep the stronger role. A viewer invite must not
  # strip a contributor; a contributor invite must promote a viewer.
  def self.higher_role(current, invited)
    current_rank = ROLE_RANK.fetch(current, -1)
    invited_rank = ROLE_RANK.fetch(invited, -1)
    invited_rank > current_rank ? invited : (current.presence || invited)
  end

  def redeem_path
    "/invite/#{token}"
  end

  private

  def normalize_email
    value = email.to_s.strip.downcase
    self.email = value.presence
  end
end
