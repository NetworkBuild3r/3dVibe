import { useEffect, useRef, useState } from "react";
import { fetchAuthedBlob, isAbortError } from "../api";

type Props = {
  url: string;
  label: string;
};

export function MeshViewer({ url, label }: Props) {
  const host = useRef<HTMLDivElement | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState("Loading mesh…");

  useEffect(() => {
    let disposed = false;
    let renderer: { dispose: () => void; forceContextLoss?: () => void } | null = null;
    let frame = 0;
    const abort = new AbortController();

    async function mount() {
      const [{ WebGLRenderer, Scene, PerspectiveCamera, Color, DirectionalLight, AmbientLight, GridHelper }, { STLLoader }, { OrbitControls }] =
        await Promise.all([import("three"), import("three/examples/jsm/loaders/STLLoader.js"), import("three/examples/jsm/controls/OrbitControls.js")]);

      if (!host.current || disposed) return;
      const blob = await fetchAuthedBlob(url, { signal: abort.signal });
      const buffer = await blob.arrayBuffer();
      const geometry = new STLLoader().parse(buffer);
      geometry.computeVertexNormals();
      geometry.center();

      const scene = new Scene();
      scene.background = new Color("#121821");
      const camera = new PerspectiveCamera(45, host.current.clientWidth / host.current.clientHeight, 0.1, 2000);
      camera.position.set(80, 70, 110);

      const webgl = new WebGLRenderer({ antialias: true });
      webgl.setSize(host.current.clientWidth, host.current.clientHeight);
      host.current.replaceChildren(webgl.domElement);
      renderer = webgl;

      const { Mesh, MeshStandardMaterial } = await import("three");
      const mesh = new Mesh(geometry, new MeshStandardMaterial({ color: "#5eead4", metalness: 0.15, roughness: 0.45 }));
      scene.add(mesh);
      scene.add(new AmbientLight(0xffffff, 0.55));
      const key = new DirectionalLight(0xffffff, 1.1);
      key.position.set(40, 80, 30);
      scene.add(key);
      scene.add(new GridHelper(120, 12, 0x243044, 0x1a2330));

      const controls = new OrbitControls(camera, webgl.domElement);
      controls.enableDamping = true;

      const tick = () => {
        controls.update();
        webgl.render(scene, camera);
        frame = requestAnimationFrame(tick);
      };
      tick();
      setStatus(label);
    }

    mount().catch((err) => {
      if (disposed || isAbortError(err)) return;
      setError(err instanceof Error ? err.message : "Viewer failed");
    });

    return () => {
      disposed = true;
      abort.abort();
      cancelAnimationFrame(frame);
      renderer?.dispose();
    };
  }, [url, label]);

  return (
    <div className="overflow-hidden rounded-2xl border border-white/10 bg-ink-900">
      <div ref={host} className="h-80 w-full" />
      <p className="border-t border-white/5 px-4 py-2 text-xs text-slate-400">{error ?? status}</p>
    </div>
  );
}
