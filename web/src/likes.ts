/** Hearts are independently busy. Another card's in-flight like must not block this one. */
export function canToggleCardLike(busyIds: readonly number[], modelId: number): boolean {
  return !busyIds.includes(modelId);
}

export function markLikeBusy(busyIds: readonly number[], modelId: number): number[] {
  return busyIds.includes(modelId) ? [...busyIds] : [...busyIds, modelId];
}

export function clearLikeBusy(busyIds: readonly number[], modelId: number): number[] {
  return busyIds.filter((id) => id !== modelId);
}

export function cardLikeBusy(busyIds: readonly number[], modelId: number): boolean {
  return busyIds.includes(modelId);
}

/** Model page: one like control — block a second click while the request is in flight. */
export function canToggleModelLike(busy: boolean): boolean {
  return !busy;
}
