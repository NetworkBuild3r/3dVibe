export type ShelfId = number | "likes";

export function nextShelfTicket(current: number): number {
  return current + 1;
}

/** Drop a shelf payload when a newer sidebar click owns the grid. */
export function shouldApplyShelfLoad(ticket: number, latest: number): boolean {
  return ticket === latest;
}

export function isLikesShelf(id: ShelfId): id is "likes" {
  return id === "likes";
}

export function emptyShelfCopy(id: ShelfId): string {
  return isLikesShelf(id) ? "No liked models yet." : "This shelf is empty.";
}
