import { useEffect, useState } from "react";
import { api, type CurationProposal } from "../api";

export function CurationPage() {
  const [proposals, setProposals] = useState<CurationProposal[]>([]);
  const [error, setError] = useState<string | null>(null);

  async function refresh() {
    const payload = await api.proposals();
    setProposals(payload.proposals);
  }

  useEffect(() => {
    refresh().catch((err) => setError(err instanceof Error ? err.message : "Failed"));
  }, []);

  async function act(id: number, action: "approve" | "reject") {
    if (action === "approve") await api.approveProposal(id);
    else await api.rejectProposal(id);
    await refresh();
  }

  return (
    <div>
      <h1 className="font-display text-3xl text-white">Curation queue</h1>
      <p className="mt-1 max-w-2xl text-sm text-slate-400">
        HITL proposals from an external sidecar. 3dvibe stores the suggestion and your decision. Spark is not required
        for this MVP.
      </p>
      {error ? <p className="mt-4 text-rose-300">{error}</p> : null}
      <div className="mt-6 space-y-3">
        {proposals.map((proposal) => (
          <article key={proposal.id} className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p className="text-xs uppercase tracking-wide text-slate-500">
                  {proposal.kind} · {proposal.status}
                </p>
                <h2 className="mt-1 text-lg text-white">{proposal.summary}</h2>
                <pre className="mt-2 overflow-auto text-xs text-slate-400">{JSON.stringify(proposal.payload, null, 2)}</pre>
              </div>
              {proposal.status === "pending" ? (
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={() => void act(proposal.id, "approve")}
                    className="rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950"
                  >
                    Approve
                  </button>
                  <button
                    type="button"
                    onClick={() => void act(proposal.id, "reject")}
                    className="rounded-lg border border-white/15 px-3 py-1.5 text-sm"
                  >
                    Reject
                  </button>
                </div>
              ) : (
                <p className="text-sm text-slate-500">Reviewed</p>
              )}
            </div>
          </article>
        ))}
        {proposals.length === 0 ? <p className="text-slate-500">No proposals yet.</p> : null}
      </div>
    </div>
  );
}
