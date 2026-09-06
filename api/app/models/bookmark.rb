class Bookmark < ApplicationRecord
  belongs_to :user
  belongs_to :vibe_model
  belongs_to :bookmark_folder

  validates :vibe_model_id, uniqueness: { scope: :bookmark_folder_id }
  validate :folder_belongs_to_user

  def as_api
    {
      id: id,
      model_id: vibe_model_id,
      bookmark_folder_id: bookmark_folder_id,
      created_at: created_at
    }
  end

  private

  def folder_belongs_to_user
    return if bookmark_folder.blank? || bookmark_folder.user_id == user_id

    errors.add(:bookmark_folder, "must belong to the same user")
  end
end
