import { useState } from "react";
import type { ModelCard } from "../types";
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
  const cheap = cheapCoverUrl(model);
  const full = fullCoverUrl(model);
  // Never leave the card on the 32px LQIP — it scales into an unreadable blob.
  // preferLqip only means "paint LQIP first"; the sharp cover is the image.
  const src = full || cheap;
  const backdrop = preferLqip && cheap && full && cheap !== full ? cheap : null;
  const showImage = visual === "image" && !broken && src;

  if (showImage) {
    return (
      <span className={`relative block h-full w-full overflow-hidden ${className}`}>
        {backdrop ? (
          <img
            src={resolveCoverUrl(backdrop)}
            alt=""
            aria-hidden
            className="absolute inset-0 h-full w-full scale-105 object-cover blur-sm"
          />
        ) : null}
        <img
          src={resolveCoverUrl(src)}
          alt={label || model.title}
          className="cover-fade-in relative h-full w-full object-cover"
          onError={() => setBroken(true)}
        />
      </span>
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
