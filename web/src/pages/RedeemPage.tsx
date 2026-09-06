import { FormEvent, useEffect, useState } from "react";
import { Link, Navigate, useParams } from "react-router-dom";
import { api, type Invite } from "../api";
import { useAuth } from "../auth";

export function RedeemPage() {
  const { token } = useParams();
  const { user, ready, redeem } = useAuth();
  const [invite, setInvite] = useState<Invite | null>(null);
  const [email, setEmail] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!token) return;
    api
      .previewInvite(token)
      .then((payload) => {
        setInvite(payload.invite);
        if (payload.invite.email) setEmail(payload.invite.email);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Invite not found"));
  }, [token]);

  if (ready && user) return <Navigate to="/" replace />;

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    if (!token) return;
    setBusy(true);
    setError(null);
    try {
      await redeem(token, { email, password, display_name: displayName || email.split("@")[0] });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not redeem invite");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto grid min-h-screen max-w-md place-items-center px-4">
      <form onSubmit={(event) => void onSubmit(event)} className="w-full rounded-2xl border border-white/10 bg-ink-900/80 p-8 shadow-2xl">
        <p className="font-display text-sm uppercase tracking-[0.2em] text-accent-400">3dvibe invite</p>
        <h1 className="mt-2 font-display text-3xl text-white">Join the shared library</h1>
        <p className="mt-2 text-sm text-slate-400">
          {invite
            ? `You are joining ${invite.library_name} as a ${invite.role}. Everyone browses the same catalog.`
            : "Checking invite…"}
        </p>
        {!invite?.pending && invite ? <p className="mt-3 text-sm text-rose-300">This invite is no longer active.</p> : null}
        <label className="mt-6 block text-sm text-slate-300">
          Email
          <input
            className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-white outline-none ring-accent-500 focus:ring-2 disabled:opacity-60"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            type="email"
            required
            disabled={Boolean(invite?.email)}
            autoComplete="username"
          />
        </label>
        <label className="mt-4 block text-sm text-slate-300">
          Display name
          <input
            className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-white outline-none ring-accent-500 focus:ring-2"
            value={displayName}
            onChange={(event) => setDisplayName(event.target.value)}
            autoComplete="nickname"
          />
        </label>
        <label className="mt-4 block text-sm text-slate-300">
          Password
          <input
            className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2 text-white outline-none ring-accent-500 focus:ring-2"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            type="password"
            required
            autoComplete="new-password"
          />
        </label>
        {error ? <p className="mt-3 text-sm text-rose-300">{error}</p> : null}
        <button
          type="submit"
          disabled={busy || !invite?.pending}
          className="mt-6 w-full rounded-lg bg-accent-500 py-2.5 font-medium text-ink-950 hover:bg-accent-400 disabled:opacity-60"
        >
          {busy ? "Creating account…" : "Create account and sign in"}
        </button>
        <p className="mt-4 text-center text-xs text-slate-500">
          Already have an account?{" "}
          <Link to="/login" className="text-accent-400">
            Sign in
          </Link>
        </p>
      </form>
    </div>
  );
}
