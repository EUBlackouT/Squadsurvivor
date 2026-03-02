#!/usr/bin/env python3
import argparse
import os
from collections import deque

try:
    from PIL import Image
except Exception as exc:
    raise SystemExit("Pillow is required: pip install pillow") from exc


def is_near_white(pixel, thresh):
    r, g, b, a = pixel
    if a < 250:
        return False
    return r >= thresh and g >= thresh and b >= thresh


def flood_fill_mask(img, thresh):
    w, h = img.size
    pixels = img.load()
    visited = [[False] * w for _ in range(h)]
    mask = [[False] * w for _ in range(h)]
    q = deque()

    def push(x, y):
        if visited[y][x]:
            return
        visited[y][x] = True
        if is_near_white(pixels[x, y], thresh):
            mask[y][x] = True
            q.append((x, y))

    # seed from edges
    for x in range(w):
        push(x, 0)
        push(x, h - 1)
    for y in range(h):
        push(0, y)
        push(w - 1, y)

    while q:
        x, y = q.popleft()
        if x > 0:
            push(x - 1, y)
        if x + 1 < w:
            push(x + 1, y)
        if y > 0:
            push(x, y - 1)
        if y + 1 < h:
            push(x, y + 1)

    return mask


def edge_white_ratio(img, thresh):
    w, h = img.size
    pixels = img.load()
    edge = []
    for x in range(w):
        edge.append(pixels[x, 0])
        edge.append(pixels[x, h - 1])
    for y in range(h):
        edge.append(pixels[0, y])
        edge.append(pixels[w - 1, y])
    if not edge:
        return 0.0
    white = sum(1 for p in edge if is_near_white(p, thresh))
    return white / float(len(edge))


def process_file(path, thresh, min_edge_ratio, dry_run):
    try:
        img = Image.open(path).convert("RGBA")
    except Exception:
        return False

    if edge_white_ratio(img, thresh) < min_edge_ratio:
        return False

    mask = flood_fill_mask(img, thresh)
    pixels = img.load()
    w, h = img.size
    changed = False
    for y in range(h):
        row = mask[y]
        for x in range(w):
            if row[x]:
                r, g, b, a = pixels[x, y]
                if a != 0:
                    pixels[x, y] = (r, g, b, 0)
                    changed = True

    if changed and not dry_run:
        img.save(path)
    return changed


def walk_pngs(roots):
    for root in roots:
        for dirpath, _dirnames, filenames in os.walk(root):
            for f in filenames:
                if f.lower().endswith(".png"):
                    yield os.path.join(dirpath, f)


def main():
    parser = argparse.ArgumentParser(description="Remove white backgrounds from PNGs.")
    parser.add_argument("--root", action="append", default=[], help="Root folder to scan (repeatable).")
    parser.add_argument("--threshold", type=int, default=245, help="RGB threshold for near-white.")
    parser.add_argument("--min-edge-ratio", type=float, default=0.6, help="Edge ratio required to treat as background.")
    parser.add_argument("--dry-run", action="store_true", help="Scan and report without writing changes.")
    args = parser.parse_args()

    roots = args.root or [
        os.path.join("godot", "assets", "characters"),
        os.path.join("godot", "assets", "pixellab"),
    ]

    changed = 0
    total = 0
    for path in walk_pngs(roots):
        total += 1
        if process_file(path, args.threshold, args.min_edge_ratio, args.dry_run):
            changed += 1

    print(f"Scanned {total} PNGs, cleaned {changed}.")


if __name__ == "__main__":
    main()
