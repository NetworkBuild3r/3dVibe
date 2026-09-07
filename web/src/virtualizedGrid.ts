export const STICKY_FILTER_CHROME_SELECTOR = ".gallery-filter-bar";

export function gridScrollMargin(node: Pick<HTMLElement, "offsetTop">): number {
  return node.offsetTop;
}

export function gridHostWidth(node: Pick<HTMLElement, "clientWidth">): number {
  return node.clientWidth;
}

export function readGridMetrics(node: Pick<HTMLElement, "offsetTop" | "clientWidth">): {
  width: number;
  scrollMargin: number;
} {
  return { width: gridHostWidth(node), scrollMargin: gridScrollMargin(node) };
}

/** Sticky chip/pill chrome above the grid — height changes must remasure scrollMargin. */
export function stickyFilterChrome(node: Pick<HTMLElement, "parentElement">): Element | null {
  return node.parentElement?.querySelector(STICKY_FILTER_CHROME_SELECTOR) ?? null;
}

export function gridMetricObserveTargets(node: HTMLElement): Element[] {
  const targets: Element[] = [node];
  const chrome = stickyFilterChrome(node);
  if (chrome) targets.push(chrome);
  const parent = node.parentElement;
  if (parent && !targets.includes(parent)) targets.push(parent);
  return targets;
}
