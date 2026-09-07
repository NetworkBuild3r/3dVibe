/** Block a second Keep / Dismiss / Merge while that action is in flight. */
export function canStartReviewAction(busy: boolean): boolean {
  return !busy;
}

export function nextReviewActionTicket(current: number): number {
  return current + 1;
}

/** Drop keep/dismiss/merge results after navigate or a newer action owns the page. */
export function shouldApplyReviewAction(ticket: number, latest: number): boolean {
  return ticket === latest;
}
