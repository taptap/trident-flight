#!/usr/bin/env python3
"""Recover the original R06 and import its rigid meshes without losing animated pivots.

Run with the original H5 zip and a locally built UrhoXCLI. The engine importer
flattens non-skinned glTF hierarchies, so each mesh is imported separately and
the source hierarchy and display-animation poses are retained as Lua data.
"""

import argparse
import base64
import copy
import itertools
import json
import math
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def accessor(gltf, binary, index):
    """Read the float animation accessors used by this uncompressed source GLB."""
    item = gltf["accessors"][index]
    view = gltf["bufferViews"][item["bufferView"]]
    assert item["componentType"] == 5126
    width = {"SCALAR": 1, "VEC4": 4}[item["type"]]
    start = view.get("byteOffset", 0) + item.get("byteOffset", 0)
    stride = view.get("byteStride", width * 4)
    return [struct.unpack_from("<" + "f" * width, binary, start + i * stride)
            for i in range(item["count"])]


def sample_rotation(gltf, binary, sampler, seconds):
    """Sample a glTF LINEAR quaternion track with normalized shortest-arc slerp."""
    times = [v[0] for v in accessor(gltf, binary, sampler["input"])]
    values = accessor(gltf, binary, sampler["output"])
    if seconds <= times[0]:
        return values[0]
    if seconds >= times[-1]:
        return values[-1]
    i = next(i for i in range(len(times) - 1) if times[i + 1] >= seconds)
    a, b = values[i], values[i + 1]
    t = (seconds - times[i]) / (times[i + 1] - times[i])
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b, dot = [-x for x in b], -dot
    if dot > 0.9995:
        q = [x + (y - x) * t for x, y in zip(a, b)]
        length = math.sqrt(sum(x * x for x in q))
        return [x / length for x in q]
    angle = math.acos(min(1, dot))
    return [(x * math.sin((1 - t) * angle) + y * math.sin(t * angle)) / math.sin(angle)
            for x, y in zip(a, b)]


def transform(node, point):
    """Apply one source node's local TRS to a point, before handedness conversion."""
    assert "matrix" not in node, "This source is expected to use decomposed TRS"
    p = [x * s for x, s in zip(point, node.get("scale", [1, 1, 1]))]
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    uv = [y * p[2] - z * p[1], z * p[0] - x * p[2], x * p[1] - y * p[0]]
    uuv = [y * uv[2] - z * uv[1], z * uv[0] - x * uv[2], x * uv[1] - y * uv[0]]
    return [v + 2 * (w * a + b) + tr for v, a, b, tr
            in zip(p, uv, uuv, node.get("translation", [0, 0, 0]))]


def lua(value):
    """Serialize generated asset metadata; node and mesh IDs remain zero-based."""
    if isinstance(value, dict):
        return "{" + ",".join("[" + json.dumps(str(k)) + "]=" + lua(v) for k, v in value.items()) + "}"
    if isinstance(value, (list, tuple)):
        return "{" + ",".join(lua(v) for v in value) + "}"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return "true" if value else "false"
    return repr(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--cli", required=True, type=Path)
    args = parser.parse_args()
    source = ROOT / "source"
    models = ROOT / "assets/Models/R06"
    scripts = ROOT / "scripts/Game"
    for folder in (source, models, scripts):
        folder.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.archive) as archive:
        html = archive.read("trident-h5/Black Emperor R06 - H5.html").decode()
        raw = base64.b64decode(re.search(r'<script id="model-data"[^>]*>(.*?)</script>', html, re.S)[1])
        (source / "R06.glb").write_bytes(raw)
        hdr = "kloppenheim_06_puresky_2k.hdr"
        (source / hdr).write_bytes(archive.read("trident-h5/" + hdr))
    size = struct.unpack_from("<I", raw, 12)[0]
    gltf = json.loads(raw[20:20 + size])
    binary = raw[28 + size:]
    assert not gltf.get("skins") and not gltf.get("textures")
    nodes = copy.deepcopy(gltf["nodes"])
    parents = {child: i for i, node in enumerate(nodes) for child in node.get("children", [])}
    low, high = [math.inf] * 3, [-math.inf] * 3
    for i, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
            pos = gltf["accessors"][primitive["attributes"]["POSITION"]]
            for corner in itertools.product(*zip(pos["min"], pos["max"])):
                index, point = i, corner
                while index is not None:
                    point = transform(nodes[index], point)
                    index = parents.get(index)
                low = [min(a, b) for a, b in zip(low, point)]
                high = [max(a, b) for a, b in zip(high, point)]
    clips = {}
    animation = gltf["animations"][0]
    for channel in animation["channels"]:
        target = channel["target"]
        assert target["path"] == "rotation"
        node = nodes[target["node"]]
        sampler = animation["samplers"][channel["sampler"]]
        assert sampler["interpolation"] == "LINEAR"
        clips[target["node"]] = {
            "closed": sample_rotation(gltf, binary, sampler, 1 / 30),
            "open": sample_rotation(gltf, binary, sampler, (49 if "Gear" in node["name"] else 64) / 30),
        }
    metadata = {"nodes": nodes, "roots": gltf["scenes"][0]["nodes"], "poses": clips,
                "materials": gltf["materials"], "meshes": gltf["meshes"],
                "center": [(a + b) / 2 for a, b in zip(low, high)],
                "size": [b - a for a, b in zip(low, high)]}
    with tempfile.TemporaryDirectory(prefix="r06-import-", dir=ROOT / ".amp/in") as temporary:
        for i, mesh in enumerate(gltf["meshes"]):
            part = {k: v for k, v in gltf.items() if k not in ("nodes", "scenes", "animations", "meshes")}
            part.update(nodes=[{"mesh": 0}], scenes=[{"nodes": [0]}], scene=0, meshes=[mesh])
            text = json.dumps(part, separators=(",", ":")).encode()
            text += b" " * (-len(text) % 4)
            glb = struct.pack("<III", 0x46546C67, 2, 28 + len(text) + len(binary))
            glb += struct.pack("<II", len(text), 0x4E4F534A) + text
            glb += struct.pack("<II", len(binary), 0x004E4942) + binary
            path = Path(temporary) / f"Part{i:02d}.glb"
            path.write_bytes(glb)
            result = subprocess.run([str(args.cli), "import-gltf", "-i", str(path), "-o",
                                     str(models / f"Part{i:02d}.mdl"), "--no-lod",
                                     "--resource-root", str(ROOT / "assets")],
                                    text=True, capture_output=True)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            print(f"[{i + 1}/{len(gltf['meshes'])}] {mesh.get('name', '')}", flush=True)
    (scripts / "AircraftData.lua").write_text("-- Generated by tools/import_aircraft.py; source IDs are zero-based.\nreturn " + lua(metadata) + "\n")
    print("Imported R06:", len(nodes), "nodes,", len(clips), "animated joints; size", metadata["size"])


if __name__ == "__main__":
    (ROOT / ".amp/in").mkdir(parents=True, exist_ok=True)
    main()
