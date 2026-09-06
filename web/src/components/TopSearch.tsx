import { FormEvent } from "react";
import { useLocation, useNavigate, useSearchParams } from "react-router-dom";
import { IconSearch } from "./Icons";

export function TopSearch() {
  const location = useLocation();
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const onCreators = location.pathname.startsWith("/creators");
  const onLibrary = location.pathname === "/";
  const query = params.get("q") || "";
  const placeholder = onCreators ? "Search creators..." : "Search models, creators, tags...";

  function applyQuery(value: string) {
    if (onCreators || onLibrary) {
      const next = new URLSearchParams(params);
      if (value) next.set("q", value);
      else next.delete("q");
      setParams(next, { replace: true });
      return;
    }
    const next = new URLSearchParams();
    if (value) next.set("q", value);
    navigate({ pathname: "/", search: next.toString() ? `?${next}` : "" });
  }

  function onSubmit(event: FormEvent) {
    event.preventDefault();
    applyQuery(query);
  }

  return (
    <form onSubmit={onSubmit} className="relative mx-auto w-full max-w-xl">
      <IconSearch className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500" />
      <input
        value={query}
        onChange={(event) => applyQuery(event.target.value)}
        placeholder={placeholder}
        aria-label={placeholder}
        className="w-full rounded-full border border-white/10 bg-ink-900 py-2 pl-10 pr-4 text-sm text-white outline-none ring-accent-500 placeholder:text-slate-500 focus:ring-2"
      />
    </form>
  );
}
