import { decodeMeshBuffer, type DecodeOptions, type DecodeResult, type DecodedMesh } from "./meshDecode";
import type { DecodeWorkerOutbound, DecodeWorkerRequest } from "./meshDecodeProtocol";
import { MeshViewerError } from "./meshViewer";

let nextId = 1;

function isAbort(signal?: AbortSignal) {
  return Boolean(signal?.aborted);
}

function createDecodeWorker(): Worker {
  return new Worker(new URL("./meshDecode.worker.ts", import.meta.url), { type: "module" });
}

function waitForReady(worker: Worker, signal?: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    const onAbort = () => {
      cleanup();
      reject(new DOMException("Aborted", "AbortError"));
    };
    const onError = (event: ErrorEvent) => {
      cleanup();
      reject(event.error instanceof Error ? event.error : new Error(event.message || "Worker failed"));
    };
    const onMessage = (event: MessageEvent<DecodeWorkerOutbound>) => {
      if (event.data?.type === "ready") {
        cleanup();
        resolve();
      }
    };
    const cleanup = () => {
      worker.removeEventListener("message", onMessage);
      worker.removeEventListener("error", onError);
      signal?.removeEventListener("abort", onAbort);
    };
    if (signal?.aborted) {
      reject(new DOMException("Aborted", "AbortError"));
      return;
    }
    worker.addEventListener("message", onMessage);
    worker.addEventListener("error", onError);
    signal?.addEventListener("abort", onAbort, { once: true });
  });
}

async function decodeMeshInWorker(buffer: ArrayBuffer, options: DecodeOptions): Promise<DecodeResult> {
  const worker = createDecodeWorker();
  const id = nextId;
  nextId += 1;
  const meshes: DecodedMesh[] = [];

  const terminate = () => {
    worker.terminate();
  };

  try {
    await waitForReady(worker, options.signal);
    if (isAbort(options.signal)) throw new DOMException("Aborted", "AbortError");

    const result = await new Promise<DecodeResult>((resolve, reject) => {
      const onAbort = () => {
        cleanup();
        terminate();
        reject(new DOMException("Aborted", "AbortError"));
      };
      const onError = (event: ErrorEvent) => {
        cleanup();
        terminate();
        reject(event.error instanceof Error ? event.error : new Error(event.message || "Worker failed"));
      };
      const onMessage = (event: MessageEvent<DecodeWorkerOutbound>) => {
        const data = event.data;
        if (!data || ("id" in data && data.id !== id)) return;
        if (data.type === "mesh") {
          meshes.push(data.mesh);
          options.onMesh?.(data.mesh, data.cumulativeVerts);
          return;
        }
        if (data.type === "done") {
          cleanup();
          terminate();
          resolve({ format: options.format, meshes, vertexCount: data.vertexCount });
          return;
        }
        if (data.type === "error") {
          cleanup();
          terminate();
          reject(new MeshViewerError((data.code as MeshViewerError["code"]) || "unsupported", data.message));
        }
      };
      const cleanup = () => {
        worker.removeEventListener("message", onMessage);
        worker.removeEventListener("error", onError);
        options.signal?.removeEventListener("abort", onAbort);
      };

      worker.addEventListener("message", onMessage);
      worker.addEventListener("error", onError);
      options.signal?.addEventListener("abort", onAbort, { once: true });

      const request: DecodeWorkerRequest = {
        type: "decode",
        id,
        format: options.format,
        buffer,
        maxVerts: options.maxVerts ?? 0
      };
      worker.postMessage(request, [buffer]);
    });
    return result;
  } catch (error) {
    terminate();
    throw error;
  }
}

/**
 * Decode off the main thread when Workers exist.
 * Falls back to the same parsers on-thread (tests / older browsers).
 */
export async function decodeMeshOffthread(buffer: ArrayBuffer, options: DecodeOptions): Promise<DecodeResult> {
  if (typeof Worker === "undefined") {
    return decodeMeshBuffer(buffer, options);
  }
  try {
    return await decodeMeshInWorker(buffer, options);
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") throw error;
    if (error instanceof MeshViewerError) throw error;
    return decodeMeshBuffer(buffer, options);
  }
}
