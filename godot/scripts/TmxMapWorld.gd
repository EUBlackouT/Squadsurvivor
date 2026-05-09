extends Node2D
class_name TmxMapWorld

@export var tmx_path: String = ""
@export var map_size: Vector2 = Vector2(4800, 3600)

var _built: bool = false
var _tile_width: int = 48
var _tile_height: int = 48
var _origin_tile: Vector2i = Vector2i.ZERO
var _world_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(4800, 3600))
var _spawn_point: Vector2 = Vector2.ZERO
var _walkable_points: Array[Vector2] = []
var _blockers: Array[Rect2] = []

var _layers_data: Array[Dictionary] = []
var _object_groups: Array[Dictionary] = []
var _tilesets: Array[Dictionary] = []
var _collision_root: Node2D = null

func _ready() -> void:
	build_if_needed()

func build_if_needed() -> void:
	if _built:
		return
	_built = true
	_build()

func get_default_spawn() -> Vector2:
	return _spawn_point

func get_world_size() -> Vector2:
	return _world_rect.size

func get_world_rect() -> Rect2:
	return _world_rect

func get_random_spawn_around(center: Vector2, min_radius: float, max_radius: float, rng: RandomNumberGenerator) -> Vector2:
	if _walkable_points.is_empty():
		return center
	var lo := minf(min_radius, max_radius)
	var hi := maxf(min_radius, max_radius)
	var lo2 := lo * lo
	var hi2 := hi * hi
	for _i in range(64):
		var p := _walkable_points[rng.randi_range(0, _walkable_points.size() - 1)]
		var d2 := p.distance_squared_to(center)
		if d2 >= lo2 and d2 <= hi2 and _is_point_walkable(p):
			return p
	for _j in range(64):
		var p2 := _walkable_points[rng.randi_range(0, _walkable_points.size() - 1)]
		if _is_point_walkable(p2):
			return p2
	return center

func _is_point_walkable(p: Vector2) -> bool:
	for r in _blockers:
		if r.has_point(p):
			return false
	return true

func _build() -> void:
	if tmx_path.is_empty():
		push_warning("TmxMapWorld: tmx_path is empty")
		return
	if not FileAccess.file_exists(tmx_path):
		push_warning("TmxMapWorld: missing TMX at %s" % tmx_path)
		return

	_parse_tmx(tmx_path)
	_build_tileset_and_layers()
	_build_blockers_and_spawn()

func _parse_tmx(path: String) -> void:
	var parser := XMLParser.new()
	var err := parser.open(path)
	if err != OK:
		push_warning("TmxMapWorld: failed to open %s (err=%d)" % [path, err])
		return

	var current_layer: Dictionary = {}
	var in_data := false
	var pending_chunk: Dictionary = {}
	var current_object_group: Dictionary = {}

	while parser.read() == OK:
		var node_type := parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var n := parser.get_node_name()
			if n == "map":
				_tile_width = int(parser.get_named_attribute_value_safe("tilewidth"))
				_tile_height = int(parser.get_named_attribute_value_safe("tileheight"))
			elif n == "tileset":
				var ts := {
					"firstgid": int(parser.get_named_attribute_value_safe("firstgid")),
					"source": String(parser.get_named_attribute_value_safe("source"))
				}
				_tilesets.append(ts)
			elif n == "layer":
				current_layer = {
					"name": String(parser.get_named_attribute_value_safe("name")),
					"cells": {}
				}
			elif n == "data":
				in_data = true
			elif n == "chunk" and in_data:
				pending_chunk = {
					"x": int(parser.get_named_attribute_value_safe("x")),
					"y": int(parser.get_named_attribute_value_safe("y"))
				}
			elif n == "objectgroup":
				current_object_group = {
					"name": String(parser.get_named_attribute_value_safe("name")),
					"objects": []
				}
			elif n == "object":
				var obj := {
					"name": String(parser.get_named_attribute_value_safe("name")),
					"type": String(parser.get_named_attribute_value_safe("type")),
					"x": float(parser.get_named_attribute_value_safe("x")),
					"y": float(parser.get_named_attribute_value_safe("y")),
					"width": float(parser.get_named_attribute_value_safe("width")),
					"height": float(parser.get_named_attribute_value_safe("height")),
					"gid": int(parser.get_named_attribute_value_safe("gid"))
				}
				(current_object_group["objects"] as Array).append(obj)

		elif node_type == XMLParser.NODE_TEXT and in_data and not current_layer.is_empty() and not pending_chunk.is_empty():
			var csv := parser.get_node_data().strip_edges()
			if csv != "":
				var vals := csv.split(",", false)
				var idx := 0
				for s in vals:
					var v := int(String(s).strip_edges())
					var tx: int = int(pending_chunk["x"]) + (idx % 16)
					var ty: int = int(pending_chunk["y"]) + int(idx / 16)
					if v != 0:
						(current_layer["cells"] as Dictionary)[Vector2i(tx, ty)] = v
					idx += 1

		elif node_type == XMLParser.NODE_ELEMENT_END:
			var en := parser.get_node_name()
			if en == "data":
				in_data = false
				pending_chunk = {}
			elif en == "layer":
				_layers_data.append(current_layer)
				current_layer = {}
			elif en == "objectgroup":
				_object_groups.append(current_object_group)
				current_object_group = {}

func _build_tileset_and_layers() -> void:
	if _layers_data.is_empty():
		return

	var min_x := 1 << 30
	var min_y := 1 << 30
	var max_x := -(1 << 30)
	var max_y := -(1 << 30)
	for l in _layers_data:
		var cells: Dictionary = l.get("cells", {})
		for c in cells.keys():
			var v := c as Vector2i
			min_x = mini(min_x, v.x)
			min_y = mini(min_y, v.y)
			max_x = maxi(max_x, v.x)
			max_y = maxi(max_y, v.y)
	if min_x > max_x or min_y > max_y:
		return

	_origin_tile = Vector2i(int(round((min_x + max_x) * 0.5)), int(round((min_y + max_y) * 0.5)))
	var w_tiles := (max_x - min_x + 1)
	var h_tiles := (max_y - min_y + 1)
	_world_rect = Rect2(Vector2(-0.5 * w_tiles * _tile_width, -0.5 * h_tiles * _tile_height), Vector2(w_tiles * _tile_width, h_tiles * _tile_height))
	map_size = _world_rect.size

	_tilesets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("firstgid", 0)) < int(b.get("firstgid", 0))
	)

	var ts_meta: Array[Dictionary] = []
	var ts_resolved: Array[Dictionary] = []
	for i in range(_tilesets.size()):
		var t := _tilesets[i]
		var first := int(t.get("firstgid", 0))
		var source_rel := String(t.get("source", ""))
		var tsx_abs := _resolve_rel_path(tmx_path, source_rel)
		var meta := _parse_tsx_meta(tsx_abs)
		if meta.is_empty():
			continue
		meta["firstgid"] = first
		ts_meta.append(meta)

		var tex: Texture2D = load(meta["image_path"])
		if tex == null:
			push_warning("TmxMapWorld: missing texture %s" % meta["image_path"])
			continue

		var atlas := TileSetAtlasSource.new()
		atlas.texture = tex
		atlas.texture_region_size = Vector2i(_tile_width, _tile_height)
		var tilecount := int(meta.get("tilecount", 0))
		var columns := maxi(1, int(meta.get("columns", 1)))
		var tex_cols := maxi(1, int(tex.get_width() / maxi(1, _tile_width)))
		var tex_rows := maxi(1, int(tex.get_height() / maxi(1, _tile_height)))
		var max_tiles := tex_cols * tex_rows
		var safe_count := mini(tilecount, max_tiles)
		for tid in range(safe_count):
			var ax := tid % columns
			var ay := int(tid / columns)
			if ax >= tex_cols or ay >= tex_rows:
				continue
			var coords := Vector2i(ax, ay)
			if not atlas.has_tile(coords):
				atlas.create_tile(coords)
		ts_resolved.append({"firstgid": first, "tilecount": safe_count, "columns": columns, "atlas": atlas})

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(_tile_width, _tile_height)
	var source_id := 0
	for r in ts_resolved:
		tile_set.add_source(r["atlas"], source_id)
		r["source_id"] = source_id
		source_id += 1

	_walkable_points.clear()
	var layer_index := 0
	for l in _layers_data:
		var tm := TileMapLayer.new()
		tm.name = String(l.get("name", "Layer%s" % layer_index))
		tm.tile_set = tile_set
		tm.z_index = -80 + layer_index
		add_child(tm)

		var cells: Dictionary = l.get("cells", {})
		for c in cells.keys():
			var cell := c as Vector2i
			var gid := int(cells[cell])
			var rmeta := _find_tileset_for_gid(ts_resolved, gid)
			if rmeta.is_empty():
				continue
			var local_id := gid - int(rmeta["firstgid"])
			var cols := int(rmeta["columns"])
			var atlas_coords := Vector2i(local_id % cols, int(local_id / cols))
			if not (rmeta["atlas"] as TileSetAtlasSource).has_tile(atlas_coords):
				continue
			var centered_cell := cell - _origin_tile
			tm.set_cell(centered_cell, int(rmeta["source_id"]), atlas_coords)
			if layer_index == 0:
				_walkable_points.append(_tile_center_from_cell(centered_cell))
		layer_index += 1

func _build_blockers_and_spawn() -> void:
	_blockers.clear()
	_collision_root = Node2D.new()
	_collision_root.name = "MapColliders"
	add_child(_collision_root)
	var named_spawn: Vector2 = Vector2.ZERO
	var has_named_spawn := false
	for og in _object_groups:
		var og_name := String(og.get("name", "")).to_lower()
		var group_collision := _looks_like_collision_tag(og_name)
		var objs: Array = og.get("objects", [])
		for ov in objs:
			var o: Dictionary = ov
			var name := String(o.get("name", "")).to_lower()
			var typ := String(o.get("type", "")).to_lower()
			var x := float(o.get("x", 0.0))
			var y := float(o.get("y", 0.0))
			var w := float(o.get("width", 0.0))
			var h := float(o.get("height", 0.0))
			var gx := x - float(_origin_tile.x * _tile_width)
			var gy := y - float(_origin_tile.y * _tile_height)
			var p := Vector2(gx, gy)
			if name.find("spawn") >= 0 or typ.find("spawn") >= 0 or typ.find("player") >= 0:
				named_spawn = p
				has_named_spawn = true
			var object_collision := _looks_like_collision_tag(name) or _looks_like_collision_tag(typ)
			if (group_collision or object_collision) and w > 1.0 and h > 1.0:
				var rect := Rect2(Vector2(gx, gy - h), Vector2(w, h))
				_blockers.append(rect)
				_add_blocker_shape(rect)

	# Safe world bounds even if object layers miss edge blockers.
	var b := _world_rect
	var t := float(_tile_width)
	_add_blocker_shape(Rect2(Vector2(b.position.x - t, b.position.y - t), Vector2(b.size.x + t * 2.0, t))) # top
	_add_blocker_shape(Rect2(Vector2(b.position.x - t, b.position.y + b.size.y), Vector2(b.size.x + t * 2.0, t))) # bottom
	_add_blocker_shape(Rect2(Vector2(b.position.x - t, b.position.y), Vector2(t, b.size.y))) # left
	_add_blocker_shape(Rect2(Vector2(b.position.x + b.size.x, b.position.y), Vector2(t, b.size.y))) # right

	_spawn_point = Vector2.ZERO
	if has_named_spawn:
		_spawn_point = named_spawn
	elif not _walkable_points.is_empty():
		var best := _walkable_points[0]
		var best_d2 := best.distance_squared_to(Vector2.ZERO)
		for p2 in _walkable_points:
			var d2 := p2.distance_squared_to(Vector2.ZERO)
			if d2 < best_d2 and _is_point_walkable(p2):
				best = p2
				best_d2 = d2
		_spawn_point = best

func _parse_tsx_meta(tsx_path: String) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open(tsx_path) != OK:
		return {}
	var out := {}
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			var n := parser.get_node_name()
			if n == "tileset":
				out["columns"] = int(parser.get_named_attribute_value_safe("columns"))
				out["tilecount"] = int(parser.get_named_attribute_value_safe("tilecount"))
			elif n == "image":
				var rel := String(parser.get_named_attribute_value_safe("source"))
				out["image_path"] = _resolve_rel_path(tsx_path, rel)
				break
	return out

func _find_tileset_for_gid(arr: Array[Dictionary], gid: int) -> Dictionary:
	for i in range(arr.size() - 1, -1, -1):
		var t := arr[i]
		var first := int(t.get("firstgid", 0))
		var count := int(t.get("tilecount", 0))
		if gid >= first and gid < first + count:
			return t
	return {}

func _tile_center_from_cell(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * _tile_width, (cell.y + 0.5) * _tile_height)

func _resolve_rel_path(base_path: String, rel: String) -> String:
	var base_dir := base_path.get_base_dir()
	var joined := base_dir.path_join(rel)
	return joined.simplify_path()

func _add_blocker_shape(rect: Rect2) -> void:
	if _collision_root == null:
		return
	if rect.size.x <= 0.5 or rect.size.y <= 0.5:
		return
	var body := StaticBody2D.new()
	# World/map collision layer (1), no mask needed for static blockers.
	body.collision_layer = 1 << 0
	body.collision_mask = 0
	body.position = rect.position + rect.size * 0.5
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = rect.size
	shape.shape = rs
	body.add_child(shape)
	_collision_root.add_child(body)

func _looks_like_collision_tag(s: String) -> bool:
	if s.is_empty():
		return false
	return s.find("coll") >= 0 or s.find("block") >= 0 or s.find("wall") >= 0 or s.find("solid") >= 0 or s.find("obstacle") >= 0
