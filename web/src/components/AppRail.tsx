import type { ReactNode } from "react";
import { NavLink } from "react-router-dom";
import { useAuth } from "../auth";
import {
  IconCreators,
  IconDuplicates,
  IconLibrary,
  IconMark,
  IconPrints,
  IconShelves,
  IconUpload
} from "./Icons";

const item =
  "relative flex items-center gap-3 rounded-xl px-3 py-2 text-sm transition";
const idle = "text-slate-400 hover:bg-white/5 hover:text-slate-100";
const active = "bg-accent-500/10 text-accent-400";

function RailLink({
  to,
  end,
  icon: Icon,
  children
}: {
  to: string;
  end?: boolean;
  icon: (props: { className?: string }) => ReactNode;
  children: ReactNode;
}) {
  return (
    <NavLink
      to={to}
      end={end}
      className={({ isActive }) => `${item} ${isActive ? active : idle}`}
    >
      {({ isActive }) => (
        <>
          {isActive ? <span className="absolute inset-y-2 left-0 w-0.5 rounded-full bg-accent-400" /> : null}
          <Icon className="h-5 w-5 shrink-0" />
          <span>{children}</span>
        </>
      )}
    </NavLink>
  );
}

export function AppRail() {
  const { user } = useAuth();

  return (
    <aside className="sticky top-0 flex h-screen w-52 shrink-0 flex-col border-r border-white/5 bg-ink-950/90 px-3 py-4">
      <NavLink to="/" className="mb-6 flex items-center gap-2 px-2">
        <IconMark className="h-8 w-8" />
        <span className="font-display text-lg tracking-tight text-white">3dvibe</span>
      </NavLink>
      <nav className="flex flex-1 flex-col gap-1">
        <RailLink to="/" end icon={IconLibrary}>
          Library
        </RailLink>
        <RailLink to="/creators" icon={IconCreators}>
          Creators
        </RailLink>
        <RailLink to="/shelves" icon={IconShelves}>
          Shelves
        </RailLink>
        <RailLink to="/prints" icon={IconPrints}>
          Prints
        </RailLink>
        <RailLink to="/duplicates" icon={IconDuplicates}>
          Duplicates
        </RailLink>
        {user?.can_upload ? (
          <RailLink to="/upload" icon={IconUpload}>
            Upload
          </RailLink>
        ) : null}
      </nav>
    </aside>
  );
}
