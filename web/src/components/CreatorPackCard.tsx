import { Link } from "react-router-dom";
import type { Creator, ModelCard } from "../api";
import { modelCountLabel, modelCountOf } from "../creators";
import { CoverMosaic } from "./CoverMosaic";

export function CreatorPackCard({
  creator,
  covers = [],
  to
}: {
  creator: Creator;
  covers?: ModelCard[];
  to: string;
}) {
  const count = modelCountOf(creator, covers);

  return (
    <Link to={to} className="group block min-w-0">
      <CoverMosaic covers={covers} className="aspect-square rounded-xl" />
      <p className="mt-2.5 truncate font-display text-[15px] text-white">{creator.name}</p>
      <p className="text-sm text-slate-400">{modelCountLabel(count)}</p>
    </Link>
  );
}
