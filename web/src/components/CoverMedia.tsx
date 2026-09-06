import { useState } from "react";
import type { ModelCard } from "../api";
import { coverStatusOf, coverVisual, resolveCoverUrl } from "../covers";

export function CoverMedia({
  model,
  className = "",
  label,
  showFailedCopy = true
}: {
  model: Pick<ModelCard, "title" | "cover_status" | "cover_url" | "cover_placeholder">;
  className?: string;
  label?: string;
  showFailedCopy?: boolean;
}) {
  const visual = coverVisual(model);
  const status = coverStatusOf(model);
  const [broken, setBroken] = useState(false);
  const showImage = visual === "image" && !broken && model.cover_url;
  const failed = status === "failed" || (visual === "placeholder" && broken);

  if (showImage) {
    return (
      <img
        src={resolveCoverUrl(model.cover_url!)}
        alt={label || model.title}
        className={`cover-fade-in h-full w-full object-cover ${className}`}
        onError={() => setBroken(true)}
      />
    );
  }

  if (visual === "shimmer") {
    return (
      <div className={`cover-shimmer h-full w-full ${className}`} role="status" aria-label="Cover pending">
        <span className="sr-only">Cover generating</span>
      </div>
    );
  }

  return (
    <div
      className={`cover-checker relative h-full w-full ${className}`}
      role="img"
      aria-label={failed ? "Cover failed" : "Cover unavailable"}
    >
      <span className="sr-only">{failed ? "Cover failed" : "Cover missing"}</span>
      {showFailedCopy && failed ? (
        <span className="pointer-events-none absolute inset-x-2 bottom-2 text-center text-[11px] leading-none text-slate-500">
          Cover failed
        </span>
      ) : null}
    </div>
  );
}
