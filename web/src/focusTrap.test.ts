import { describe, expect, it } from "vitest";
import { innermostModal, isEscapeKey, shouldRestoreFocus, tabFocusWrap } from "./focusTrap";

describe("overlay focus trap", () => {
  it("treats Escape as the dialog close key", () => {
    expect(isEscapeKey({ key: "Escape" })).toBe(true);
    expect(isEscapeKey({ key: "Tab" })).toBe(false);
    expect(isEscapeKey({ key: "Enter" })).toBe(false);
  });

  it("wraps Tab from last to first and Shift+Tab from first to last", () => {
    expect(tabFocusWrap({ key: "Tab", shiftKey: false }, 4, 3)).toBe("first");
    expect(tabFocusWrap({ key: "Tab", shiftKey: true }, 4, 0)).toBe("last");
    expect(tabFocusWrap({ key: "Tab", shiftKey: true }, 4, -1)).toBe("last");
    expect(tabFocusWrap({ key: "Tab", shiftKey: false }, 4, -1)).toBe("first");
    expect(tabFocusWrap({ key: "Tab", shiftKey: false }, 4, 1)).toBeNull();
    expect(tabFocusWrap({ key: "Enter", shiftKey: false }, 4, 3)).toBeNull();
  });

  it("keeps Tab inside an empty overlay instead of escaping to the page", () => {
    expect(tabFocusWrap({ key: "Tab", shiftKey: false }, 0, -1)).toBe("empty");
    expect(tabFocusWrap({ key: "Tab", shiftKey: true }, 0, -1)).toBe("empty");
  });

  it("traps an open chip dropdown the same way — Tab wraps, Escape closes", () => {
    expect(tabFocusWrap({ key: "Tab", shiftKey: false }, 6, 5)).toBe("first");
    expect(tabFocusWrap({ key: "Tab", shiftKey: true }, 6, 0)).toBe("last");
    expect(isEscapeKey({ key: "Escape" })).toBe(true);
  });

  it("traps an open avatar menu the same way — Tab wraps, Escape closes, restore opener", () => {
    expect(tabFocusWrap({ key: "Tab", shiftKey: false }, 5, 4)).toBe("first");
    expect(tabFocusWrap({ key: "Tab", shiftKey: true }, 5, 0)).toBe("last");
    expect(isEscapeKey({ key: "Escape" })).toBe(true);
    const opener = { id: "avatar" };
    const inside = { id: "menuitem" };
    const outside = { id: "search" };
    const trap = { contains: (node: object | null) => node === inside };
    expect(shouldRestoreFocus(opener, trap, inside)).toBe(true);
    expect(shouldRestoreFocus(opener, trap, opener)).toBe(true);
    expect(shouldRestoreFocus(opener, trap, outside)).toBe(false);
  });

  it("uses the nested confirm dialog as the trap, not the drawer behind it", () => {
    const sheet = { id: "confirm" };
    const drawer = { id: "drawer" };
    expect(
      innermostModal({
        querySelectorAll: () => [drawer, sheet]
      })
    ).toBe(sheet);
    expect(
      innermostModal({
        querySelectorAll: () => [drawer]
      })
    ).toBe(drawer);
    expect(innermostModal({ querySelectorAll: () => [] })).toBeNull();
  });

  it("restores focus to the opener unless click-away already moved it", () => {
    const opener = { id: "opener" };
    const inside = { id: "inside" };
    const outside = { id: "outside" };
    const trap = { contains: (node: object | null) => node === inside };
    expect(shouldRestoreFocus(opener, trap, inside)).toBe(true);
    expect(shouldRestoreFocus(opener, trap, opener)).toBe(true);
    expect(shouldRestoreFocus(opener, trap, null)).toBe(true);
    expect(shouldRestoreFocus(opener, trap, { nodeName: "BODY" })).toBe(true);
    expect(shouldRestoreFocus(opener, null, inside)).toBe(true);
    expect(shouldRestoreFocus(opener, trap, outside)).toBe(false);
    expect(shouldRestoreFocus(null, trap, inside)).toBe(false);
  });
});
