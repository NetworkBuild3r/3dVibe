class ApplicationController < ActionController::API
  before_action :authenticate!

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable
  rescue_from ArgumentError, with: :bad_request

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

  # One shared catalog: every signed-in user sees every library and model.
  # Membership roles gate write actions (invite / upload), not visibility.
  def accessible_libraries
    Library.all
  end

  def accessible_models
    VibeModel.all
  end

  def not_found
    render json: { error: "not_found" }, status: :not_found
  end

  def unprocessable(exception)
    render json: { error: "invalid", details: exception.record.errors.full_messages }, status: :unprocessable_entity
  end

  def bad_request(exception)
    render json: { error: "invalid", details: [exception.message] }, status: :unprocessable_entity
  end

  def require_owner!(library)
    return if current_user.owner_of?(library)

    render json: { error: "forbidden" }, status: :forbidden
  end

  def require_upload!(library)
    return if current_user.can_upload?(library)

    render json: { error: "forbidden" }, status: :forbidden
  end

  def require_curator!(library)
    return if current_user.can_curate?(library)

    render json: { error: "forbidden" }, status: :forbidden
  end

  def require_print!(library)
    return if current_user.can_print?(library)

    render json: { error: "forbidden" }, status: :forbidden
  end

  def cover_authorized?
    expected = ENV["VIBE_COVER_TOKEN"].to_s
    return false if expected.blank?

    presented = cover_token.to_s
    return false if presented.blank?

    ActiveSupport::SecurityUtils.secure_compare(presented, expected)
  end

  def cover_token
    header = request.headers["Authorization"].to_s
    bearer = header.split(" ", 2).last if header.start_with?("Bearer ")
    request.headers["X-Cover-Token"].presence || bearer
  end

  def curator_authorized?
    expected = ENV["VIBE_CURATOR_TOKEN"].to_s
    return false if expected.blank?

    presented = curator_token.to_s
    return false if presented.blank?

    ActiveSupport::SecurityUtils.secure_compare(presented, expected)
  end

  def curator_token
    header = request.headers["Authorization"].to_s
    bearer = header.split(" ", 2).last if header.start_with?("Bearer ")
    request.headers["X-Curator-Token"].presence || bearer
  end

  def geometry_authorized?
    expected = ENV["VIBE_GEOMETRY_TOKEN"].to_s
    return false if expected.blank?

    presented = geometry_token.to_s
    return false if presented.blank?

    ActiveSupport::SecurityUtils.secure_compare(presented, expected)
  end

  def geometry_token
    header = request.headers["Authorization"].to_s
    bearer = header.split(" ", 2).last if header.start_with?("Bearer ")
    request.headers["X-Geometry-Token"].presence || bearer
  end
end
