extends Node
class_name TilesetLoader

# Converts PixelLab JSON metadata to Godot TileSet at runtime
# This creates TileSet resources programmatically from downloaded tilesets

# Cache for Wang index to atlas position mappings per biome
static var _wang_maps: Dictionary = {}

static func get_wang_map(biome: String) -> Dictionary:
	return _wang_maps.get(biome, {})

static func load_tileset(metadata_path: String, image_path: String, biome: String = "") -> TileSet:
	"""Load a PixelLab tileset from JSON metadata and PNG image."""
	
	# Load the PNG image directly via Image (works even if not imported by Godot)
	var img = Image.new()
	var actual_path = image_path
	
	# Convert res:// to absolute path for Image.load()
	if image_path.begins_with("res://"):
		actual_path = ProjectSettings.globalize_path(image_path)
	
	print("TilesetLoader: Loading image from: %s" % actual_path)
	var err = img.load(actual_path)
	if err != OK:
		push_error("TilesetLoader: Failed to load image: %s (error: %d)" % [actual_path, err])
		return null
	# Remove visible per-tile border seams from baked atlases.
	# Some generated atlases have brighter edge pixels per 32x32 tile, which produces
	# "square boxes" in-game when many transition tiles are adjacent.
	_desquare_atlas_borders(img, 32)
	
	var texture = ImageTexture.create_from_image(img)
	if texture == null:
		push_error("TilesetLoader: Failed to create texture from image: %s" % image_path)
		return null
	
	print("TilesetLoader: Loaded texture %dx%d" % [img.get_width(), img.get_height()])
	
	# Load and parse JSON metadata
	var file = FileAccess.open(metadata_path, FileAccess.READ)
	if file == null:
		push_error("TilesetLoader: Failed to open metadata: %s" % metadata_path)
		return null
	
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("TilesetLoader: Invalid JSON in: %s" % metadata_path)
		return null
	file.close()
	
	var data: Dictionary = json.data
	var tile_size_data = data.get("tile_size", {"width": 32, "height": 32})
	var tile_size = Vector2i(tile_size_data.width, tile_size_data.height)
	
	var tileset_data: Dictionary = data.get("tileset_data", {})
	var tiles: Array = tileset_data.get("tiles", [])
	
	# Create TileSet
	var tileset = TileSet.new()
	tileset.tile_size = tile_size
	
	# Create TileSetAtlasSource
	var source = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = tile_size
	
	# Add terrain set (corner-only matching for Wang tiles)
	tileset.add_terrain_set(0)
	tileset.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	
	# Add terrains
	var metadata_block: Dictionary = data.get("metadata", {})
	var terrain_prompts: Dictionary = metadata_block.get("terrain_prompts", {})
	var lower_name = terrain_prompts.get("lower", "Ground")
	var upper_name = terrain_prompts.get("upper", "Feature")
	
	tileset.add_terrain(0, 0)  # Terrain 0 = lower
	tileset.set_terrain_name(0, 0, lower_name.substr(0, 20))
	tileset.set_terrain_color(0, 0, Color(0.3, 0.3, 0.3))
	
	tileset.add_terrain(0, 1)  # Terrain 1 = upper
	tileset.set_terrain_name(0, 1, upper_name.substr(0, 20))
	tileset.set_terrain_color(0, 1, Color(0.6, 0.6, 0.6))
	
	# Build Wang index to atlas coords mapping
	var wang_map: Dictionary = {}
	
	# Map tiles to atlas positions
	for tile_data_entry in tiles:
		var bbox: Dictionary = tile_data_entry.get("bounding_box", {})
		var corners: Dictionary = tile_data_entry.get("corners", {})
		
		# Calculate atlas position from bounding_box
		var atlas_x = int(bbox.get("x", 0)) / tile_size.x
		var atlas_y = int(bbox.get("y", 0)) / tile_size.y
		var atlas_coords = Vector2i(atlas_x, atlas_y)
		
		# Create tile at this position
		source.create_tile(atlas_coords)
		
		# Get TileData for this tile
		var td := source.get_tile_data(atlas_coords, 0)
		if td == null:
			continue
		
		# Set terrain set
		td.terrain_set = 0
		
		# Calculate Wang index from corners (NW*8 + NE*4 + SW*2 + SE)
		var nw = 1 if corners.get("NW", "lower") == "upper" else 0
		var ne = 1 if corners.get("NE", "lower") == "upper" else 0
		var sw = 1 if corners.get("SW", "lower") == "upper" else 0
		var se = 1 if corners.get("SE", "lower") == "upper" else 0
		var wang_idx = nw * 8 + ne * 4 + sw * 2 + se
		
		# Store the mapping
		wang_map[wang_idx] = atlas_coords
		
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, nw)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, ne)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, sw)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, se)
	
	# Cache the Wang mapping for this biome
	if biome != "":
		_wang_maps[biome] = wang_map
		print("TilesetLoader: Built Wang map for '%s' with %d entries: %s" % [biome, wang_map.size(), wang_map])
	
	tileset.add_source(source)
	return tileset

static func _desquare_atlas_borders(img: Image, tile_size: int) -> void:
	if img == null or tile_size <= 2:
		return
	var w := img.get_width()
	var h := img.get_height()
	if w < tile_size or h < tile_size:
		return
	# Snap border pixels to neighboring interior pixels for each tile cell.
	for ty in range(0, h, tile_size):
		for tx in range(0, w, tile_size):
			var x0 := tx
			var y0 := ty
			var x1 := mini(tx + tile_size - 1, w - 1)
			var y1 := mini(ty + tile_size - 1, h - 1)
			if x1 - x0 < 2 or y1 - y0 < 2:
				continue
			# Top / bottom rows
			for x in range(x0, x1 + 1):
				img.set_pixel(x, y0, img.get_pixel(x, y0 + 1))
				img.set_pixel(x, y1, img.get_pixel(x, y1 - 1))
			# Left / right columns
			for y in range(y0, y1 + 1):
				img.set_pixel(x0, y, img.get_pixel(x0 + 1, y))
				img.set_pixel(x1, y, img.get_pixel(x1 - 1, y))


static func create_procedural_tileset(biome: String, tile_size: int = 32) -> TileSet:
	"""Create a procedural fallback tileset for a biome."""
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(tile_size, tile_size)
	
	var colors = _get_biome_colors(biome)
	var atlas = _generate_biome_atlas(colors, tile_size)
	var texture = ImageTexture.create_from_image(atlas)
	
	var source = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(tile_size, tile_size)
	
	# Add terrain set (corner-only for Wang tiles)
	tileset.add_terrain_set(0)
	tileset.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	tileset.add_terrain(0, 0)
	tileset.set_terrain_name(0, 0, "Ground")
	tileset.set_terrain_color(0, 0, colors.base)
	tileset.add_terrain(0, 1)
	tileset.set_terrain_name(0, 1, "Feature")
	tileset.set_terrain_color(0, 1, colors.feature)
	
	# Build Wang map for procedural tileset
	var wang_map: Dictionary = {}
	
	# Create tiles from atlas (4x4 grid)
	# Wang index = NW*8 + NE*4 + SW*2 + SE
	for i in range(16):
		var x = i % 4
		var y = i / 4
		var coords = Vector2i(x, y)
		source.create_tile(coords)
		
		var td := source.get_tile_data(coords, 0)
		if td == null:
			continue
		
		# Decode Wang index to corners
		var nw = (i >> 3) & 1
		var ne = (i >> 2) & 1
		var sw = (i >> 1) & 1
		var se = i & 1
		
		wang_map[i] = coords
		
		td.terrain_set = 0
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, nw)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, ne)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, sw)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, se)
	
	# Cache the Wang mapping
	_wang_maps[biome] = wang_map
	
	tileset.add_source(source)
	return tileset


static func _get_biome_colors(biome: String) -> Dictionary:
	match biome:
		"graveyard":
			return {
				"base": Color(0.06, 0.10, 0.08),
				"feature": Color(0.15, 0.20, 0.14),
				"accent": Color(0.2, 0.4, 0.3)
			}
		"library", "arcane_ruins":
			return {
				"base": Color(0.08, 0.08, 0.14),
				"feature": Color(0.15, 0.12, 0.25),
				"accent": Color(0.5, 0.3, 0.8)
			}
		"foundry":
			return {
				"base": Color(0.10, 0.06, 0.06),
				"feature": Color(0.20, 0.10, 0.08),
				"accent": Color(1.0, 0.5, 0.2)
			}
		"cathedral":
			return {
				"base": Color(0.11, 0.11, 0.13),
				"feature": Color(0.20, 0.20, 0.24),
				"accent": Color(0.82, 0.82, 0.90)
			}
		_:
			return {
				"base": Color(0.1, 0.1, 0.1),
				"feature": Color(0.2, 0.2, 0.2),
				"accent": Color(0.5, 0.5, 0.5)
			}


static func _generate_biome_atlas(colors: Dictionary, tile_size: int) -> Image:
	"""Generate a 4x4 tile atlas procedurally."""
	var atlas_size = tile_size * 4
	var img = Image.create(atlas_size, atlas_size, false, Image.FORMAT_RGBA8)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(colors.base))
	
	# Generate 16 Wang tiles
	for tile_idx in range(16):
		var tx = (tile_idx % 4) * tile_size
		var ty = (tile_idx / 4) * tile_size
		
		# Decode corners from Wang index
		var nw = (tile_idx >> 3) & 1
		var ne = (tile_idx >> 2) & 1
		var sw = (tile_idx >> 1) & 1
		var se = tile_idx & 1
		
		# Draw tile with bilinear corner interpolation
		for px in range(tile_size):
			for py in range(tile_size):
				var fx = float(px) / tile_size
				var fy = float(py) / tile_size
				
				# Bilinear interpolation of corners
				var top = nw * (1.0 - fx) + ne * fx
				var bottom = sw * (1.0 - fx) + se * fx
				var blend = top * (1.0 - fy) + bottom * fy
				
				# Interpolate colors
				var c = colors.base.lerp(colors.feature, blend)
				
				# Add noise
				var noise_val = rng.randf() * 0.08 - 0.04
				c.r = clampf(c.r + noise_val, 0.0, 1.0)
				c.g = clampf(c.g + noise_val, 0.0, 1.0)
				c.b = clampf(c.b + noise_val, 0.0, 1.0)
				
				img.set_pixel(tx + px, ty + py, c)
	
	return img

