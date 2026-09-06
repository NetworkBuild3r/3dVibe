class ApplyCurationProposalJob < ApplicationJob
  queue_as :curation

  def perform(proposal_id)
    proposal = CurationProposal.find(proposal_id)
    unless proposal.approved?
      Rails.logger.info("[ApplyCurationProposalJob] skip proposal=#{proposal.id} status=#{proposal.status}")
      return
    end

    CurationApplier.new(proposal).apply!
    Rails.logger.info(
      "[ApplyCurationProposalJob] applied kind=#{proposal.kind} proposal=#{proposal.id} error=#{proposal.apply_error}"
    )
  end
end
