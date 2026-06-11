"""Downscale + recompress oversized map background PNGs to WebP.

8688x6516 PNGs (~95 MB) decode in >1s at map boot. Half resolution WebP q90
is visually identical as a zoomed background and decodes in a fraction of
the time.
"""
import os

from PIL import Image

Image.MAX_IMAGE_PIXELS = None

MAPS_DIR = r"E:\SplitCode\godot\assets\maps"
JOBS = [
    ("angelic.png", "angelic.webp"),
    ("robot map.png", "robot_map.webp"),
    ("ChatGPT Image May 28, 2026, 09_01_37 PM-creative-upscaler.png", "forest_map.webp"),
]

for src_name, dst_name in JOBS:
    src = os.path.join(MAPS_DIR, src_name)
    dst = os.path.join(MAPS_DIR, dst_name)
    img = Image.open(src)
    w, h = img.size
    img = img.convert("RGB").resize((w // 2, h // 2), Image.LANCZOS)
    img.save(dst, "WEBP", quality=90, method=6)
    src_mb = os.path.getsize(src) / 1e6
    dst_mb = os.path.getsize(dst) / 1e6
    print(f"{src_name}: {w}x{h} {src_mb:.1f}MB -> {img.size[0]}x{img.size[1]} {dst_mb:.1f}MB")
    os.remove(src)
    for suffix in (".import",):
        leftover = src + suffix
        if os.path.exists(leftover):
            os.remove(leftover)
print("done")
