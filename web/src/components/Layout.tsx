import { useEffect, useRef } from "react";
import { Outlet } from "react-router-dom";
import { AppRail } from "./AppRail";
import { AvatarMenu } from "./AvatarMenu";
import { ScanButton } from "./ScanButton";
import { TopSearch } from "./TopSearch";

export function Layout() {
  const headerRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    const node = headerRef.current;
    if (!node) return;
    const sync = () => {
      document.documentElement.style.setProperty("--app-header-height", `${node.offsetHeight}px`);
    };
    sync();
    const observer = new ResizeObserver(sync);
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  return (
    <div className="flex min-h-screen">
      <AppRail />
      <div className="flex min-w-0 flex-1 flex-col">
        <header ref={headerRef} className="sticky top-0 z-20 border-b border-white/5 bg-ink-950/85 backdrop-blur">
          <div className="flex items-center gap-4 px-5 py-3">
            <div className="flex-1" />
            <div className="w-full max-w-xl flex-1">
              <TopSearch />
            </div>
            <div className="flex flex-1 items-center justify-end gap-3">
              <ScanButton />
              <AvatarMenu />
            </div>
          </div>
        </header>
        <main className="min-w-0 flex-1 px-6 py-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
