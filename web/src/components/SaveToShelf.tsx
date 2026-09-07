import { Link } from "react-router-dom";
import type { BookmarkFolder } from "../types";

type SaveToShelfProps = {
  folders: BookmarkFolder[];
  folderIds?: number[];
  onSave: (folderId: number) => void;
  disabled?: boolean;
  className?: string;
  selectClassName?: string;
};

export function SaveToShelf({
  folders,
  folderIds,
  onSave,
  disabled,
  className = "text-sm text-accent-400",
  selectClassName = "rounded-lg border border-white/10 bg-ink-950 px-3 py-1.5 text-sm"
}: SaveToShelfProps) {
  if (!folders.length) {
    return (
      <Link to="/shelves" className={className}>
        Create a shelf
      </Link>
    );
  }

  return (
    <select
      className={`${selectClassName} disabled:opacity-60`}
      defaultValue=""
      aria-label="Save to shelf"
      disabled={disabled}
      onChange={(event) => {
        const folderId = Number(event.target.value);
        if (folderId) onSave(folderId);
        event.target.value = "";
      }}
    >
      <option value="">Save to shelf…</option>
      {folders.map((folder) => (
        <option key={folder.id} value={folder.id}>
          {folder.name}
          {folderIds?.includes(folder.id) ? " ✓" : ""}
        </option>
      ))}
    </select>
  );
}
