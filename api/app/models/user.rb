class User < ApplicationRecord
  has_secure_password

  has_many :access_tokens, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :libraries, through: :memberships
  has_many :invites_sent, class_name: "Invite", foreign_key: :invited_by_id, inverse_of: :invited_by, dependent: :nullify
  has_many :library_uploads, foreign_key: :uploaded_by_id, inverse_of: :uploaded_by, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :display_name, presence: true

  before_validation :normalize_email

  def owner_of?(library)
    memberships.exists?(library: library, role: Membership::OWNER)
  end

  def member_of?(library)
    memberships.exists?(library: library)
  end

  def can_upload?(library)
    memberships.exists?(library: library, role: Membership::UPLOAD_ROLES)
  end

  def can_upload_anywhere?
    memberships.exists?(role: Membership::UPLOAD_ROLES)
  end

  def can_curate?(library)
    can_upload?(library)
  end

  def can_curate_anywhere?
    can_upload_anywhere?
  end

  def owner_anywhere?
    memberships.exists?(role: Membership::OWNER)
  end

  def primary_role
    roles = memberships.pluck(:role)
    return Membership::OWNER if roles.include?(Membership::OWNER)
    return Membership::CONTRIBUTOR if roles.include?(Membership::CONTRIBUTOR)

    Membership::VIEWER
  end

  def api_payload
    {
      id: id,
      email: email,
      display_name: display_name,
      role: primary_role,
      can_invite: owner_anywhere?,
      can_upload: can_upload_anywhere?,
      can_curate: can_curate_anywhere?,
      libraries: memberships.includes(:library).map do |membership|
        {
          id: membership.library_id,
          name: membership.library.name,
          role: membership.role
        }
      end
    }
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
