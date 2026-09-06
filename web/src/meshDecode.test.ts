import { describe, expect, it } from "vitest";
import {
  decode3mf,
  decodeAsciiStl,
  decodeBinaryStl,
  decodeMeshBuffer,
  decodeObj,
  isBinaryStl
} from "./meshDecode";
import { MeshViewerError } from "./meshViewer";

const ASCII_TRIANGLE = `solid tri
  facet normal 0 0 1
    outer loop
      vertex 0 0 0
      vertex 1 0 0
      vertex 0 1 0
    endloop
  endfacet
endsolid
`;

const OBJ_TRIANGLE = `v 0 0 0
v 1 0 0
v 0 1 0
f 1 2 3
`;

function binaryStl(triangles = 1) {
  const buffer = new ArrayBuffer(84 + triangles * 50);
  const view = new DataView(buffer);
  view.setUint32(80, triangles, true);
  let offset = 84;
  for (let i = 0; i < triangles; i += 1) {
    view.setFloat32(offset + 8, 1, true);
    view.setFloat32(offset + 12, 0, true);
    view.setFloat32(offset + 24, 1, true);
    view.setFloat32(offset + 36, 0, true);
    view.setFloat32(offset + 40, 1, true);
    offset += 50;
  }
  return buffer;
}

function storeZip(files: Record<string, string>) {
  const encoder = new TextEncoder();
  const parts: Uint8Array[] = [];
  for (const [name, body] of Object.entries(files)) {
    const nameBytes = encoder.encode(name);
    const data = encoder.encode(body);
    const header = new ArrayBuffer(30);
    const view = new DataView(header);
    view.setUint32(0, 0x04034b50, true);
    view.setUint32(18, data.byteLength, true);
    view.setUint32(22, data.byteLength, true);
    view.setUint16(26, nameBytes.byteLength, true);
    parts.push(new Uint8Array(header), nameBytes, data);
  }
  const central = new ArrayBuffer(4);
  new DataView(central).setUint32(0, 0x02014b50, true);
  parts.push(new Uint8Array(central));
  const total = parts.reduce((sum, part) => sum + part.byteLength, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.byteLength;
  }
  return out.buffer;
}

const MODEL_XML = `<?xml version="1.0"?>
<model unit="millimeter"><resources><object id="1" type="model"><mesh>
<vertices>
<vertex x="0" y="0" z="0"/>
<vertex x="1" y="0" z="0"/>
<vertex x="0" y="1" z="0"/>
</vertices>
<triangles><triangle v1="0" v2="1" v3="2"/></triangles>
</mesh></object></resources></model>`;

describe("mesh decode (worker-equivalent parsers)", () => {
  it("parses ASCII and binary STL without Three.js", () => {
    const ascii = decodeAsciiStl(ASCII_TRIANGLE);
    expect(ascii.vertexCount).toBe(3);
    expect(ascii.positions[3]).toBe(1);
    const binary = decodeBinaryStl(binaryStl(2));
    expect(isBinaryStl(binaryStl(2))).toBe(true);
    expect(binary.vertexCount).toBe(6);
  });

  it("parses a triangle OBJ and a stored 3MF model member", async () => {
    const obj = decodeObj(OBJ_TRIANGLE);
    expect(obj.vertexCount).toBe(3);
    expect(obj.index?.length).toBe(3);
    const meshes = await decode3mf(
      storeZip({
        "[Content_Types].xml": "<Types></Types>",
        "3D/3dmodel.model": MODEL_XML
      })
    );
    expect(meshes).toHaveLength(1);
    expect(meshes[0].vertexCount).toBe(3);
  });

  it("enforces vertex budgets before a huge binary STL can expand", async () => {
    expect(() => decodeBinaryStl(binaryStl(2), 3)).toThrowError(MeshViewerError);
    await expect(decodeMeshBuffer(binaryStl(1), { format: "stl", maxVerts: 2 })).rejects.toBeInstanceOf(MeshViewerError);
    await expect(decodeMeshBuffer(new TextEncoder().encode(OBJ_TRIANGLE).buffer, { format: "obj", maxVerts: 2 })).rejects.toMatchObject({
      code: "too_many_verts"
    });
  });

  it("reports progressive meshes for a 3MF then a final vertex count", async () => {
    const seen: number[] = [];
    const result = await decodeMeshBuffer(
      storeZip({
        "3D/a.model": MODEL_XML,
        "3D/b.model": MODEL_XML
      }),
      {
        format: "3mf",
        onMesh: (_mesh, cumulative) => seen.push(cumulative)
      }
    );
    expect(seen).toEqual([3, 6]);
    expect(result.vertexCount).toBe(6);
    expect(result.meshes).toHaveLength(2);
  });

  it("aborts decode when the signal is already aborted", async () => {
    const abort = new AbortController();
    abort.abort();
    await expect(decodeMeshBuffer(binaryStl(1), { format: "stl", signal: abort.signal })).rejects.toMatchObject({
      name: "AbortError"
    });
  });
});
