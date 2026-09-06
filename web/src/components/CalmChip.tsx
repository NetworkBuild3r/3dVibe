import { useEffect, useRef, useState, type ReactNode } from "react";
import { IconChevron } from "./Icons";

const chipBase =
  "inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm transition";
const chipIdle = "border-white/10 bg-transparent text-slate-300 hover:border-white/20 hover:text-white";
const chipActive = "border-accent-500/40 bg-accent-500 text-ink-950 hover:bg-accent-400";

export function CalmChip({
  active,
  children,
  onClick,
  type = "button"
}: {
  active?: boolean;
  children: ReactNode;
  onClick?: () => void;
  type?: "button" | "submit";
}) {
  return (
    <button type={type} onClick={onClick} className={`${chipBase} ${active ? chipActive : chipIdle}`}>
      {children}
    </button>
  );
}

export function ChipDropdown({
  label,
  activeLabel,
  active,
  children,
  empty
}: {
  label: string;
  activeLabel?: string;
  active?: boolean;
  children: ReactNode;
  empty?: string;
}) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    function onDoc(event: MouseEvent) {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    }
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onDoc);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDoc);
      document.removeEventListener("keydown", onKey);
    };
  }, []);

  return (
    <div ref={root} className="relative">
      <button
        type="button"
        aria-expanded={open}
        aria-haspopup="listbox"
        onClick={() => setOpen((current) => !current)}
        className={`${chipBase} ${active ? chipActive : chipIdle}`}
      >
        {active && activeLabel ? activeLabel : label}
        <IconChevron className={`h-3.5 w-3.5 ${open ? "rotate-180" : ""}`} />
      </button>
      {open ? (
        <div
          role="listbox"
          className="absolute left-0 z-40 mt-2 max-h-72 min-w-[14rem] overflow-auto rounded-2xl border border-white/10 bg-ink-900 p-1.5 shadow-2xl"
          onClick={() => setOpen(false)}
        >
          {children}
          {empty ? <p className="px-3 py-2 text-xs text-slate-500">{empty}</p> : null}
        </div>
      ) : null}
    </div>
  );
}

export function FilterPill({
  label,
  onRemove
}: {
  label: string;
  onRemove: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onRemove}
      className={`${chipBase} ${chipActive}`}
      aria-label={`Remove ${label} filter`}
    >
      <span>{label}</span>
      <span aria-hidden className="text-ink-950/70">
        ×
      </span>
    </button>
  );
}

export function ChipOption({
  selected,
  onSelect,
  children
}: {
  selected?: boolean;
  onSelect: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      role="option"
      aria-selected={Boolean(selected)}
      onClick={onSelect}
      className={`flex w-full items-center justify-between rounded-xl px-3 py-2 text-left text-sm ${
        selected ? "bg-accent-500/15 text-accent-300" : "text-slate-200 hover:bg-white/5"
      }`}
    >
      {children}
    </button>
  );
}
