"""Author 'Grand Basilica' — an original map designed from scratch.

Layout is deliberate: north altar dais, central carpet processional, four pew
blocks forming combat lanes, side chapels with pedestals, candle clusters at
the carpet corners. Tile vocabulary matches the authored kokoro samples
(floor k24, carpet k21, accents k27/k28, wall cap k16, wall face k11).
"""
import os
import pickle
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compose_map import Composer, harvest_stamps

PACK = r"godot\assets\third_party\kokoro\cathedral\sample maps (RPG Maker MV-MZ)"

W, H = 44, 30

FLOOR = ("a2", 24)     # pale stone slab
CARPET = ("a2", 21)    # red/gold processional carpet
DAIS = ("a2", 27)      # ornate red tile
CHAPEL = ("a2", 28)    # diamond tile
WALL_CAP = ("a4f", 16) # gold ornate wall top
WALL_FACE = ("a4w", 11)# cream paneled wall face


def build():
    stamps = []
    for n in (1, 3, 4, 5, 7):
        stamps.extend(harvest_stamps(PACK, n))
    # Indices from the reviewed contact sheet.
    st_candles = stamps[2]    # 2x2 candle planter
    st_pew = stamps[3]        # 5x1 single pew
    st_altar = stamps[13]     # 9x5 curtained altar (top rows are wall decor)
    st_pews_l = stamps[14]    # 7x8 pew block
    st_pews_r = stamps[15]    # 9x8 pew block with statues
    st_pedestal_a = stamps[8] # 1x2 flower pedestal
    st_pedestal_b = stamps[9] # 1x2 flower pedestal variant
    st_bunting = stamps[10]   # 9x1 garland

    c = Composer(PACK, 1, W, H)

    # ── shell: floor everywhere, wall cap ring, north wall face ─────────────
    c.fill_rect(0, 0, 0, W - 1, H - 1, FLOOR)
    c.fill_rect(0, 0, 0, W - 1, 0, WALL_CAP)            # north cap
    c.fill_rect(0, 0, H - 1, W - 1, H - 1, WALL_CAP)    # south cap
    c.fill_rect(0, 0, 0, 0, H - 1, WALL_CAP)            # west cap
    c.fill_rect(0, W - 1, 0, W - 1, H - 1, WALL_CAP)    # east cap
    c.fill_rect(0, 1, 1, W - 2, 2, WALL_FACE)           # north wall face

    # ── side chapel alcoves (recessed by wall stubs) ─────────────────────────
    # West chapel: diamond floor, framed by wall stubs above and below.
    c.fill_rect(0, 1, 7, 6, 12, CHAPEL)
    c.fill_rect(0, 1, 18, 6, 23, CHAPEL)
    # East chapels mirror.
    c.fill_rect(0, W - 7, 7, W - 2, 12, CHAPEL)
    c.fill_rect(0, W - 7, 18, W - 2, 23, CHAPEL)
    # Wall stubs that separate the chapels from the nave (cap + face).
    for x1, x2 in ((1, 6), (W - 7, W - 2)):
        for ytop in (5, 16, 26):
            c.fill_rect(0, x1, ytop, x2, ytop, WALL_CAP)
            c.fill_rect(0, x1, ytop + 1, x2, ytop + 1, WALL_FACE)

    # ── altar dais (north center) + processional carpet ─────────────────────
    c.fill_rect(0, 15, 3, 28, 9, DAIS)
    c.fill_rect(0, 19, 3, 24, H - 3, CARPET)

    # ── furniture ────────────────────────────────────────────────────────────
    c.stamp(st_altar, 17, 1)        # altar against the north wall, on the dais
    c.stamp(st_bunting, 5, 2)       # garlands flanking the altar
    c.stamp(st_bunting, 30, 2)
    c.stamp(st_pews_l, 9, 12)       # four pew blocks framing the carpet lanes
    c.stamp(st_pews_l, 28, 12)
    c.stamp(st_pews_l, 9, 21)
    c.stamp(st_pews_l, 28, 21)
    # Statue pedestals flanking the dais steps.
    c.stamp(st_pedestal_a, 17, 9)
    c.stamp(st_pedestal_b, 26, 9)
    # Candle clusters at the dais corners.
    c.stamp(st_candles, 14, 8)
    c.stamp(st_candles, 28, 8)
    # Pedestals inside each chapel.
    for y0 in (8, 19):
        c.stamp(st_pedestal_a, 2, y0)
        c.stamp(st_pedestal_b, 5, y0 + 2)
        c.stamp(st_pedestal_b, W - 3, y0)
        c.stamp(st_pedestal_a, W - 6, y0 + 2)
    # Single pews as cover in the south open hall.
    c.stamp(st_pew, 12, H - 4)
    c.stamp(st_pew, 27, H - 4)

    return c


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else r"scratch\compose"
    name = sys.argv[2] if len(sys.argv) > 2 else "grand_basilica"
    scale = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    c = build()
    c.bake(out_dir, name, scale=scale)
