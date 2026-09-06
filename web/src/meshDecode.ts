import { MeshViewerError, isOverVertBudget, throwIfOverVerts, type MeshFormat } from "./meshViewer";

export type DecodedMesh = {
  positions: Float32Array;
  normals?: Float32Array;
  index?: Uint32Array;
  vertexCount: number;
};

export type DecodeResult = {
  format: MeshFormat;
  meshes: DecodedMesh[];
  vertexCount: number;
};

export type DecodeOptions = {
  format: MeshFormat;
  maxVerts?: number;
  signal?: AbortSignal;
  onMesh?: (mesh: DecodedMesh, cumulativeVerts: number) => void;
};

function abortIfNeeded(signal?: AbortSignal) {
  if (signal?.aborted) throw new DOMException("Aborted", "AbortError");
}

function asDecoded(positions: number[] | Float32Array, normals?: number[] | Float32Array, index?: number[] | Uint32Array): DecodedMesh {
  const pos = positions instanceof Float32Array ? positions : new Float32Array(positions);
  const vertexCount = Math.floor(pos.length / 3);
  if (vertexCount < 3) throw new MeshViewerError("empty");
  return {
    positions: pos,
    normals: normals ? (normals instanceof Float32Array ? normals : new Float32Array(normals)) : undefined,
    index: index ? (index instanceof Uint32Array ? index : new Uint32Array(index)) : undefined,
    vertexCount
  };
}

export function isBinaryStl(buffer: ArrayBuffer) {
  if (buffer.byteLength < 84) return false;
  const triangles = new DataView(buffer).getUint32(80, true);
  const expected = 84 + triangles * 50;
  if (expected === buffer.byteLength) return true;
  const prefix = new TextDecoder("latin1").decode(new Uint8Array(buffer, 0, Math.min(5, buffer.byteLength)));
  return !prefix.toLowerCase().startsWith("solid");
}

export function decodeBinaryStl(buffer: ArrayBuffer, maxVerts = 0): DecodedMesh {
  if (buffer.byteLength < 84) throw new MeshViewerError("empty");
  const view = new DataView(buffer);
  const triangles = view.getUint32(80, true);
  throwIfOverVerts(triangles * 3, maxVerts);
  if (buffer.byteLength < 84 + triangles * 50) throw new MeshViewerError("empty");

  const positions = new Float32Array(triangles * 9);
  const normals = new Float32Array(triangles * 9);
  let offset = 84;
  let cursor = 0;
  for (let i = 0; i < triangles; i += 1) {
    const nx = view.getFloat32(offset, true);
    const ny = view.getFloat32(offset + 4, true);
    const nz = view.getFloat32(offset + 8, true);
    offset += 12;
    for (let v = 0; v < 3; v += 1) {
      positions[cursor] = view.getFloat32(offset, true);
      positions[cursor + 1] = view.getFloat32(offset + 4, true);
      positions[cursor + 2] = view.getFloat32(offset + 8, true);
      normals[cursor] = nx;
      normals[cursor + 1] = ny;
      normals[cursor + 2] = nz;
      cursor += 3;
      offset += 12;
    }
    offset += 2;
  }
  return asDecoded(positions, normals);
}

export function decodeAsciiStl(text: string, maxVerts = 0): DecodedMesh {
  const positions: number[] = [];
  const normals: number[] = [];
  let nx = 0;
  let ny = 0;
  let nz = 1;
  const lines = text.split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.toLowerCase().startsWith("facet normal")) {
      const parts = trimmed.split(/\s+/);
      nx = Number(parts[2]) || 0;
      ny = Number(parts[3]) || 0;
      nz = Number(parts[4]) || 0;
    } else if (trimmed.toLowerCase().startsWith("vertex")) {
      const parts = trimmed.split(/\s+/);
      positions.push(Number(parts[1]) || 0, Number(parts[2]) || 0, Number(parts[3]) || 0);
      normals.push(nx, ny, nz);
      if (isOverVertBudget(positions.length / 3, maxVerts)) throw new MeshViewerError("too_many_verts");
    }
  }
  return asDecoded(positions, normals);
}

export function decodeStl(buffer: ArrayBuffer, maxVerts = 0): DecodedMesh {
  if (isBinaryStl(buffer)) return decodeBinaryStl(buffer, maxVerts);
  return decodeAsciiStl(new TextDecoder("utf-8").decode(buffer), maxVerts);
}

function parseObjIndex(token: string, count: number) {
  const raw = token.split("/")[0];
  const value = Number(raw);
  if (!Number.isFinite(value) || value === 0) return -1;
  return value < 0 ? count + value : value - 1;
}

export function decodeObj(text: string, maxVerts = 0): DecodedMesh {
  const verts: number[] = [];
  const index: number[] = [];
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    if (trimmed.startsWith("v ")) {
      const parts = trimmed.split(/\s+/);
      verts.push(Number(parts[1]) || 0, Number(parts[2]) || 0, Number(parts[3]) || 0);
      if (isOverVertBudget(verts.length / 3, maxVerts)) throw new MeshViewerError("too_many_verts");
    } else if (trimmed.startsWith("f ")) {
      const tokens = trimmed.split(/\s+/).slice(1);
      const ids = tokens.map((token) => parseObjIndex(token, verts.length / 3)).filter((id) => id >= 0);
      for (let i = 1; i + 1 < ids.length; i += 1) {
        index.push(ids[0], ids[i], ids[i + 1]);
      }
    }
  }
  if (verts.length < 9 || index.length < 3) throw new MeshViewerError("empty");
  return asDecoded(verts, undefined, index);
}

function tagAttrs(tag: string) {
  const attrs: Record<string, string> = {};
  const re = /([:\w.]+)\s*=\s*["']([^"']*)["']/g;
  let match: RegExpExecArray | null;
  while ((match = re.exec(tag))) {
    attrs[match[1].toLowerCase()] = match[2];
  }
  return attrs;
}

export function decode3mfModelXml(xml: string, maxVerts = 0, startVerts = 0): DecodedMesh[] {
  const meshes: DecodedMesh[] = [];
  let cumulative = startVerts;
  const blocks = xml.split(/<mesh\b/i).slice(1);
  for (const block of blocks) {
    const body = block.split(/<\/mesh>/i)[0] || block;
    const verts: number[] = [];
    const index: number[] = [];
    const vertexRe = /<vertex\b[^>]*>/gi;
    let match: RegExpExecArray | null;
    while ((match = vertexRe.exec(body))) {
      const attrs = tagAttrs(match[0]);
      verts.push(Number(attrs.x) || 0, Number(attrs.y) || 0, Number(attrs.z) || 0);
      if (isOverVertBudget(cumulative + verts.length / 3, maxVerts)) throw new MeshViewerError("too_many_verts");
    }
    const triRe = /<triangle\b[^>]*>/gi;
    while ((match = triRe.exec(body))) {
      const attrs = tagAttrs(match[0]);
      index.push(Number(attrs.v1) || 0, Number(attrs.v2) || 0, Number(attrs.v3) || 0);
    }
    if (verts.length < 9 || index.length < 3) continue;
    const mesh = asDecoded(verts, undefined, index);
    meshes.push(mesh);
    cumulative += mesh.vertexCount;
  }
  if (meshes.length === 0) throw new MeshViewerError("empty");
  return meshes;
}

async function inflateRaw(data: Uint8Array): Promise<Uint8Array> {
  if (typeof DecompressionStream === "function") {
    const copy = Uint8Array.from(data);
    const stream = new Blob([copy]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }
  throw new MeshViewerError("unsupported");
}

export async function readZipEntries(buffer: ArrayBuffer): Promise<Array<{ name: string; data: Uint8Array }>> {
  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  const entries: Array<{ name: string; data: Uint8Array }> = [];
  let offset = 0;
  const decoder = new TextDecoder();

  while (offset + 30 <= bytes.length) {
    const signature = view.getUint32(offset, true);
    if (signature !== 0x04034b50) break;
    const flags = view.getUint16(offset + 6, true);
    const method = view.getUint16(offset + 8, true);
    const compSize = view.getUint32(offset + 18, true);
    const nameLen = view.getUint16(offset + 26, true);
    const extraLen = view.getUint16(offset + 28, true);
    if (flags & 0x8) throw new MeshViewerError("unsupported");
    const nameStart = offset + 30;
    const name = decoder.decode(bytes.subarray(nameStart, nameStart + nameLen));
    const dataStart = nameStart + nameLen + extraLen;
    const dataEnd = dataStart + compSize;
    if (dataEnd > bytes.length) throw new MeshViewerError("unsupported");
    const compressed = new Uint8Array(bytes.subarray(dataStart, dataEnd));
    let data: Uint8Array;
    if (method === 8) data = await inflateRaw(compressed);
    else if (method === 0) data = compressed;
    else throw new MeshViewerError("unsupported");
    entries.push({ name: name.replace(/\\/g, "/"), data });
    offset = dataEnd;
  }
  return entries;
}

export async function decode3mf(buffer: ArrayBuffer, maxVerts = 0, signal?: AbortSignal): Promise<DecodedMesh[]> {
  abortIfNeeded(signal);
  const entries = await readZipEntries(buffer);
  abortIfNeeded(signal);
  const models = entries.filter((entry) => /\.model$/i.test(entry.name) && !entry.name.endsWith("/"));
  if (models.length === 0) throw new MeshViewerError("unsupported");
  const meshes: DecodedMesh[] = [];
  let cumulative = 0;
  const decoder = new TextDecoder();
  for (const entry of models) {
    abortIfNeeded(signal);
    const parsed = decode3mfModelXml(decoder.decode(entry.data), maxVerts, cumulative);
    for (const mesh of parsed) {
      meshes.push(mesh);
      cumulative += mesh.vertexCount;
    }
  }
  if (meshes.length === 0) throw new MeshViewerError("empty");
  return meshes;
}

export async function decodeMeshBuffer(buffer: ArrayBuffer, options: DecodeOptions): Promise<DecodeResult> {
  abortIfNeeded(options.signal);
  const maxVerts = options.maxVerts ?? 0;
  const meshes: DecodedMesh[] = [];

  const push = (mesh: DecodedMesh) => {
    meshes.push(mesh);
    const vertexCount = meshes.reduce((sum, item) => sum + item.vertexCount, 0);
    throwIfOverVerts(vertexCount, maxVerts);
    options.onMesh?.(mesh, vertexCount);
  };

  if (options.format === "stl") {
    push(decodeStl(buffer, maxVerts));
  } else if (options.format === "obj") {
    push(decodeObj(new TextDecoder("utf-8").decode(buffer), maxVerts));
  } else if (options.format === "3mf") {
    const decoded = await decode3mf(buffer, maxVerts, options.signal);
    for (const mesh of decoded) push(mesh);
  } else {
    throw new MeshViewerError("unsupported");
  }

  const vertexCount = meshes.reduce((sum, item) => sum + item.vertexCount, 0);
  if (vertexCount === 0) throw new MeshViewerError("empty");
  return { format: options.format, meshes, vertexCount };
}
