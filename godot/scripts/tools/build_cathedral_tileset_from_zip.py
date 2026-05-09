#!/usr/bin/env python3
"""
Build a Godot-ready cathedral Wang tileset from the Kokoro Cathedral pack.

Outputs:
- godot/tilesets/cathedral_image.png
- godot/tilesets/cathedral_metadata.json

This version avoids synthetic blending artifacts and instead picks a real
4x4 block from the pack that best matches two-terrain Wang corner behavior.
If a few Wang combinations are missing, they are filled by nearest Hamming
pattern so map generation never collapses to a single tile.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]  # godot/
ZIP_DEFAULT = ROOT / "cathedral.zip"
PACK_DIR_DEFAULT = ROOT / "cathedral"
OUT_IMG = ROOT / "tilesets" / "cathedral_image.png"
OUT_META = ROOT / "tilesets" / "cathedral_metadata.json"

TILE_SIZE = 32
ATLAS_GRID = 4
ATLAS_SIZE = TILE_SIZE * ATLAS_GRID

SOURCE_FILES = [
    "32px+VXACE/non-rm-a2-square.png",
    "32px+VXACE/Church_A2.png",
    "32px+VXACE/Church_A5.png",
]


def _load_pack_image(pack_dir: Path, rel_path: str) -> Image.Image | None:
    p = pack_dir / rel_path
    if not p.exists():
        return None
    return Image.open(p).convert("RGBA")


def _alpha_coverage(tile: Image.Image) -> float:
    a = tile.getchannel("A")
    opaque = sum(a.histogram()[220:])
    return opaque / float(tile.width * tile.height)


def _corner_vec(tile: Image.Image, corner: int, sample: int = 8) -> tuple[float, float, float]:
    px = tile.load()
    w, h = tile.size
    if corner == 0:
        xr, yr = range(0, sample), range(0, sample)
    elif corner == 1:
        xr, yr = range(w - sample, w), range(0, sample)
    elif corner == 2:
        xr, yr = range(0, sample), range(h - sample, h)
    else:
        xr, yr = range(w - sample, w), range(h - sample, h)
    vals: list[tuple[int, int, int]] = []
    for y in yr:
        for x in xr:
            r, g, b, a = px[x, y]
            if a > 220:
                vals.append((r, g, b))
    if not vals:
        return (0.0, 0.0, 0.0)
    n = float(len(vals))
    return (
        sum(v[0] for v in vals) / n,
        sum(v[1] for v in vals) / n,
        sum(v[2] for v in vals) / n,
    )


def _kmeans2(points: list[tuple[float, float, float]]) -> tuple[tuple[float, float, float], tuple[float, float, float], float]:
    c0 = list(points[0])
    c1 = list(points[-1])
    for _ in range(12):
        g0: list[tuple[float, float, float]] = []
        g1: list[tuple[float, float, float]] = []
        for p in points:
            d0 = (p[0] - c0[0]) ** 2 + (p[1] - c0[1]) ** 2 + (p[2] - c0[2]) ** 2
            d1 = (p[0] - c1[0]) ** 2 + (p[1] - c1[1]) ** 2 + (p[2] - c1[2]) ** 2
            (g0 if d0 <= d1 else g1).append(p)
        if not g0 or not g1:
            break
        c0 = [sum(p[i] for p in g0) / len(g0) for i in range(3)]
        c1 = [sum(p[i] for p in g1) / len(g1) for i in range(3)]
    sep = math.sqrt((c0[0] - c1[0]) ** 2 + (c0[1] - c1[1]) ** 2 + (c0[2] - c1[2]) ** 2)
    return (tuple(c0), tuple(c1), sep)


def _hamming(a: int, b: int) -> int:
    x = a ^ b
    c = 0
    while x:
        c += x & 1
        x >>= 1
    return c


def _extract_best_wang_block(img: Image.Image) -> dict | None:
    cols = img.width // TILE_SIZE
    rows = img.height // TILE_SIZE
    best: dict | None = None

    for by in range(rows - 3):
        for bx in range(cols - 3):
            tiles: list[Image.Image] = []
            ok = True
            for gy in range(4):
                for gx in range(4):
                    x0 = (bx + gx) * TILE_SIZE
                    y0 = (by + gy) * TILE_SIZE
                    t = img.crop((x0, y0, x0 + TILE_SIZE, y0 + TILE_SIZE))
                    if _alpha_coverage(t) < 0.98:
                        ok = False
                        break
                    tiles.append(t)
                if not ok:
                    break
            if not ok:
                continue

            per_corner_bits: list[list[int]] = []
            separations: list[float] = []
            for corner in range(4):
                pts = [_corner_vec(t, corner) for t in tiles]
                c0, c1, sep = _kmeans2(pts)
                separations.append(sep)
                bits: list[int] = []
                for p in pts:
                    d0 = (p[0] - c0[0]) ** 2 + (p[1] - c0[1]) ** 2 + (p[2] - c0[2]) ** 2
                    d1 = (p[0] - c1[0]) ** 2 + (p[1] - c1[1]) ** 2 + (p[2] - c1[2]) ** 2
                    bits.append(0 if d0 <= d1 else 1)
                per_corner_bits.append(bits)

            idx_to_tile: dict[int, Image.Image] = {}
            for i, t in enumerate(tiles):
                idx = (
                    (per_corner_bits[0][i] << 3)
                    | (per_corner_bits[1][i] << 2)
                    | (per_corner_bits[2][i] << 1)
                    | per_corner_bits[3][i]
                )
                idx_to_tile[idx] = t

            unique_count = len(idx_to_tile)
            # Prefer more unique Wang states first.
            # Extremely high corner separation usually indicates hard-edged/non-floor tiles
            # (walls/icons), so keep a "moderate separation" preference.
            min_sep = min(separations)
            sep_penalty = max(0.0, min_sep - 120.0) * 2.0
            score = unique_count * 100.0 + min_sep - sep_penalty
            cand = {
                "score": score,
                "bx": bx,
                "by": by,
                "unique_count": unique_count,
                "idx_to_tile": idx_to_tile,
                "separations": separations,
            }
            if best is None or cand["score"] > best["score"]:
                best = cand
    return best


def _corners_dict(wang_idx: int) -> dict[str, str]:
    return {
        "NW": "upper" if ((wang_idx >> 3) & 1) else "lower",
        "NE": "upper" if ((wang_idx >> 2) & 1) else "lower",
        "SW": "upper" if ((wang_idx >> 1) & 1) else "lower",
        "SE": "upper" if (wang_idx & 1) else "lower",
    }


def build(pack_dir: Path) -> None:
    if not pack_dir.exists():
        raise FileNotFoundError(f"Pack folder not found: {pack_dir}")

    best_global: dict | None = None
    best_name = ""
    for rel in SOURCE_FILES:
        img = _load_pack_image(pack_dir, rel)
        if img is None:
            continue
        cand = _extract_best_wang_block(img)
        if cand is None:
            continue
        if best_global is None or cand["score"] > best_global["score"]:
            best_global = cand
            best_name = rel

    if best_global is None:
        raise RuntimeError("Could not find a usable 4x4 Wang-like block in cathedral sources.")

    idx_to_tile: dict[int, Image.Image] = dict(best_global["idx_to_tile"])
    present = sorted(idx_to_tile.keys())
    # Fill missing Wang states with nearest existing corner pattern to avoid fallback-to-zero spam.
    for idx in range(16):
        if idx in idx_to_tile:
            continue
        nearest = min(present, key=lambda x: _hamming(x, idx))
        idx_to_tile[idx] = idx_to_tile[nearest].copy()

    atlas = Image.new("RGBA", (ATLAS_SIZE, ATLAS_SIZE), (0, 0, 0, 0))
    tiles: list[dict] = []
    for wang_idx in range(16):
        tx = (wang_idx % 4) * TILE_SIZE
        ty = (wang_idx // 4) * TILE_SIZE
        atlas.paste(idx_to_tile[wang_idx], (tx, ty))
        tiles.append(
            {
                "id": str(wang_idx),
                "name": f"wang_{wang_idx}",
                "corners": _corners_dict(wang_idx),
                "bounding_box": {"x": tx, "y": ty, "width": TILE_SIZE, "height": TILE_SIZE},
            }
        )

    OUT_IMG.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT_IMG)

    metadata = {
        "id": "cathedral_custom_from_pack",
        "name": f"cathedral wang block from {best_name}",
        "lower_description": "cathedral floor terrain A",
        "upper_description": "cathedral floor terrain B",
        "transition_description": "direct source block (no synthetic blend)",
        "tile_size": {"width": TILE_SIZE, "height": TILE_SIZE},
        "tileset_data": {
            "tiles": tiles,
            "tile_size": {"width": TILE_SIZE, "height": TILE_SIZE},
            "total_tiles": 16,
            "terrain_types": ["lower", "upper"],
        },
        "metadata": {
            "terrain_prompts": {
                "lower": "dark worn cathedral floor",
                "upper": "light polished cathedral floor",
                "transition": "natural stone floor transition",
            }
        },
        "tileset_image": {
            "filename": OUT_IMG.name,
            "format": "PNG",
            "dimensions": {"width": ATLAS_SIZE, "height": ATLAS_SIZE},
        },
    }

    OUT_META.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(f"Generated: {OUT_IMG}")
    print(f"Generated: {OUT_META}")
    print(
        "Selected block:",
        best_name,
        "at",
        (best_global["bx"], best_global["by"]),
        "unique_wang_states=",
        best_global["unique_count"],
    )


if __name__ == "__main__":
    pack_dir = PACK_DIR_DEFAULT if PACK_DIR_DEFAULT.exists() else (ROOT / "assets" / "third_party" / "kokoro" / "cathedral")
    if not pack_dir.exists() and ZIP_DEFAULT.exists():
        raise RuntimeError(
            "Please extract cathedral.zip to godot/cathedral first. "
            "Current builder expects extracted files."
        )
    build(pack_dir)
