import { decodeMeshBuffer } from "./meshDecode";
import { MeshViewerError } from "./meshViewer";
import type { DecodeWorkerOutbound, DecodeWorkerRequest } from "./meshDecodeProtocol";

const workerScope = self as unknown as {
  postMessage: (message: DecodeWorkerOutbound, transfer?: Transferable[]) => void;
};

function post(message: DecodeWorkerOutbound, transfer: Transferable[] = []) {
  workerScope.postMessage(message, transfer);
}

function transferablesOf(mesh: { positions: Float32Array; normals?: Float32Array; index?: Uint32Array }) {
  const list: Transferable[] = [mesh.positions.buffer];
  if (mesh.normals) list.push(mesh.normals.buffer);
  if (mesh.index) list.push(mesh.index.buffer);
  return list;
}

self.postMessage({ type: "ready" } satisfies DecodeWorkerOutbound);

self.onmessage = (event: MessageEvent<DecodeWorkerRequest>) => {
  const data = event.data;
  if (!data || data.type !== "decode") return;

  void decodeMeshBuffer(data.buffer, {
    format: data.format,
    maxVerts: data.maxVerts,
    onMesh: (mesh, cumulativeVerts) => {
      post({ type: "mesh", id: data.id, mesh, cumulativeVerts }, transferablesOf(mesh));
    }
  })
    .then((result) => {
      post({ type: "done", id: data.id, vertexCount: result.vertexCount, meshCount: result.meshes.length });
    })
    .catch((error: unknown) => {
      const code = error instanceof MeshViewerError ? error.code : "unsupported";
      const message = error instanceof Error ? error.message : "Could not decode mesh";
      post({ type: "error", id: data.id, code, message });
    });
};
