import type { ModelCard } from "../api";
import { mosaicSlots } from "../creators";
import { CoverMedia } from "./CoverMedia";

export function CoverMosaic({
  covers,
  className = "",
  gapClass = "gap-px"
}: {
  covers: ModelCard[];
  className?: string;
  gapClass?: string;
}) {
  const cells = mosaicSlots(covers);

  return (
    <div className={`grid grid-cols-2 overflow-hidden bg-ink-800 ${gapClass} ${className}`}>
      {cells.map((model, index) => (
        <div key={model?.id ?? `empty-${index}`} className="aspect-square min-h-0 overflow-hidden">
          {model ? (
            <CoverMedia model={model} label={`${model.title} cover`} showFailedCopy={false} />
          ) : (
            <div className="cover-checker h-full w-full" />
          )}
        </div>
      ))}
    </div>
  );
}
