type IconProps = { className?: string };

export function IconLibrary({ className = "h-5 w-5" }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" aria-hidden>
      <rect x="3" y="4" width="7" height="7" rx="1.5" />
      <rect x="14" y="4" width="7" height="7" rx="1.5" />
      <rect x="3" y="13" width="7" height="7" rx="1.5" />
      <rect x="14" y="13" width="7" height="7" rx="1.5" />
    </svg>
  );
}

export function IconCreators({ className = "h-5 w-5" }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" aria-hidden>
      <circle cx="9" cy="8" r="3" />
      <path d="M4 19c.4-3.2 2.6-5 5-5s4.6 1.8 5 5" />
      <circle cx="17" cy="9" r="2.5" />
      <path d="M16 19c.3-2.2 1.6-3.5 3.4-3.8" />
    </svg>
  );
}

export function IconShelves({ className = "h-5 w-5" }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" aria-hidden>
      <path d="M4 6h16M4 12h16M4 18h16" />
    </svg>
  );
}

export function IconPrints({ className = "h-5 w-5" }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" aria-hidden>
      <path d="M7 8V5h10v3" />
      <rect x="5" y="8" width="14" height="8" rx="2" />
      <path d="M7 16v3h10v-3" />
    </svg>
  );
}

export function IconDuplicates({ className = "h-5 w-5" }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" aria-hidden>
      <rect x="7" y="7" width="11" height="11" rx="2" />
      <path d="M6 16V6a2 2 0 0 1 2-2h10" />
    </svg>
  );
}

export function IconUpload({ className = "h-5 w-5" }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" aria-hidden>
      <path d="M12 16V6" />
      <path d="M8 10l4-4 4 4" />
      <path d="M5 18h14" />
    </svg>
  );
}

export function IconSearch({ className = "h-4 w-4" }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" aria-hidden>
      <circle cx="11" cy="11" r="6.5" />
      <path d="M16 16l4.5 4.5" />
    </svg>
  );
}

export function IconScan({ className = "h-4 w-4" }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" aria-hidden>
      <path d="M7 4H5a1 1 0 0 0-1 1v2" />
      <path d="M17 4h2a1 1 0 0 1 1 1v2" />
      <path d="M7 20H5a1 1 0 0 1-1-1v-2" />
      <path d="M17 20h2a1 1 0 0 0 1-1v-2" />
      <path d="M4 12h16" />
    </svg>
  );
}

export function IconChevron({ className = "h-4 w-4" }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" aria-hidden>
      <path d="M8 10l4 4 4-4" />
    </svg>
  );
}

export function IconChevronRight({ className = "h-4 w-4" }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" aria-hidden>
      <path d="M9 7l6 5-6 5" />
    </svg>
  );
}

export function IconHeart({ className = "h-5 w-5", filled = false }: IconProps & { filled?: boolean }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth="1.75"
      aria-hidden
    >
      <path d="M12 20s-7-4.4-9.2-8.2C1.2 9.2 2.4 6 5.6 6c1.9 0 3.1 1.1 3.9 2.3C10.3 7.1 11.5 6 13.4 6c3.2 0 4.4 3.2 2.8 5.8C14 15.6 12 20 12 20z" />
    </svg>
  );
}

export function IconMark({ className = "h-7 w-7" }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 32 32" fill="none" aria-hidden>
      <rect width="32" height="32" rx="8" className="fill-ink-800" />
      <path d="M7 22 L16 8 L25 22 Z" className="stroke-accent-400" strokeWidth="2" fill="none" />
      <circle cx="16" cy="18" r="2.2" className="fill-accent-400" />
    </svg>
  );
}
