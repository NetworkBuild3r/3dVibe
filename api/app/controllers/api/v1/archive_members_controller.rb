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
            mtime: member.mtime,
            accept_ranges: member.streamable?,
            stream_max_bytes: ArchiveIndexer.stream_bytes,
            stream_max_seconds: ArchiveIndexer.stream_seconds,
            content_path: member.streamable? ? "/api/v1/archive_members/#{member.id}/content" : nil,
            preview_path: "/api/v1/archive_members/#{member.id}/preview"
          )
        }
      end

      def content
        stream_member!(find_member, max_bytes: ArchiveIndexer.stream_bytes, download: params[:download].present?)
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
          stream_member!(member, max_bytes: ArchiveIndexer.preview_bytes)
          return
        end

        if member.mesh?
          render json: { error: "use_content", content_path: "/api/v1/archive_members/#{member.id}/content" },
                 status: :unprocessable_entity
          return
        end

        render json: { error: "preview_unavailable" }, status: :unprocessable_entity
      end

      def extract
        perform_extract!(merge: false)
      end

      def extract_and_merge
        perform_extract!(merge: true)
      end

      private

      def perform_extract!(merge:)
        ids = selected_archive_member_ids
        raise ArgumentError, "select archive members to extract" if ids.empty?

        members = ArchiveMember.joins(asset: :vibe_model).where(id: ids).includes(asset: :vibe_model).to_a
        raise ArgumentError, "archive members not found" if members.size != ids.uniq.size

        library = if params[:library_id].present?
          accessible_libraries.find(params[:library_id])
        else
          members.first.asset.vibe_model.library
        end
        return if require_curator!(library)

        unless members.all? { |member| member.asset.vibe_model.library_id == library.id }
          raise ArgumentError, "archive members must share one library"
        end

        extractor = ArchiveMemberExtractor.new(library, performed_by: current_user)
        kwargs = {
          archive_member_ids: ids,
          target_id: extract_target_id,
          title: params[:title],
          folder_name: params[:folder_name]
        }
        result = if merge
          extractor.extract_and_merge!(
            **kwargs,
            source_ids: params[:source_ids] || params[:model_ids],
            asset_ids: params[:asset_ids]
          )
        else
          extractor.extract!(**kwargs)
        end

        target = accessible_models.includes(:tags, :uploaded_by, :creator, assets: %i[archive_members uploaded_by])
                                 .find(result.model.id)
        render json: {
          model: detail_payload(target),
          assets: result.extracted,
          extracted: result.extracted,
          merge: result.merge&.as_api
        }, status: :created
      end

      def selected_archive_member_ids
        ids = Array(params[:archive_member_ids])
        ids << params[:archive_member_id] if params[:archive_member_id].present?
        ids << params[:id] if params[:id].present? && action_name != "show"
        ids.map(&:to_i).reject(&:zero?)
      end

      def extract_target_id
        params[:target_model_id].presence || params[:target_id].presence
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
              mergeable: true,
              uploaded_by: asset.uploaded_by && { id: asset.uploaded_by.id, display_name: asset.uploaded_by.display_name }
            }
          end
        )
      end

      def find_member
        ArchiveMember.joins(asset: :vibe_model)
                     .where(vibe_models: { library_id: accessible_libraries.select(:id) })
                     .find(params[:id])
      end

      def stream_member!(member, max_bytes:, download: false)
        raise ArgumentError, "Member is not streamable" unless member.streamable?

        streamer = ArchiveMemberStreamer.for_member(member)
        total = streamer.known_size
        raise ArgumentError, "Refusing to load oversized member" if total && total > max_bytes

        range = ArchiveMemberStreamer.parse_range(request.get_header("HTTP_RANGE"), total: total)
        if range == :unsatisfiable
          response.set_header("Content-Range", "bytes */#{total}")
          head :range_not_satisfiable
          return
        end

        filename = member.basename.presence || File.basename(member.internal_path)
        response.set_header("Accept-Ranges", "bytes")
        response.set_header("Cache-Control", "private, no-store")
        response.set_header("X-Accel-Buffering", "no")
        response.set_header("Content-Type", member.content_type.presence || "application/octet-stream")
        response.set_header(
          "Content-Disposition",
          ActionDispatch::Http::ContentDisposition.format(
            disposition: download ? "attachment" : "inline",
            filename: filename
          )
        )

        offset = 0
        length = nil
        if range
          response.status = 206
          response.set_header("Content-Range", "bytes #{range.first}-#{range.last}/#{range.total}")
          response.set_header("Content-Length", range.length.to_s)
          offset = range.first
          length = range.length
        elsif total
          response.set_header("Content-Length", total.to_s)
        end

        self.response_body = Enumerator.new do |yielder|
          streamer.each(max_bytes: max_bytes, offset: offset, length: length) do |chunk|
            yielder << chunk
          end
        end
      rescue ArchiveShellLister::Error => e
        raise ArgumentError, e.message
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
          accept_ranges: member.streamable?,
          extension: member.extension,
          listing_source: member.listing_source,
          child_count: member.directory? ? child_count.to_i : nil,
          has_children: member.directory? && child_count.to_i.positive?,
          content_path: member.streamable? ? "/api/v1/archive_members/#{member.id}/content" : nil,
          preview_path: member.id ? "/api/v1/archive_members/#{member.id}/preview" : nil
        }
      end
    end
  end
end
