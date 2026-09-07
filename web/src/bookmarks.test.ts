import { describe, expect, it } from "vitest";
import { emptyShelfCopy, isLikesShelf, nextShelfTicket, shouldApplyShelfLoad } from "./bookmarks";

describe("bookmark shelf request ticket", () => {
  it("ignores a slower previous shelf after a newer click", () => {
    const first = nextShelfTicket(0);
    const second = nextShelfTicket(first);
    expect(first).toBe(1);
    expect(second).toBe(2);
    expect(shouldApplyShelfLoad(first, second)).toBe(false);
    expect(shouldApplyShelfLoad(second, second)).toBe(true);
  });

  it("keeps likes vs folder empty copy honest", () => {
    expect(isLikesShelf("likes")).toBe(true);
    expect(isLikesShelf(4)).toBe(false);
    expect(emptyShelfCopy("likes")).toBe("No liked models yet.");
    expect(emptyShelfCopy(4)).toBe("This shelf is empty.");
  });
});
