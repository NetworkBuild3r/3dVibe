import { useState } from "react";
import type { ModelCard } from "../api";
import { coverVisual, resolveCoverUrl } from "../covers";

export function CoverMedia({
  model,
  className = "",
  label
}: {
  model: Pick<ModelCard, "title" | "cover_status" | "cover_url" | "cover_placeholder">;
  className?: string;
  label?: string;
}) {
  const visual = coverVisual(model);
  const [broken, setBroken] = useState(false);
  const showImage = visual === "image" && !broken && model.cover_url;

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
    <div className={`cover-checker h-full w-full ${className}`} role="img" aria-label="Cover unavailable">
      <span className="sr-only">Cover missing</span>
    </div>
  );
}
