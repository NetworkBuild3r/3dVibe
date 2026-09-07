/** Block a second Save / Merge / Split / Print while that action is in flight. */
export function canStartModelAction(busy: boolean): boolean {
  return !busy;
}

export function nextModelActionTicket(current: number): number {
  return current + 1;
}

/** Drop save/merge/split/print results after navigate or a newer action owns the page. */
export function shouldApplyModelAction(ticket: number, latest: number): boolean {
  return ticket === latest;
}
