#!/usr/bin/env python3
"""
Build a usable graveyard Wang tileset (4x4 / 16 tiles) from the user ZIP pack.

Outputs:
- godot/tilesets/graveyard_image.png
- godot/tilesets/graveyard_metadata.json

The generated metadata matches the existing TilesetLoader expectations:
- tile_size
- tileset_data.tiles[] with corners + bounding_box
- metadata.terrain_prompts
"""

from __future__ import annotations

import json
import math
import zipfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]  # godot/
ZIP_DEFAULT = ROOT / "godot_tileset_ready_renamed_and_sliced.zip"
OUT_IMG = ROOT / "tilesets" / "graveyard_image.png"
OUT_META = ROOT / "tilesets" / "graveyard_metadata.json"

TILE_SIZE = 32
ATLAS_GRID = 4
ATLAS_SIZE = TILE_SIZE * ATLAS_GRID


def _load_image_from_zip(zf: zipfile.ZipFile, name: str) -> Image.Image:
    with zf.open(name, "r") as f:
        return Image.open(f).convert("RGBA")


def _make_base_texture(zf: zipfile.ZipFile, names: list[str]) -> Image.Image:
    """Average multiple texture candidates into one seamless-looking source."""
    images = [_load_image_from_zip(zf, n).resize((1024, 1024), Image.Resampling.LANCZOS) for n in names]
    out = Image.new("RGBA", (1024, 1024), (0, 0, 0, 255))
    out_px = out.load()
    all_px = [im.load() for im in images]
    n = len(images)
    for y in range(1024):
        for x in range(1024):
            r = g = b = a = 0
            for px in all_px:
                pr, pg, pb, pa = px[x, y]
                r += pr
                g += pg
                b += pb
                a += pa
            out_px[x, y] = (r // n, g // n, b // n, a // n)
    return out


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge0 == edge1:
        return 0.0
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _make_wang_tile(
    lower_set: list[Image.Image],
    upper_set: list[Image.Image],
    detail_set: list[Image.Image],
    overlay: Image.Image | None,
    wang_idx: int,
) -> Image.Image:
    """
    Build one 32x32 tile by blending lower/upper base textures according
    to corner states encoded in Wang index: NW*8 + NE*4 + SW*2 + SE.
    """
    nw = (wang_idx >> 3) & 1
    ne = (wang_idx >> 2) & 1
    sw = (wang_idx >> 1) & 1
    se = wang_idx & 1

    out = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), (0, 0, 0, 255))
    out_px = out.load()
    lower = lower_set[wang_idx % len(lower_set)]
    upper = upper_set[(wang_idx * 3) % len(upper_set)]
    detail = detail_set[(wang_idx * 5) % len(detail_set)]
    lpx = lower.load()
    upx = upper.load()
    dpx = detail.load()
    w, h = lower.size

    # Small deterministic offsets per tile reduce visible repetition.
    off_x = (wang_idx * 73) % w
    off_y = (wang_idx * 97) % h

    for py in range(TILE_SIZE):
        fy = py / max(1, (TILE_SIZE - 1))
        for px in range(TILE_SIZE):
            fx = px / max(1, (TILE_SIZE - 1))

            top = nw * (1.0 - fx) + ne * fx
            bot = sw * (1.0 - fx) + se * fx
            mix = top * (1.0 - fy) + bot * fy
            mix = _smoothstep(0.35, 0.65, mix)

            sx = (off_x + px * 8) % w
            sy = (off_y + py * 8) % h
            lr, lg, lb, la = lpx[sx, sy]
            ur, ug, ub, ua = upx[sx, sy]
            dr, dg, db, _da = dpx[sx, sy]

            r = int(lr * (1.0 - mix) + ur * mix)
            g = int(lg * (1.0 - mix) + ug * mix)
            b = int(lb * (1.0 - mix) + ub * mix)
            a = int(la * (1.0 - mix) + ua * mix)

            # Add subtle third-texture variation so tiles don't read as "2 textures only".
            detail_mix = 0.08 + (0.05 * (((wang_idx + px + py) % 7) / 6.0))
            r = int(r * (1.0 - detail_mix) + dr * detail_mix)
            g = int(g * (1.0 - detail_mix) + dg * detail_mix)
            b = int(b * (1.0 - detail_mix) + db * detail_mix)

            # Subtle value variation for a less flat look.
            n = ((math.sin((px + wang_idx) * 0.9) + math.cos((py + wang_idx) * 0.7)) * 0.5) * 4.0
            r = max(0, min(255, int(r + n)))
            g = max(0, min(255, int(g + n)))
            b = max(0, min(255, int(b + n)))
            out_px[px, py] = (r, g, b, a)

    if overlay is not None:
        ov = overlay.resize((TILE_SIZE, TILE_SIZE), Image.Resampling.LANCZOS)
        ov_px = ov.load()
        for py in range(TILE_SIZE):
            for px in range(TILE_SIZE):
                br, bg, bb, ba = out_px[px, py]
                or_, og, ob, oa = ov_px[px, py]
                alpha = (oa / 255.0) * 0.28
                out_px[px, py] = (
                    int(br * (1.0 - alpha) + or_ * alpha),
                    int(bg * (1.0 - alpha) + og * alpha),
                    int(bb * (1.0 - alpha) + ob * alpha),
                    ba,
                )
    return out


def _corners_dict(wang_idx: int) -> dict[str, str]:
    return {
        "NW": "upper" if ((wang_idx >> 3) & 1) else "lower",
        "NE": "upper" if ((wang_idx >> 2) & 1) else "lower",
        "SW": "upper" if ((wang_idx >> 1) & 1) else "lower",
        "SE": "upper" if (wang_idx & 1) else "lower",
    }


def build(zip_path: Path) -> None:
    if not zip_path.exists():
        raise FileNotFoundError(f"ZIP not found: {zip_path}")

    with zipfile.ZipFile(zip_path, "r") as zf:
        lower_set = [
            _make_base_texture(zf, ["dirt_base_01.png", "dead_grass_base_01.png"]),
            _make_base_texture(zf, ["dirt_base_02.png", "gravel_path_base_01.png"]),
            _make_base_texture(zf, ["rocky_dirt_base_01.png", "dirt_base_01.png"]),
        ]
        upper_set = [
            _make_base_texture(zf, ["cobble_base_01.png", "cobble_cracked_01.png"]),
            _make_base_texture(zf, ["cobble_base_02.png", "cobble_cracked_01.png"]),
        ]
        detail_set = [
            _make_base_texture(zf, ["gravel_path_base_01.png", "rocky_dirt_base_01.png"]),
            _make_base_texture(zf, ["dead_grass_base_01.png", "dirt_base_02.png"]),
        ]
        overlay_names = [
            "cobble_to_dirt_edge_south.png",
            "broken_cobble_to_dirt_edge_south.png",
            "cobble_to_grass_edge_north.png",
            "cobble_to_grass_edge_west.png",
            "cobble_to_grass_edge_east.png",
        ]
        overlays: list[Image.Image] = []
        for n in overlay_names:
            try:
                overlays.append(_load_image_from_zip(zf, n))
            except KeyError:
                continue

    atlas = Image.new("RGBA", (ATLAS_SIZE, ATLAS_SIZE), (0, 0, 0, 0))

    tiles = []
    for wang_idx in range(16):
        tx = (wang_idx % 4) * TILE_SIZE
        ty = (wang_idx // 4) * TILE_SIZE
        ov = overlays[wang_idx % len(overlays)] if overlays else None
        tile = _make_wang_tile(lower_set, upper_set, detail_set, ov, wang_idx)
        atlas.paste(tile, (tx, ty))

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
        "id": "graveyard_custom_from_zip",
        "name": "graveyard soil -> cobble (custom zipped assets)",
        "lower_description": "graveyard dirt, dead grass, and soil",
        "upper_description": "weathered cobblestone path",
        "transition_description": "organic blend between dirt and cobble",
        "tile_size": {"width": TILE_SIZE, "height": TILE_SIZE},
        "tileset_data": {
            "tiles": tiles,
            "tile_size": {"width": TILE_SIZE, "height": TILE_SIZE},
            "total_tiles": 16,
            "terrain_types": ["lower", "upper"],
        },
        "metadata": {
            "terrain_prompts": {
                "lower": "graveyard dirt and dead grass",
                "upper": "aged cracked cobblestone",
                "transition": "soft dirt-to-cobble blend",
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


if __name__ == "__main__":
    build(ZIP_DEFAULT)
