Pixel fidelity: In Godot Import dock, for all UI textures (panel/card/button/chip):
- Filter: OFF (or Nearest)
- Mipmaps: OFF
- (optional) Compression: Lossless

Project already has textures/default_filters=false (nearest).
Menu.gd sets viewport canvas_item_default_texture_filter = NEAREST on ready.
