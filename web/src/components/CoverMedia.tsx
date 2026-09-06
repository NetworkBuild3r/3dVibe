import { useState } from "react";
import type { ModelCard } from "../api";
import { cheapCoverUrl, coverStatusOf, coverVisual, fullCoverUrl, resolveCoverUrl } from "../covers";

export function CoverMedia({
  model,
  className = "",
  label,
  showFailedCopy = true,
  preferLqip = false
}: {
  model: Pick<ModelCard, "title" | "cover_status" | "cover_url" | "cover_lqip_url" | "cover_placeholder">;
  className?: string;
  label?: string;
  showFailedCopy?: boolean;
  preferLqip?: boolean;
}) {
  const visual = coverVisual(model);
  const status = coverStatusOf(model);
  const [broken, setBroken] = useState(false);
  const src = preferLqip ? cheapCoverUrl(model) : fullCoverUrl(model);
  const showImage = visual === "image" && !broken && src;

  if (showImage) {
    return (
      <img
        src={resolveCoverUrl(src)}
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

  const failed = status === "failed" || (visual === "placeholder" && broken);

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
