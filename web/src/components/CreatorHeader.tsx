import { Link } from "react-router-dom";
import type { Creator, ModelCard } from "../api";
import { libraryHrefForCreator, modelCountLabel, modelCountOf } from "../creators";
import { CoverMosaic } from "./CoverMosaic";

export function CreatorHeader({
  creator,
  covers = []
}: {
  creator: Creator;
  covers?: ModelCard[];
}) {
  const count = modelCountOf(creator, covers);

  return (
    <header className="flex flex-wrap items-center gap-4">
      <CoverMosaic covers={covers} className="h-20 w-20 shrink-0 rounded-xl" />
      <div className="min-w-0 flex-1">
        <h1 className="font-display text-3xl text-white">{creator.name}</h1>
        <p className="mt-1 text-sm text-slate-400">{modelCountLabel(count)}</p>
      </div>
      <Link
        to={libraryHrefForCreator(creator.slug)}
        className="inline-flex items-center rounded-full bg-accent-500 px-4 py-2 text-sm font-medium text-ink-950 hover:bg-accent-400"
      >
        View in Library
      </Link>
    </header>
  );
}
