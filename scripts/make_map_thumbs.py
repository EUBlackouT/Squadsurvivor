"""Generate small per-map thumbnails for the main menu command deck.

Menu cards and the hero backdrop must never decode the full 4K map art.
"""
import json
import os

from PIL import Image

Image.MAX_IMAGE_PIXELS = None

ROOT = r"E:\SplitCode\godot"
OUT_DIR = os.path.join(ROOT, "assets", "maps", "thumbs")
os.makedirs(OUT_DIR, exist_ok=True)

data = json.load(open(os.path.join(ROOT, "data", "maps.json"), encoding="utf-8"))


def iter_maps(node):
    if isinstance(node, dict):
        if "id" in node and isinstance(node.get("visuals"), dict):
            yield node
        for v in node.values():
            yield from iter_maps(v)
    elif isinstance(node, list):
        for item in node:
            yield from iter_maps(item)


count = 0
for m in iter_maps(data):
    map_id = str(m.get("id", ""))
    vis = m.get("visuals", {})
    bg = str(vis.get("bg_image_path", "")) or str(m.get("metadata_image_path", ""))
    if not map_id or not bg:
        continue
    src = bg.replace("res://", ROOT + os.sep).replace("/", os.sep)
    if not os.path.exists(src):
        print(f"skip {map_id}: missing {src}")
        continue
    img = Image.open(src).convert("RGB")
    w, h = img.size
    tw = 960
    th = max(1, round(h * tw / w))
    img = img.resize((tw, th), Image.LANCZOS)
    dst = os.path.join(OUT_DIR, f"{map_id}.webp")
    img.save(dst, "WEBP", quality=85, method=6)
    print(f"{map_id}: {os.path.getsize(dst)//1024} KB")
    count += 1

print(f"done, {count} thumbs")
