# Enqueue contract for budgeted covers. Rendering owns generate.
# Job args are a single JSON object (see README / CoverEnqueue#payload).
class GenerateCoverJob < ApplicationJob
  queue_as :covers

  def perform(payload)
    data = (payload.presence || {}).to_h.stringify_keys
    Rails.logger.info(
      "[GenerateCoverJob] stub generate model=#{data['model_id']} asset=#{data['asset_id']} " \
      "jailed_path=#{data['jailed_path']} budget=#{data['budget'].inspect}"
    )
    :stubbed
  end
end
