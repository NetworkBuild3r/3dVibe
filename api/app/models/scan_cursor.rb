class ScanCursor < ApplicationRecord
  belongs_to :library

  validates :path_prefix, presence: true, uniqueness: { scope: :library_id }

  # Content fingerprint: max file mtime + total size. NFS often has 1s mtime
  # resolution, so size (and inode on the folder identity) must also change.
  def stale?(mtime:, byte_size:, file_count: nil)
    last_mtime.blank? ||
      last_byte_size.to_i != byte_size.to_i ||
      last_mtime.to_i != mtime.to_i ||
      (file_count && last_file_count.present? && last_file_count.to_i != file_count.to_i)
  end

  def identity_stale?(stat)
    last_dir_mtime.blank? ||
      last_inode.to_i != stat.ino.to_i ||
      last_nlink.to_i != stat.nlink.to_i ||
      last_dir_mtime.to_i != stat.mtime.to_i
  end

  def skip_deep_walk?(stat)
    return false if resume_relative_path.present?
    return false unless ScanSettings.trust_dir_mtime?
    return false if identity_stale?(stat)
    return false if last_deep_scanned_at.blank?

    last_deep_scanned_at > ScanSettings.deep_interval.seconds.ago
  end

  def remember!(mtime:, byte_size:, file_count: nil, dir_stat: nil)
    attrs = {
      last_mtime: Time.at(mtime.to_i),
      last_byte_size: byte_size,
      last_file_count: file_count,
      last_scanned_at: Time.current,
      last_deep_scanned_at: Time.current,
      resume_relative_path: nil
    }
    if dir_stat
      attrs[:last_inode] = dir_stat.ino
      attrs[:last_nlink] = dir_stat.nlink
      attrs[:last_dir_mtime] = dir_stat.mtime
    end
    update!(attrs)
  end
end
