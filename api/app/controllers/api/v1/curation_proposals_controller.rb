module API
  module V1
    class CurationProposalsController < ApplicationController
      def index
        proposals = CurationProposal.where(library_id: accessible_libraries.select(:id))
        proposals = proposals.where(status: params[:status]) if params[:status].present?
        render json: { proposals: proposals.order(created_at: :desc).map { |proposal| serialize(proposal) } }
      end

      def create
        library = accessible_libraries.find(params.require(:library_id))
        return if require_owner!(library)

        proposal = library.curation_proposals.create!(proposal_params.merge(status: CurationProposal::PENDING))
        render json: { proposal: serialize(proposal) }, status: :created
      end

      def approve
        proposal = find_proposal
        return if require_owner!(proposal.library)
        return unless pending!(proposal)

        proposal.update!(status: CurationProposal::APPROVED, reviewed_by: current_user, reviewed_at: Time.current)
        ApplyCurationProposalJob.perform_later(proposal.id)
        render json: { proposal: serialize(proposal.reload) }
      end

      def reject
        proposal = find_proposal
        return if require_owner!(proposal.library)
        return unless pending!(proposal)

        proposal.update!(status: CurationProposal::REJECTED, reviewed_by: current_user, reviewed_at: Time.current)
        render json: { proposal: serialize(proposal) }
      end

      private

      def find_proposal
        CurationProposal.where(library_id: accessible_libraries.select(:id)).find(params[:id])
      end

      def pending!(proposal)
        return true if proposal.pending?

        render json: { error: "already_reviewed" }, status: :conflict
        false
      end

      def proposal_params
        params.require(:curation_proposal).permit(:kind, :summary, :sidecar_ref, payload: {})
      end

      def serialize(proposal)
        {
          id: proposal.id,
          library_id: proposal.library_id,
          kind: proposal.kind,
          status: proposal.status,
          summary: proposal.summary,
          payload: proposal.payload,
          sidecar_ref: proposal.sidecar_ref,
          reviewed_at: proposal.reviewed_at,
          created_at: proposal.created_at
        }
      end
    end
  end
end
