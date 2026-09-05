class HealthController < ActionController::API
  def show
    render json: { ok: true, app: "3dvibe" }, status: :ok
  end
end
