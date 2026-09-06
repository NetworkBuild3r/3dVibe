module API
  module V1
    class DuplicatesController < ApplicationController
      def index
        library = if params[:library_id].present?
          accessible_libraries.find(params[:library_id])
        else
          accessible_libraries.order(:id).first
        end
        raise ActiveRecord::RecordNotFound unless library

        groups = library.duplicate_groups.includes(duplicate_group_members: { asset: { vibe_model: VibeModel::CARD_INCLUDES } })
        groups = groups.where(status: params[:status]) if params[:status].present?
        rows = groups.recent.to_a
        render json: {
          library_id: library.id,
          group_count: rows.size,
          groups: rows.map { |group| group.as_api(viewer: current_user) }
        }
      end

      def analyze
        library = accessible_libraries.find(params[:id])
        return if require_curator!(library)

        AnalyzeDuplicatesJob.perform_later(library.id)
        render json: { queued: true, library_id: library.id }, status: :accepted
      end

      def keep
        decide!(DuplicateReview::KEEP, DuplicateGroup::KEPT)
      end

      def dismiss
        decide!(DuplicateReview::DISMISS, DuplicateGroup::DISMISSED)
      end

      def merge
        group = find_group
        return if require_curator!(group.library)
        return unless open!(group)

        record = ModelComposer.new(group.library, performed_by: current_user).merge!(
          source_ids: params[:source_ids] || params[:model_ids],
          asset_ids: params[:asset_ids],
          target_id: params[:target_id],
          title: params[:title],
          folder_name: params[:folder_name]
        )
        review = record_review!(group, DuplicateReview::MERGE, merge_payload(record))
        group.update!(status: DuplicateGroup::MERGED)
        target = accessible_models.includes(:tags, :uploaded_by, :creator, assets: %i[archive_members uploaded_by])
                                 .find(record.target_vibe_model_id)
        render json: {
          group: group.reload.as_api(viewer: current_user),
          review: review.as_api,
          merge: record.as_api,
          model: detail_payload(target)
        }
      end

      private

      def decide!(decision, status)
        group = find_group
        return if require_curator!(group.library)
        return unless open!(group)

        review = record_review!(group, decision, review_payload)
        group.update!(status: status)
        render json: { group: group.reload.as_api(viewer: current_user), review: review.as_api }
      end

      def find_group
        DuplicateGroup.where(library_id: accessible_libraries.select(:id)).find(params[:id])
      end

      def open!(group)
        return true if group.open?

        render json: { error: "invalid", details: ["group is #{group.status}"] }, status: :unprocessable_entity
        false
      end

      def record_review!(group, decision, payload)
        group.duplicate_reviews.create!(user: current_user, decision: decision, payload: payload)
      end

      def review_payload
        raw = params[:payload]
        return {} if raw.blank?
        return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
        return raw.to_h if raw.respond_to?(:to_h)

        {}
      end

      def merge_payload(record)
        {
          "source_ids" => Array(params[:source_ids] || params[:model_ids]),
          "asset_ids" => Array(params[:asset_ids]),
          "target_id" => params[:target_id],
          "title" => params[:title],
          "folder_name" => params[:folder_name],
          "merge_id" => record.id
        }.compact
      end

      def detail_payload(model)
        card = VibeModel.card_payloads([model], viewer: current_user).first
        card.merge(
          folder_mtime: model.folder_mtime,
          merges: model.model_merges.includes(:performed_by).recent.map(&:as_api),
          assets: model.assets.order(:relative_path).map do |asset|
            {
              id: asset.id,
              filename: asset.filename,
              relative_path: asset.relative_path,
              kind: asset.kind,
              byte_size: asset.byte_size,
              content_digest: asset.content_digest,
              geometry_digest: asset.geometry_digest,
              archive: asset.archive?,
              mesh: asset.mesh?,
              archive_member_count: asset.archive_members.size,
              archive_truncated: asset.archive_truncated,
              archive_support: asset.archive_support,
              uploaded_by: asset.uploaded_by && { id: asset.uploaded_by.id, display_name: asset.uploaded_by.display_name }
            }
          end
        )
      end
    end
  end
end
