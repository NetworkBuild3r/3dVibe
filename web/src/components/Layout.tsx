import { NavLink, Outlet } from "react-router-dom";
import { useAuth } from "../auth";

const link = ({ isActive }: { isActive: boolean }) =>
  `rounded-full px-3 py-1.5 text-sm ${isActive ? "bg-accent-500/15 text-accent-400" : "text-slate-300 hover:text-white"}`;

export function Layout() {
  const { user, logout } = useAuth();

  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-20 border-b border-white/5 bg-ink-950/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3">
          <div className="flex items-center gap-6">
            <NavLink to="/" className="font-display text-lg tracking-tight text-white">
              3dvibe
            </NavLink>
            <nav className="flex flex-wrap items-center gap-1">
              <NavLink to="/" className={link} end>
                Library
              </NavLink>
              <NavLink to="/shelves" className={link}>
                Shelves
              </NavLink>
              <NavLink to="/duplicates" className={link}>
                Duplicates
              </NavLink>
              {user?.can_upload ? (
                <NavLink to="/upload" className={link}>
                  Upload
                </NavLink>
              ) : null}
              {user?.can_invite || user?.can_manage_libraries ? (
                <NavLink to="/libraries" className={link}>
                  Libraries
                </NavLink>
              ) : null}
              {user?.can_invite ? (
                <NavLink to="/invites" className={link}>
                  Invites
                </NavLink>
              ) : null}
              <NavLink to="/curation" className={link}>
                Curation
              </NavLink>
              <NavLink to="/prints" className={link}>
                Prints
              </NavLink>
              {user?.can_manage_printers ? (
                <NavLink to="/printers" className={link}>
                  Printers
                </NavLink>
              ) : null}
            </nav>
          </div>
          <div className="flex items-center gap-3 text-sm text-slate-400">
            <span>
              {user?.display_name}
              {user?.role ? <span className="ml-2 text-xs uppercase tracking-wide text-slate-500">{user.role}</span> : null}
            </span>
            <button
              type="button"
              onClick={() => void logout()}
              className="rounded-full border border-white/10 px-3 py-1 text-slate-200 hover:border-accent-500/40"
            >
              Sign out
            </button>
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6">
        <Outlet />
      </main>
    </div>
  );
}
