import type { Creator, LibraryMember, ModelCard } from "../types";
import {
  allChipActive,
  creatorDisplayName,
  facetCreators,
  facetTags,
  friendDisplayName,
  hasActiveFilters,
  searchPillLabel,
  truncateUploaderLabel,
  uploaderSegment,
  type CatalogFacets,
  type GalleryDensity,
  type GalleryFilters
} from "../gallery";
import { CalmChip, ChipDropdown, ChipOption, FilterPill } from "./CalmChip";
import { IconGrid } from "./Icons";
import { ChipRowSkeleton, InlineError } from "./UiStates";

export function GalleryFilterBar({
  filters,
  facets,
  creators,
  models,
  members,
  membersReady,
  membersError,
  density,
  engine,
  facetsReady,
  loadError,
  onPatch,
  onClear,
  onRetry,
  onRetryMembers,
  onDensity
}: {
  filters: GalleryFilters;
  facets?: CatalogFacets;
  creators: Creator[];
  models: ModelCard[];
  members: LibraryMember[];
  membersReady: boolean;
  membersError: string | null;
  density: GalleryDensity;
  engine: string;
  facetsReady: boolean;
  loadError: string | null;
  onPatch: (updates: Record<string, string | null>) => void;
  onClear: () => void;
  onRetry: () => void;
  onRetryMembers: () => void;
  onDensity: (density: GalleryDensity) => void;
}) {
  const creatorOptions = facetCreators(facets, creators, models);
  const tagOptions = facetTags(facets);
  const selectedCreatorName = creatorDisplayName(filters.creator, creators, models);
  const filtersActive = hasActiveFilters(filters);
  const queryLabel = searchPillLabel(filters);
  const segment = uploaderSegment(filters);
  const friendName = friendDisplayName(filters.uploadedBy, members);
  const friendLabel = friendName ? truncateUploaderLabel(friendName) : undefined;
  const memberOptions = members.filter((member) => member.display_name);
  const pickerEmpty = membersError
    ? undefined
    : membersReady && memberOptions.length === 0
      ? "No members yet"
      : undefined;

  return (
    <div className="gallery-filter-bar">
      <div className="flex flex-wrap items-center gap-2">
        <CalmChip active={segment === "everyone"} onClick={() => onPatch({ uploaded_by: null })}>
          Everyone
        </CalmChip>
        <CalmChip active={segment === "mine"} onClick={() => onPatch({ uploaded_by: "me" })}>
          Mine
        </CalmChip>
        <ChipDropdown
          label="Friend…"
          active={segment === "friend"}
          activeLabel={friendLabel}
          empty={pickerEmpty}
        >
          {memberOptions.map((member) => (
            <ChipOption
              key={member.id}
              selected={filters.uploadedBy === String(member.id)}
              onSelect={() =>
                onPatch({
                  uploaded_by: filters.uploadedBy === String(member.id) ? null : String(member.id)
                })
              }
            >
              <span>{member.display_name}</span>
            </ChipOption>
          ))}
          {membersError ? (
            <div className="px-3 py-2">
              <InlineError message={membersError} onRetry={onRetryMembers} />
            </div>
          ) : null}
        </ChipDropdown>
        {!facetsReady && creatorOptions.length === 0 && tagOptions.length === 0 ? (
          <ChipRowSkeleton />
        ) : (
          <>
            <CalmChip active={allChipActive(filters)} onClick={onClear}>
              All
            </CalmChip>
            <ChipDropdown
              label="Creators"
              active={Boolean(filters.creator)}
              activeLabel={selectedCreatorName || undefined}
              empty={creatorOptions.length ? undefined : "No creators yet"}
            >
              {creatorOptions.map((item) => (
                <ChipOption
                  key={item.slug}
                  selected={filters.creator === item.slug}
                  onSelect={() => onPatch({ creator: filters.creator === item.slug ? null : item.slug })}
                >
                  <span>{item.name}</span>
                  {item.count ? <span className="text-xs text-slate-500">{item.count}</span> : null}
                </ChipOption>
              ))}
            </ChipDropdown>
            <ChipDropdown
              label="Tags"
              active={Boolean(filters.tag)}
              activeLabel={filters.tag || undefined}
              empty={tagOptions.length ? undefined : "No tags yet"}
            >
              {tagOptions.map((item) => (
                <ChipOption
                  key={item.name}
                  selected={filters.tag === item.name}
                  onSelect={() => onPatch({ tag: filters.tag === item.name ? null : item.name })}
                >
                  <span>{item.name}</span>
                  {item.count ? <span className="text-xs text-slate-500">{item.count}</span> : null}
                </ChipOption>
              ))}
            </ChipDropdown>
            <CalmChip active={filters.hasCover} onClick={() => onPatch({ cover: filters.hasCover ? null : "1" })}>
              Has cover
            </CalmChip>
          </>
        )}
        <CalmChip
          active={density === "compact"}
          onClick={() => onDensity(density === "compact" ? "comfortable" : "compact")}
        >
          <IconGrid className="h-3.5 w-3.5" />
          Compact
        </CalmChip>
        {engine ? <span className="ml-auto text-xs text-slate-500">{engine}</span> : null}
      </div>

      {filtersActive ? (
        <div className="mt-2 flex flex-wrap items-center gap-2">
          {queryLabel ? <FilterPill label={queryLabel} onRemove={() => onPatch({ q: null })} /> : null}
          {filters.creator && selectedCreatorName ? (
            <FilterPill label={selectedCreatorName} onRemove={() => onPatch({ creator: null })} />
          ) : null}
          {filters.tag ? <FilterPill label={filters.tag} onRemove={() => onPatch({ tag: null })} /> : null}
          {filters.hasCover ? <FilterPill label="Has cover" onRemove={() => onPatch({ cover: null })} /> : null}
          <button type="button" onClick={onClear} className="text-xs text-slate-400 hover:text-white">
            Clear All
          </button>
        </div>
      ) : null}

      {loadError ? (
        <div className="mt-3">
          <InlineError message={loadError} onRetry={onRetry} />
        </div>
      ) : null}
    </div>
  );
}
