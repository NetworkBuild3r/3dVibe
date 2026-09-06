import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import type { DuplicateGroup, DuplicateMember } from "../api";
import {
  EXTRACT_AND_MERGE_COPY,
  EXTRACT_COPY,
  EXTRACTING_COPY,
  MERGE_UNSUPPORTED_COPY,
  allMembersMergeable,
  archiveMemberIds,
  archiveMembersToExtract,
  canExtractArchiveMembers,
  confidenceMeta,
  coverFromMembers,
  digestSnippet,
  groupMembers,
  isArchiveResident,
  looseAssetIds,
  memberColumns,
  memberDisplayPath,
  memberKey,
  mergePayloadForGroup,
  preferredTargetId,
  reasonLabel,
  statusMeta,
  truncateArchivePath,
  type MemberColumn
} from "../duplicates";
import { formatBytes } from "../format";
import { CoverMedia } from "./CoverMedia";
import { InlineError, Pulse } from "./UiStates";

export function ConfidenceBadge({
  confidence,
  reason,
  size = "sm"
}: {
  confidence: string;
  reason?: string;
  size?: "sm" | "md";
}) {
  const meta = confidenceMeta(confidence);
  const title = reason ? `${meta.hint} · ${reasonLabel(reason)}` : meta.hint;
  return (
    <span
      title={title}
      className={`inline-flex rounded-full border px-2 py-0.5 uppercase tracking-wide text-slate-300 ${
        size === "md" ? "text-xs" : "text-[11px]"
      } ${
        meta.confidence === "exact"
          ? "border-accent-500/40 text-accent-400"
          : meta.confidence === "geometry"
            ? "border-white/20 text-slate-200"
            : "border-white/10 text-slate-400"
      }`}
    >
      {meta.label}
    </span>
  );
}

export function StatusChip({ status }: { status: string }) {
  const meta = statusMeta(status);
  if (meta.status === "open") return null;
  return (
    <span title={meta.hint} className="rounded-full bg-white/5 px-2 py-0.5 text-[11px] uppercase tracking-wide text-slate-400">
      {meta.label}
    </span>
  );
}

export function ResidencePill({ archive, size = "md" }: { archive: boolean; size?: "sm" | "md" }) {
  return (
    <span
      className={`inline-flex rounded-full border border-white/10 uppercase tracking-wide text-slate-400 ${
        size === "sm" ? "px-1.5 py-0.5 text-[10px]" : "px-2 py-0.5 text-[11px]"
      }`}
    >
      {archive ? "In archive" : "Loose"}
    </span>
  );
}

function MemberPath({ member }: { member: DuplicateMember }) {
  const full = memberDisplayPath(member);
  const archive = isArchiveResident(member);
  return (
    <p className={`mt-1 font-mono text-xs text-slate-500 ${archive ? "" : "truncate"}`} title={full}>
      {archive ? truncateArchivePath(full) : full}
    </p>
  );
}

export function DuplicateReviewSkeleton() {
  return (
    <div className="grid gap-4 md:grid-cols-2" aria-hidden>
      {[0, 1].map((index) => (
        <div key={index} className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
          <Pulse className="aspect-square" />
          <Pulse className="mt-3 h-4 w-2/3" />
          <Pulse className="mt-2 h-3 w-1/2" />
          <Pulse className="mt-3 h-3 w-full" />
        </div>
      ))}
    </div>
  );
}

export function DuplicateReview({
  group,
  canReview,
  busy,
  busyLabel,
  error,
  onKeep,
  onDismiss,
  onMerge,
  onExtract,
  onExtractAndMerge,
  onClose
}: {
  group: DuplicateGroup;
  canReview: boolean;
  busy: boolean;
  busyLabel?: string | null;
  error: string | null;
  onKeep: () => void;
  onDismiss: () => void;
  onMerge: (payload: { source_ids: number[]; asset_ids?: number[]; target_id: number; title?: string }) => void;
  onExtract?: (payload: { archive_member_ids: number[]; target_id?: number; title?: string }) => void;
  onExtractAndMerge?: (payload: {
    archive_member_ids: number[];
    asset_ids: number[];
    target_id?: number;
    title?: string;
  }) => void;
  onClose: () => void;
}) {
  const columns = useMemo(() => memberColumns(group), [group]);
  const members = useMemo(() => groupMembers(group), [group]);
  const extractMembers = useMemo(() => archiveMembersToExtract(group), [group]);
  const open = group.status === "open";
  const showActions = canReview && open;
  const mergeableSelection = allMembersMergeable(group);
  const extractable = canExtractArchiveMembers(group);
  const [targetId, setTargetId] = useState(preferredTargetId(group));
  const [confirming, setConfirming] = useState<"merge" | "extract" | "extract-merge" | null>(null);

  useEffect(() => {
    setTargetId(preferredTargetId(group));
    setConfirming(null);
  }, [group.id]);

  useEffect(() => {
    if (!columns.some((column) => column.modelId === targetId)) {
      setTargetId(columns[0]?.modelId);
    }
  }, [columns, targetId]);

  useEffect(() => {
    if (error) setConfirming(null);
  }, [error]);

  const target = columns.find((column) => column.modelId === targetId) || columns[0];
  const sources = columns.filter((column) => column.modelId !== target?.modelId);
  const canMerge = Boolean(target && sources.length > 0 && mergeableSelection);
  const showTargetRadios = showActions && (canMerge || extractable);
  const extracting = busy && (confirming === "extract" || confirming === "extract-merge");

  function submitMerge() {
    if (!target || !canMerge) return;
    onMerge(mergePayloadForGroup(group, target.modelId, target.title));
  }

  function extractPayload() {
    return {
      archive_member_ids: archiveMemberIds(group),
      target_id: target?.modelId,
      title: target?.title
    };
  }

  function submitExtract() {
    if (!extractable || !onExtract) return;
    onExtract(extractPayload());
  }

  function submitExtractAndMerge() {
    if (!extractable || !onExtractAndMerge) return;
    onExtractAndMerge({
      ...extractPayload(),
      asset_ids: looseAssetIds(group)
    });
  }

  return (
    <div className="fixed inset-0 z-40 flex justify-end bg-ink-950/65 backdrop-blur-sm">
      <button type="button" className="absolute inset-0 cursor-default" aria-label="Close review" onClick={onClose} />
      <aside className="relative flex h-full w-full max-w-4xl flex-col border-l border-white/10 bg-ink-950 shadow-2xl">
        <div className="flex items-start justify-between gap-4 border-b border-white/5 px-5 py-4">
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <ConfidenceBadge confidence={group.confidence} reason={group.reason} size="md" />
              <StatusChip status={group.status} />
              <span className="text-xs text-slate-500">
                {members.length} {members.length === 1 ? "member" : "members"}
              </span>
            </div>
            <h2 className="mt-2 font-display text-2xl text-white">{group.filename || "Duplicate group"}</h2>
            <p className="mt-1 max-w-xl text-sm text-slate-400">
              Compare copies side by side. Exact is the same bytes. Geometry is the same mesh in different files. Likely
              is a weak signal — you decide. Kept copies stay in the shared catalog.
            </p>
          </div>
          <button type="button" onClick={onClose} className="rounded-lg border border-white/10 px-2.5 py-1 text-sm text-slate-300 hover:text-white">
            Close
          </button>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-5">
          {error ? <div className="mb-4"><InlineError message={error} /></div> : null}
          <div className={`grid gap-4 ${columns.length > 2 ? "md:grid-cols-3" : "md:grid-cols-2"}`}>
            {columns.map((column) => {
              const creator = column.model?.creator?.name || column.model?.uploaded_by?.display_name;
              const cover = column.model || coverFromMembers(column.members, column.title);
              return (
                <article key={column.modelId} className="rounded-2xl border border-white/10 bg-ink-900/70 p-4">
                  <div className="overflow-hidden rounded-xl bg-ink-950">
                    {cover ? (
                      <div className="aspect-square">
                        <CoverMedia model={cover} />
                      </div>
                    ) : (
                      <div className="cover-checker aspect-square" role="img" aria-label="Cover unavailable" />
                    )}
                  </div>
                  <div className="mt-3 flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <Link to={`/models/${column.modelId}`} className="block truncate font-display text-white hover:text-accent-400">
                        {column.title}
                      </Link>
                      {creator ? <p className="mt-0.5 truncate text-sm text-slate-400">{creator}</p> : null}
                    </div>
                    {showTargetRadios ? (
                      <label className="flex shrink-0 items-center gap-1.5 text-xs text-slate-300">
                        <input
                          type="radio"
                          name={`merge-target-${group.id}`}
                          checked={target?.modelId === column.modelId}
                          onChange={() => setTargetId(column.modelId)}
                          disabled={busy}
                        />
                        Target
                      </label>
                    ) : null}
                  </div>
                  <ul className="mt-3 space-y-3">
                    {column.members.map((member) => {
                      const archive = isArchiveResident(member);
                      return (
                        <li key={memberKey(member)} className="rounded-xl border border-white/5 bg-ink-950/70 p-3 text-sm">
                          <div className="flex items-start justify-between gap-2">
                            <p className="min-w-0 truncate text-slate-200">{member.filename}</p>
                            <ResidencePill archive={archive} />
                          </div>
                          <MemberPath member={member} />
                          {member.byte_size != null ? (
                            <p className="mt-2 text-xs text-slate-400">{formatBytes(member.byte_size)}</p>
                          ) : null}
                          <dl className="mt-2 grid gap-1 text-[11px] text-slate-500">
                            {!archive ? (
                              <div>
                                <dt className="uppercase tracking-wide">Content</dt>
                                <dd className="font-mono text-slate-300">{digestSnippet(member.content_digest)}</dd>
                              </div>
                            ) : null}
                            <div>
                              <dt className="uppercase tracking-wide">Geometry</dt>
                              <dd className="font-mono text-slate-300">{digestSnippet(member.geometry_digest)}</dd>
                            </div>
                          </dl>
                        </li>
                      );
                    })}
                  </ul>
                </article>
              );
            })}
          </div>
        </div>

        {showActions ? (
          <div className="sticky bottom-0 border-t border-white/10 bg-ink-950/95 px-5 py-4 backdrop-blur">
            <div className="flex flex-wrap items-center gap-2">
              <button
                type="button"
                disabled={busy}
                onClick={onKeep}
                className="rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950 disabled:opacity-60"
              >
                Keep
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={onDismiss}
                className="rounded-lg border border-white/15 px-3 py-1.5 text-sm text-slate-200 disabled:opacity-60"
              >
                Dismiss
              </button>
              <button
                type="button"
                disabled={busy || !canMerge}
                onClick={() => {
                  if (!canMerge) return;
                  setConfirming("merge");
                }}
                className="rounded-lg border border-white/15 px-3 py-1.5 text-sm text-slate-200 disabled:opacity-60"
              >
                Merge
              </button>
              {extractable && onExtractAndMerge ? (
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => setConfirming("extract-merge")}
                  className="rounded-lg border border-accent-500/40 px-3 py-1.5 text-sm text-accent-200 disabled:opacity-60"
                >
                  Extract & merge…
                </button>
              ) : null}
              {extractable && onExtract ? (
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => setConfirming("extract")}
                  className="rounded-lg border border-white/15 px-3 py-1.5 text-sm text-slate-200 disabled:opacity-60"
                >
                  Extract…
                </button>
              ) : null}
            </div>
            {!mergeableSelection ? <p className="mt-2 text-xs text-slate-500">{MERGE_UNSUPPORTED_COPY}</p> : null}
            {extractable ? <p className="mt-1 text-xs text-slate-500">{EXTRACT_COPY}</p> : null}
            <p className={`text-xs text-slate-500 ${mergeableSelection ? "mt-2" : "mt-1"}`}>
              Keep both in the library. Dismiss means it is not a duplicate — reversible from the Dismissed filter, not a
              delete. Merge reparents into the target model; files stay on NFS under the path jail and are never
              silent-deleted.
            </p>
          </div>
        ) : (
          <div className="border-t border-white/10 px-5 py-3 text-xs text-slate-500">
            {open ? "Read-only compare. Viewers cannot keep, dismiss, or merge." : statusMeta(group.status).hint}
          </div>
        )}
      </aside>

      {confirming === "merge" && canMerge && target ? (
        <div className="absolute inset-0 z-50 grid place-items-center bg-ink-950/70 px-4">
          <div className="w-full max-w-md rounded-2xl border border-white/10 bg-ink-900 p-5 shadow-2xl">
            <h3 className="font-display text-xl text-white">Merge into {target.title}?</h3>
            <p className="mt-2 text-sm text-slate-400">
              Other models in this group are reparented under <span className="text-slate-200">{target.title}</span>{" "}
              inside the library path jail. Files stay on NFS at their jailed destination. Merge never silent-deletes.
            </p>
            <ul className="mt-3 list-disc space-y-1 pl-5 text-xs text-slate-500">
              {sources.map((column) => (
                <li key={column.modelId}>{column.title}</li>
              ))}
            </ul>
            <div className="mt-5 flex flex-wrap gap-2">
              <button
                type="button"
                disabled={busy}
                onClick={submitMerge}
                className="rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950 disabled:opacity-60"
              >
                {busy ? busyLabel || "Merging…" : "Merge"}
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={() => setConfirming(null)}
                className="rounded-lg border border-white/15 px-3 py-1.5 text-sm"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {confirming === "extract-merge" && extractable && target ? (
        <ExtractConfirmSheet
          title={`Extract & merge into ${target.title}?`}
          copy={EXTRACT_AND_MERGE_COPY}
          members={extractMembers}
          columns={columns}
          targetId={target.modelId}
          groupId={group.id}
          busy={busy}
          busyLabel={extracting ? EXTRACTING_COPY : busyLabel}
          confirmLabel="Extract & merge"
          onTargetChange={setTargetId}
          onConfirm={submitExtractAndMerge}
          onCancel={() => setConfirming(null)}
        />
      ) : null}

      {confirming === "extract" && extractable && target ? (
        <ExtractConfirmSheet
          title={`Extract into ${target.title}?`}
          copy={EXTRACT_COPY}
          members={extractMembers}
          columns={columns}
          targetId={target.modelId}
          groupId={group.id}
          busy={busy}
          busyLabel={extracting ? EXTRACTING_COPY : busyLabel}
          confirmLabel="Extract"
          onTargetChange={setTargetId}
          onConfirm={submitExtract}
          onCancel={() => setConfirming(null)}
        />
      ) : null}
    </div>
  );
}

function ExtractConfirmSheet({
  title,
  copy,
  members,
  columns,
  targetId,
  groupId,
  busy,
  busyLabel,
  confirmLabel,
  onTargetChange,
  onConfirm,
  onCancel
}: {
  title: string;
  copy: string;
  members: DuplicateMember[];
  columns: MemberColumn[];
  targetId: number;
  groupId: number;
  busy: boolean;
  busyLabel?: string | null;
  confirmLabel: string;
  onTargetChange: (id: number) => void;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="absolute inset-0 z-50 grid place-items-center bg-ink-950/70 px-4">
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-ink-900 p-5 shadow-2xl">
        <h3 className="font-display text-xl text-white">{title}</h3>
        <p className="mt-2 text-sm text-slate-400">{copy}</p>
        {members.length > 0 ? (
          <ul className="mt-3 list-disc space-y-1 pl-5 font-mono text-xs text-slate-400">
            {members.map((member) => {
              const path = memberDisplayPath(member);
              return (
                <li key={memberKey(member)} title={path}>
                  {truncateArchivePath(path)}
                </li>
              );
            })}
          </ul>
        ) : null}
        <fieldset className="mt-4 space-y-2" disabled={busy}>
          <legend className="text-xs uppercase tracking-wide text-slate-500">Target model</legend>
          {columns.map((column) => (
            <label key={column.modelId} className="flex items-center gap-2 text-sm text-slate-200">
              <input
                type="radio"
                name={`extract-target-${groupId}`}
                checked={targetId === column.modelId}
                onChange={() => onTargetChange(column.modelId)}
              />
              {column.title}
            </label>
          ))}
        </fieldset>
        <div className="mt-5 flex flex-wrap gap-2">
          <button
            type="button"
            disabled={busy}
            onClick={onConfirm}
            className="rounded-lg bg-accent-500 px-3 py-1.5 text-sm text-ink-950 disabled:opacity-60"
          >
            {busy ? busyLabel || EXTRACTING_COPY : confirmLabel}
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={onCancel}
            className="rounded-lg border border-white/15 px-3 py-1.5 text-sm"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  );
}
