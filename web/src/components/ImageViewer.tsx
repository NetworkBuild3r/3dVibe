import { useEffect, useState } from "react";
import { fetchAuthedBlob } from "../api";

type Props = {
  url: string;
  label: string;
};

export function ImageViewer({ url, label }: Props) {
  const [src, setSrc] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let objectUrl: string | null = null;
    let cancelled = false;
    fetchAuthedBlob(url)
      .then((blob) => {
        if (cancelled) return;
        objectUrl = URL.createObjectURL(blob);
        setSrc(objectUrl);
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load image");
      });
    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [url]);

  return (
    <div className="overflow-hidden rounded-2xl border border-white/10 bg-ink-900">
      <div className="grid h-80 place-items-center bg-[#1a2330]">
        {src ? (
          <img
            src={src}
            alt={label}
            className="h-48 w-48 object-contain shadow-lg"
            style={{ imageRendering: "pixelated" }}
          />
        ) : null}
        {!src && !error ? <p className="text-sm text-slate-500">Loading image…</p> : null}
      </div>
      <p className="border-t border-white/5 px-4 py-2 text-xs text-slate-400">{error ?? label}</p>
    </div>
  );
}
