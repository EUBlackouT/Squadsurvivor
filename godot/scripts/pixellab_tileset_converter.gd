extends SceneTree

# PixelLab to Godot Tileset Converter
# Converts PixelLab metadata JSON + PNG sprite sheets to Godot terrain system
# Usage: godot --headless -s pixellab_tileset_converter.gd metadata1.json image1.png metadata2.json image2.png ...

var output_path = "res://tilesets/combined_terrain.tres"
var tile_size = 0
var terrains = {}
var tiles = []

# Corner-based tile layout for optimal terrain painting
var corner_layout = [
	"ss/sw", "ss/ww", "ss/ws", "ww/ws", "ww/sw",
	"sw/sw", "ww/ww", "ws/ws", "ws/ww", "sw/ww",
	"sw/ss", "ww/ss", "ws/ss", "ws/sw", "sw/ws",
	"ww/ww", "ss/ss", "", "", ""
]

func _init():
	print("\n🎨 PixelLab to Godot Converter")
	print("================================")
	
	var tileset_pairs = []
	var args = OS.get_cmdline_args()
	
	var i = 0
	while i < args.size():
		var arg = args[i]
		if arg.ends_with(".json"):
			var json_path = arg
			var png_path = ""
			if i + 1 < args.size() and args[i + 1].ends_with(".png"):
				png_path = args[i + 1]
				i += 1
			if png_path != "":
				tileset_pairs.append({"json": json_path, "png": png_path})
		i += 1
	
	if tileset_pairs.is_empty():
		print("❌ No valid JSON/PNG pairs found!")
		print("Usage: godot --headless -s pixellab_tileset_converter.gd metadata.json image.png")
		quit()
		return
	
	print("📦 Found %d tileset pairs" % tileset_pairs.size())
	
	# Ensure output directory exists
	DirAccess.make_dir_recursive_absolute("res://tilesets")
	
	for pair in tileset_pairs:
		load_tileset_pair(pair.json, pair.png)
	
	if tiles.is_empty():
		print("❌ No tiles loaded")
		quit()
		return
	
	create_tileset()
	print("\n✅ Created: %s" % output_path)
	quit()

func load_tileset_pair(json_path: String, png_path: String):
	print("\n📁 Loading %s..." % json_path)
	
	if not FileAccess.file_exists(json_path):
		print("  ❌ JSON not found")
		return
	
	var file = FileAccess.open(json_path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		print("  ❌ Invalid JSON")
		return
	file.close()
	
	var metadata = json.data
	
	if not FileAccess.file_exists(png_path):
		print("  ❌ PNG not found")
		return
	
	var sprite_sheet = Image.new()
	if sprite_sheet.load(png_path) != OK:
		print("  ❌ Failed to load PNG")
		return
	
	# Get tile size
	if tile_size == 0:
		var size = metadata.tileset_data.tile_size
		tile_size = size.width
		print("  Tile size: %dx%d" % [tile_size, tile_size])
	
	# Get terrain names
	var lower_name = metadata.metadata.terrain_prompts.lower
	var upper_name = metadata.metadata.terrain_prompts.upper
	
	var lower_id = get_terrain_id(lower_name)
	var upper_id = get_terrain_id(upper_name)
	
	# Index tiles by Wang number
	var wang_tiles = {}
	for tile in metadata.tileset_data.tiles:
		var corners = tile.corners
		var bbox = tile.bounding_box
		
		var tile_image = Image.create(bbox.width, bbox.height, false, Image.FORMAT_RGBA8)
		tile_image.blit_rect(sprite_sheet, Rect2i(bbox.x, bbox.y, bbox.width, bbox.height), Vector2i.ZERO)
		
		var nw = 1 if corners.NW == "upper" else 0
		var ne = 1 if corners.NE == "upper" else 0
		var sw = 1 if corners.SW == "upper" else 0
		var se = 1 if corners.SE == "upper" else 0
		var wang_idx = nw * 8 + ne * 4 + sw * 2 + se
		
		wang_tiles[wang_idx] = {
			"image": tile_image,
			"corners": [
				upper_id if nw == 1 else lower_id,
				upper_id if ne == 1 else lower_id,
				upper_id if sw == 1 else lower_id,
				upper_id if se == 1 else lower_id
			]
		}
	
	# Add tiles
	var added = 0
	for pattern in corner_layout:
		if pattern == "":
			tiles.append(null)
		else:
			var parts = pattern.split("/")
			var top = parts[0]
			var bottom = parts[1]
			
			var nw = 1 if top[0] == "s" else 0
			var ne = 1 if top[1] == "s" else 0
			var sw = 1 if bottom[0] == "s" else 0
			var se = 1 if bottom[1] == "s" else 0
			var wang_idx = nw * 8 + ne * 4 + sw * 2 + se
			
			if wang_tiles.has(wang_idx):
				tiles.append(wang_tiles[wang_idx])
				added += 1
			else:
				tiles.append(null)
	
	print("  ✅ Added %d tiles" % added)

func get_terrain_id(name: String) -> int:
	for id in terrains:
		if terrains[id] == name:
			return id
	var id = terrains.size()
	terrains[id] = name
	return id

func create_tileset():
	print("\n🔨 Creating tileset...")
	
	var cols = 5
	var rows = (tiles.size() + cols - 1) / cols
	var atlas = Image.create(cols * tile_size, rows * tile_size, false, Image.FORMAT_RGBA8)
	
	for i in range(tiles.size()):
		if tiles[i] == null:
			continue
		var img = tiles[i].image
		var x = (i % cols) * tile_size
		var y = (i / cols) * tile_size
		atlas.blit_rect(img, Rect2i(0, 0, tile_size, tile_size), Vector2i(x, y))
	
	var atlas_path = output_path.replace(".tres", "_atlas.png")
	atlas.save_png(atlas_path)
	print("  Atlas: %s" % atlas_path)
	
	# Generate tile definitions
	var tile_defs = []
	for i in range(tiles.size()):
		if tiles[i] == null:
			continue
		var x = i % cols
		var y = i / cols
		var corners = tiles[i].corners
		tile_defs.append("%d:%d/0 = 0" % [x, y])
		tile_defs.append("%d:%d/0/terrain_set = 0" % [x, y])
		tile_defs.append("%d:%d/0/terrains_peering_bit/top_left_corner = %d" % [x, y, corners[0]])
		tile_defs.append("%d:%d/0/terrains_peering_bit/top_right_corner = %d" % [x, y, corners[1]])
		tile_defs.append("%d:%d/0/terrains_peering_bit/bottom_left_corner = %d" % [x, y, corners[2]])
		tile_defs.append("%d:%d/0/terrains_peering_bit/bottom_right_corner = %d" % [x, y, corners[3]])
	
	# Terrain definitions
	var terrain_defs = []
	var terrain_colors = {}
	for i in range(tiles.size()):
		if tiles[i] == null:
			continue
		var corners = tiles[i].corners
		if corners[0] == corners[1] and corners[1] == corners[2] and corners[2] == corners[3]:
			var terrain_id = corners[0]
			if not terrain_colors.has(terrain_id):
				var img = tiles[i].image
				terrain_colors[terrain_id] = img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	
	for id in terrains:
		var name = terrains[id]
		var color = terrain_colors.get(id, Color(0.5, 0.5, 0.5))
		terrain_defs.append('terrain_set_0/terrain_%d/name = "%s"' % [id, name])
		terrain_defs.append('terrain_set_0/terrain_%d/color = Color(%f, %f, %f, 1)' % [id, color.r, color.g, color.b])
	
	# Write .tres file
	var tres = '[gd_resource type="TileSet" load_steps=2 format=3]\n\n'
	tres += '[ext_resource type="Texture2D" path="%s" id="1"]\n\n' % atlas_path
	tres += '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_1"]\n'
	tres += 'texture = ExtResource("1")\n'
	tres += 'texture_region_size = Vector2i(%d, %d)\n' % [tile_size, tile_size]
	tres += "\n".join(tile_defs) + '\n\n'
	tres += '[resource]\n'
	tres += 'tile_size = Vector2i(%d, %d)\n' % [tile_size, tile_size]
	tres += 'terrain_set_0/mode = 0\n'
	tres += "\n".join(terrain_defs) + '\n'
	tres += 'sources/0 = SubResource("TileSetAtlasSource_1")\n'
	
	var file = FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(tres)
	file.close()

