import { Link } from "react-router-dom";
import type { Creator, ModelCard } from "../api";
import { CoverMedia } from "./CoverMedia";
import { IconChevronRight } from "./Icons";

function MosaicCell({ model }: { model?: ModelCard }) {
  if (!model) {
    return <div className="cover-checker aspect-square rounded-sm" />;
  }
  return (
    <div className="aspect-square overflow-hidden rounded-sm">
      <CoverMedia model={model} label={`${model.title} cover`} />
    </div>
  );
}

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
  const cells = [0, 1, 2, 3].map((index) => covers[index]);
  const count = creator.model_count ?? covers.length;

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
      <div className="grid h-12 w-12 shrink-0 grid-cols-2 gap-0.5 overflow-hidden rounded-md bg-ink-800">
        {cells.map((model, index) => (
          <MosaicCell key={model?.id ?? index} model={model} />
        ))}
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate font-medium text-white">{creator.name}</p>
        <p className="text-xs text-slate-500">
          {count} model{count === 1 ? "" : "s"}
        </p>
      </div>
      <IconChevronRight className="h-4 w-4 shrink-0 text-slate-600" />
    </Link>
  );
}
