extends Node2D
class_name TileMapWorld

# Tile-based map renderer using actual tiles instead of shaders.
# Procedurally generates terrain using Godot's TileMapLayer terrain system.

@export var map_size: Vector2 = Vector2(4800, 3600)
@export var biome: String = "graveyard" # graveyard | library | foundry
@export var seed_value: int = 0

@export var prop_count: int = 80  # More scenery!
@export var prop_min_dist_from_center: float = 250.0

# Tileset JSON metadata + PNG paths per biome
# Keys match theme_id from maps.json and map IDs
const TILESET_DATA = {
	"graveyard": {
		"metadata": "res://tilesets/graveyard_metadata.json",
		"image": "res://tilesets/graveyard_image.png"
	},
	"library": {
		"metadata": "res://tilesets/library_metadata.json",
		"image": "res://tilesets/library_image.png"
	},
	"arcane_ruins": {  # theme_id for library map
		"metadata": "res://tilesets/library_metadata.json",
		"image": "res://tilesets/library_image.png"
	},
	"foundry": {
		"metadata": "res://tilesets/foundry_metadata.json",
		"image": "res://tilesets/foundry_image.png"
	}
}

# Props per biome (keys match theme_id from maps.json)
const PROPS = {
	"graveyard": [
		"res://assets/map_props/gravestone.png",
		"res://assets/map_props/dead_tree.png",
		"res://assets/structures/obelisk_sheet.png",
		"res://assets/structures/green_fountain_sheet.png"
	],
	"library": [
		"res://assets/map_props/magic_book.png",
		"res://assets/map_props/crystal_pillar.png",
		"res://assets/structures/arcane_cube_sheet.png",
		"res://assets/structures/obelisk_sheet.png"
	],
	"arcane_ruins": [
		"res://assets/map_props/magic_book.png",
		"res://assets/map_props/crystal_pillar.png",
		"res://assets/structures/arcane_cube_sheet.png",
		"res://assets/structures/obelisk_sheet.png"
	],
	"foundry": [
		"res://assets/map_props/anvil.png",
		"res://assets/map_props/cauldron.png",
		"res://assets/structures/obelisk_sheet.png"
	]
}

var _rng: RandomNumberGenerator
var _tile_map: TileMapLayer
var _props_node: Node2D
var _fog: Sprite2D

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value if seed_value != 0 else hash(biome + str(Time.get_ticks_msec()))
	
	# Add a solid background color first (lowest z-order)
	_add_background_color()
	
	_setup_tilemap()
	_generate_terrain()
	_spawn_props()
	_setup_fog()

func _add_background_color() -> void:
	# Add solid background as the base layer - make it huge to cover all camera views
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block game input!
	bg.color = _get_biome_base_color()
	bg.size = map_size * 3.0  # 3x the map size to cover any camera position
	bg.position = -map_size * 1.5
	bg.z_index = -100
	add_child(bg)

func _setup_tilemap() -> void:
	_tile_map = TileMapLayer.new()
	_tile_map.name = "TerrainLayer"
	_tile_map.z_index = -50  # Behind props and characters
	_tile_map.modulate = _get_tilemap_modulate()  # Brighten dark tilesets
	add_child(_tile_map)
	
	var data: Dictionary = TILESET_DATA.get(biome, TILESET_DATA["graveyard"])
	var metadata_path: String = data.get("metadata", "")
	var image_path: String = data.get("image", "")
	
	# Try to load real tileset from PixelLab data
	# Use FileAccess to check existence (works even if not imported by Godot)
	var json_exists := FileAccess.file_exists(metadata_path)
	var img_exists := FileAccess.file_exists(image_path)
	print("TileMapWorld: Checking files - JSON: %s (%s), IMG: %s (%s)" % [metadata_path, json_exists, image_path, img_exists])
	
	if json_exists and img_exists:
		print("TileMapWorld: Loading tileset from %s" % metadata_path)
		var tileset = TilesetLoader.load_tileset(metadata_path, image_path, biome)
		if tileset != null:
			_tile_map.tile_set = tileset
			print("TileMapWorld: Tileset loaded successfully for biome: %s" % biome)
			return
		else:
			push_error("TileMapWorld: Failed to load tileset from metadata")
	else:
		push_warning("TileMapWorld: Tileset files not found - JSON exists: %s, IMG exists: %s" % [json_exists, img_exists])
	
	# Fallback to procedural tileset
	push_warning("TileMapWorld: Using procedural tileset for biome: %s" % biome)
	_tile_map.tile_set = TilesetLoader.create_procedural_tileset(biome)

func _get_tilemap_modulate() -> Color:
	# Brighten tiles that were generated too dark
	match biome:
		"graveyard":
			return Color(1.8, 1.7, 1.5, 1.0)  # Strong brightness boost
		"library", "arcane_ruins":
			return Color(1.4, 1.4, 1.5, 1.0)  # Cool brightness
		"foundry":
			return Color(1.5, 1.4, 1.3, 1.0)  # Warm glow
		_:
			return Color(1.4, 1.4, 1.4, 1.0)


func _get_biome_base_color() -> Color:
	match biome:
		"graveyard":
			return Color(0.18, 0.22, 0.16)  # Brighter mossy green-brown
		"library", "arcane_ruins":
			return Color(0.12, 0.14, 0.22)  # Brighter purple-blue
		"foundry":
			return Color(0.18, 0.12, 0.10)  # Brighter rust-orange
		_:
			return Color(0.15, 0.15, 0.15)

func _generate_terrain() -> void:
	if _tile_map == null:
		push_error("TileMapWorld: TileMap is null!")
		return
	if _tile_map.tile_set == null:
		push_error("TileMapWorld: No tileset available!")
		return
	
	print("TileMapWorld: Generating terrain with tileset (tile_size: %s)" % _tile_map.tile_set.tile_size)
	var tile_size = _tile_map.tile_set.tile_size.x
	
	# Extra padding to ensure full coverage beyond visible area
	var padding := 20  # Extra tiles in each direction
	var half_w = int(map_size.x / 2 / tile_size) + padding
	var half_h = int(map_size.y / 2 / tile_size) + padding
	
	# Build a terrain grid (0 = lower, 1 = upper) with clusters
	var terrain_grid: Dictionary = {}
	for x in range(-half_w - 1, half_w + 2):
		for y in range(-half_h - 1, half_h + 2):
			terrain_grid[Vector2i(x, y)] = 0
	
	# Add organic clusters of upper terrain - more clusters for visual interest
	var num_clusters = int(_rng.randf_range(25, 40))
	for _i in range(num_clusters):
		var cx = _rng.randi_range(-half_w + 5, half_w - 5)
		var cy = _rng.randi_range(-half_h + 5, half_h - 5)
		var cluster_size = _rng.randi_range(5, 14)
		for dx in range(-cluster_size, cluster_size + 1):
			for dy in range(-cluster_size, cluster_size + 1):
				var dist = sqrt(dx * dx + dy * dy)
				var threshold = cluster_size * (0.5 + _rng.randf() * 0.5)
				if dist < threshold:
					terrain_grid[Vector2i(cx + dx, cy + dy)] = 1
	
	# Place tiles based on corner terrain values (Wang tiling)
	var tiles_placed := 0
	for x in range(-half_w, half_w + 1):
		for y in range(-half_h, half_h + 1):
			var cell = Vector2i(x, y)
			# Sample corners (NW, NE, SW, SE)
			var nw = terrain_grid.get(Vector2i(x, y), 0)
			var ne = terrain_grid.get(Vector2i(x + 1, y), 0)
			var sw = terrain_grid.get(Vector2i(x, y + 1), 0)
			var se = terrain_grid.get(Vector2i(x + 1, y + 1), 0)
			
			# Calculate Wang index
			var wang_idx = nw * 8 + ne * 4 + sw * 2 + se
			
			# Find the tile with matching corners in our tileset
			var atlas_coords = _wang_to_atlas(wang_idx)
			_tile_map.set_cell(cell, 0, atlas_coords)
			tiles_placed += 1
	
	print("TileMapWorld: Placed %d tiles over %dx%d area" % [tiles_placed, half_w * 2, half_h * 2])

func _wang_to_atlas(wang_idx: int) -> Vector2i:
	# Get the Wang mapping built during tileset loading
	var wang_map: Dictionary = TilesetLoader.get_wang_map(biome)
	
	if wang_map.has(wang_idx):
		return wang_map[wang_idx]
	
	# Fallback: use the "all lower" tile for any missing index
	# This ensures the entire map is covered with at least base terrain
	if wang_map.has(0):
		return wang_map[0]
	
	# If no wang_map at all, use a simple grid layout
	return Vector2i(wang_idx % 4, wang_idx / 4)

func _spawn_props() -> void:
	_props_node = Node2D.new()
	_props_node.name = "Props"
	add_child(_props_node)
	
	var prop_paths = PROPS.get(biome, PROPS["graveyard"])
	var available_textures: Array[Texture2D] = []
	
	for path in prop_paths:
		if ResourceLoader.exists(path):
			available_textures.append(load(path))
	
	# If no props available, create simple procedural ones
	if available_textures.is_empty():
		available_textures.append(_create_procedural_prop())
	
	var half_w = map_size.x / 2
	var half_h = map_size.y / 2
	var center_exclusion_sq = prop_min_dist_from_center * prop_min_dist_from_center
	
	# Spawn main props (gravestones, trees, etc)
	for _i in range(prop_count):
		var pos = Vector2(
			_rng.randf_range(-half_w + 100, half_w - 100),
			_rng.randf_range(-half_h + 100, half_h - 100)
		)
		
		# Skip if too close to center
		if pos.length_squared() < center_exclusion_sq:
			continue
		
		var spr = Sprite2D.new()
		spr.texture = available_textures[_rng.randi() % available_textures.size()]
		spr.position = pos
		spr.z_index = int(pos.y)  # Y-sorting
		spr.modulate.a = _rng.randf_range(0.7, 1.0)
		
		# Random scale variation
		var scale_factor = _rng.randf_range(0.8, 1.2)
		spr.scale = Vector2(scale_factor, scale_factor)
		
		_props_node.add_child(spr)
	
	# Spawn extra scenery (grass tufts, rocks, bones, etc)
	_spawn_scenery_details(half_w, half_h, center_exclusion_sq)

func _spawn_scenery_details(half_w: float, half_h: float, center_exclusion_sq: float) -> void:
	# Spawn lots of small scenery for visual interest
	var detail_count := prop_count * 3  # 3x more small details than props
	
	for _i in range(detail_count):
		var pos = Vector2(
			_rng.randf_range(-half_w + 50, half_w - 50),
			_rng.randf_range(-half_h + 50, half_h - 50)
		)
		
		# Allow closer to center for small details
		if pos.length_squared() < center_exclusion_sq * 0.4:
			continue
		
		var spr = Sprite2D.new()
		var roll := _rng.randf()
		
		if roll < 0.4:
			spr.texture = _create_grass_tuft()
		elif roll < 0.65:
			spr.texture = _create_small_rock()
		elif roll < 0.8:
			spr.texture = _create_bone_scatter() if biome == "graveyard" else _create_small_rock()
		else:
			spr.texture = _create_debris()
		
		spr.position = pos
		spr.z_index = int(pos.y) - 10  # Behind main props
		spr.modulate.a = _rng.randf_range(0.5, 0.85)
		
		var scale_factor = _rng.randf_range(0.5, 1.0)
		spr.scale = Vector2(scale_factor, scale_factor)
		spr.rotation = _rng.randf() * TAU if _rng.randf() < 0.3 else 0.0
		
		_props_node.add_child(spr)

func _create_grass_tuft() -> Texture2D:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	var green := Color(0.3, 0.5, 0.25) if biome == "graveyard" else Color(0.2, 0.4, 0.3)
	if biome == "foundry":
		green = Color(0.35, 0.3, 0.25)  # Brown-ish dead grass
	
	# Draw grass blades
	for blade in range(_rng.randi_range(3, 6)):
		var bx := _rng.randi_range(3, size - 4)
		var height := _rng.randi_range(6, 12)
		var blade_green := green.lightened(_rng.randf() * 0.3 - 0.15)
		for y in range(size - 1, size - height - 1, -1):
			var wobble := int(_rng.randf() * 2 - 1) if y < size - 4 else 0
			if bx + wobble >= 0 and bx + wobble < size and y >= 0:
				img.set_pixel(bx + wobble, y, blade_green)
	
	return ImageTexture.create_from_image(img)

func _create_small_rock() -> Texture2D:
	var size := 12
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	var base := Color(0.4, 0.38, 0.35)
	if biome == "library" or biome == "arcane_ruins":
		base = Color(0.35, 0.35, 0.45)
	elif biome == "foundry":
		base = Color(0.45, 0.35, 0.30)
	
	var cx := size / 2
	var cy := size / 2
	var rx := _rng.randi_range(3, 5)
	var ry := _rng.randi_range(2, 4)
	
	for x in range(size):
		for y in range(size):
			var dx := float(x - cx) / float(rx)
			var dy := float(y - cy) / float(ry)
			if dx * dx + dy * dy <= 1.0:
				var shade := 1.0 - (dy * 0.3)
				var c := base.lightened(shade * 0.15 + _rng.randf() * 0.1 - 0.05)
				img.set_pixel(x, y, c)
	
	return ImageTexture.create_from_image(img)

func _create_bone_scatter() -> Texture2D:
	var size := 14
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	var bone := Color(0.85, 0.82, 0.75)
	
	# Draw random bone shapes
	if _rng.randf() < 0.5:
		# Small skull
		for x in range(4, 10):
			for y in range(3, 9):
				var dx := float(x - 7)
				var dy := float(y - 6)
				if dx * dx / 9 + dy * dy / 6 <= 1.0:
					img.set_pixel(x, y, bone.darkened(_rng.randf() * 0.1))
		# Eye sockets
		img.set_pixel(5, 5, Color(0.2, 0.15, 0.1))
		img.set_pixel(8, 5, Color(0.2, 0.15, 0.1))
	else:
		# Long bone
		var angle := _rng.randf() * PI
		for t in range(10):
			var px := int(7 + cos(angle) * (t - 5))
			var py := int(7 + sin(angle) * (t - 5))
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, bone.darkened(_rng.randf() * 0.1))
	
	return ImageTexture.create_from_image(img)

func _create_debris() -> Texture2D:
	var size := 10
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	var base := _get_biome_base_color().lightened(0.1)
	
	# Scatter random pixels
	for _p in range(_rng.randi_range(8, 15)):
		var x := _rng.randi_range(1, size - 2)
		var y := _rng.randi_range(1, size - 2)
		var c := base.lightened(_rng.randf() * 0.3 - 0.15)
		img.set_pixel(x, y, c)
		if _rng.randf() < 0.3:
			img.set_pixel(x + 1, y, c.darkened(0.1))
	
	return ImageTexture.create_from_image(img)

func _create_procedural_prop() -> Texture2D:
	# Create a simple procedural prop (rock/stone)
	var size = 32
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	
	var base_color = _get_biome_base_color().lightened(0.2)
	
	for x in range(size):
		for y in range(size):
			var cx = x - size / 2
			var cy = y - size / 2
			var dist = sqrt(cx * cx + cy * cy * 0.7)  # Slightly oval
			
			if dist < size * 0.35:
				var shade = 1.0 - (dist / (size * 0.35)) * 0.3
				shade += _rng.randf() * 0.1 - 0.05
				var c = base_color
				c.r = clampf(c.r * shade, 0.0, 1.0)
				c.g = clampf(c.g * shade, 0.0, 1.0)
				c.b = clampf(c.b * shade, 0.0, 1.0)
				img.set_pixel(x, y, c)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	
	return ImageTexture.create_from_image(img)

func _setup_fog() -> void:
	_fog = Sprite2D.new()
	_fog.name = "Fog"
	add_child(_fog)
	
	# Create fog texture
	var fog_size = 256
	var img = Image.create(fog_size, fog_size, false, Image.FORMAT_RGBA8)
	
	var fog_color = _get_fog_color()
	
	for x in range(fog_size):
		for y in range(fog_size):
			var cx = float(x) / fog_size - 0.5
			var cy = float(y) / fog_size - 0.5
			var dist = sqrt(cx * cx + cy * cy) * 2.0
			
			var alpha = clampf(dist * dist * 0.3, 0.0, 0.25)
			img.set_pixel(x, y, Color(fog_color.r, fog_color.g, fog_color.b, alpha))
	
	_fog.texture = ImageTexture.create_from_image(img)
	_fog.scale = map_size / Vector2(fog_size, fog_size) * 1.5
	_fog.z_index = 100

func _get_fog_color() -> Color:
	match biome:
		"graveyard":
			return Color(0.3, 0.5, 0.4)
		"library", "arcane_ruins":
			return Color(0.4, 0.5, 0.75)
		"foundry":
			return Color(1.0, 0.5, 0.3)
		_:
			return Color(0.5, 0.5, 0.5)

func _process(delta: float) -> void:
	# Keep fog centered on camera
	var cam = get_viewport().get_camera_2d()
	if cam != null and _fog != null:
		_fog.global_position = cam.global_position

