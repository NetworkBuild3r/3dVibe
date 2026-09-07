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

const MODAL_DIALOG_SELECTOR = '[role="dialog"][aria-modal="true"]';

/** Confirm sheets nest inside the drawer — Tab must use the topmost modal, not the drawer. */
export function innermostModal<T>(root: { querySelectorAll: (selector: string) => ArrayLike<T> }): T | null {
  const dialogs = root.querySelectorAll(MODAL_DIALOG_SELECTOR);
  if (dialogs.length === 0) return null;
  return dialogs[dialogs.length - 1] ?? null;
}

export function trapScope(root: HTMLElement): HTMLElement {
  return (innermostModal(root) as HTMLElement | null) ?? root;
}

/** Restore to the opener unless click-away already moved it to another control. */
export function shouldRestoreFocus(
  restore: object | null,
  trap: { contains: (node: never) => boolean } | null,
  active: { nodeName?: string } | object | null
): boolean {
  if (!restore) return false;
  if (!active) return true;
  if (typeof active === "object" && "nodeName" in active && active.nodeName === "BODY") return true;
  if (active === restore) return true;
  if (!trap) return true;
  return trap.contains(active as never);
}

export function useFocusTrap(
  active: boolean,
  rootRef: RefObject<HTMLElement | null>,
  options: { onEscape?: () => void; layer?: string | number | null } = {}
) {
  const onEscapeRef = useRef(options.onEscape);
  onEscapeRef.current = options.onEscape;
  const layer = options.layer ?? null;
  const layerRestoreRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!active) return;
    const root = rootRef.current;
    if (!root) return;

    const prior = document.activeElement;
    const restore = prior instanceof HTMLElement ? prior : null;

    const focusInitial = () => {
      const scope = trapScope(root);
      const items = focusableIn(scope);
      if (items[0]) items[0].focus();
      else scope.focus();
    };
    const frame = window.requestAnimationFrame(focusInitial);

    function onKeyDown(event: KeyboardEvent) {
      const host = rootRef.current;
      if (!host) return;
      const trap = trapScope(host);
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
      const activeEl = document.activeElement instanceof HTMLElement ? document.activeElement : null;
      if (shouldRestoreFocus(restore, rootRef.current, activeEl)) restore?.focus();
    };
  }, [active, rootRef]);

  useEffect(() => {
    if (!active) {
      layerRestoreRef.current = null;
      return;
    }
    const root = rootRef.current;
    if (!root) return;

    if (layer != null && layer !== "") {
      const prior = document.activeElement;
      if (prior instanceof HTMLElement && !layerRestoreRef.current) {
        layerRestoreRef.current = prior;
      }
      const frame = window.requestAnimationFrame(() => {
        const scope = trapScope(root);
        const items = focusableIn(scope);
        if (items[0]) items[0].focus();
        else scope.focus();
      });
      return () => window.cancelAnimationFrame(frame);
    }

    const restore = layerRestoreRef.current;
    layerRestoreRef.current = null;
    restore?.focus();
  }, [active, layer, rootRef]);
}
