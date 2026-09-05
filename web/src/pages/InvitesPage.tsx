import { FormEvent, useEffect, useState } from "react";
import { api, type Invite, type LibraryInfo } from "../api";

function inviteUrl(invite: Invite) {
  const path = invite.redeem_path || `/invite/${invite.token || ""}`;
  return `${window.location.origin}${path}`;
}

export function InvitesPage() {
  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [invites, setInvites] = useState<Invite[]>([]);
  const [libraryId, setLibraryId] = useState<number | "">("");
  const [email, setEmail] = useState("");
  const [role, setRole] = useState("contributor");
  const [expiresInDays, setExpiresInDays] = useState("14");
  const [created, setCreated] = useState<Invite | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function refresh() {
    const [libraryPayload, invitePayload] = await Promise.all([api.libraries(), api.invites()]);
    setLibraries(libraryPayload.libraries);
    setInvites(invitePayload.invites);
    if (libraryId === "" && libraryPayload.libraries[0]) setLibraryId(libraryPayload.libraries[0].id);
  }

  useEffect(() => {
    refresh().catch((err) => setError(err instanceof Error ? err.message : "Failed to load invites"));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    if (libraryId === "") return;
    setBusy(true);
    setError(null);
    try {
      const payload = await api.createInvite({
        library_id: libraryId,
        email: email.trim() || undefined,
        role,
        expires_in_days: expiresInDays.trim() === "" ? "" : Number(expiresInDays)
      });
      setCreated(payload.invite);
      setEmail("");
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create invite");
    } finally {
      setBusy(false);
    }
  }

  async function revoke(id: number) {
    await api.revokeInvite(id);
    await refresh();
  }

  async function copy(invite: Invite) {
    await navigator.clipboard.writeText(inviteUrl(invite));
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="font-display text-3xl text-white">Friend invites</h1>
        <p className="mt-2 max-w-2xl text-sm text-slate-400">
          Invite people into the one shared library. They browse and search the whole catalog. Contributors can upload
          into the same pile. There are no private folders.
        </p>
      </div>

      <form onSubmit={(event) => void onSubmit(event)} className="rounded-2xl border border-white/10 bg-ink-900/70 p-5">
        <h2 className="font-display text-xl text-white">Create invite</h2>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <label className="text-sm text-slate-300">
            Library
            <select
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              value={libraryId}
              onChange={(event) => setLibraryId(Number(event.target.value))}
            >
              {libraries.map((library) => (
                <option key={library.id} value={library.id}>
                  {library.name}
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm text-slate-300">
            Role
            <select
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              value={role}
              onChange={(event) => setRole(event.target.value)}
            >
              <option value="contributor">Contributor (can upload)</option>
              <option value="viewer">Viewer (read-only)</option>
            </select>
          </label>
          <label className="text-sm text-slate-300">
            Email (optional)
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              type="email"
              placeholder="Leave blank for a shareable link"
            />
          </label>
          <label className="text-sm text-slate-300">
            Expires in days
            <input
              className="mt-1 w-full rounded-lg border border-white/10 bg-ink-950 px-3 py-2"
              value={expiresInDays}
              onChange={(event) => setExpiresInDays(event.target.value)}
              placeholder="Blank = no expiry"
            />
          </label>
        </div>
        {error ? <p className="mt-3 text-sm text-rose-300">{error}</p> : null}
        <button
          type="submit"
          disabled={busy || libraryId === ""}
          className="mt-4 rounded-lg bg-accent-500 px-4 py-2 text-sm font-medium text-ink-950 hover:bg-accent-400 disabled:opacity-60"
        >
          {busy ? "Creating…" : "Create invite link"}
        </button>
        {created?.token ? (
          <div className="mt-4 rounded-xl border border-accent-500/30 bg-ink-950 p-3 text-sm">
            <p className="text-slate-400">Share this single-use link:</p>
            <p className="mt-1 break-all font-mono text-accent-400">{inviteUrl(created)}</p>
            <button type="button" className="mt-2 text-accent-400" onClick={() => void copy(created)}>
              Copy link
            </button>
          </div>
        ) : null}
      </form>

      <section className="rounded-2xl border border-white/10 bg-ink-900/70 p-5">
        <h2 className="font-display text-xl text-white">Issued invites</h2>
        <ul className="mt-4 divide-y divide-white/5">
          {invites.map((invite) => (
            <li key={invite.id} className="flex flex-wrap items-center justify-between gap-3 py-3 text-sm">
              <div>
                <p className="text-slate-100">
                  {invite.email || "Open link"} · {invite.role}
                </p>
                <p className="text-xs text-slate-500">
                  {invite.pending ? "Pending" : invite.revoked_at ? "Revoked" : "Redeemed"}
                  {invite.expires_at ? ` · expires ${new Date(invite.expires_at).toLocaleDateString()}` : ""}
                </p>
              </div>
              <div className="flex gap-2">
                {invite.pending && invite.token ? (
                  <button type="button" className="text-accent-400" onClick={() => void copy(invite)}>
                    Copy
                  </button>
                ) : null}
                {invite.pending ? (
                  <button type="button" className="text-rose-300" onClick={() => void revoke(invite.id)}>
                    Revoke
                  </button>
                ) : null}
              </div>
            </li>
          ))}
          {invites.length === 0 ? <li className="py-3 text-slate-500">No invites yet.</li> : null}
        </ul>
      </section>
    </div>
  );
}
