class Tag < ApplicationRecord
  has_many :tag_assignments, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_validation { self.name = name.to_s.strip.downcase }
end
