class User < ApplicationRecord
  has_secure_password

  has_many :access_tokens, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :libraries, through: :memberships
  has_many :invites_sent, class_name: "Invite", foreign_key: :invited_by_id, inverse_of: :invited_by, dependent: :nullify

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :display_name, presence: true

  before_validation :normalize_email

  def owner_of?(library)
    memberships.exists?(library: library, role: Membership::OWNER)
  end

  def member_of?(library)
    memberships.exists?(library: library)
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
