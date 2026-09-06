export function formatBytes(value: number | null | undefined) {
  const bytes = value ?? 0;
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function formatRelativeTime(value?: string | null) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  const seconds = Math.round((Date.now() - date.getTime()) / 1000);
  if (Math.abs(seconds) < 45) return "just now";
  if (seconds < 90) return "1m ago";
  if (seconds < 3600) return `${Math.round(seconds / 60)}m ago`;
  if (seconds < 5400) return "1h ago";
  if (seconds < 86400) return `${Math.round(seconds / 3600)}h ago`;
  if (seconds < 86400 * 2) return "1d ago";
  if (seconds < 86400 * 7) return `${Math.round(seconds / 86400)}d ago`;
  return date.toLocaleDateString();
}
