extends Node2D

# TileMap-based map renderer using user-provided tileset atlases.
# Keep this removable: Main.gd will gate instantiation behind a single bool.
#
# NOTE: This is a lightweight “best effort” auto-slicer + auto-composer.
# It uses color heuristics to pick likely ground/path/prop tiles.

@export var theme_id: String = "graveyard" # graveyard/dungeon/ruins/swamp/crystal_cave/void
@export var tile_size: int = 32
@export var map_size: Vector2 = Vector2(3200, 2000) # pixels
@export var seed: int = 0

@export var path_width_tiles: int = 3
@export var prop_density: float = 0.020 # per-tile chance

var _rng: RandomNumberGenerator
var _ground: TileMap
var _props: TileMap

var _source_id: int = -1
var _atlas: TileSetAtlasSource
var _tileset: TileSet

var _grid_start: Vector2i = Vector2i.ZERO
var _grid_cols: int = 0
var _grid_rows: int = 0

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(Time.get_unix_time_from_system()) if seed == 0 else seed

	_ground = TileMap.new()
	_ground.name = "Ground"
	_ground.z_index = -100
	add_child(_ground)

	_props = TileMap.new()
	_props.name = "Props"
	_props.z_index = -95
	add_child(_props)

	var origin := Vector2(-map_size.x * 0.5, -map_size.y * 0.5)
	_ground.position = origin
	_props.position = origin

	_build_tileset_from_atlas()
	_generate_layout()

func _tileset_path() -> String:
	# Convention from your folder.
	var p := "res://assets/tilesets/%s_tileset.png" % theme_id
	if ResourceLoader.exists(p):
		return p
	# fallback: attempt exact file
	p = "res://assets/tilesets/%s.png" % theme_id
	return p

func _build_tileset_from_atlas() -> void:
	var tex_path := _tileset_path()
	if tex_path == "" or not ResourceLoader.exists(tex_path):
		push_warning("MapTilesetRenderer: missing tileset texture for theme '%s'" % theme_id)
		return
	var tex := load(tex_path) as Texture2D
	if tex == null:
		return

	var img := tex.get_image()
	if img == null:
		return

	_grid_start = _detect_grid_start(img)
	_grid_cols = maxi(0, int(floor(float(img.get_width() - _grid_start.x) / float(tile_size))))
	_grid_rows = maxi(0, int(floor(float(img.get_height() - _grid_start.y) / float(tile_size))))
	if _grid_cols <= 0 or _grid_rows <= 0:
		push_warning("MapTilesetRenderer: could not detect atlas grid for %s" % tex_path)
		return

	_tileset = TileSet.new()
	_atlas = TileSetAtlasSource.new()
	_atlas.texture = tex
	_atlas.texture_region_size = Vector2i(tile_size, tile_size)
	# Skip title/blank area by using margins.
	_atlas.margins = _grid_start
	_atlas.separation = Vector2i(0, 0)

	_source_id = _tileset.add_source(_atlas)

	# Create tiles for the full grid (so we can reference by atlas coords).
	for y in range(_grid_rows):
		for x in range(_grid_cols):
			_atlas.create_tile(Vector2i(x, y))

	_ground.tile_set = _tileset
	_props.tile_set = _tileset

func _detect_grid_start(img: Image) -> Vector2i:
	# Heuristic: find the first “mostly black” horizontal and vertical lines that indicate grid borders.
	# Works well on these tilesets which have solid black tile outlines.
	var w := img.get_width()
	var h := img.get_height()

	var start_y := 0
	for y in range(h):
		var black: int = 0
		var sample_step := 4
		for x in range(0, w, sample_step):
			var c := img.get_pixel(x, y)
			if c.a > 0.2 and c.r < 0.12 and c.g < 0.12 and c.b < 0.12:
				black += 1
		var ratio := float(black) / maxf(1.0, float(w / sample_step))
		if ratio > 0.70:
			start_y = y + 1
			break

	var start_x := 0
	for x in range(w):
		var black2: int = 0
		var sample_step2 := 4
		for y in range(0, h, sample_step2):
			var c2 := img.get_pixel(x, y)
			if c2.a > 0.2 and c2.r < 0.12 and c2.g < 0.12 and c2.b < 0.12:
				black2 += 1
		var ratio2 := float(black2) / maxf(1.0, float(h / sample_step2))
		if ratio2 > 0.55:
			start_x = x + 1
			break

	# Clamp to grid.
	start_x = maxi(0, start_x)
	start_y = maxi(0, start_y)
	return Vector2i(start_x, start_y)

func _score_tile(img: Image, atlas_xy: Vector2i) -> Dictionary:
	# Sample a handful of pixels to classify tiles roughly.
	var x0 := _grid_start.x + atlas_xy.x * tile_size
	var y0 := _grid_start.y + atlas_xy.y * tile_size
	var samples := 0
	var a_sum := 0.0
	var r_sum := 0.0
	var g_sum := 0.0
	var b_sum := 0.0

	var step := 6
	for yy in range(2, tile_size - 2, step):
		for xx in range(2, tile_size - 2, step):
			var c := img.get_pixel(x0 + xx, y0 + yy)
			samples += 1
			a_sum += c.a
			r_sum += c.r
			g_sum += c.g
			b_sum += c.b

	var a_avg := a_sum / maxf(1.0, float(samples))
	var r_avg := r_sum / maxf(1.0, float(samples))
	var g_avg := g_sum / maxf(1.0, float(samples))
	var b_avg := b_sum / maxf(1.0, float(samples))

	var green_score := g_avg - (r_avg + b_avg) * 0.5
	var brown_score := (r_avg + g_avg) * 0.5 - b_avg
	var dark_score := 1.0 - (r_avg + g_avg + b_avg) / 3.0
	return {
		"a": a_avg,
		"green": green_score,
		"brown": brown_score,
		"dark": dark_score
	}

func _pick_tile_set(img: Image) -> Dictionary:
	# Choose candidate tiles for ground/path/props.
	var ground: Array[Vector2i] = []
	var path: Array[Vector2i] = []
	var props: Array[Vector2i] = []

	var scored: Array = []
	for y in range(_grid_rows):
		for x in range(_grid_cols):
			var xy := Vector2i(x, y)
			var s := _score_tile(img, xy)
			# Skip near-empty tiles.
			if float(s["a"]) < 0.05:
				continue
			scored.append({"xy": xy, "s": s})

	# Sort by green for ground candidates.
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float((a["s"] as Dictionary)["green"]) > float((b["s"] as Dictionary)["green"])
	)
	for i in range(mini(10, scored.size())):
		ground.append((scored[i]["xy"] as Vector2i))

	# Sort by brown for path candidates.
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float((a["s"] as Dictionary)["brown"]) > float((b["s"] as Dictionary)["brown"])
	)
	for i in range(mini(8, scored.size())):
		path.append((scored[i]["xy"] as Vector2i))

	# Props: high alpha, not very green, not very brown.
	for e in scored:
		var s := e["s"] as Dictionary
		var a := float(s["a"])
		var g := float(s["green"])
		var br := float(s["brown"])
		if a > 0.18 and g < 0.05 and br < 0.20:
			props.append(e["xy"] as Vector2i)
	# Keep only a subset for variety.
	props.shuffle()
	props = props.slice(0, mini(24, props.size()))

	return {"ground": ground, "path": path, "props": props}

func _generate_layout() -> void:
	if _tileset == null or _atlas == null or _source_id < 0:
		return
	var tex_path := _tileset_path()
	var tex := load(tex_path) as Texture2D
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return

	var picks := _pick_tile_set(img)
	var ground_tiles: Array[Vector2i] = picks["ground"]
	var path_tiles: Array[Vector2i] = picks["path"]
	var prop_tiles: Array[Vector2i] = picks["props"]
	if ground_tiles.is_empty():
		ground_tiles = [Vector2i(0, 0)]
	if path_tiles.is_empty():
		path_tiles = ground_tiles

	var w_tiles := maxi(8, int(floor(map_size.x / float(tile_size))))
	var h_tiles := maxi(8, int(floor(map_size.y / float(tile_size))))

	# Base fill
	for y in range(h_tiles):
		for x in range(w_tiles):
			var at := ground_tiles[_rng.randi_range(0, ground_tiles.size() - 1)]
			_ground.set_cell(0, Vector2i(x, y), _source_id, at)

	# Compose a main “play arena” + a winding path (Vampire Survivors-ish readability).
	var cx := w_tiles / 2
	var cy := h_tiles / 2
	var arena_r := int(minf(float(w_tiles), float(h_tiles)) * 0.22)

	for y in range(h_tiles):
		for x in range(w_tiles):
			var dx := float(x - cx)
			var dy := float(y - cy)
			var d := sqrt(dx * dx + dy * dy)
			# central clearing (slightly brighter path)
			if d <= float(arena_r):
				var at2 := path_tiles[_rng.randi_range(0, path_tiles.size() - 1)]
				_ground.set_cell(0, Vector2i(x, y), _source_id, at2)

	# Cross path
	var pw := maxi(1, path_width_tiles)
	for y in range(h_tiles):
		for x in range(cx - pw, cx + pw + 1):
			var at3 := path_tiles[_rng.randi_range(0, path_tiles.size() - 1)]
			_ground.set_cell(0, Vector2i(x, y), _source_id, at3)
	for x in range(w_tiles):
		for y in range(cy - pw, cy + pw + 1):
			var at4 := path_tiles[_rng.randi_range(0, path_tiles.size() - 1)]
			_ground.set_cell(0, Vector2i(x, y), _source_id, at4)

	# Props: avoid the immediate center for visibility.
	for y in range(1, h_tiles - 1):
		for x in range(1, w_tiles - 1):
			if prop_tiles.is_empty():
				break
			var dx := float(x - cx)
			var dy := float(y - cy)
			var d := sqrt(dx * dx + dy * dy)
			if d < float(arena_r) * 0.7:
				continue
			if _rng.randf() < prop_density:
				var atp := prop_tiles[_rng.randi_range(0, prop_tiles.size() - 1)]
				_props.set_cell(0, Vector2i(x, y), _source_id, atp)


