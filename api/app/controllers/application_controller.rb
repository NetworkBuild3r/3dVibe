class ApplicationController < ActionController::API
  before_action :authenticate!

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable

  private

  def authenticate!
    token = bearer_token
    @current_token = AccessToken.active.find_by(token: token) if token.present?
    render json: { error: "unauthorized" }, status: :unauthorized and return unless @current_token

    @current_user = @current_token.user
  end

  def current_user
    @current_user
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    header.split(" ", 2).last if header.start_with?("Bearer ")
  end

  def accessible_libraries
    current_user.libraries
  end

  def accessible_models
    VibeModel.where(library_id: accessible_libraries.select(:id))
  end

  def not_found
    render json: { error: "not_found" }, status: :not_found
  end

  def unprocessable(exception)
    render json: { error: "invalid", details: exception.record.errors.full_messages }, status: :unprocessable_entity
  end

  def require_owner!(library)
    return if current_user.owner_of?(library)

    render json: { error: "forbidden" }, status: :forbidden
  end
end
