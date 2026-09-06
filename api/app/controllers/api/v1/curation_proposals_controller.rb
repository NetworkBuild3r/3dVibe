module API
  module V1
    class CurationProposalsController < ApplicationController
      skip_before_action :authenticate!, only: :ingest
      before_action :authenticate_ingest!, only: :ingest

      def index
        proposals = CurationProposal.where(library_id: accessible_libraries.select(:id)).includes(:library, :reviewed_by)
        proposals = proposals.where(status: params[:status]) if params[:status].present?
        render json: { proposals: proposals.order(created_at: :desc).map { |proposal| serialize(proposal) } }
      end

      def create
        library = accessible_libraries.find(params.require(:library_id))
        return if require_curator!(library)

        proposal = library.curation_proposals.create!(proposal_attrs.merge(status: CurationProposal::PENDING))
        render json: { proposal: serialize(proposal) }, status: :created
      end

      def fetch
        library = accessible_libraries.find(params.require(:library_id))
        return if require_curator!(library)

        records = CurationSidecar.new(library).ingest_remote!
        render json: { proposals: records.map { |proposal| serialize(proposal) } }
      rescue CurationHttpClient::Error => e
        render json: { error: "curator_unreachable", details: [e.message] }, status: :bad_gateway
      end

      def ingest
        library = ingest_library
        return unless library

        drafts = Array(ingest_proposal_params).filter_map { |item| draft_from(item) }
        records = CurationSidecar.new(library).ingest!(drafts)
        render json: { proposals: records.map { |proposal| serialize(proposal) } }, status: :created
      end

      def approve
        proposal = find_proposal
        return if require_curator!(proposal.library)
        return unless pending!(proposal)

        review!(proposal, CurationProposal::APPROVED)
        apply_after_approve!(proposal)
        render json: { proposal: serialize(proposal.reload) }
      end

      def reject
        proposal = find_proposal
        return if require_curator!(proposal.library)
        return unless pending!(proposal)

        review!(proposal, CurationProposal::REJECTED)
        render json: { proposal: serialize(proposal) }
      end

      def bulk
        decision = params.require(:decision).to_s
        unless %w[approve reject].include?(decision)
          render json: { error: "invalid", details: ["decision must be approve or reject"] }, status: :unprocessable_entity
          return
        end

        ids = Array(params[:ids]).map(&:to_i).reject(&:zero?)
        proposals = CurationProposal.where(library_id: accessible_libraries.select(:id), id: ids)
        results = proposals.map { |proposal| apply_bulk_action(proposal, decision) }
        render json: { proposals: results }
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

      def review!(proposal, status)
        proposal.update!(status: status, reviewed_by: current_user, reviewed_at: Time.current)
      end

      def apply_after_approve!(proposal)
        if proposal.immediate_apply?
          CurationApplier.new(proposal).apply!
        else
          ApplyCurationProposalJob.perform_later(proposal.id)
        end
      end

      def apply_bulk_action(proposal, action)
        unless current_user.can_curate?(proposal.library)
          return serialize(proposal).merge(error: "forbidden")
        end
        unless proposal.pending?
          return serialize(proposal).merge(error: "already_reviewed")
        end

        if action == "approve"
          review!(proposal, CurationProposal::APPROVED)
          apply_after_approve!(proposal)
        else
          review!(proposal, CurationProposal::REJECTED)
        end
        serialize(proposal.reload)
      end

      def proposal_attrs
        permitted = params.require(:curation_proposal).permit(:kind, :summary, :sidecar_ref, payload: permitted_payload)
        permitted[:payload] = normalize_payload(permitted[:payload])
        permitted
      end

      def ingest_proposal_params
        raw = params[:proposals]
        return raw if raw.is_a?(Array)

        Array.wrap(params.permit(proposals: [:kind, :summary, :sidecar_ref, { payload: permitted_payload }])[:proposals])
      end

      def draft_from(item)
        data = item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item
        data = data.stringify_keys
        return if data["kind"].blank? || data["summary"].blank?

        CurationSidecar::ProposalDraft.new(
          kind: data["kind"],
          summary: data["summary"],
          payload: normalize_payload(data["payload"]),
          sidecar_ref: data["sidecar_ref"]
        )
      end

      def permitted_payload
        [
          :tag, :title, :to, :from, :folder_name, :shelf, :model_id, :source_id, :target_id,
          :left_id, :right_id, :relative_path, :destination_folder, :destination_relative_path,
          :asset_id, { tags: [], model_ids: [], folder_names: [] }
        ]
      end

      def normalize_payload(value)
        (value.presence || {}).to_h.stringify_keys
      end

      def ingest_library
        if params[:library_id].present?
          library = Library.find(params[:library_id])
        else
          root = params[:library_root].presence
          library = Library.find_by(root_path: root) if root.present?
        end
        return library if library

        render json: { error: "library_not_found" }, status: :not_found
        nil
      end

      def authenticate_ingest!
        return if curator_authorized?

        authenticate!
        return if performed?

        library = ingest_library
        return unless library

        require_curator!(library)
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
          reviewed_by_id: proposal.reviewed_by_id,
          applied_at: proposal.applied_at,
          apply_error: proposal.apply_error,
          result: proposal.result,
          preview: CurationPreview.new(proposal).as_json,
          created_at: proposal.created_at
        }
      end
    end
  end
end
