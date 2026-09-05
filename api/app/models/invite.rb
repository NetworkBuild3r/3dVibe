class Invite < ApplicationRecord
  belongs_to :library
  belongs_to :invited_by, class_name: "User"

  has_secure_token :token

  validates :role, inclusion: { in: Membership::ROLES }
  validates :email, presence: true

  scope :pending, -> { where(redeemed_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def pending?
    redeemed_at.nil? && (expires_at.nil? || expires_at > Time.current)
  end

  def redeem!(user)
    raise "Invite already used" unless pending?

    transaction do
      Membership.find_or_create_by!(user: user, library: library) do |membership|
        membership.role = role
      end
      update!(redeemed_at: Time.current, redeemed_by_id: user.id)
    end
  end
end
