"""Original authored maps for every playable zone, built with compose_map.

Each builder designs a deliberate layout (focal point, combat lanes, cover,
readable silhouettes) instead of baking a sample map. Stamps are harvested
from the professionally authored pack samples so furniture stays coherent.

Usage:
    python scripts/author_originals.py <out_dir> <map_name|all> [scale]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compose_map import Composer, harvest_stamps

CATHEDRAL = r"godot\assets\third_party\kokoro\cathedral\sample maps (RPG Maker MV-MZ)"
GOTHIC = r"godot\gothic\sample maps (RPG Maker MV-MZ)"
ELDUN = r"godot\eldun_fwew\sample maps (RPG Maker MV-MZ)"

_stamp_cache = {}


def stamps_for(pack, nums):
    key = (pack, tuple(nums))
    if key not in _stamp_cache:
        out = []
        for n in nums:
            out.extend(harvest_stamps(pack, n))
        _stamp_cache[key] = out
    return _stamp_cache[key]


# ── shared structure helpers ─────────────────────────────────────────────────

def shell(c, floor, cap, face, face_h=2):
    """Interior shell: floor fill, perimeter cap ring, north wall face."""
    c.fill_rect(0, 0, 0, c.w - 1, c.h - 1, floor)
    c.fill_rect(0, 0, 0, c.w - 1, 0, cap)
    c.fill_rect(0, 0, c.h - 1, c.w - 1, c.h - 1, cap)
    c.fill_rect(0, 0, 0, 0, c.h - 1, cap)
    c.fill_rect(0, c.w - 1, 0, c.w - 1, c.h - 1, cap)
    c.fill_rect(0, 1, 1, c.w - 2, face_h, face)


def wall_block(c, x1, y1, x2, y2, cap, face, face_h=2):
    """Freestanding interior wall: cap on top, south-facing face below."""
    c.fill_rect(0, x1, y1, x2, max(y1, y2 - face_h), cap)
    if y2 - y1 + 1 > face_h:
        c.fill_rect(0, x1, y2 - face_h + 1, x2, y2, face)
    else:
        c.fill_rect(0, x1, y1, x2, y2, cap)


# ── 1. Church (I) — cathedral pack: humble parish chapel ─────────────────────

def build_church():
    S = stamps_for(CATHEDRAL, (1, 3, 4, 5, 7))
    st_candles, st_pew = S[2], S[3]
    st_altar = S[13]
    st_ped_a, st_ped_b = S[8], S[9]
    st_bunting = S[10]

    W, H = 30, 20
    FLOOR = ("a2", 2)       # warm wood planks
    CARPET = ("a2", 21)     # red/gold runner
    DAIS = ("a2", 3)        # octagon stone
    CAP = ("a4f", 0)        # dark wood frame cap
    FACE = ("a4w", 9)       # cream plaster face

    c = Composer(CATHEDRAL, 1, W, H)
    shell(c, FLOOR, CAP, FACE)

    c.fill_rect(0, 10, 3, 19, 7, DAIS)            # altar dais
    c.fill_rect(0, 13, 3, 16, H - 2, CARPET)      # processional runner

    c.stamp(st_altar, 10, 1)                      # altar against north wall
    c.stamp(st_bunting, 1, 2)
    c.stamp(st_bunting, 20, 2)
    # Two columns of simple pews framing the runner.
    for y in (9, 11, 13, 15):
        c.stamp(st_pew, 4, y)
        c.stamp(st_pew, 21, y)
    c.stamp(st_candles, 10, 6)
    c.stamp(st_candles, 18, 6)
    # Pedestals along the side walls.
    for y in (8, 14):
        c.stamp(st_ped_a, 1, y)
        c.stamp(st_ped_b, W - 2, y)
    return c


# ── 2. Arcane Library (II) — gothic pack: manor great hall ──────────────────

def build_library():
    S = stamps_for(GOTHIC, (1, 2, 3, 4, 7, 8))
    st_bottles = S[2]
    st_table = S[15]      # purple-draped altar table
    st_piano = S[18]
    st_organ = S[20]
    st_door_a, st_door_b = S[21], S[22]
    st_fire_a, st_fire_b = S[23], S[24]

    W, H = 38, 26
    FLOOR = ("a2", 16)     # wood planks
    RUG = ("a2", 25)       # ornate purple rug
    RUG2 = ("a2", 26)      # purple rug variant
    ACCENT = ("a2", 17)    # octagon stone
    CAP = ("a4f", 0)
    FACE = ("a4w", 25)     # ornate paneled face

    c = Composer(GOTHIC, 1, W, H)
    shell(c, FLOOR, CAP, FACE)

    # Stone landing strips at north (under fireplaces) and south doors.
    c.fill_rect(0, 1, 3, W - 2, 4, ACCENT)
    c.fill_rect(0, 14, H - 3, 23, H - 2, ACCENT)

    # Central reading rug with a grand table.
    c.fill_rect(0, 11, 9, 26, 18, RUG)
    c.fill_rect(0, 13, 11, 24, 16, RUG2)
    c.stamp(st_table, 16, 12)

    # North wall: twin fireplaces flanking the organ loft.
    c.stamp(st_fire_a, 3, 1)
    c.stamp(st_fire_b, 29, 1)
    c.stamp(st_organ, 16, 1)

    # Study alcoves: interior wall stubs make two reading nooks mid-room.
    wall_block(c, 7, 8, 9, 11, CAP, FACE)
    wall_block(c, 28, 8, 30, 11, CAP, FACE)
    wall_block(c, 7, 16, 9, 19, CAP, FACE)
    wall_block(c, 28, 16, 30, 19, CAP, FACE)

    # Piano corner + bottle shelves on the side walls.
    c.stamp(st_piano, W - 6, H - 7)
    c.stamp(st_bottles, 2, 6)
    c.stamp(st_bottles, 32, 6)

    # South double doors.
    c.stamp(st_door_a, 15, H - 3)
    c.stamp(st_door_b, 20, H - 3)
    return c


# ── 3. Mansion Grounds (II) — gothic pack: formal garden exterior ───────────

def build_mansion_grounds():
    S = stamps_for(GOTHIC, (1, 2, 3, 4, 7, 8))
    st_facade = S[6]       # 27x8 mansion frontage
    st_tower_a, st_tower_b = S[3], S[4]
    st_tree, st_tree_fl = S[9], S[12]
    st_lamp_a, st_lamp_b = S[13], S[14]
    st_spire_a, st_spire_b = S[7], S[8]

    W, H = 40, 28
    GRASS = ("a2", 0)
    PATH = ("a2", 2)       # cobblestone
    PLAZA = ("a2", 3)      # pale stone
    HEDGE_CAP = ("a4f", 37)
    HEDGE_FACE = ("a4w", 45)

    c = Composer(GOTHIC, 1, W, H)
    c.fill_rect(0, 0, 0, W - 1, H - 1, GRASS)

    # Hedge perimeter (cap ring + south-facing face under the north run).
    c.fill_rect(0, 0, 0, W - 1, 0, HEDGE_CAP)
    c.fill_rect(0, 0, H - 1, W - 1, H - 1, HEDGE_CAP)
    c.fill_rect(0, 0, 0, 0, H - 1, HEDGE_CAP)
    c.fill_rect(0, W - 1, 0, W - 1, H - 1, HEDGE_CAP)
    c.fill_rect(0, 1, 1, W - 2, 1, HEDGE_FACE)

    # Stone building band so the frontage props sit on a real mansion body.
    wall_block(c, 6, 1, 32, 7, ("a4f", 34), ("a4w", 13), face_h=2)
    # Mansion frontage spans the north edge; towers anchor the corners.
    c.stamp(st_facade, 6, 1)
    c.stamp(st_tower_a, 1, 1)
    c.stamp(st_tower_b, W - 6, 1)

    # Cross paths meeting at a central plaza.
    c.fill_rect(0, 17, 9, 22, H - 2, PATH)
    c.fill_rect(0, 1, 15, W - 2, 18, PATH)
    c.fill_rect(0, 13, 11, 26, 21, PLAZA)

    # Hedge maze blocks in the four quadrants (cover + lanes).
    for x1, y1 in ((5, 11), (30, 11), (5, 22), (30, 22)):
        wall_block(c, x1, y1, x1 + 4, y1 + 2, HEDGE_CAP, HEDGE_FACE, face_h=1)

    # Trees soften the corners; lamps light the plaza; spires mark the gate.
    c.stamp(st_tree, 1, 9)
    c.stamp(st_tree_fl, W - 5, 9)
    c.stamp(st_tree_fl, 1, H - 6)
    c.stamp(st_tree, W - 5, H - 6)
    c.stamp(st_lamp_a, 12, 12)
    c.stamp(st_lamp_b, 26, 12)
    c.stamp(st_spire_a, 15, 22)
    c.stamp(st_spire_b, 24, 22)
    return c


# ── 4. Iron Foundry (III) — eldun ts1: scorched forge halls ─────────────────

def build_foundry():
    S = stamps_for(ELDUN, (2, 3, 13, 14))
    st_face = S[12]        # 7x7 demon face
    st_gate_a, st_gate_b = S[6], S[7]
    st_statue_a, st_statue_b = S[13], S[16]
    st_chal = S[8]
    st_sigil = S[3]        # 4x4 red mandala
    st_inlay = S[26]       # 2x2 white inlay tile

    W, H = 40, 28
    FLOOR = ("a2", 16)     # concrete
    SCORCH = ("a2", 2)     # black scorched ground
    BRICK = ("a2", 8)      # red brick pad
    FIRE = ("a2", 12)      # fire scatter overlay (layer 1)
    CAP = ("a4f", 20)      # black cross cap
    FACE = ("a4w", 25)     # fire panel face

    c = Composer(ELDUN, 1, W, H)
    shell(c, FLOOR, CAP, FACE)

    # Molten channels run east-west; brick service pads beside them.
    for y1 in (8, 19):
        c.fill_rect(0, 1, y1, W - 2, y1 + 1, SCORCH)
        for x in range(3, W - 3, 5):
            c.set_cell(1, x, y1, FIRE)
            c.set_cell(1, x + 2, y1 + 1, FIRE)
    c.fill_rect(0, 4, 11, 12, 16, BRICK)
    c.fill_rect(0, W - 13, 11, W - 5, 16, BRICK)

    # Demon face shrine dominates the north wall, gates at its flanks.
    c.stamp(st_face, 16, 1)
    c.stamp(st_gate_a, 9, 2)
    c.stamp(st_gate_b, 28, 2)

    # Interior ribs split the floor into three lanes with wide gaps.
    BRICK_FACE = ("a4w", 9)
    wall_block(c, 6, 5, 15, 7, CAP, BRICK_FACE)
    wall_block(c, 24, 5, 33, 7, CAP, BRICK_FACE)
    wall_block(c, 6, 22, 15, 24, CAP, BRICK_FACE)
    wall_block(c, 24, 22, 33, 24, CAP, BRICK_FACE)

    # Central sigil arena with statue guardians.
    c.fill_rect(0, 16, 12, 23, 15, BRICK)
    c.stamp(st_sigil, 18, 12)
    c.stamp(st_statue_a, 12, 12)
    c.stamp(st_statue_b, 25, 12)

    # Chalice torches + inlay accents down the side walls.
    for y in (6, 12, 18):
        c.stamp(st_chal, 1, y)
        c.stamp(st_chal, W - 2, y)
    for x, y in ((4, 4), (34, 4), (4, 25), (34, 25)):
        c.stamp(st_inlay, x, y)
    return c


# ── 5. Infernal Reliquary (III) — eldun ts1: void platform sanctum ──────────

def build_reliquary():
    S = stamps_for(ELDUN, (2, 3, 13, 14))
    st_crown_a, st_crown_b = S[0], S[1]
    st_disc = S[2]
    st_mandala = S[20]
    st_gate_a, st_gate_b = S[14], S[15]
    st_chal = S[9]
    st_sigil_sm = S[4]
    st_flower = S[42]

    W, H = 38, 26
    VOID = ("a2", 24)      # black ash
    TILE = ("a2", 26)      # ornate gold-red tile
    TILE2 = ("a2", 27)     # variant
    SAND = ("a2", 0)
    CAP = ("a4f", 20)
    FACE = ("a4w", 24)     # red gem-pillar face

    c = Composer(ELDUN, 1, W, H)
    shell(c, VOID, CAP, FACE)

    # Sand walk ring keeps the outer lane readable against the void.
    c.fill_rect(0, 3, 4, W - 4, 5, SAND)
    c.fill_rect(0, 3, H - 5, W - 4, H - 4, SAND)
    c.fill_rect(0, 3, 4, 4, H - 4, SAND)
    c.fill_rect(0, W - 5, 4, W - 4, H - 4, SAND)

    # Grand central platform with inner sanctum tile.
    c.fill_rect(0, 10, 7, 27, 19, TILE)
    c.fill_rect(0, 13, 9, 24, 17, TILE2)
    c.stamp(st_mandala, 17, 11)

    # Tile causeways bridge the void to the outer ring.
    c.fill_rect(0, 17, 4, 20, 7, TILE)
    c.fill_rect(0, 17, 19, 20, H - 4, TILE)
    c.fill_rect(0, 4, 12, 10, 14, TILE)
    c.fill_rect(0, 27, 12, W - 5, 14, TILE)

    # Relics: demon crowns NW/NE, silver disc south, gates north.
    c.stamp(st_crown_a, 4, 5)
    c.stamp(st_crown_b, W - 9, 5)
    c.stamp(st_disc, 16, H - 7)
    c.stamp(st_gate_a, 11, 2)
    c.stamp(st_gate_b, 24, 2)

    # Chalices at the platform corners, sigils scattered on the void.
    for x, y in ((10, 7), (26, 7), (10, 18), (26, 18)):
        c.stamp(st_chal, x, y)
    c.stamp(st_sigil_sm, 6, 9)
    c.stamp(st_sigil_sm, 30, 9)
    c.stamp(st_flower, 6, 16)
    c.stamp(st_flower, 30, 16)
    return c


# ── 6. Cathedral (IV) — cathedral pack: grand transept ──────────────────────

def build_cathedral():
    S = stamps_for(CATHEDRAL, (1, 3, 4, 5, 7))
    st_candles, st_pew = S[2], S[3]
    st_altar = S[13]
    st_pews = S[14]
    st_ped_a, st_ped_b = S[8], S[9]
    st_bunting = S[10]

    W, H = 46, 32
    FLOOR = ("a2", 12)     # gold lattice marble
    CARPET = ("a2", 21)
    DAIS = ("a2", 27)
    CHAPEL = ("a2", 28)
    WOOD = ("a2", 29)      # dark parquet
    CAP = ("a4f", 16)      # gold ornate cap
    FACE = ("a4w", 10)     # marble arch face

    c = Composer(CATHEDRAL, 1, W, H)
    shell(c, FLOOR, CAP, FACE)

    # Cross/transept: wall blocks pinch the four inner corners.
    wall_block(c, 1, 9, 9, 11, CAP, FACE)
    wall_block(c, W - 10, 9, W - 2, 11, CAP, FACE)
    wall_block(c, 1, 22, 9, 24, CAP, FACE)
    wall_block(c, W - 10, 22, W - 2, 24, CAP, FACE)
    # Corner chapels behind the pinches.
    c.fill_rect(0, 1, 3, 9, 8, CHAPEL)
    c.fill_rect(0, W - 10, 3, W - 2, 8, CHAPEL)
    c.fill_rect(0, 1, 25, 9, H - 2, WOOD)
    c.fill_rect(0, W - 10, 25, W - 2, H - 2, WOOD)

    # Altar dais + twin carpet processionals (vertical + transept arm).
    c.fill_rect(0, 16, 3, 29, 9, DAIS)
    c.fill_rect(0, 20, 3, 25, H - 3, CARPET)
    c.fill_rect(0, 11, 14, 34, 17, CARPET)

    c.stamp(st_altar, 18, 1)
    c.stamp(st_bunting, 5, 2)
    c.stamp(st_bunting, 32, 2)
    # Pew quads in the nave south of the transept.
    c.stamp(st_pews, 11, 19)
    c.stamp(st_pews, 28, 19)
    # Transept arms get single-pew cover rows.
    for y in (12, 14, 16):
        c.stamp(st_pew, 3, y)
        c.stamp(st_pew, 38, y)
    c.stamp(st_candles, 15, 8)
    c.stamp(st_candles, 29, 8)
    for x in (12, 33):
        c.stamp(st_ped_a, x, 10)
        c.stamp(st_ped_b, x, 18)
    # Chapel pedestals.
    for x0 in (2, W - 9):
        c.stamp(st_ped_a, x0, 4)
        c.stamp(st_ped_b, x0 + 6, 4)
    return c


# ── 7. Emerald Sanctum (II) — eldun ts3: overgrown reliquary ────────────────

def build_emerald():
    S = stamps_for(ELDUN, (6, 7, 11))
    st_arch_a, st_arch_b = S[0], S[3]
    st_throne = S[2]
    st_reliq = S[5]
    st_mandala = S[25]
    st_sigil = S[4]
    st_door = S[23]
    st_chal_a, st_chal_b = S[6], S[7]
    st_crys_a, st_crys_b = S[19], S[27]
    st_rocks = S[15]
    st_bench = S[21]

    W, H = 36, 26
    ROCK = ("a2", 24)      # brown rock floor
    MUD = ("a2", 0)        # pale sand
    COPPER = ("a2", 26)    # copper tile
    COPPER2 = ("a2", 27)
    CAP = ("a4f", 16)      # cream cross cap
    FACE = ("a4w", 28)     # brown gem-pillar face

    c = Composer(ELDUN, 3, W, H)
    shell(c, ROCK, CAP, FACE)

    # Mud clearings break up the rock.
    c.fill_rect(0, 3, 10, 10, 16, MUD)
    c.fill_rect(0, W - 11, 10, W - 4, 16, MUD)

    # Throne terrace north, copper court center.
    c.fill_rect(0, 13, 3, 22, 8, COPPER)
    c.fill_rect(0, 12, 11, 23, 19, COPPER)
    c.fill_rect(0, 14, 13, 21, 17, COPPER2)
    c.stamp(st_throne, 15, 1)
    c.stamp(st_arch_a, 9, 2)
    c.stamp(st_arch_b, 24, 2)
    c.stamp(st_mandala, 16, 13)

    # Side chambers with wall stubs.
    wall_block(c, 6, 6, 11, 8, CAP, FACE)
    wall_block(c, W - 12, 6, W - 7, 8, CAP, FACE)
    wall_block(c, 6, 20, 11, 22, CAP, FACE)
    wall_block(c, W - 12, 20, W - 7, 22, CAP, FACE)

    # Reliquary + green door shrine on the south wall axis.
    c.stamp(st_reliq, 2, H - 8)
    c.stamp(st_door, 28, H - 5)
    c.stamp(st_sigil, 16, H - 4)

    # Crystals, rocks, chalice torches scattered through the ruin.
    c.stamp(st_crys_a, 4, 4)
    c.stamp(st_crys_b, 30, 4)
    c.stamp(st_rocks, 3, 18)
    c.stamp(st_rocks, 31, 18)
    for x, y in ((12, 9), (22, 9), (12, 19), (22, 19)):
        c.stamp(st_chal_a if x < 18 else st_chal_b, x, y)
    c.stamp(st_bench, 15, 20)
    return c


# ── 8. Aurelian Court (IV) — eldun ts4: gold sky sanctum ────────────────────

def build_aurelian():
    S = stamps_for(ELDUN, (8, 9, 10))
    st_door = S[0]
    st_statue = S[2]
    st_arch_a, st_arch_b = S[3], S[5]
    st_sigil = S[6]
    st_torch = S[12]
    st_chal = S[16]
    st_altar = S[20]       # 11x11 grand altar with chandelier
    st_bench_a, st_bench_b = S[21], S[22]
    st_cols_a, st_cols_b = S[24], S[25]

    W, H = 40, 28
    CLOUD = ("a2", 10)     # cloud ground
    GOLD = ("a2", 26)      # gold tile
    GOLD2 = ("a2", 29)
    MARBLE = ("a2", 16)    # grey stone
    CAP = ("a4f", 16)
    FACE = ("a4w", 30)     # gold ornate face

    c = Composer(ELDUN, 4, W, H)
    shell(c, CLOUD, CAP, FACE)

    # Gold court floats on the clouds; marble walk ring frames it.
    c.fill_rect(0, 8, 6, W - 9, H - 6, MARBLE)
    c.fill_rect(0, 10, 8, W - 11, H - 8, GOLD)
    c.fill_rect(0, 14, 11, W - 15, H - 11, GOLD2)

    # Grand altar dominates the north court.
    c.stamp(st_altar, 14, 1)
    c.stamp(st_arch_a, 8, 2)
    c.stamp(st_arch_b, 28, 2)
    c.stamp(st_door, 18, H - 4)

    # Column pairs guard the court corners.
    c.stamp(st_cols_a, 9, 9)
    c.stamp(st_cols_b, 28, 9)
    c.stamp(st_cols_a, 9, H - 12)
    c.stamp(st_cols_b, 28, H - 12)

    # Torches line the central axis; benches give south-hall cover.
    for y in (12, 16, 20):
        c.stamp(st_torch, 12, y)
        c.stamp(st_torch, 27, y)
    for x in (14, 19, 24):
        c.stamp(st_bench_a, x, H - 7)
    c.stamp(st_bench_b, 17, 13)
    c.stamp(st_bench_b, 21, 13)
    c.stamp(st_statue, 11, 4)
    c.stamp(st_statue, 27, 4)
    c.stamp(st_sigil, 18, 17)
    c.stamp(st_chal, 8, 13)
    c.stamp(st_chal, 31, 13)
    return c


BUILDERS = {
    "church": build_church,
    "library": build_library,
    "mansion_grounds": build_mansion_grounds,
    "foundry": build_foundry,
    "infernal_reliquary": build_reliquary,
    "cathedral": build_cathedral,
    "emerald_sanctum": build_emerald,
    "aurelian_court": build_aurelian,
}


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else r"scratch\compose"
    which = sys.argv[2] if len(sys.argv) > 2 else "all"
    scale = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    names = list(BUILDERS) if which == "all" else [which]
    for name in names:
        c = BUILDERS[name]()
        c.bake(out_dir, name, scale=scale)
        print("baked", name)
