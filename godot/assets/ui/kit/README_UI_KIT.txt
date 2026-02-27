Squad Protocol - UI Kit Assets
==============================

LUDO-GENERATED ASSETS (currently integrated)
--------------------------------------------
These are used as StyleBoxTexture for 9-slice panels and buttons:

- menu_panel_ludo.webp      Main menu card/panel background
- menu_button_primary_ludo.webp   Primary action buttons (Start, etc.)
- menu_button_secondary_ludo.webp Secondary buttons (Armory, Settings, etc.)
- panel_frame_ludo_v2.webp  Fallback panel if menu_panel missing
- button_primary_ludo_v2.webp     Fallback primary button
- button_secondary_ludo_v2.webp  Fallback secondary button

Integration: MainMenu.gd loads these and applies them via StyleBoxTexture.
Margins are tuned for 9-slice (corners fixed, edges stretch).


OPTIONAL: Kenney Sci-Fi UI Pack (CC0)
-------------------------------------
Free, public domain: https://opengameart.org/content/ui-pack-sci-fi

1. Download kenney_ui-pack-scifi.zip
2. Extract PNGs to this folder (or a subfolder like kenney/)
3. Update MainMenu.gd ASSET_* constants to point at the Kenney files
4. Adjust texture_margin values in _make_panel_style() / _make_button_stylebox()
   (Kenney assets may need different 9-slice margins)
