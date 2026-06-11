"""One-shot import of regenerated machine characters from Ludo spritesheets.

Downloads each 5x5 walk spritesheet, splits it into individual frames, and
installs them into godot/assets/characters/machines/<char>/frames/<dir>/.
"""

import io
import shutil
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(r"E:/SplitCode/godot/assets/characters/machines")

SHEETS = {
    "robot_elite": {
        "walk_front": "a62b7fd542dfa2618870eff9251ae21f",
        "walk_back": "d63f4d8981a8db3ee2057b3f83335be2",
        "walk_side_right": "73a08181fa73de4ca1a791ebac12b3c8",
    },
    "ion_scout": {
        "walk_front": "ce54c4114a56a34cd9853e574309364e",
        "walk_back": "34fa009971a09fa50a8ca744e763a65f",
        "walk_side_right": "26544ec90db3d8c4c208aff943a0342c",
    },
    "iron_warden": {
        "walk_front": "f24a964f0c462d3d4d333f5735bb396b",
        "walk_back": "99aa5071dcc43c0d4d0463b723f0557d",
        "walk_side_right": "5bef21e6b88fc90f43a30253396851c6",
    },
}

COLS = 5
ROWS = 5


def main() -> None:
    for char, dirs in SHEETS.items():
        char_root = ROOT / char
        sheets_dir = char_root / "spritesheets"
        sheets_dir.mkdir(parents=True, exist_ok=True)

        for dir_name, sheet_id in dirs.items():
            url = f"https://storage.googleapis.com/ludo-assets/api/{sheet_id}.webp"
            data = urllib.request.urlopen(url, timeout=60).read()
            (sheets_dir / f"{dir_name}.webp").write_bytes(data)

            sheet = Image.open(io.BytesIO(data)).convert("RGBA")
            fw, fh = sheet.width // COLS, sheet.height // ROWS

            out_dir = char_root / "frames" / dir_name
            if out_dir.exists():
                shutil.rmtree(out_dir)  # also clears stale frames + .import files
            out_dir.mkdir(parents=True)

            idx = 0
            for r in range(ROWS):
                for c in range(COLS):
                    frame = sheet.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
                    frame.save(out_dir / f"frame_{idx:03d}.png")
                    idx += 1
            print(f"{char}/{dir_name}: {idx} frames @ {fw}x{fh}")

    # Legacy dir superseded by walk_side_right; remove so it can't be picked up.
    legacy = ROOT / "iron_warden" / "frames" / "walk_side"
    if legacy.exists():
        shutil.rmtree(legacy)
        print("removed legacy iron_warden/frames/walk_side")


if __name__ == "__main__":
    main()
