Wood Menu Assets - Setup
========================

Alle 9 bestanden staan in res://assets/ui/wood_menu/
(button_wood_pressed was een kopie van normal als fallback - vervang met echte pressed als je die hebt)

  bg_fantasy_1920x1080.jpg  (was JPEG met .png extensie - hernoemd)
  panel_wood_9slice_512.png
  button_wood_normal_512x128.png
  button_wood_hover_512x128.png
  button_wood_pressed_512x128.png
  button_wood_disabled_512x128.png
  tab_wood_normal_384x128.png
  tab_wood_hover_384x128.png
  tab_wood_pressed_384x128.png

Godot import (belangrijk voor pixel look):
  1. Selecteer elke texture in de FileSystem
  2. Open de Import dock (rechts)
  3. Zet "Filter" = Nearest (of "Nearest" in de dropdown)
  4. Zet "Mipmaps" = Off (Generate Mipmaps uit)
  5. Klik Reimport

Project-wide pixel filter (alternatief):
  Project → Project Settings → Rendering → Textures → Default Filter = Nearest
