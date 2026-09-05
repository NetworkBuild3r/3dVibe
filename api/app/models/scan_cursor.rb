class ScanCursor < ApplicationRecord
  belongs_to :library

  validates :path_prefix, presence: true, uniqueness: { scope: :library_id }

  def stale?(mtime:, byte_size:)
    last_mtime.blank? || last_byte_size != byte_size || last_mtime.to_i != mtime.to_i
  end

  def remember!(mtime:, byte_size:)
    update!(
      last_mtime: Time.at(mtime.to_i),
      last_byte_size: byte_size,
      last_scanned_at: Time.current
    )
  end
end
