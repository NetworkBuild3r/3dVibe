# Resolves gallery/search `uploaded_by=me|<user_id>` (and the `uploaded_by_id` alias).
# Authorship is a filter, never visibility: omit/blank keeps the shared pile (All).
# Invalid or unknown tokens apply an unmatched filter — never silently fall back to All.
class UploadedByParam
  NONE = :none

  def self.resolve(value, current_user:)
    raw = value.to_s.strip
    return nil if raw.blank?
    return current_user.id if raw.casecmp("me").zero?
    return raw.to_i if raw.match?(/\A\d+\z/)

    NONE
  end

  def self.from_params(params, current_user:)
    raw = params[:uploaded_by]
    raw = params[:uploaded_by_id] if raw.nil? || raw == ""
    resolve(raw, current_user: current_user)
  end
end
