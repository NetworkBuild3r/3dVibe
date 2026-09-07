import { describe, expect, it } from "vitest";
import { canStartModelAction, nextModelActionTicket, shouldApplyModelAction } from "./modelActions";

describe("model page action tickets", () => {
  it("blocks a second Save / Merge / Split / Print while that action is in flight", () => {
    expect(canStartModelAction(false)).toBe(true);
    expect(canStartModelAction(true)).toBe(false);
  });

  it("drops a slower previous print or organize action after navigate or a newer ticket", () => {
    const first = nextModelActionTicket(0);
    const second = nextModelActionTicket(first);
    expect(first).toBe(1);
    expect(second).toBe(2);
    expect(shouldApplyModelAction(first, second)).toBe(false);
    expect(shouldApplyModelAction(second, second)).toBe(true);
  });
});
