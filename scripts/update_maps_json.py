"""One-shot maps.json update for the original-authored map rollout."""
import copy
import json
import os

MAPS = r"godot\data\maps.json"
META_DIR = r"godot\assets\maps\authored"

d = json.load(open(MAPS, encoding="utf-8"))
by_id = {m["id"]: m for m in d["maps"]}


def meta_size(name):
    md = json.load(open(os.path.join(META_DIR, name + "_metadata.json"), encoding="utf-8"))
    return md["image_size_px"]


# 1. Refresh sizes for zones whose playfield was replaced in place.
for zid in ("church", "library", "foundry", "cathedral", "infernal_reliquary"):
    m = by_id[zid]
    m["map_size"] = meta_size(zid)
    m["metadata_path"] = "res://assets/maps/authored/%s_metadata.json" % zid

# 2. Re-theme cathedral_nave -> Mansion Grounds (gothic garden exterior).
nave = by_id["cathedral_nave"]
nave["name"] = "Mansion Grounds (II)"
nave["tagline"] = "Original-authored gothic gardens. Hedge cover, open plaza, long sightlines."
nave["map_size"] = meta_size("mansion_grounds")
nave["metadata_path"] = "res://assets/maps/authored/mansion_grounds_metadata.json"
nave["race_pool"] = ["HUMANOID", "UNDEAD", "AVIAN"]
nave["visuals"].update({
    "theme_id": "mansion_grounds",
    "base_color": "#0d130d",
    "alt_color": "#131b12",
    "accent_color": "#2e4a2e",
    "fog_color": "#aac8aa",
    "fog_strength": 0.07,
    "rays_color": "#e8ffd8",
    "rays_strength": 0.09,
    "atmo_color": "#cfe8c0",
})

# 3. New zones cloned from authored templates, then tuned.
emerald = copy.deepcopy(by_id["cathedral_nave"])
emerald.update({
    "id": "emerald_sanctum",
    "tier": 2,
    "always_unlocked": True,
    "name": "Emerald Sanctum (II)",
    "tagline": "Original-authored overgrown reliquary. Copper courts under emerald wards.",
    "map_size": meta_size("emerald_sanctum"),
    "metadata_path": "res://assets/maps/authored/emerald_sanctum_metadata.json",
    "race_pool": ["AQUATIC", "SLIMEKIN", "PLANTOID"],
})
emerald["visuals"] = dict(emerald["visuals"], **{
    "theme_id": "emerald_sanctum",
    "base_color": "#0b120c",
    "alt_color": "#121b10",
    "accent_color": "#2c4d2a",
    "fog_color": "#9fd8a8",
    "fog_strength": 0.09,
    "rays_color": "#b8ffc8",
    "rays_strength": 0.1,
    "atmo_color": "#a8f0b8",
})

aurelian = copy.deepcopy(by_id["infernal_reliquary"])
aurelian.update({
    "id": "aurelian_court",
    "tier": 4,
    "always_unlocked": True,
    "name": "Aurelian Court (IV)",
    "tagline": "Original-authored sky sanctum. Gold courts on cloud, elite pressure.",
    "map_size": meta_size("aurelian_court"),
    "metadata_path": "res://assets/maps/authored/aurelian_court_metadata.json",
    "race_pool": ["CELESTIAL", "AVIAN", "DRACONIC"],
})
aurelian["visuals"] = dict(aurelian["visuals"], **{
    "theme_id": "aurelian_court",
    "base_color": "#14120a",
    "alt_color": "#1d1a10",
    "accent_color": "#54482a",
    "fog_color": "#e8d8a0",
    "fog_strength": 0.07,
    "atmo_style": 0,
    "rays_color": "#fff0c0",
    "rays_strength": 0.14,
    "atmo_color": "#f5e8b8",
})
# Tier-4 pressure tuning (matches cathedral's danger band).
aurelian.update({
    "enemy_hp_mult": 2.3,
    "enemy_damage_mult": 1.68,
    "enemy_speed_mult": 1.12,
    "spawn_interval_mult": 0.76,
    "max_enemies_mult": 1.24,
    "initial_enemies_mult": 1.22,
    "elite_spawn_mult": 1.8,
    "essence_mult": 1.85,
})

# Insert emerald after cathedral_nave, aurelian after grand_basilica.
maps = [m for m in d["maps"] if m["id"] not in ("emerald_sanctum", "aurelian_court")]
out = []
for m in maps:
    out.append(m)
    if m["id"] == "cathedral_nave":
        out.append(emerald)
    if m["id"] == "grand_basilica":
        out.append(aurelian)
d["maps"] = out

json.dump(d, open(MAPS, "w", encoding="utf-8"), indent=2)
print("zones now:")
for m in d["maps"]:
    print(" ", m["id"], "|", m.get("name"), "| tier", m.get("tier"),
          "|", ",".join(m.get("race_pool", [])))
