import { FormEvent, useState } from "react";
import { Link, Navigate } from "react-router-dom";
import { useAuth } from "../auth";

export function LoginPage() {
  const { user, ready, login } = useAuth();
  const [email, setEmail] = useState("owner@3dvibe.local");
  const [password, setPassword] = useState("vibe-dev-password");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (ready && user) return <Navigate to="/" replace />;

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await login(email, password);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto grid min-h-screen max-w-md place-items-center px-4">
      <form onSubmit={(event) => void onSubmit(event)} className="w-full rounded-2xl border border-white/10 bg-ink-900/80 p-8 shadow-2xl">
        <p className="font-display text-sm uppercase tracking-[0.2em] text-accent-400">3dvibe</p>
        <h1 className="mt-2 font-display text-3xl text-white">Open the library</h1>
        <p className="mt-2 text-sm text-slate-400">
          One shared catalog on the owner&apos;s disk. Friends who were invited can sign in here.
        </p>
        <label className="mt-6 block text-sm text-slate-300">
          Email
          <input
            className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-white outline-none ring-accent-500 focus:ring-2"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            type="email"
            autoComplete="username"
          />
        </label>
        <label className="mt-4 block text-sm text-slate-300">
          Password
          <input
            className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-white outline-none ring-accent-500 focus:ring-2"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            type="password"
            autoComplete="current-password"
          />
        </label>
        {error ? <p className="mt-3 text-sm text-rose-300">{error}</p> : null}
        <button
          type="submit"
          disabled={busy}
          className="mt-6 w-full rounded-lg bg-accent-500 py-2.5 font-medium text-ink-950 hover:bg-accent-400 disabled:opacity-60"
        >
          {busy ? "Signing in…" : "Sign in"}
        </button>
        <p className="mt-4 text-center text-xs text-slate-500">
          Have an invite link? Open it to create an account.{" "}
          <Link to="/" className="text-accent-400">
            Library
          </Link>
        </p>
      </form>
    </div>
  );
}
