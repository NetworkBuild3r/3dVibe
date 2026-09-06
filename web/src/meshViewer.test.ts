import { describe, expect, it } from "vitest";
import { ApiError } from "./api";
import { CANT_PREVIEW_COPY, CANCELLED_COPY, isPreviewUnavailable, viewerStatusCopy } from "./archives";
import {
  DECODING_COPY,
  DISPLAYING_COPY,
  MeshViewerError,
  VIEWABLE_MESH_KINDS,
  VIEWER_ARCHIVE_MAX_BYTES,
  VIEWER_LOOSE_MAX_BYTES,
  defaultViewerMaxBytes,
  inferMeshSource,
  isViewableMeshAsset,
  meshFormatFromHints,
  meshViewerStatusCopy,
  preferredLooseMesh,
  resolveViewerMaxBytes,
  throwIfOverVerts,
  throwIfOversize,
  viewerStageCopy
} from "./meshViewer";

describe("lazy 3D viewer shell", () => {
  it("detects stl/obj/3mf from kind, filename, or url and ignores gcode", () => {
    expect(meshFormatFromHints({ kind: "STL" })).toBe("stl");
    expect(meshFormatFromHints({ filename: "hero.obj" })).toBe("obj");
    expect(meshFormatFromHints({ url: "/files/kit.3mf?download=1" })).toBe("3mf");
    expect(meshFormatFromHints({ label: "pack.zip → path/foo.stl" })).toBe("stl");
    expect(meshFormatFromHints({ kind: "gcode", filename: "print.gcode" })).toBeNull();
    expect(VIEWABLE_MESH_KINDS).toEqual(["stl", "obj", "3mf"]);
    expect(isViewableMeshAsset({ kind: "obj", mesh: true })).toBe(true);
    expect(isViewableMeshAsset({ kind: "gcode", mesh: true })).toBe(false);
  });

  it("uses archive vs loose byte budgets and honors stream-one archive URLs", () => {
    expect(inferMeshSource("/api/v1/archive_members/12/content")).toBe("archive");
    expect(inferMeshSource("/api/v1/assets/4/content")).toBe("loose");
    expect(defaultViewerMaxBytes("archive")).toBe(VIEWER_ARCHIVE_MAX_BYTES);
    expect(defaultViewerMaxBytes("loose")).toBe(VIEWER_LOOSE_MAX_BYTES);
    expect(resolveViewerMaxBytes({ url: "/api/v1/archive_members/1/content" })).toBe(VIEWER_ARCHIVE_MAX_BYTES);
    expect(resolveViewerMaxBytes({ source: "loose", maxBytes: 1024 })).toBe(1024);
  });

  it("prefers a loose stl/obj over an archive 3mf for Load mesh", () => {
    const assets = [
      { id: 1, kind: "3mf", mesh: true, archive: true, filename: "kit.3mf" },
      { id: 2, kind: "stl", mesh: true, archive: false, filename: "hero.stl" },
      { id: 3, kind: "gcode", mesh: true, archive: false, filename: "print.gcode" }
    ];
    expect(preferredLooseMesh(assets)?.filename).toBe("hero.stl");
  });

  it("exposes stable shell stage copy", () => {
    expect(viewerStageCopy("fetching", { loaded: 50, total: 100 })).toBe("Loading mesh… 50%");
    expect(viewerStageCopy("decoding")).toBe(DECODING_COPY);
    expect(viewerStageCopy("displaying")).toBe(DISPLAYING_COPY);
    expect(viewerStageCopy("ready", { label: "hero.stl" })).toBe("hero.stl");
    expect(viewerStageCopy("cancelled")).toBe(CANCELLED_COPY);
    expect(viewerStageCopy("unavailable")).toBe(CANT_PREVIEW_COPY);
  });

  it("maps budget and abort errors to calm copy (no toast codes)", () => {
    expect(meshViewerStatusCopy(new MeshViewerError("oversized"))).toBe(CANT_PREVIEW_COPY);
    expect(meshViewerStatusCopy(new MeshViewerError("too_many_verts"))).toBe(CANT_PREVIEW_COPY);
    expect(meshViewerStatusCopy(new MeshViewerError("unsupported"))).toBe(CANT_PREVIEW_COPY);
    expect(meshViewerStatusCopy(new MeshViewerError("cancelled"))).toBe(CANCELLED_COPY);
    expect(meshViewerStatusCopy(new ApiError("Refusing to load oversized mesh", 422, "oversized"))).toBe(
      CANT_PREVIEW_COPY
    );
    expect(viewerStatusCopy(new ApiError("too big", 422, "oversized"))).toBe(CANT_PREVIEW_COPY);
    expect(isPreviewUnavailable(new ApiError("nope", 422, "too_many_verts"))).toBe(true);
    expect(() => throwIfOversize(33 * 1024 * 1024, VIEWER_ARCHIVE_MAX_BYTES)).toThrowError(MeshViewerError);
    expect(() => throwIfOverVerts(2_000_000, 1_500_000)).toThrowError(MeshViewerError);
  });
});
