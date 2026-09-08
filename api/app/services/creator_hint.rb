# Maps a pack folder onto a shared Creator.
# Priority (INIT-020/SPEC-005): datapackage.json creator > pack `Creator - Title`
# prefix > category as a weak hint. Category shelves (Anime, …) are not creators.
# NFS is the source of truth. We never invent private shelves or federation.
class CreatorHint
  Result = Struct.new(:slug, :name, :source, :keywords, :authority, :title, keyword_init: true)

  SOURCE = Creator::SOURCE_NFS
  AUTHORITY_DATAPACKAGE = "datapackage"
  AUTHORITY_PACK_PREFIX = "pack_prefix"
  AUTHORITY_CATEGORY = "category"
  AUTHORITY_FOLDER = "folder"

  # Common 3D-print pack dumps that land as "Prefix - Title" or a known folder.
  KNOWN_PACKS = [
    { slug: "mz4250", name: "Mz4250", aliases: %w[mz4250 mz4250-miniatures] },
    { slug: "printable-scenery", name: "Printable Scenery", aliases: %w[printable-scenery printablescenery] },
    { slug: "titan-forge", name: "Titan Forge", aliases: %w[titan-forge titanforge] },
    { slug: "artisan-guild", name: "Artisan Guild", aliases: %w[artisan-guild artisanguild] },
    { slug: "loot-studios", name: "Loot Studios", aliases: %w[loot-studios lootstudios] },
    { slug: "duncan-shadow", name: "Duncan Shadow", aliases: %w[duncan-shadow duncanshadow] }
  ].freeze

  # Genre / marketplace / meta shelves — never the creator solely because they
  # are the first path segment under Category/Pack.
  WEAK_CATEGORY_DENY = %w[
    anime cartoons cosplay d-d d&d dnd dc games movie-tv movie tv
    untagged unknown anystl cults3d gumroad
  ].freeze

  PACK_SEPARATOR = /\s+[–—\-]{1,2}\s+/.freeze
  DATAPACKAGE_READ_LIMIT = 64 * 1024
  CREATOR_ROLES = %w[creator author].freeze

  def self.parse(folder_name, pack_root: nil)
    new(folder_name, pack_root: pack_root).parse
  end

  def self.upsert!(folder_name, pack_root: nil)
    hint = parse(folder_name, pack_root: pack_root)
    return unless hint&.slug.present?

    creator = Creator.find_or_initialize_by(slug: hint.slug)
    creator.name = hint.name if creator.new_record? || creator.name.blank?
    creator.source ||= hint.source
    creator.save!
    creator
  end

  def initialize(folder_name, pack_root: nil)
    @folder_name = folder_name.to_s.strip
    @pack_root = pack_root
  end

  def parse
    return if @folder_name.blank?

    category, pack_leaf = split_pack(@folder_name)
    leaf = pack_leaf || category

    if (from_dp = datapackage_hint)
      return from_dp if from_dp.slug.present? || from_dp.keywords.present?
    end

    if pack_leaf
      if (from_leaf = hint_from_pack_leaf(leaf))
        return from_leaf
      end

      return weak_category_hint(category)
    end

    hint_from_flat(leaf)
  end

  private

  def split_pack(folder_name)
    parts = folder_name.to_s.tr("\\", "/").split("/").reject(&:blank?)
    return [nil, nil] if parts.include?("..") || parts.any? { |part| part == "." || part.start_with?(".") }

    case parts.size
    when 1 then [parts.first, nil]
    when 2 then [parts.first, parts.last]
    else [parts.first, parts.last]
    end
  end

  def datapackage_hint
    data = read_datapackage(@pack_root)
    return unless data

    keywords = Array(data["keywords"]).filter_map { |word| word.to_s.strip.presence }.uniq
    title = data["title"].to_s.strip.presence
    creator_name = datapackage_creator_name(data)
    unless creator_name
      return result(nil, nil, keywords: keywords, authority: AUTHORITY_DATAPACKAGE, title: title) if keywords.any? || title

      return
    end

    if (known = known_pack(creator_name))
      return result(known[:slug], known[:name], keywords: keywords, authority: AUTHORITY_DATAPACKAGE, title: title)
    end

    result(slugify(creator_name), creator_name, keywords: keywords, authority: AUTHORITY_DATAPACKAGE, title: title)
  end

  def hint_from_pack_leaf(leaf)
    if (known = known_pack(leaf))
      return result(known[:slug], known[:name], authority: AUTHORITY_PACK_PREFIX)
    end

    left = pack_prefix(leaf)
    return unless left

    if (known = known_pack(left))
      return result(known[:slug], known[:name], authority: AUTHORITY_PACK_PREFIX)
    end

    result(slugify(left), left.strip, authority: AUTHORITY_PACK_PREFIX)
  end

  def hint_from_flat(leaf)
    if (known = known_pack(leaf))
      return result(known[:slug], known[:name], authority: AUTHORITY_PACK_PREFIX)
    end

    left = pack_prefix(leaf)
    if left.present?
      if (known = known_pack(left))
        return result(known[:slug], known[:name], authority: AUTHORITY_PACK_PREFIX)
      end

      return result(slugify(left), left.strip, authority: AUTHORITY_PACK_PREFIX)
    end

    result(slugify(leaf), humanize(leaf), authority: AUTHORITY_FOLDER)
  end

  def weak_category_hint(category)
    return if category.blank? || weak_category_denied?(category)

    if (known = known_pack(category))
      return result(known[:slug], known[:name], authority: AUTHORITY_CATEGORY)
    end

    result(slugify(category), humanize(category), authority: AUTHORITY_CATEGORY)
  end

  def weak_category_denied?(category)
    key = normalize_key(category)
    WEAK_CATEGORY_DENY.include?(key)
  end

  def read_datapackage(pack_root)
    file = datapackage_file(pack_root)
    return unless file

    data = JSON.parse(file.read(DATAPACKAGE_READ_LIMIT))
    Rails.logger.info("[CreatorHint] datapackage applied folder=#{@folder_name}")
    data
  rescue JSON::ParserError, Errno::EACCES, Errno::ENOENT, Errno::ELOOP
    Rails.logger.warn("[CreatorHint] datapackage unreadable folder=#{@folder_name}")
    nil
  end

  def datapackage_file(pack_root)
    return if pack_root.blank?

    raw = pack_root.to_s
    raise ArgumentError, "invalid pack root" if raw.include?("\0") || raw.tr("\\", "/").split("/").include?("..")

    root = Pathname.new(raw)
    return if root.symlink?

    file = root.join("datapackage.json")
    return unless file.file? && !file.symlink?

    file
  end

  def datapackage_creator_name(data)
    raw = data["creator"]
    name = case raw
    when String then raw
    when Hash then raw["name"].presence || raw["title"]
    end
    return name.to_s.strip.presence if name.present?

    Array(data["contributors"]).each do |row|
      next unless row.is_a?(Hash)

      roles = Array(row["roles"] || row["role"]).map { |role| role.to_s.downcase }
      next unless roles.intersect?(CREATOR_ROLES)

      title = row["title"].presence || row["name"]
      return title.to_s.strip.presence if title.present?
    end
    nil
  end

  def known_pack(value)
    key = normalize_key(value)
    KNOWN_PACKS.find do |pack|
      pack[:slug] == key || pack[:aliases].include?(key) || key.start_with?("#{pack[:slug]}-") ||
        pack[:aliases].any? { |alias_name| key == alias_name || key.start_with?("#{alias_name}-") }
    end
  end

  def pack_prefix(value)
    return unless value.match?(PACK_SEPARATOR)

    value.split(PACK_SEPARATOR, 2).first.to_s.strip.presence
  end

  def result(slug, name, keywords: [], authority: AUTHORITY_FOLDER, title: nil)
    Result.new(slug: slug, name: name, source: SOURCE, keywords: keywords, authority: authority, title: title)
  end

  def slugify(value)
    slug = value.to_s.parameterize
    return slug if slug.present?

    "nfs-#{Digest::SHA256.hexdigest(value.to_s)[0, 12]}"
  end

  def normalize_key(value)
    value.to_s.downcase.tr("_", "-").gsub(/\s+/, "-").gsub(/-+/, "-").gsub(/\A-|-\z/, "")
  end

  def humanize(value)
    value.to_s.tr("_-", " ").squeeze(" ").strip.split.map { |part| part[0] ? part[0].upcase + part[1..] : part }.join(" ")
  end
end
