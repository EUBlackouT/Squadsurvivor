PATCHBOUND Assets TODO

Gameplay placeholders to replace with art:

1) Player avatar
   - Idle, walk, firing, fusion aura

2) Enemy cubes (entangled pair) + boss
   - Entangled variants per branch tint
   - Boss: phase-specific visuals

3) Projectiles
   - Threadneedle bolt (A/B tint)
   - Refactor Harpoon
   - Garbage Collector orb
   - Shader Scepter wave projectile

4) Council pads and UI
   - Pads A/B visuals
   - Council choice panel/buttons

5) Phase gates and FX
   - Phase swap pulse
   - Denial pulse

6) Merge visuals
   - Merge overlay and timer

7) Boss phase polish
   - Red Build overlay/FX
   - Cleansing pads (red)

8) HUD elements
   - Room/enemy counters
   - Phase/merge timers
   - Blueprints indicator (count/token icons)

10) Blueprints Menu UI
   - Panel frame art
   - Token icon + spend animation
   - Blueprint slot icons (locked/owned)
   - Research button art (normal/pressed)

11) FX/Animations
   - Council pads charge FX
   - Merge overlay pulse
   - Weapon verbs: Harpoon tether line, Shader beam/impact, GC orb implode
   - Entangled sync-kill flash

9) Tilemap/rooms
   - 6–8 rooms, boss arena, extract

Integration plan:
- Leonardo or Scenario pipeline to generate spritesheets, then wire frame-based animations in Phaser.
- Maintain placeholder rectangles until assets are ready.

