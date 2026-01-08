Squad Protocol - Main Menu Art
==============================

To match the "Squad Protocol" menu mock exactly, place these two files here:

1) Background art (full screen)
   - File:  main_menu_bg.jpg   (or .png)
   - Should be 16:9 (e.g. 1920×1080 or higher)

2) Frame overlay (transparent center)
   - File:  main_menu_frame.png
   - Must have alpha transparency (PNG)

These are referenced by:
  - res://scenes/MainMenu.tscn
  - res://scripts/MainMenu.gd

If you use different filenames, update the exported paths in MainMenu.gd:
  - bg_art_path
  - frame_art_path






