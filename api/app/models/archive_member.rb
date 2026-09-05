class ArchiveMember < ApplicationRecord
  belongs_to :asset

  validates :internal_path, presence: true, uniqueness: { scope: :asset_id }

  def previewable?
    %w[stl obj 3mf png jpg jpeg webp txt md].include?(extension)
  end

  def extension
    File.extname(internal_path).delete(".").downcase
  end
end
