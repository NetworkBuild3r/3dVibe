import type { Creator, ModelCard } from "../api";
import {
  creatorDisplayName,
  facetCreators,
  facetTags,
  hasChipFilters,
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
  density,
  engine,
  facetsReady,
  loadError,
  onPatch,
  onClear,
  onRetry,
  onDensity
}: {
  filters: GalleryFilters;
  facets?: CatalogFacets;
  creators: Creator[];
  models: ModelCard[];
  density: GalleryDensity;
  engine: string;
  facetsReady: boolean;
  loadError: string | null;
  onPatch: (updates: Record<string, string | null>) => void;
  onClear: () => void;
  onRetry: () => void;
  onDensity: (density: GalleryDensity) => void;
}) {
  const creatorOptions = facetCreators(facets, creators, models);
  const tagOptions = facetTags(facets);
  const selectedCreatorName = creatorDisplayName(filters.creator, creators, models);
  const chipsActive = hasChipFilters(filters);

  return (
    <div className="gallery-filter-bar">
      <div className="flex flex-wrap items-center gap-2">
        {!facetsReady && creatorOptions.length === 0 && tagOptions.length === 0 ? (
          <ChipRowSkeleton />
        ) : (
          <>
            <CalmChip active={!chipsActive} onClick={onClear}>
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

      {chipsActive ? (
        <div className="mt-2 flex flex-wrap items-center gap-2">
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
