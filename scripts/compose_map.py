"""Original map authoring on top of the RPG Maker tileset packs.

Key difference from baking sample maps: WE design the tile grid. Autotile
shapes (edges/corners/wall faces) are computed from the authored layout's
neighbors, and furniture is placed as coherent multi-tile stamps harvested
from the professionally authored sample maps.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bake_rmmv_map import Baker, TILE

A1_BASE = 2048
A2_BASE = 2816
A3_BASE = 4352
A4_BASE = 5888
A5_BASE = 1536


def floor_shape(u, d, l, r, ul, ur, dl, dr):
    """RPG Maker 47-shape floor autotile index from 8 same-kind neighbor flags."""
    if u and d and l and r:
        s = 0
        if not ul: s += 1
        if not ur: s += 2
        if not dr: s += 4
        if not dl: s += 8
        return s
    if not l and u and d and r:
        return 16 + (0 if ur else 1) + (0 if dr else 2)
    if not u and l and d and r:
        return 20 + (0 if dr else 1) + (0 if dl else 2)
    if not r and u and d and l:
        return 24 + (0 if dl else 1) + (0 if ul else 2)
    if not d and u and l and r:
        return 28 + (0 if ul else 1) + (0 if ur else 2)
    if not l and not r and u and d:
        return 32
    if not u and not d and l and r:
        return 33
    if not l and not u and d and r:
        return 34 + (0 if dr else 1)
    if not u and not r and d and l:
        return 36 + (0 if dl else 1)
    if not r and not d and u and l:
        return 38 + (0 if ul else 1)
    if not d and not l and u and r:
        return 40 + (0 if ur else 1)
    if not l and not u and not r and d:
        return 42
    if not u and not r and not d and l:
        return 43
    if not r and not d and not l and u:
        return 44
    if not d and not l and not u and r:
        return 45
    return 46


def wall_shape(u, d, l, r):
    """RPG Maker 16-shape wall autotile index from 4 edge neighbor flags."""
    s = 0
    if not l: s += 1
    if not u: s += 2
    if not r: s += 4
    if not d: s += 8
    return s


class Composer:
    """Authors an original map: 4 tile layers + autotile finalization."""

    def __init__(self, pack_dir, tileset_id, w, h):
        self.pack = pack_dir
        self.w = w
        self.h = h
        self.tileset_id = tileset_id
        # Working grids hold (kind_marker) for autotiles and raw ids for the rest.
        # autotile cells: ("a2", kind) / ("a4f", kind) / ("a4w", kind) / ("a1", kind)
        # raw cells: int tile id (B/C/D/E/A5). None = empty.
        self.grid = [[[None] * w for _ in range(h)] for _ in range(4)]

    # ── authoring ops ────────────────────────────────────────────────────────
    def fill_rect(self, z, x1, y1, x2, y2, cell):
        for y in range(max(0, y1), min(self.h, y2 + 1)):
            for x in range(max(0, x1), min(self.w, x2 + 1)):
                self.grid[z][y][x] = cell

    def set_cell(self, z, x, y, cell):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.grid[z][y][x] = cell

    def stamp(self, st, x0, y0):
        """Place a harvested stamp (dict with w,h,layers) at tile (x0, y0)."""
        for z in range(4):
            for dy in range(st["h"]):
                for dx in range(st["w"]):
                    t = st["layers"][z][dy][dx]
                    if t:
                        self.set_cell(z, x0 + dx, y0 + dy, t)

    # ── finalization: markers -> real tile ids with computed shapes ─────────
    def _same(self, z, x, y, cell):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return True  # out-of-bounds counts as same so borders stay clean
        other = self.grid[z][y][x]
        return other == cell

    def finalize(self):
        data = [[[0] * self.w for _ in range(self.h)] for _ in range(6)]
        for z in range(4):
            for y in range(self.h):
                for x in range(self.w):
                    cell = self.grid[z][y][x]
                    if cell is None:
                        continue
                    if isinstance(cell, int):
                        data[z][y][x] = cell
                        continue
                    tag, kind = cell
                    nb = lambda dx, dy: self._same(z, x + dx, y + dy, cell)
                    if tag in ("a2", "a1"):
                        shape = floor_shape(
                            nb(0, -1), nb(0, 1), nb(-1, 0), nb(1, 0),
                            nb(-1, -1), nb(1, -1), nb(-1, 1), nb(1, 1))
                        base = A2_BASE if tag == "a2" else A1_BASE
                        data[z][y][x] = base + kind * 48 + shape
                    elif tag == "a4f":  # A4 wall-top (floor-type autotile)
                        shape = floor_shape(
                            nb(0, -1), nb(0, 1), nb(-1, 0), nb(1, 0),
                            nb(-1, -1), nb(1, -1), nb(-1, 1), nb(1, 1))
                        data[z][y][x] = A4_BASE + kind * 48 + shape
                    elif tag == "a4w":  # A4 wall face (wall-type autotile)
                        shape = wall_shape(nb(0, -1), nb(0, 1), nb(-1, 0), nb(1, 0))
                        data[z][y][x] = A4_BASE + kind * 48 + shape
                    elif tag == "a3":
                        shape = wall_shape(nb(0, -1), nb(0, 1), nb(-1, 0), nb(1, 0))
                        data[z][y][x] = A3_BASE + kind * 48 + shape
        flat = []
        for z in range(6):
            for y in range(self.h):
                flat.extend(data[z][y])
        return {
            "width": self.w, "height": self.h, "tilesetId": self.tileset_id,
            "data": flat,
        }

    def bake(self, out_dir, out_name, scale=3):
        from bake_rmmv_map import bake as bake_fn
        map_json = self.finalize()
        tmp = os.path.join(out_dir, "_compose_tmp")
        os.makedirs(os.path.join(tmp, "data"), exist_ok=True)
        json.dump(map_json, open(os.path.join(tmp, "data", "Map001.json"), "w"))
        # Borrow tileset config + images from the source pack.
        ts_src = os.path.join(self.pack, "data", "Tilesets.json")
        json.dump(json.load(open(ts_src, encoding="utf-8")),
                  open(os.path.join(tmp, "data", "Tilesets.json"), "w"))
        if not os.path.exists(os.path.join(tmp, "img")):
            os.symlink(os.path.join(os.path.abspath(self.pack), "img"),
                       os.path.join(tmp, "img"), target_is_directory=True) \
                if hasattr(os, "symlink") and os.name != "nt" else None
        if os.name == "nt" and not os.path.exists(os.path.join(tmp, "img")):
            import shutil
            os.makedirs(os.path.join(tmp, "img", "tilesets"), exist_ok=True)
            for f in os.listdir(os.path.join(self.pack, "img", "tilesets")):
                src = os.path.join(self.pack, "img", "tilesets", f)
                dst = os.path.join(tmp, "img", "tilesets", f)
                if not os.path.exists(dst):
                    shutil.copy2(src, dst)
        return bake_fn(tmp, 1, out_dir, out_name, scale)


# ── stamp harvesting from authored sample maps ──────────────────────────────

def harvest_stamps(pack_dir, map_num, min_cells=2, max_cells=400):
    """Extract connected clusters of non-autotile content (props/furniture)."""
    map_path = os.path.join(pack_dir, "data", "Map%03d.json" % map_num)
    b = Baker(pack_dir, map_path)

    def is_prop(t):
        return 0 < t < A5_BASE  # B/C/D/E sheets only

    marked = [[any(is_prop(b.tile_at(x, y, z)) for z in range(4))
               for x in range(b.w)] for y in range(b.h)]
    seen = [[False] * b.w for _ in range(b.h)]
    stamps = []
    for y in range(b.h):
        for x in range(b.w):
            if not marked[y][x] or seen[y][x]:
                continue
            cells = []
            queue = [(x, y)]
            seen[y][x] = True
            while queue:
                cx, cy = queue.pop()
                cells.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1),
                               (1, 1), (-1, -1), (1, -1), (-1, 1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < b.w and 0 <= ny < b.h \
                            and marked[ny][nx] and not seen[ny][nx]:
                        seen[ny][nx] = True
                        queue.append((nx, ny))
            if not (min_cells <= len(cells) <= max_cells):
                continue
            xs = [c[0] for c in cells]
            ys = [c[1] for c in cells]
            x1, x2, y1, y2 = min(xs), max(xs), min(ys), max(ys)
            w, h = x2 - x1 + 1, y2 - y1 + 1
            layers = [[[0] * w for _ in range(h)] for _ in range(4)]
            for z in range(4):
                for yy in range(y1, y2 + 1):
                    for xx in range(x1, x2 + 1):
                        t = b.tile_at(xx, yy, z)
                        if is_prop(t):
                            layers[z][yy - y1][xx - x1] = t
            stamps.append({
                "src": "map%03d_(%d,%d)" % (map_num, x1, y1),
                "w": w, "h": h, "layers": layers,
            })
    return stamps


def render_stamp(pack_dir, st, scale=1):
    """Render a stamp to a PIL image for contact sheets / reuse preview."""
    c = Composer(pack_dir, 1, st["w"], st["h"])
    c.stamp(st, 0, 0)
    map_json = c.finalize()

    class _B(Baker):
        def __init__(self, pack, mj):
            ts = json.load(open(os.path.join(pack, "data", "Tilesets.json"), encoding="utf-8"))
            t = ts[mj["tilesetId"]]
            self.flags = t["flags"]
            self.bitmaps = []
            for name in t["tilesetNames"]:
                p = os.path.join(pack, "img", "tilesets", name + ".png") if name else ""
                self.bitmaps.append(Image.open(p).convert("RGBA") if p and os.path.exists(p) else None)
            self.w, self.h, self.data = mj["width"], mj["height"], mj["data"]
    return _B(pack_dir, map_json).render()


def make_contact_sheets(pack_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    ts = json.load(open(os.path.join(pack_dir, "data", "Tilesets.json"), encoding="utf-8"))[1]
    names = ts["tilesetNames"]
    flags = ts["flags"]

    def annotate(img, text):
        d = ImageDraw.Draw(img)
        d.rectangle((0, 0, len(text) * 7 + 4, 14), fill=(0, 0, 0, 200))
        d.text((2, 2), text, fill=(255, 255, 80, 255))
        return img

    # A2 floor kinds: render shape 47 ("complete" preview tile, top-left 2x2).
    a2_path = os.path.join(pack_dir, "img", "tilesets", names[1] + ".png")
    if os.path.exists(a2_path):
        src = Image.open(a2_path).convert("RGBA")
        cols, rows = 8, 4
        sheet = Image.new("RGBA", (cols * 96, rows * 96), (20, 20, 26, 255))
        for k in range(32):
            tx, ty = k % 8, k // 8
            tile = src.crop((tx * 96, ty * 144, tx * 96 + 96, ty * 144 + 96))
            base_tid = A2_BASE + k * 48
            f = flags[base_tid] if base_tid < len(flags) else 0
            blocked = (f & 0x0F) == 0x0F
            tile = annotate(tile, "k%d%s" % (k, " X" if blocked else ""))
            sheet.paste(tile, ((k % 8) * 96, (k // 8) * 96))
        sheet.save(os.path.join(out_dir, "a2_kinds.png"))

    # A4 wall kinds: wall-top rows (floor-type) + wall-face rows.
    a4_path = os.path.join(pack_dir, "img", "tilesets", names[3] + ".png")
    if os.path.exists(a4_path):
        src = Image.open(a4_path).convert("RGBA")
        sheet = Image.new("RGBA", (8 * 96, 6 * 96), (20, 20, 26, 255))
        for k in range(48):
            tx, ty = k % 8, k // 8
            if ty % 2 == 0:
                py = int((ty) * 2.5) * 48
                tile = src.crop((tx * 96, py, tx * 96 + 96, py + 96))
            else:
                py = int((ty - 1) * 2.5 + 3) * 48
                tile = src.crop((tx * 96, py, tx * 96 + 96, py + 96))
            base_tid = A4_BASE + k * 48
            f = flags[base_tid] if base_tid < len(flags) else 0
            blocked = (f & 0x0F) == 0x0F
            kind_tag = "k%d%s%s" % (k, "w" if ty % 2 == 1 else "f", " X" if blocked else "")
            tile = annotate(tile, kind_tag)
            sheet.paste(tile, (tx * 96, (k // 8) * 96))
        sheet.save(os.path.join(out_dir, "a4_kinds.png"))

    # A5 tiles.
    a5_path = os.path.join(pack_dir, "img", "tilesets", names[4] + ".png")
    if os.path.exists(a5_path):
        src = Image.open(a5_path).convert("RGBA")
        sheet = src.copy()
        d = ImageDraw.Draw(sheet)
        for i in range(128):
            tx, ty = i % 8, i // 8
            tid = A5_BASE + i
            f = flags[tid] if tid < len(flags) else 0
            blocked = (f & 0x0F) == 0x0F
            d.text((tx * 48 + 2, ty * 48 + 2), "%d%s" % (i, "X" if blocked else ""),
                   fill=(255, 255, 80, 255))
        sheet.save(os.path.join(out_dir, "a5_tiles.png"))


if __name__ == "__main__":
    pack = sys.argv[1]
    out = sys.argv[2]
    make_contact_sheets(pack, out)
    print("contact sheets written to", out)
