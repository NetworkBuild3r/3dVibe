# Maps a first-level library folder onto a shared Creator.
# NFS is the source of truth: we only label from the folder name / pack-style
# prefixes. We never invent private shelves, per-user piles, or federation.
class CreatorHint
  Result = Struct.new(:slug, :name, :source, keyword_init: true)

  SOURCE = Creator::SOURCE_NFS

  # Common 3D-print pack dumps that land as "Prefix - Title" or a known folder.
  KNOWN_PACKS = [
    { slug: "mz4250", name: "Mz4250", aliases: %w[mz4250 mz4250-miniatures] },
    { slug: "printable-scenery", name: "Printable Scenery", aliases: %w[printable-scenery printablescenery] },
    { slug: "titan-forge", name: "Titan Forge", aliases: %w[titan-forge titanforge] },
    { slug: "artisan-guild", name: "Artisan Guild", aliases: %w[artisan-guild artisanguild] },
    { slug: "loot-studios", name: "Loot Studios", aliases: %w[loot-studios lootstudios] },
    { slug: "duncan-shadow", name: "Duncan Shadow", aliases: %w[duncan-shadow duncanshadow] }
  ].freeze

  PACK_SEPARATOR = /\s+[–—\-]{1,2}\s+/.freeze

  def self.parse(folder_name)
    new(folder_name).parse
  end

  def self.upsert!(folder_name)
    hint = parse(folder_name)
    return unless hint

    creator = Creator.find_or_initialize_by(slug: hint.slug)
    creator.name = hint.name if creator.new_record? || creator.name.blank?
    creator.source ||= hint.source
    creator.save!
    creator
  end

  def initialize(folder_name)
    @folder_name = folder_name.to_s.strip
  end

  def parse
    return if @folder_name.blank?

    if (known = known_pack(@folder_name))
      return result(known[:slug], known[:name])
    end

    left = pack_prefix(@folder_name)
    if left.present?
      if (known = known_pack(left))
        return result(known[:slug], known[:name])
      end

      return result(slugify(left), left.strip)
    end

    result(slugify(@folder_name), humanize(@folder_name))
  end

  private

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

  def result(slug, name)
    Result.new(slug: slug, name: name, source: SOURCE)
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
