import { describe, expect, it } from "vitest";
import { canStartReviewAction, nextReviewActionTicket, shouldApplyReviewAction } from "./reviewActions";

describe("duplicate review action tickets", () => {
  it("blocks a second Keep / Dismiss / Merge while that action is in flight", () => {
    expect(canStartReviewAction(false)).toBe(true);
    expect(canStartReviewAction(true)).toBe(false);
  });

  it("drops a slower previous keep, dismiss, or merge after navigate or a newer ticket", () => {
    const first = nextReviewActionTicket(0);
    const second = nextReviewActionTicket(first);
    expect(first).toBe(1);
    expect(second).toBe(2);
    expect(shouldApplyReviewAction(first, second)).toBe(false);
    expect(shouldApplyReviewAction(second, second)).toBe(true);
  });
});
