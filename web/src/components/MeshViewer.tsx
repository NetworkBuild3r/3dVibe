import { useEffect, useRef, useState } from "react";
import { fetchAuthedBytes, isAbortError } from "../api";
import { decodeMeshOffthread } from "../meshDecodeClient";
import type { DecodedMesh } from "../meshDecode";
import {
  MeshViewerError,
  VIEWER_MAX_VERTS,
  meshFormatFromHints,
  meshViewerStatusCopy,
  resolveViewerMaxBytes,
  throwIfOversize,
  viewerStageCopy,
  type MeshSource,
  type ViewerStage
} from "../meshViewer";
import { CANCELLED_COPY } from "../archives";

type Props = {
  url: string;
  label: string;
  filename?: string;
  meshKind?: string | null;
  byteSize?: number | null;
  source?: MeshSource;
  maxBytes?: number;
  maxVerts?: number;
};

export function MeshViewer({
  url,
  label,
  filename,
  meshKind,
  byteSize,
  source,
  maxBytes,
  maxVerts = VIEWER_MAX_VERTS
}: Props) {
  const host = useRef<HTMLDivElement | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState(viewerStageCopy("fetching"));
  const [stage, setStage] = useState<ViewerStage>("fetching");

  useEffect(() => {
    let disposed = false;
    let frame = 0;
    let handle: SceneHandle | null = null;
    const abort = new AbortController();
    const format = meshFormatFromHints({ kind: meshKind, filename, label, url });
    const budget = resolveViewerMaxBytes({ source, url, maxBytes });

    setError(null);
    setStage("fetching");
    setStatus(viewerStageCopy("fetching"));

    async function mount() {
      if (!format) throw new MeshViewerError("unsupported");
      if (byteSize != null) throwIfOversize(byteSize, budget);

      const threePromise = Promise.all([
        import("three"),
        import("three/examples/jsm/controls/OrbitControls.js")
      ]);
      const buffer = await fetchAuthedBytes(url, {
        signal: abort.signal,
        maxBytes: budget,
        onProgress: (loaded, total) => {
          if (!disposed) setStatus(viewerStageCopy("fetching", { loaded, total }));
        }
      });
      if (disposed || abort.signal.aborted) return;

      setStage("decoding");
      setStatus(viewerStageCopy("decoding"));

      const [three, { OrbitControls }] = await threePromise;
      if (!host.current || disposed) return;

      handle = createScene(host.current, {
        WebGLRenderer: three.WebGLRenderer,
        Scene: three.Scene,
        PerspectiveCamera: three.PerspectiveCamera,
        Color: three.Color,
        DirectionalLight: three.DirectionalLight,
        AmbientLight: three.AmbientLight,
        GridHelper: three.GridHelper,
        Box3: three.Box3,
        Vector3: three.Vector3,
        OrbitControls,
        BufferGeometry: three.BufferGeometry,
        BufferAttribute: three.BufferAttribute,
        Mesh: three.Mesh,
        MeshStandardMaterial: three.MeshStandardMaterial
      });

      const tick = () => {
        handle?.render();
        frame = requestAnimationFrame(tick);
      };
      tick();

      let seen = 0;
      await decodeMeshOffthread(buffer, {
        format,
        maxVerts,
        signal: abort.signal,
        onMesh: (mesh) => {
          if (disposed) return;
          seen += 1;
          handle?.addMesh(mesh);
          setStage("displaying");
          setStatus(viewerStageCopy("displaying"));
        }
      });
      if (disposed) return;
      if (seen === 0) throw new MeshViewerError("empty");
      setStage("ready");
      setStatus(viewerStageCopy("ready", { label }));
    }

    mount().catch((err) => {
      if (disposed) return;
      if (isAbortError(err) || abort.signal.aborted) {
        setStage("cancelled");
        setStatus(CANCELLED_COPY);
        return;
      }
      setStage("unavailable");
      setError(meshViewerStatusCopy(err));
    });

    return () => {
      disposed = true;
      abort.abort();
      cancelAnimationFrame(frame);
      handle?.dispose();
    };
  }, [url, label, filename, meshKind, byteSize, source, maxBytes, maxVerts]);

  const showShimmer = !error && (stage === "fetching" || stage === "decoding");
  const faded = stage === "ready" || stage === "displaying";

  return (
    <div className="overflow-hidden rounded-2xl border border-white/10 bg-ink-900">
      <div className="relative h-80 w-full">
        <div ref={host} className={`h-full w-full ${faded ? "cover-fade-in" : ""}`} />
        {showShimmer ? <div className="cover-shimmer absolute inset-0" role="status" aria-label={status} /> : null}
      </div>
      <p className="border-t border-white/5 px-4 py-2 text-xs text-slate-400">{error ?? status}</p>
    </div>
  );
}

type SceneLibs = {
  WebGLRenderer: typeof import("three").WebGLRenderer;
  Scene: typeof import("three").Scene;
  PerspectiveCamera: typeof import("three").PerspectiveCamera;
  Color: typeof import("three").Color;
  DirectionalLight: typeof import("three").DirectionalLight;
  AmbientLight: typeof import("three").AmbientLight;
  GridHelper: typeof import("three").GridHelper;
  Box3: typeof import("three").Box3;
  Vector3: typeof import("three").Vector3;
  OrbitControls: typeof import("three/examples/jsm/controls/OrbitControls.js").OrbitControls;
  BufferGeometry: typeof import("three").BufferGeometry;
  BufferAttribute: typeof import("three").BufferAttribute;
  Mesh: typeof import("three").Mesh;
  MeshStandardMaterial: typeof import("three").MeshStandardMaterial;
};

type SceneHandle = {
  addMesh: (decoded: DecodedMesh) => void;
  render: () => void;
  dispose: () => void;
};

function createScene(host: HTMLDivElement, libs: SceneLibs): SceneHandle {
  const scene = new libs.Scene();
  scene.background = new libs.Color("#121821");
  const camera = new libs.PerspectiveCamera(45, host.clientWidth / Math.max(host.clientHeight, 1), 0.1, 4000);
  camera.position.set(80, 70, 110);

  const webgl = new libs.WebGLRenderer({ antialias: true });
  webgl.setSize(host.clientWidth, host.clientHeight);
  host.replaceChildren(webgl.domElement);

  scene.add(new libs.AmbientLight(0xffffff, 0.55));
  const key = new libs.DirectionalLight(0xffffff, 1.1);
  key.position.set(40, 80, 30);
  scene.add(key);
  scene.add(new libs.GridHelper(120, 12, 0x243044, 0x1a2330));

  const controls = new libs.OrbitControls(camera, webgl.domElement);
  controls.enableDamping = true;

  const geometries: InstanceType<typeof libs.BufferGeometry>[] = [];
  const materials: InstanceType<typeof libs.MeshStandardMaterial>[] = [];
  const meshes: InstanceType<typeof libs.Mesh>[] = [];

  function fitCamera() {
    const box = new libs.Box3();
    for (const mesh of meshes) box.expandByObject(mesh);
    if (box.isEmpty()) return;
    const size = new libs.Vector3();
    const center = new libs.Vector3();
    box.getSize(size);
    box.getCenter(center);
    const radius = Math.max(size.length() * 0.5, 8);
    camera.position.set(center.x + radius * 1.6, center.y + radius * 1.2, center.z + radius * 1.8);
    camera.near = Math.max(radius / 200, 0.01);
    camera.far = Math.max(radius * 20, 2000);
    camera.updateProjectionMatrix();
    controls.target.copy(center);
    controls.update();
  }

  return {
    addMesh(decoded) {
      const geometry = new libs.BufferGeometry();
      geometry.setAttribute("position", new libs.BufferAttribute(decoded.positions, 3));
      if (decoded.normals && decoded.normals.length === decoded.positions.length) {
        geometry.setAttribute("normal", new libs.BufferAttribute(decoded.normals, 3));
      }
      if (decoded.index && decoded.index.length >= 3) {
        geometry.setIndex(new libs.BufferAttribute(decoded.index, 1));
      }
      if (!geometry.getAttribute("normal")) geometry.computeVertexNormals();
      geometry.center();
      const material = new libs.MeshStandardMaterial({ color: "#5eead4", metalness: 0.15, roughness: 0.45 });
      const mesh = new libs.Mesh(geometry, material);
      scene.add(mesh);
      geometries.push(geometry);
      materials.push(material);
      meshes.push(mesh);
      fitCamera();
    },
    render() {
      controls.update();
      webgl.render(scene, camera);
    },
    dispose() {
      controls.dispose();
      geometries.forEach((geometry) => geometry.dispose());
      materials.forEach((material) => material.dispose());
      webgl.dispose();
      webgl.forceContextLoss?.();
    }
  };
}
