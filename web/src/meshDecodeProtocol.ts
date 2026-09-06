import type { DecodedMesh } from "./meshDecode";
import type { MeshFormat } from "./meshViewer";

export type DecodeWorkerReady = { type: "ready" };

export type DecodeWorkerRequest = {
  type: "decode";
  id: number;
  format: MeshFormat;
  buffer: ArrayBuffer;
  maxVerts: number;
};

export type DecodeWorkerMesh = {
  type: "mesh";
  id: number;
  mesh: DecodedMesh;
  cumulativeVerts: number;
};

export type DecodeWorkerDone = {
  type: "done";
  id: number;
  vertexCount: number;
  meshCount: number;
};

export type DecodeWorkerError = {
  type: "error";
  id: number;
  code: string;
  message: string;
};

export type DecodeWorkerOutbound = DecodeWorkerReady | DecodeWorkerMesh | DecodeWorkerDone | DecodeWorkerError;
