# Shared extract HTTP surface. Archive members is the primitive;
# duplicates stay thin wrappers that attach group / review.
module ExtractsArchiveMembers
  extend ActiveSupport::Concern

  EXTRACT_DETAIL_INCLUDES = [:tags, :uploaded_by, :creator, { assets: %i[archive_members uploaded_by] }].freeze

  private

  def extract_target_id
    params[:target_model_id].presence || params[:target_id].presence
  end

  def selected_archive_member_ids(include_route_id: false)
    ids = Array(params[:archive_member_ids])
    ids << params[:archive_member_id] if params[:archive_member_id].present?
    ids << params[:id] if include_route_id && params[:id].present? && action_name != "show"
    ids.map(&:to_i).reject(&:zero?)
  end

  def run_extract!(library, merge:, archive_member_ids:, target_id: nil, title: nil, folder_name: nil,
                   source_ids: nil, asset_ids: nil)
    extractor = ArchiveMemberExtractor.new(library, performed_by: current_user)
    kwargs = {
      archive_member_ids: archive_member_ids,
      target_id: target_id,
      title: title,
      folder_name: folder_name
    }
    if merge
      extractor.extract_and_merge!(**kwargs, source_ids: source_ids, asset_ids: asset_ids)
    else
      extractor.extract!(**kwargs)
    end
  end

  def render_extract(result, group: nil, review: nil)
    target = accessible_models.includes(*EXTRACT_DETAIL_INCLUDES).find(result.model.id)
    render json: ArchiveMemberExtractor.as_api(
      result,
      model: target,
      group: group,
      review: review,
      viewer: current_user
    ), status: :created
  end
end
