class Like < ApplicationRecord
  belongs_to :user
  belongs_to :vibe_model

  validates :user_id, uniqueness: { scope: :vibe_model_id }
end
