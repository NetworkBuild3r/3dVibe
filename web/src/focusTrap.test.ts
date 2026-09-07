import { describe, expect, it } from "vitest";
import { isEscapeKey, tabFocusWrap } from "./focusTrap";

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
});
