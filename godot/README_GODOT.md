Godot pilot (structures animation)

Prereqs
- Install Godot 4.2+.

Open project
- In Godot, open the folder E:/SplitCode/godot (or the repo’s godot/).
- The main scene is res://scenes/Main.tscn.

What this shows
- Three static structures (obelisk, arcane cube, green fountain) animating in place.
- Each uses a 1×8 sheet (256×256 per frame); Sprite2D/AnimatedSprite2D with hframes=8, vframes=1 at ~10 FPS.
- Bottom-center anchoring is applied so the object is a “still animation” with no drift.

Assets
- Sheets are under res://assets/structures/*.png.
- To convert raw strips (even with black backgrounds) use the included editor tool below.

Run
- Click Play; you should see all three structures animate smoothly without lateral/vertical movement.

Convert raw PNG strips for Godot (no jitter)
- Put your source PNGs (horizontal strips with 4/6/8 frames) into: res://assets/_incoming/
- In the Godot editor, open the script: res://tools/ConvertStructures.gd
- Run it from the Script Editor: File → Run
- Output: res://assets/structures/<name>_sheet.png (1×8, 256×256, RGBA, bottom-center aligned with padding)
- Then set up an AnimatedSprite2D or Sprite2D with hframes=8, vframes=1 and playing=true.

Next steps (migration)
- Player + camera: create Player scene, apply pixel snap, WASD movement.
- Map/tiles: use TileMap with your tileset; chunking likely unnecessary initially.
- Enemies: replace Phaser AI with Godot Nodes and Areas; collisions via Physics layers.
- VFX: use AnimatedSprite2D or Sprite2D+AnimationPlayer for procedural FX.


