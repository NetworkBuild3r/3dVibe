module API
  module V1
    class ArchiveMembersController < ApplicationController
      def index
        model = accessible_models.includes(assets: :archive_members).find(params[:model_id])
        scope = ArchiveMember.joins(:asset).where(assets: { vibe_model_id: model.id })
        scope = scope.where(asset_id: params[:asset_id]) if params[:asset_id].present?

        limit = [[params.fetch(:limit, 200).to_i, 1].max, 500].min
        offset = [params.fetch(:offset, params[:cursor]).to_i, 0].max
        tree = ArchiveTree.new(scope)

        if params[:q].present?
          nodes, total = tree.search(query: params[:q], limit: limit, offset: offset)
          render json: list_payload(model, nodes, total, limit, offset, view: "search", extra: { q: params[:q] })
        elsif params[:view] == "flat"
          nodes, total = tree.flat(limit: limit, offset: offset)
          render json: list_payload(model, nodes, total, limit, offset, view: "flat")
        else
          prefix = params.fetch(:prefix, "")
          nodes, total, counts = tree.children(prefix: prefix, limit: limit, offset: offset)
          render json: list_payload(
            model, nodes, total, limit, offset,
            view: "tree",
            extra: { prefix: ArchiveMember.normalize_prefix(prefix) },
            counts: counts
          )
        end
      end

      def show
        member = find_member
        render json: {
          member: serialize(member).merge(
            model_id: member.asset.vibe_model_id,
            asset_filename: member.asset.filename,
            asset_kind: member.asset.kind,
            archive_support: member.asset.archive_support,
            mtime: member.mtime
          )
        }
      end

      def content
        member = find_member
        tmp = ArchiveIndexer.new(member.asset).extract_member(member.internal_path)
        send_file tmp.path,
                  filename: member.basename.presence || File.basename(member.internal_path),
                  type: member.content_type.presence || "application/octet-stream",
                  disposition: params[:download].present? ? "attachment" : "inline"
      end

      def preview
        member = find_member

        if member.preview_file_present?
          send_file member.preview_absolute_path,
                    filename: member.basename,
                    type: member.content_type.presence || "application/octet-stream",
                    disposition: "inline"
          return
        end

        if member.image? && member.streamable?
          tmp = ArchiveIndexer.new(member.asset).extract_member(
            member.internal_path,
            max_bytes: ArchiveIndexer.preview_bytes
          )
          send_file tmp.path,
                    filename: member.basename,
                    type: member.content_type.presence || "application/octet-stream",
                    disposition: "inline"
          return
        end

        if member.mesh?
          render json: { error: "use_content", content_path: "/api/v1/archive_members/#{member.id}/content" },
                 status: :unprocessable_entity
          return
        end

        render json: { error: "preview_unavailable" }, status: :unprocessable_entity
      end

      private

      def find_member
        ArchiveMember.joins(asset: :vibe_model)
                     .where(vibe_models: { library_id: accessible_libraries.select(:id) })
                     .find(params[:id])
      end

      def list_payload(model, nodes, total, limit, offset, view:, extra: {}, counts: {})
        serialized = nodes.map { |node| serialize(node, child_count: counts[node.internal_path]) }
        {
          model_id: model.id,
          view: view,
          archives: archive_summaries(model),
          nodes: serialized,
          members: serialized,
          next_offset: (offset + nodes.size < total) && nodes.size == limit ? offset + nodes.size : nil,
          estimated_total: total,
          truncated: model.assets.any?(&:archive_truncated)
        }.merge(extra)
      end

      def archive_summaries(model)
        model.assets.select(&:archive?).sort_by(&:relative_path).map do |asset|
          {
            asset_id: asset.id,
            filename: asset.filename,
            kind: asset.kind,
            member_count: asset.archive_members.size,
            truncated: asset.archive_truncated,
            support: asset.archive_support
          }
        end
      end

      def serialize(member, child_count: nil)
        {
          id: member.id,
          asset_id: member.asset_id,
          internal_path: member.internal_path,
          name: member.basename.presence || File.basename(member.internal_path.to_s.delete_suffix("/")),
          path: member.internal_path,
          parent_path: member.parent_path,
          directory: member.directory,
          compressed_size: member.compressed_size,
          uncompressed_size: member.uncompressed_size,
          content_type: member.content_type,
          previewable: member.previewable?,
          has_preview: member.has_preview?,
          mesh: member.mesh?,
          image: member.image?,
          streamable: member.streamable?,
          extension: member.extension,
          listing_source: member.listing_source,
          child_count: member.directory? ? child_count.to_i : nil,
          has_children: member.directory? && child_count.to_i.positive?
        }
      end
    end
  end
end
