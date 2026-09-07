import { describe, expect, it } from "vitest";
import {
  STICKY_FILTER_CHROME_SELECTOR,
  gridHostWidth,
  gridMetricObserveTargets,
  gridScrollMargin,
  readGridMetrics,
  stickyFilterChrome
} from "./virtualizedGrid";

describe("virtualized grid scrollMargin", () => {
  it("uses the host offsetTop as the window virtualizer scrollMargin", () => {
    expect(gridScrollMargin({ offsetTop: 240 })).toBe(240);
    expect(gridHostWidth({ clientWidth: 960 })).toBe(960);
    expect(readGridMetrics({ offsetTop: 312, clientWidth: 800 })).toEqual({
      width: 800,
      scrollMargin: 312
    });
  });

  it("finds the sticky filter bar so a pill-row height change remasures", () => {
    const bar = { className: "gallery-filter-bar" } as unknown as Element;
    const parent = {
      querySelector: (selector: string) => (selector === STICKY_FILTER_CHROME_SELECTOR ? bar : null)
    } as unknown as HTMLElement;
    const host = { parentElement: parent } as HTMLElement;

    expect(stickyFilterChrome(host)).toBe(bar);
    expect(stickyFilterChrome({ parentElement: null })).toBeNull();
  });

  it("observes the host, sticky chrome, and parent — not only the grid box", () => {
    const chrome = { id: "pills" } as unknown as Element;
    const parent = {
      querySelector: (selector: string) => (selector === STICKY_FILTER_CHROME_SELECTOR ? chrome : null)
    } as unknown as HTMLElement;
    const host = { parentElement: parent } as HTMLElement;

    expect(gridMetricObserveTargets(host)).toEqual([host, chrome, parent]);
  });
});
