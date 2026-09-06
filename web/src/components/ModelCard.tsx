import { Link } from "react-router-dom";
import type { ModelCard as ModelCardType } from "../api";
import { CoverMedia } from "./CoverMedia";
import { IconHeart } from "./Icons";

export function ModelCard({
  model,
  onLike,
  likeBusy,
  onTag
}: {
  model: ModelCardType;
  onLike?: (model: ModelCardType) => void;
  likeBusy?: boolean;
  onTag?: (tag: string) => void;
}) {
  const tag = model.tags[0];
  const creator = model.creator;

  return (
    <article className="group">
      <div className="relative overflow-hidden rounded-xl bg-ink-900">
        <Link to={`/models/${model.id}`} className="block aspect-square">
          <CoverMedia model={model} />
        </Link>
        {onLike ? (
          <button
            type="button"
            aria-pressed={Boolean(model.liked)}
            aria-label={model.liked ? "Unlike" : "Like"}
            disabled={likeBusy}
            onClick={() => onLike(model)}
            className={`absolute right-2.5 top-2.5 rounded-full bg-ink-950/55 p-1.5 backdrop-blur-sm transition disabled:opacity-60 ${
              model.liked ? "text-rose-300" : "text-white hover:text-rose-200"
            }`}
          >
            <IconHeart filled={Boolean(model.liked)} className="h-4 w-4" />
          </button>
        ) : null}
      </div>
      <div className="mt-2.5 min-w-0">
        <Link to={`/models/${model.id}`} className="block truncate font-display text-[15px] text-white hover:text-accent-400">
          {model.title}
        </Link>
        {creator ? (
          <Link
            to={`/creators/${creator.slug}`}
            className="mt-0.5 block truncate text-sm text-slate-400 hover:text-slate-200"
          >
            {creator.name}
          </Link>
        ) : null}
        {tag ? (
          onTag ? (
            <button
              type="button"
              onClick={() => onTag(tag)}
              className="mt-2 inline-flex rounded-full border border-accent-500/45 px-2 py-0.5 text-[11px] text-accent-400 hover:border-accent-400"
            >
              {tag}
            </button>
          ) : (
            <span className="mt-2 inline-flex rounded-full border border-accent-500/45 px-2 py-0.5 text-[11px] text-accent-400">
              {tag}
            </span>
          )
        ) : null}
      </div>
    </article>
  );
}
