class LibraryUpload < ApplicationRecord
  PENDING = "pending"
  COMPLETED = "completed"
  FAILED = "failed"
  STATUSES = [PENDING, COMPLETED, FAILED].freeze

  belongs_to :library
  belongs_to :uploaded_by, class_name: "User"

  validates :folder_name, :relative_path, :filename, presence: true
  validates :byte_size, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }

  def pending?
    status == PENDING
  end

  def completed?
    status == COMPLETED
  end

  def incoming_path
    LibraryPathJail.new(library.root_path).incoming_dir.join(id.to_s)
  end

  def destination_path
    LibraryPathJail.new(library.root_path).join(folder_name, relative_path)
  end
end
