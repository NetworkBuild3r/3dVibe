class ApplyCurationProposalJob < ApplicationJob
  queue_as :curation

  # Stub: applying organize/merge/tag suggestions is HITL-approved later.
  def perform(proposal_id)
    proposal = CurationProposal.find(proposal_id)
    Rails.logger.info("[ApplyCurationProposalJob] apply #{proposal.kind} proposal=#{proposal.id} status=#{proposal.status}")
  end
end
