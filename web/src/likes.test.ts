import { describe, expect, it } from "vitest";
import { canToggleCardLike, canToggleModelLike, cardLikeBusy, clearLikeBusy, markLikeBusy } from "./likes";

describe("per-card like busy", () => {
  it("lets a second heart start while another card is in flight", () => {
    expect(canToggleCardLike([], 2)).toBe(true);
    expect(canToggleCardLike([1], 2)).toBe(true);
    expect(canToggleCardLike([1], 1)).toBe(false);
    expect(canToggleCardLike([1, 3], 2)).toBe(true);
  });

  it("tracks busy ids without a global lock", () => {
    const one = markLikeBusy([], 9);
    expect(one).toEqual([9]);
    expect(cardLikeBusy(one, 9)).toBe(true);
    expect(cardLikeBusy(one, 8)).toBe(false);
    expect(markLikeBusy(one, 9)).toEqual([9]);
    expect(markLikeBusy(one, 8)).toEqual([9, 8]);
    expect(clearLikeBusy([9, 8], 9)).toEqual([8]);
    expect(clearLikeBusy([8], 8)).toEqual([]);
  });

  it("blocks a second click on the model-page Like while in flight", () => {
    expect(canToggleModelLike(false)).toBe(true);
    expect(canToggleModelLike(true)).toBe(false);
  });
});
