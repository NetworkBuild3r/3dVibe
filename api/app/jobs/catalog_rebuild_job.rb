# INIT-020/SPEC-009 — owner-gated rebuild on the isolated scan queue. Not a cron.
class CatalogRebuildJob < ApplicationJob
  queue_as { ScanSettings.queue }

  def perform(library_id, apply = false, wipe = CatalogRebuild::WIPE_MEGA, actor_user_id = nil)
    library = Library.find(library_id)
    actor = User.find_by(id: actor_user_id) if actor_user_id
    CatalogRebuild.new(library, apply: apply, wipe: wipe, actor: actor).call
  end
end
