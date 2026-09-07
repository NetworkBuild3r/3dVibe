import { useEffect, useRef, type RefObject } from "react";

export const FOCUSABLE_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "textarea:not([disabled])",
  'input:not([disabled]):not([type="hidden"])',
  "select:not([disabled])",
  '[tabindex]:not([tabindex="-1"])'
].join(", ");

export function isEscapeKey(event: Pick<KeyboardEvent, "key">): boolean {
  return event.key === "Escape";
}

export type TabFocusWrap = "first" | "last" | "empty" | null;

/** Keep Tab inside the overlay. null means the browser can move within the trap. */
export function tabFocusWrap(
  event: Pick<KeyboardEvent, "key" | "shiftKey">,
  itemCount: number,
  activeIndex: number
): TabFocusWrap {
  if (event.key !== "Tab") return null;
  if (itemCount === 0) return "empty";
  if (event.shiftKey && activeIndex <= 0) return "last";
  if (!event.shiftKey && (activeIndex < 0 || activeIndex >= itemCount - 1)) return "first";
  return null;
}

export function focusableIn(root: ParentNode): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)).filter((node) => {
    if (node.tabIndex < 0) return false;
    if (node.getAttribute("aria-hidden") === "true") return false;
    return true;
  });
}

export function useFocusTrap(
  active: boolean,
  rootRef: RefObject<HTMLElement | null>,
  options: { onEscape?: () => void } = {}
) {
  const onEscapeRef = useRef(options.onEscape);
  onEscapeRef.current = options.onEscape;

  useEffect(() => {
    if (!active) return;
    const root = rootRef.current;
    if (!root) return;

    const prior = document.activeElement;
    const restore = prior instanceof HTMLElement ? prior : null;

    const focusInitial = () => {
      const items = focusableIn(root);
      if (items[0]) items[0].focus();
      else root.focus();
    };
    const frame = window.requestAnimationFrame(focusInitial);

    function onKeyDown(event: KeyboardEvent) {
      const trap = rootRef.current;
      if (!trap) return;
      if (isEscapeKey(event)) {
        event.preventDefault();
        event.stopPropagation();
        onEscapeRef.current?.();
        return;
      }
      const items = focusableIn(trap);
      const activeIndex = items.indexOf(document.activeElement as HTMLElement);
      const wrap = tabFocusWrap(event, items.length, activeIndex);
      if (wrap === "empty") {
        event.preventDefault();
        trap.focus();
        return;
      }
      if (wrap === "first") {
        event.preventDefault();
        items[0]?.focus();
        return;
      }
      if (wrap === "last") {
        event.preventDefault();
        items[items.length - 1]?.focus();
      }
    }

    document.addEventListener("keydown", onKeyDown);
    return () => {
      window.cancelAnimationFrame(frame);
      document.removeEventListener("keydown", onKeyDown);
      restore?.focus();
    };
  }, [active, rootRef]);
}
