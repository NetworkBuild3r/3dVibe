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

        groups = library.duplicate_groups.includes(duplicate_group_members: DuplicateGroup::MEMBER_INCLUDES)
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

      MERGE_UNSUPPORTED = "merge_unsupported"
      MERGE_UNSUPPORTED_MESSAGE = "Archive-resident members cannot be merged out of a zip. Extract them to disk first, then merge, or call extract_and_merge."

      def merge
        group = find_group
        return if require_curator!(group.library)
        return unless open!(group)
        return unless mergeable_selection!(group)

        record = ModelComposer.new(group.library, performed_by: current_user).merge!(
          source_ids: params[:source_ids] || params[:model_ids],
          asset_ids: params[:asset_ids],
          target_id: params[:target_id] || params[:target_model_id],
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

      def extract
        group = find_group
        return if require_curator!(group.library)
        return unless open!(group)

        result = ArchiveMemberExtractor.new(group.library, performed_by: current_user).extract!(
          archive_member_ids: extract_member_ids(group),
          target_id: extract_destination_id(group),
          title: params[:title],
          folder_name: params[:folder_name]
        )
        render json: extract_payload(result, group: group), status: :created
      end

      def extract_and_merge
        group = find_group
        return if require_curator!(group.library)
        return unless open!(group)

        result = ArchiveMemberExtractor.new(group.library, performed_by: current_user).extract_and_merge!(
          archive_member_ids: extract_member_ids(group),
          source_ids: params[:source_ids] || params[:model_ids],
          asset_ids: params.key?(:asset_ids) ? params[:asset_ids] : default_loose_asset_ids(group),
          target_id: extract_destination_id(group),
          title: params[:title],
          folder_name: params[:folder_name]
        )
        review = record_review!(group, DuplicateReview::MERGE, extract_merge_payload(result))
        group.update!(status: DuplicateGroup::MERGED)
        render json: extract_payload(result, group: group.reload, review: review), status: :created
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

      def mergeable_selection!(group)
        if archive_merge_blocked?(group)
          render json: { error: MERGE_UNSUPPORTED, message: MERGE_UNSUPPORTED_MESSAGE },
                 status: :unprocessable_entity
          return false
        end

        true
      end

      def archive_merge_blocked?(group)
        return true if selected_archive_member_ids.any?
        return true if selected_member_payloads_include_archive?
        return false if explicit_on_disk_selection?
        return true if group.duplicate_group_members.where.not(archive_member_id: nil).exists?

        false
      end

      def explicit_on_disk_selection?
        Array(params[:source_ids] || params[:model_ids]).any? || Array(params[:asset_ids]).any?
      end

      def extract_target_id
        params[:target_model_id].presence || params[:target_id].presence
      end

      def extract_destination_id(group)
        return extract_target_id if extract_target_id
        return if params[:folder_name].present? || params[:title].present?

        default_extract_target_id(group)
      end

      def extract_member_ids(group)
        ids = selected_archive_member_ids
        return ids if ids.any?

        group.duplicate_group_members.where.not(archive_member_id: nil).pluck(:archive_member_id)
      end

      def default_extract_target_id(group)
        group.duplicate_group_members.filter_map(&:asset).first&.vibe_model_id
      end

      def default_loose_asset_ids(group)
        group.duplicate_group_members.filter_map(&:asset_id)
      end

      def extract_payload(result, group: nil, review: nil)
        target = accessible_models.includes(:tags, :uploaded_by, :creator, assets: %i[archive_members uploaded_by])
                                 .find(result.model.id)
        payload = {
          model: detail_payload(target),
          assets: result.extracted,
          extracted: result.extracted,
          merge: result.merge&.as_api
        }
        payload[:group] = group.as_api(viewer: current_user) if group
        payload[:review] = review.as_api if review
        payload
      end

      def extract_merge_payload(result)
        {
          "archive_member_ids" => Array(params[:archive_member_ids]),
          "source_ids" => Array(params[:source_ids] || params[:model_ids]),
          "asset_ids" => Array(params[:asset_ids]),
          "target_id" => extract_target_id,
          "title" => params[:title],
          "folder_name" => params[:folder_name],
          "extracted" => result.extracted,
          "merge_id" => result.merge&.id
        }.compact
      end

      def selected_archive_member_ids
        ids = Array(params[:archive_member_ids])
        ids << params[:archive_member_id] if params[:archive_member_id].present?
        ids.map(&:to_i).reject(&:zero?)
      end

      def selected_member_payloads_include_archive?
        raw = params[:members]
        return false if raw.blank?

        Array(raw).any? do |item|
          hash = item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item.to_h
          hash["kind"].to_s == "archive_member" ||
            hash["archive_member_id"].present? ||
            hash.key?("mergeable") && ActiveModel::Type::Boolean.new.cast(hash["mergeable"]) == false
        end
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
