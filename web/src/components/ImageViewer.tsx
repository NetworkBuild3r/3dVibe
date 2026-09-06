import { useEffect, useState } from "react";
import { fetchMemberPreview, isAbortError } from "../api";
import { CANCELLED_COPY, viewerStatusCopy } from "../archives";

type Props = {
  url: string;
  label: string;
};

export function ImageViewer({ url, label }: Props) {
  const [src, setSrc] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState("Loading image…");

  useEffect(() => {
    let objectUrl: string | null = null;
    let cancelled = false;
    const abort = new AbortController();
    setSrc(null);
    setError(null);
    setStatus("Loading image…");

    fetchMemberPreview(url, { signal: abort.signal })
      .then((blob) => {
        if (cancelled) return;
        objectUrl = URL.createObjectURL(blob);
        setSrc(objectUrl);
        setStatus(label);
      })
      .catch((err) => {
        if (cancelled) return;
        if (isAbortError(err)) {
          setStatus(CANCELLED_COPY);
          return;
        }
        setError(viewerStatusCopy(err));
      });

    return () => {
      cancelled = true;
      abort.abort();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [url, label]);

  return (
    <div className="overflow-hidden rounded-2xl border border-white/10 bg-ink-900">
      <div className="relative grid h-80 place-items-center bg-[#1a2330]">
        {src ? (
          <img
            src={src}
            alt={label}
            className="cover-fade-in h-48 w-48 object-contain shadow-lg"
            style={{ imageRendering: "pixelated" }}
          />
        ) : null}
        {!src && !error ? <div className="cover-shimmer absolute inset-0" role="status" aria-label={status} /> : null}
      </div>
      <p className="border-t border-white/5 px-4 py-2 text-xs text-slate-400">{error ?? status}</p>
    </div>
  );
}
