// Shared library list + selected-id state for Scan / Invites / Upload / Printers /
// Libraries (scan console) / Dupes pickers. See docs/thin-cut-audit.md (Frontend DRY).
// Selection persistence matches today's pages; this is not the "one implicit library" demote.
import { useCallback, useEffect, useRef, useState } from "react";
import { api, type LibraryInfo, type User } from "./api";

export type LibraryId = number | "";

type LibraryRef = { id: number };

export function persistLibraryId<T extends LibraryRef>(libraries: T[], currentId: LibraryId): LibraryId {
  if (currentId !== "") return currentId;
  return libraries[0]?.id ?? "";
}

export function selectedLibrary<T extends LibraryRef>(libraries: T[], libraryId: LibraryId): T | undefined {
  if (libraryId === "") return undefined;
  return libraries.find((library) => library.id === libraryId);
}

export function isWritableLibrary(library: Pick<LibraryInfo, "can_upload">) {
  return Boolean(library.can_upload);
}

export function writableLibraries<T extends Pick<LibraryInfo, "can_upload">>(libraries: T[]) {
  return libraries.filter(isWritableLibrary);
}

export function scanTargetLibrary<T extends Pick<LibraryInfo, "can_scan">>(libraries: T[]) {
  return libraries.find((library) => library.can_scan) || libraries[0];
}

export function canScanLibraries(user?: Pick<User, "can_invite" | "can_manage_libraries"> | null) {
  return Boolean(user?.can_manage_libraries || user?.can_invite);
}

export function canReadLibraryOps(user?: Pick<User, "can_curate"> | null) {
  return Boolean(user?.can_curate);
}

export type UseLibraryOptions = {
  enabled?: boolean;
  autoLoad?: boolean;
  filter?: (library: LibraryInfo) => boolean;
  resolveId?: (libraries: LibraryInfo[], currentId: LibraryId) => LibraryId;
  onError?: (message: string) => void;
};

export function useLibrary(options: UseLibraryOptions = {}) {
  const enabled = options.enabled ?? true;
  const autoLoad = options.autoLoad ?? true;
  const filterRef = useRef(options.filter);
  const resolveRef = useRef(options.resolveId);
  const onErrorRef = useRef(options.onError);
  filterRef.current = options.filter;
  resolveRef.current = options.resolveId;
  onErrorRef.current = options.onError;

  const [libraries, setLibraries] = useState<LibraryInfo[]>([]);
  const [libraryId, setLibraryId] = useState<LibraryId>("");

  const applyLibraries = useCallback((rows: LibraryInfo[]) => {
    const next = filterRef.current ? rows.filter(filterRef.current) : rows;
    setLibraries(next);
    setLibraryId((current) => (resolveRef.current ?? persistLibraryId)(next, current));
    return next;
  }, []);

  const refresh = useCallback(async () => {
    const payload = await api.libraries();
    return applyLibraries(payload.libraries);
  }, [applyLibraries]);

  useEffect(() => {
    if (!enabled || !autoLoad) return;
    let cancelled = false;
    api
      .libraries()
      .then((payload) => {
        if (!cancelled) applyLibraries(payload.libraries);
      })
      .catch((err) => {
        if (cancelled) return;
        onErrorRef.current?.(err instanceof Error ? err.message : "Failed to load libraries");
      });
    return () => {
      cancelled = true;
    };
  }, [enabled, autoLoad, applyLibraries]);

  return {
    libraries,
    libraryId,
    setLibraryId,
    library: selectedLibrary(libraries, libraryId),
    applyLibraries,
    refresh
  };
}
