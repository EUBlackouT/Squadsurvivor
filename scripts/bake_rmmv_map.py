"""Bake RPG Maker MV/MZ authored maps into game-ready assets.

Renders all tile layers (with correct autotile quadrant composition, ported
from rpg_core.js) into a flat image, and derives collision rectangles +
walkability from the tileset passability flags. Output plugs into
MetadataMapWorld (source image + Collision_Static polygons).
"""
import json
import os
import sys

from PIL import Image

TILE = 48

# Ported verbatim from rpg_core.js Tilemap tables.
FLOOR_AUTOTILE_TABLE = [
    [[2,4],[1,4],[2,3],[1,3]],[[2,0],[1,4],[2,3],[1,3]],
    [[2,4],[3,0],[2,3],[1,3]],[[2,0],[3,0],[2,3],[1,3]],
    [[2,4],[1,4],[2,3],[3,1]],[[2,0],[1,4],[2,3],[3,1]],
    [[2,4],[3,0],[2,3],[3,1]],[[2,0],[3,0],[2,3],[3,1]],
    [[2,4],[1,4],[2,1],[1,3]],[[2,0],[1,4],[2,1],[1,3]],
    [[2,4],[3,0],[2,1],[1,3]],[[2,0],[3,0],[2,1],[1,3]],
    [[2,4],[1,4],[2,1],[3,1]],[[2,0],[1,4],[2,1],[3,1]],
    [[2,4],[3,0],[2,1],[3,1]],[[2,0],[3,0],[2,1],[3,1]],
    [[0,4],[1,4],[0,3],[1,3]],[[0,4],[3,0],[0,3],[1,3]],
    [[0,4],[1,4],[0,3],[3,1]],[[0,4],[3,0],[0,3],[3,1]],
    [[2,2],[1,2],[2,3],[1,3]],[[2,2],[1,2],[2,3],[3,1]],
    [[2,2],[1,2],[2,1],[1,3]],[[2,2],[1,2],[2,1],[3,1]],
    [[2,4],[3,4],[2,3],[3,3]],[[2,4],[3,4],[2,1],[3,3]],
    [[2,0],[3,4],[2,3],[3,3]],[[2,0],[3,4],[2,1],[3,3]],
    [[2,4],[1,4],[2,5],[1,5]],[[2,0],[1,4],[2,5],[1,5]],
    [[2,4],[3,0],[2,5],[1,5]],[[2,0],[3,0],[2,5],[1,5]],
    [[0,4],[3,4],[0,3],[3,3]],[[2,2],[1,2],[2,5],[1,5]],
    [[0,2],[1,2],[0,3],[1,3]],[[0,2],[1,2],[0,3],[3,1]],
    [[2,2],[3,2],[2,3],[3,3]],[[2,2],[3,2],[2,1],[3,3]],
    [[2,4],[3,4],[2,5],[3,5]],[[2,0],[3,4],[2,5],[3,5]],
    [[0,4],[1,4],[0,5],[1,5]],[[0,4],[3,0],[0,5],[1,5]],
    [[0,2],[3,2],[0,3],[3,3]],[[0,2],[1,2],[0,5],[1,5]],
    [[0,4],[3,4],[0,5],[3,5]],[[2,2],[3,2],[2,5],[3,5]],
    [[0,2],[3,2],[0,5],[3,5]],[[0,0],[1,0],[0,1],[1,1]],
]
WALL_AUTOTILE_TABLE = [
    [[2,2],[1,2],[2,1],[1,1]],[[0,2],[1,2],[0,1],[1,1]],
    [[2,0],[1,0],[2,1],[1,1]],[[0,0],[1,0],[0,1],[1,1]],
    [[2,2],[3,2],[2,1],[3,1]],[[0,2],[3,2],[0,1],[3,1]],
    [[2,0],[3,0],[2,1],[3,1]],[[0,0],[3,0],[0,1],[3,1]],
    [[2,2],[1,2],[2,3],[1,3]],[[0,2],[1,2],[0,3],[1,3]],
    [[2,0],[1,0],[2,3],[1,3]],[[0,0],[1,0],[0,3],[1,3]],
    [[2,2],[3,2],[2,3],[3,3]],[[0,2],[3,2],[0,3],[3,3]],
    [[2,0],[3,0],[2,3],[3,3]],[[0,0],[3,0],[0,3],[3,3]],
]
WATERFALL_AUTOTILE_TABLE = [
    [[2,0],[1,0],[2,1],[1,1]],[[0,0],[1,0],[0,1],[1,1]],
    [[2,0],[3,0],[2,1],[3,1]],[[0,0],[3,0],[0,1],[3,1]],
]


def is_a1(t): return 2048 <= t < 2816
def is_a2(t): return 2816 <= t < 4352
def is_a3(t): return 4352 <= t < 5888
def is_a4(t): return 5888 <= t < 8192
def is_a5(t): return 1536 <= t < 1792
def is_autotile(t): return t >= 2048
def at_kind(t): return (t - 2048) // 48
def at_shape(t): return (t - 2048) % 48


class Baker:
    def __init__(self, pack_dir, map_path):
        self.pack = pack_dir
        self.map = json.load(open(map_path, encoding="utf-8"))
        tilesets = json.load(open(os.path.join(pack_dir, "data", "Tilesets.json"), encoding="utf-8"))
        ts = tilesets[self.map["tilesetId"]]
        self.flags = ts["flags"]
        self.bitmaps = []
        for name in ts["tilesetNames"]:
            if not name:
                self.bitmaps.append(None)
                continue
            p = os.path.join(pack_dir, "img", "tilesets", name + ".png")
            self.bitmaps.append(Image.open(p).convert("RGBA") if os.path.exists(p) else None)
        self.w = self.map["width"]
        self.h = self.map["height"]
        self.data = self.map["data"]

    def tile_at(self, x, y, z):
        return self.data[(z * self.h + y) * self.w + x]

    def blt(self, dst, set_number, sx, sy, sw, sh, dx, dy):
        src = self.bitmaps[set_number]
        if src is None:
            return
        region = src.crop((sx, sy, sx + sw, sy + sh))
        dst.alpha_composite(region, (dx, dy))

    def draw_normal(self, dst, tile_id, dx, dy):
        if is_a5(tile_id):
            set_number = 4
            tid = tile_id - 1536
            sx = ((tid // 128) % 2 * 8 + tid % 8) * TILE
            sy = ((tid % 128) // 8) * TILE
        else:
            set_number = 5 + tile_id // 256
            sx = ((tile_id // 128) % 2 * 8 + tile_id % 8) * TILE
            sy = ((tile_id % 256) // 8 % 16) * TILE
        self.blt(dst, set_number, sx, sy, TILE, TILE, dx, dy)

    def is_table_tile(self, tile_id):
        return is_a2(tile_id) and bool(self.flags[tile_id] & 0x80)

    def draw_autotile(self, dst, tile_id, dx, dy):
        table = FLOOR_AUTOTILE_TABLE
        kind = at_kind(tile_id)
        shape = at_shape(tile_id)
        tx, ty = kind % 8, kind // 8
        bx = by = 0
        set_number = 0
        is_table = False
        if is_a1(tile_id):
            set_number = 0
            if kind == 0:
                bx, by = 0, 0
            elif kind == 1:
                bx, by = 0, 3
            elif kind == 2:
                bx, by = 6, 0
            elif kind == 3:
                bx, by = 6, 3
            else:
                bx = (tx // 4) * 8
                by = ty * 6 + (tx // 2) % 2 * 3
                if kind % 2 == 1:
                    bx += 6
                    table = WATERFALL_AUTOTILE_TABLE
        elif is_a2(tile_id):
            set_number = 1
            bx, by = tx * 2, (ty - 2) * 3
            is_table = self.is_table_tile(tile_id)
        elif is_a3(tile_id):
            set_number = 2
            bx, by = tx * 2, (ty - 6) * 2
            table = WALL_AUTOTILE_TABLE
        elif is_a4(tile_id):
            set_number = 3
            bx = tx * 2
            by = int((ty - 10) * 2.5 + (0.5 if ty % 2 == 1 else 0))
            if ty % 2 == 1:
                table = WALL_AUTOTILE_TABLE
        if shape >= len(table):
            shape = 0
        quads = table[shape]
        w1 = h1 = TILE // 2
        for i in range(4):
            qsx, qsy = quads[i]
            sx1 = (bx * 2 + qsx) * w1
            sy1 = (by * 2 + qsy) * h1
            dx1 = dx + (i % 2) * w1
            dy1 = dy + (i // 2) * h1
            if is_table and qsy in (1, 5):
                qsx2 = [0, 3, 2, 1][qsx] if qsy == 1 else qsx
                sx2 = (bx * 2 + qsx2) * w1
                sy2 = (by * 2 + 3) * h1
                self.blt(dst, set_number, sx2, sy2, w1, h1, dx1, dy1)
                self.blt(dst, set_number, sx1, sy1, w1, h1 // 2, dx1, dy1 + h1 // 2)
            else:
                self.blt(dst, set_number, sx1, sy1, w1, h1, dx1, dy1)

    def draw_tile(self, dst, tile_id, dx, dy):
        if tile_id <= 0 or tile_id >= 8192:
            return
        if is_autotile(tile_id):
            self.draw_autotile(dst, tile_id, dx, dy)
        else:
            self.draw_normal(dst, tile_id, dx, dy)

    def draw_shadow(self, dst, bits, dx, dy):
        if bits <= 0:
            return
        h2 = TILE // 2
        shade = Image.new("RGBA", (h2, h2), (0, 0, 0, 128))
        for i in range(4):
            if bits & (1 << i):
                dst.alpha_composite(shade, (dx + (i % 2) * h2, dy + (i // 2) * h2))

    def render(self):
        img = Image.new("RGBA", (self.w * TILE, self.h * TILE), (10, 10, 14, 255))
        for y in range(self.h):
            for x in range(self.w):
                dx, dy = x * TILE, y * TILE
                self.draw_tile(img, self.tile_at(x, y, 0), dx, dy)
                self.draw_tile(img, self.tile_at(x, y, 1), dx, dy)
                self.draw_shadow(img, self.tile_at(x, y, 4), dx, dy)
                self.draw_tile(img, self.tile_at(x, y, 2), dx, dy)
                self.draw_tile(img, self.tile_at(x, y, 3), dx, dy)
        return img

    def passable_grid(self):
        """Game_Map.checkPassage approximation: topmost non-star tile decides."""
        grid = []
        for y in range(self.h):
            row = []
            for x in range(self.w):
                passable = True
                for z in (3, 2, 1, 0):
                    t = self.tile_at(x, y, z)
                    if t <= 0:
                        continue
                    flag = self.flags[t] if t < len(self.flags) else 0
                    if flag & 0x10:  # star: above characters, ignore
                        continue
                    passable = (flag & 0x0F) != 0x0F
                    break
                row.append(passable)
            grid.append(row)
        return grid

    def collision_rects(self):
        """Merge blocked cells into maximal rectangles (greedy row strips)."""
        grid = self.passable_grid()
        blocked = [[not c for c in row] for row in grid]
        rects = []
        used = [[False] * self.w for _ in range(self.h)]
        for y in range(self.h):
            x = 0
            while x < self.w:
                if blocked[y][x] and not used[y][x]:
                    x2 = x
                    while x2 + 1 < self.w and blocked[y][x2 + 1] and not used[y][x2 + 1]:
                        x2 += 1
                    y2 = y
                    while y2 + 1 < self.h and all(
                            blocked[y2 + 1][i] and not used[y2 + 1][i] for i in range(x, x2 + 1)):
                        y2 += 1
                    for yy in range(y, y2 + 1):
                        for xx in range(x, x2 + 1):
                            used[yy][xx] = True
                    rects.append((x, y, x2 + 1, y2 + 1))
                    x = x2 + 1
                else:
                    x += 1
        return rects

    def best_spawn(self):
        """Open cell with the largest free square around it, biased to center."""
        grid = self.passable_grid()
        best, best_score = (self.w // 2, self.h // 2), -1
        for y in range(self.h):
            for x in range(self.w):
                if not grid[y][x]:
                    continue
                r = 0
                while True:
                    r += 1
                    ok = (y - r >= 0 and y + r < self.h and
                          x - r >= 0 and x + r < self.w)
                    if ok:
                        for yy in range(y - r, y + r + 1):
                            for xx in range(x - r, x + r + 1):
                                if not grid[yy][xx]:
                                    ok = False
                                    break
                            if not ok:
                                break
                    if not ok or r > 12:
                        break
                cx, cy = abs(x - self.w / 2) / self.w, abs(y - self.h / 2) / self.h
                score = r - (cx + cy) * 8.0
                if score > best_score:
                    best_score, best = score, (x, y)
        return best


def bake(pack_dir, map_num, out_dir, out_name, scale=2):
    map_path = os.path.join(pack_dir, "data", "Map%03d.json" % map_num)
    b = Baker(pack_dir, map_path)
    img = b.render()
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    os.makedirs(out_dir, exist_ok=True)
    img_path = os.path.join(out_dir, out_name + ".webp")
    img.convert("RGB").save(img_path, "WEBP", quality=92, method=6)

    px = TILE * scale
    rects = b.collision_rects()
    sx, sy = b.best_spawn()
    meta = {
        "normalized_coordinates": False,
        "image_size_px": [img.width, img.height],
        "source_image": out_name + ".webp",
        "camera_bounds": {
            "points": [[0, 0], [img.width, 0], [img.width, img.height], [0, img.height]],
            "centroid": [(sx + 0.5) * px, (sy + 0.5) * px],
        },
        "layers": {
            "Collision_Static": [
                {
                    "id": "block_%d" % i,
                    "kind": "solid",
                    "points": [[x1 * px, y1 * px], [x2 * px, y1 * px],
                               [x2 * px, y2 * px], [x1 * px, y2 * px]],
                }
                for i, (x1, y1, x2, y2) in enumerate(rects)
            ],
        },
    }
    meta_path = os.path.join(out_dir, out_name + "_metadata.json")
    json.dump(meta, open(meta_path, "w", encoding="utf-8"), indent=1)
    open_cells = sum(r.count(True) for r in b.passable_grid())
    print("%s: %dx%d tiles -> %dx%d px, %d collision rects, %d open cells, spawn=(%d,%d)" % (
        out_name, b.w, b.h, img.width, img.height, len(rects), open_cells, sx, sy))
    return img_path


if __name__ == "__main__":
    pack, num, out_dir, name = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
    scale = int(sys.argv[5]) if len(sys.argv) > 5 else 2
    bake(pack, num, out_dir, name, scale)
