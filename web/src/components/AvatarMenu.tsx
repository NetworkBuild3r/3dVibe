import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth";
import { IconChevron } from "./Icons";

export function AvatarMenu() {
  const { user, logout } = useAuth();
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement | null>(null);
  const initial = (user?.display_name || user?.email || "?").trim().charAt(0).toUpperCase();

  useEffect(() => {
    function onDoc(event: MouseEvent) {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onDoc);
    return () => document.removeEventListener("mousedown", onDoc);
  }, []);

  if (!user) return null;

  return (
    <div ref={root} className="relative">
      <button
        type="button"
        aria-expanded={open}
        aria-haspopup="menu"
        onClick={() => setOpen((current) => !current)}
        className="flex items-center gap-2 rounded-full border border-white/10 py-1 pl-1 pr-2 text-sm text-slate-200 hover:border-white/20"
      >
        <span className="grid h-7 w-7 place-items-center rounded-full bg-ink-800 text-xs font-medium text-accent-300">
          {initial}
        </span>
        <IconChevron className="h-3.5 w-3.5 text-slate-500" />
      </button>
      {open ? (
        <div
          role="menu"
          className="absolute right-0 z-30 mt-2 w-52 overflow-hidden rounded-2xl border border-white/10 bg-ink-900 py-1 shadow-2xl"
        >
          <div className="border-b border-white/5 px-3 py-2">
            <p className="truncate text-sm text-white">{user.display_name}</p>
            <p className="text-[11px] uppercase tracking-wide text-slate-500">{user.role}</p>
          </div>
          {user.can_invite || user.can_manage_libraries ? (
            <Link to="/libraries" role="menuitem" className="block px-3 py-2 text-sm text-slate-200 hover:bg-white/5" onClick={() => setOpen(false)}>
              Libraries
            </Link>
          ) : null}
          {user.can_invite ? (
            <Link to="/invites" role="menuitem" className="block px-3 py-2 text-sm text-slate-200 hover:bg-white/5" onClick={() => setOpen(false)}>
              Invites
            </Link>
          ) : null}
          <Link to="/curation" role="menuitem" className="block px-3 py-2 text-sm text-slate-200 hover:bg-white/5" onClick={() => setOpen(false)}>
            Curation
          </Link>
          {user.can_invite ? (
            <Link to="/settings/curator" role="menuitem" className="block px-3 py-2 text-sm text-slate-200 hover:bg-white/5" onClick={() => setOpen(false)}>
              Curator
            </Link>
          ) : null}
          {user.can_manage_printers ? (
            <Link to="/printers" role="menuitem" className="block px-3 py-2 text-sm text-slate-200 hover:bg-white/5" onClick={() => setOpen(false)}>
              Printers
            </Link>
          ) : null}
          <button
            type="button"
            role="menuitem"
            className="block w-full px-3 py-2 text-left text-sm text-slate-200 hover:bg-white/5"
            onClick={() => void logout()}
          >
            Sign out
          </button>
        </div>
      ) : null}
    </div>
  );
}
