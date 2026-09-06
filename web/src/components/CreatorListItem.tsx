import { Link } from "react-router-dom";
import type { Creator, ModelCard } from "../api";
import { modelCountLabel, modelCountOf } from "../creators";
import { CoverMosaic } from "./CoverMosaic";
import { IconChevronRight } from "./Icons";

export function CreatorListItem({
  creator,
  covers = [],
  selected,
  to
}: {
  creator: Creator;
  covers?: ModelCard[];
  selected?: boolean;
  to: string;
}) {
  const count = modelCountOf(creator, covers);

  return (
    <Link
      to={to}
      aria-current={selected ? "page" : undefined}
      className={`flex items-center gap-3 rounded-xl border px-3 py-2.5 transition ${
        selected
          ? "border-accent-500/55 bg-ink-900"
          : "border-transparent bg-ink-900/60 hover:border-white/10 hover:bg-ink-900"
      }`}
    >
      <CoverMosaic covers={covers} className="h-12 w-12 shrink-0 rounded-md" />
      <div className="min-w-0 flex-1">
        <p className="truncate font-medium text-white">{creator.name}</p>
        <p className="text-xs text-slate-500">{modelCountLabel(count)}</p>
      </div>
      <IconChevronRight className="h-4 w-4 shrink-0 text-slate-600" />
    </Link>
  );
}
