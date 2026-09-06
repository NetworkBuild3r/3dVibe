owner_email = ENV.fetch("VIBE_OWNER_EMAIL", "owner@3dvibe.local")
owner_password = ENV.fetch("VIBE_OWNER_PASSWORD", "vibe-dev-password")
library_root = ENV["VIBE_LIBRARY_ROOT"].presence || File.expand_path("../../fixtures/library", __dir__)
library_name = ENV.fetch("VIBE_LIBRARY_NAME", "Studio library")

owner = User.find_or_initialize_by(email: owner_email)
owner.display_name = "Library owner"
owner.password = owner_password
owner.password_confirmation = owner_password
owner.save!

library = Library.find_or_initialize_by(root_path: library_root)
library.name = library_name
library.notes = "NFS-backed (or local fixture) model collection for 3dvibe."
library.save!

Membership.find_or_create_by!(user: owner, library: library) do |membership|
  membership.role = Membership::OWNER
end

if Dir.exist?(library_root)
  LibraryScanner.new(library).scan!
end

if library.curation_proposals.none?
  first = library.vibe_models.order(:title).first
  second = library.vibe_models.order(:title).second
  library.curation_proposals.create!(
    kind: "tag",
    summary: "Sidecar suggests tagging calibration prints together",
    payload: { tag: "calibration", model_ids: [first&.id].compact },
    sidecar_ref: "stub:tag-calibration",
    status: CurationProposal::PENDING
  )
  library.curation_proposals.create!(
    kind: "organize",
    summary: "Group packed archives under a 'kits' shelf",
    payload: { shelf: "kits", folder_names: library.vibe_models.limit(3).pluck(:folder_name) },
    sidecar_ref: "stub:organize-kits",
    status: CurationProposal::PENDING
  )
  if first && second
    library.curation_proposals.create!(
      kind: "merge",
      summary: "Possible duplicate folders worth a human look",
      payload: { left_id: first.id, right_id: second.id },
      sidecar_ref: "stub:merge-review",
      status: CurationProposal::PENDING
    )
  end
end

Invite.find_or_create_by!(library: library, email: "friend@3dvibe.local") do |invite|
  invite.invited_by = owner
  invite.role = Membership::CONTRIBUTOR
  invite.expires_at = 30.days.from_now
end

puts "Seeded owner #{owner.email} / library #{library.name} (#{library.vibe_models.count} models)"
