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
var _prop_root: Node2D = null
var _animated_layer_cells: Array[Dictionary] = []
var _animated_props: Array[Dictionary] = []
var _tile_visible_cache: Dictionary = {}
var _texture_image_cache: Dictionary = {}
var _anim_rng := RandomNumberGenerator.new()
const TMX_FLAG_H: int = 0x80000000
const TMX_FLAG_V: int = 0x40000000
const TMX_FLAG_D: int = 0x20000000
const TMX_FLAG_R120: int = 0x10000000
const TMX_GID_MASK: int = 0x0FFFFFFF

func _ready() -> void:
	build_if_needed()

func _process(delta: float) -> void:
	if _animated_layer_cells.is_empty() and _animated_props.is_empty():
		return
	var cam_rect := _current_camera_world_rect().grow(maxf(_tile_width, _tile_height) * 2.0)
	_tick_layer_animations(delta, cam_rect)
	_tick_prop_animations(delta, cam_rect)

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

func get_random_walkable_point(rng: RandomNumberGenerator) -> Vector2:
	if _walkable_points.is_empty():
		return _spawn_point
	for _i in range(96):
		var p := _walkable_points[rng.randi_range(0, _walkable_points.size() - 1)]
		if _is_point_walkable(p):
			return p
	return _spawn_point

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
	_anim_rng.seed = int(hash(tmx_path))
	_build_tileset_and_layers()
	_build_blockers_and_spawn()

func _parse_tmx(path: String) -> void:
	_layers_data.clear()
	_object_groups.clear()
	_tilesets.clear()
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
				var layer_opacity_s := String(parser.get_named_attribute_value_safe("opacity"))
				var layer_visible_s := String(parser.get_named_attribute_value_safe("visible"))
				current_layer = {
					"name": String(parser.get_named_attribute_value_safe("name")),
					"cells": {},
					"offsetx": float(parser.get_named_attribute_value_safe("offsetx")),
					"offsety": float(parser.get_named_attribute_value_safe("offsety")),
					"opacity": float(layer_opacity_s) if layer_opacity_s != "" else 1.0,
					"visible": int(layer_visible_s) if layer_visible_s != "" else 1
				}
			elif n == "data":
				in_data = true
			elif n == "chunk" and in_data:
				pending_chunk = {
					"x": int(parser.get_named_attribute_value_safe("x")),
					"y": int(parser.get_named_attribute_value_safe("y")),
					"width": maxi(1, int(parser.get_named_attribute_value_safe("width"))),
					"height": maxi(1, int(parser.get_named_attribute_value_safe("height")))
				}
			elif n == "objectgroup":
				var group_opacity_s := String(parser.get_named_attribute_value_safe("opacity"))
				var group_visible_s := String(parser.get_named_attribute_value_safe("visible"))
				current_object_group = {
					"name": String(parser.get_named_attribute_value_safe("name")),
					"objects": [],
					"offsetx": float(parser.get_named_attribute_value_safe("offsetx")),
					"offsety": float(parser.get_named_attribute_value_safe("offsety")),
					"opacity": float(group_opacity_s) if group_opacity_s != "" else 1.0,
					"visible": int(group_visible_s) if group_visible_s != "" else 1
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
				var chunk_w := int(pending_chunk.get("width", 16))
				for s in vals:
					var v := int(String(s).strip_edges())
					var tx: int = int(pending_chunk["x"]) + (idx % chunk_w)
					var ty: int = int(pending_chunk["y"]) + int(idx / chunk_w)
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
	_animated_layer_cells.clear()
	_animated_props.clear()
	_tile_visible_cache.clear()
	_texture_image_cache.clear()

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
		var declared_columns := maxi(1, int(meta.get("columns", 1)))
		var tex_cols := maxi(1, int(tex.get_width() / maxi(1, _tile_width)))
		var tex_rows := maxi(1, int(tex.get_height() / maxi(1, _tile_height)))
		var columns := declared_columns
		if declared_columns != tex_cols:
			# Some imported TSX files carry stale RPG-Maker metadata.
			# Trust the actual atlas dimensions to avoid black/garbage tile sampling.
			columns = tex_cols
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
		ts_resolved.append({
			"firstgid": first,
			"tilecount": safe_count,
			"columns": columns,
			"atlas": atlas,
			"animations": meta.get("animations", {}),
			"texture": tex
		})

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(_tile_width, _tile_height)
	var source_id := 0
	for r in ts_resolved:
		tile_set.add_source(r["atlas"], source_id)
		r["source_id"] = source_id
		source_id += 1

	if _prop_root != null and is_instance_valid(_prop_root):
		_prop_root.queue_free()
	_prop_root = Node2D.new()
	_prop_root.name = "MapProps"
	_prop_root.z_index = -8
	add_child(_prop_root)

	_walkable_points.clear()
	var layer_index := 0
	for l in _layers_data:
		var tm := TileMapLayer.new()
		tm.name = String(l.get("name", "Layer%s" % layer_index))
		tm.tile_set = tile_set
		tm.z_index = -80 + layer_index
		tm.position = Vector2(float(l.get("offsetx", 0.0)), float(l.get("offsety", 0.0)))
		tm.visible = int(l.get("visible", 1)) != 0
		var layer_opacity := clampf(float(l.get("opacity", 1.0)), 0.0, 1.0)
		tm.modulate = Color(1, 1, 1, layer_opacity)
		add_child(tm)

		var cells: Dictionary = l.get("cells", {})
		for c in cells.keys():
			var cell := c as Vector2i
			var raw_gid := int(cells[cell])
			var gid := raw_gid & TMX_GID_MASK
			var rmeta := _find_tileset_for_gid(ts_resolved, gid)
			if rmeta.is_empty():
				continue
			var local_id := gid - int(rmeta["firstgid"])
			var cols := int(rmeta["columns"])
			var atlas_coords := Vector2i(local_id % cols, int(local_id / cols))
			if not (rmeta["atlas"] as TileSetAtlasSource).has_tile(atlas_coords):
				continue
			var centered_cell := cell - _origin_tile
			var alt := _godot_alt_from_tmx_raw_gid(raw_gid)
			tm.set_cell(centered_cell, int(rmeta["source_id"]), atlas_coords, alt)
			var anims: Dictionary = rmeta.get("animations", {})
			if anims.has(local_id):
				var frames_any: Variant = anims.get(local_id, [])
				var frames: Array = frames_any as Array
				var tex_anim := rmeta.get("texture", null) as Texture2D
				var sane_frames := _sanitize_animation_frames(frames, cols, tex_anim)
				if sane_frames.size() >= 2:
					var first_frame: Dictionary = sane_frames[0]
					var first_tid := int(first_frame.get("tileid", local_id))
					var first_coords := _tile_id_to_coords(first_tid, tile_set, int(rmeta["source_id"]), cols)
					if first_coords.x >= 0:
						tm.set_cell(centered_cell, int(rmeta["source_id"]), first_coords, alt)
					var start_idx := _anim_rng.randi_range(0, sane_frames.size() - 1)
					var start_frame: Dictionary = sane_frames[start_idx]
					var start_tid := int(start_frame.get("tileid", first_tid))
					var start_dur := maxf(0.03, float(start_frame.get("duration", 0.12)))
					var local_center := _tile_center_from_cell(centered_cell)
					var world_center := tm.to_global(local_center)
					var start_coords := _tile_id_to_coords(start_tid, tile_set, int(rmeta["source_id"]), cols)
					if start_coords.x >= 0:
						tm.set_cell(centered_cell, int(rmeta["source_id"]), start_coords, alt)
					_animated_layer_cells.append({
						"layer": tm,
						"cell": centered_cell,
						"world_center": world_center,
						"source_id": int(rmeta["source_id"]),
						"alt": alt,
						"columns": cols,
						"frames": sane_frames,
						"frame_idx": start_idx,
						"current_tid": start_tid,
						"timer": _anim_rng.randf_range(0.02, start_dur)
					})
			if layer_index == 0:
				_walkable_points.append(_tile_center_from_cell(centered_cell))
		layer_index += 1

	_build_object_props(ts_meta, ts_resolved)
	set_process((not _animated_layer_cells.is_empty()) or (not _animated_props.is_empty()))

func _build_object_props(ts_meta: Array[Dictionary], ts_resolved: Array[Dictionary]) -> void:
	if _prop_root == null or not is_instance_valid(_prop_root):
		return
	var meta_by_firstgid: Dictionary = {}
	var tex_by_firstgid: Dictionary = {}
	for m in ts_meta:
		var fg := int(m.get("firstgid", -1))
		if fg < 0:
			continue
		meta_by_firstgid[fg] = m
		var image_path := String(m.get("image_path", ""))
		if image_path != "":
			tex_by_firstgid[fg] = load(image_path)
	var group_index := 0
	for og in _object_groups:
		var group_visible := int(og.get("visible", 1)) != 0
		var group_opacity := clampf(float(og.get("opacity", 1.0)), 0.0, 1.0)
		var group_offset := Vector2(float(og.get("offsetx", 0.0)), float(og.get("offsety", 0.0)))
		var objs: Array = og.get("objects", [])
		for ov in objs:
			var o: Dictionary = ov
			var raw_gid := int(o.get("gid", 0))
			var gid_raw := raw_gid & TMX_GID_MASK
			if gid_raw == 0:
				continue
			var gid := gid_raw
			var ts := _find_tileset_for_gid(ts_resolved, gid)
			if ts.is_empty():
				continue
			var local_id := gid - int(ts.get("firstgid", 0))
			var cols := maxi(1, int(ts.get("columns", 1)))
			var atlas_coords := Vector2i(local_id % cols, int(local_id / cols))

			var firstgid := int(ts.get("firstgid", 0))
			var meta: Dictionary = meta_by_firstgid.get(firstgid, {})
			if meta.is_empty():
				continue
			var tex := tex_by_firstgid.get(firstgid, null) as Texture2D
			if tex == null:
				continue
			var region := Rect2(
				Vector2(float(atlas_coords.x * _tile_width), float(atlas_coords.y * _tile_height)),
				Vector2(float(_tile_width), float(_tile_height))
			)
			if region.position.x + region.size.x > tex.get_width() or region.position.y + region.size.y > tex.get_height():
				continue

			var x := float(o.get("x", 0.0))
			var y := float(o.get("y", 0.0))
			var w := float(o.get("width", float(_tile_width)))
			var h := float(o.get("height", float(_tile_height)))
			if w <= 0.001:
				w = float(_tile_width)
			if h <= 0.001:
				h = float(_tile_height)
			var gx := x - float(_origin_tile.x * _tile_width)
			var gy := y - float(_origin_tile.y * _tile_height)

			var spr := Sprite2D.new()
			spr.texture = tex
			spr.region_enabled = true
			spr.region_rect = region
			spr.centered = false
			# TMX tile objects are anchored to bottom-left in orthogonal maps.
			# Respect object width/height so tiny candle flames don't get upscaled to full 48x48.
			spr.scale = Vector2(w / float(_tile_width), h / float(_tile_height))
			spr.position = Vector2(gx, gy - h) + group_offset
			spr.visible = group_visible
			spr.modulate = Color(1, 1, 1, group_opacity)
			spr.z_as_relative = false
			spr.z_index = -20 + group_index
			_apply_tmx_object_flip_to_sprite(spr, raw_gid)
			_prop_root.add_child(spr)
			var anims: Dictionary = ts.get("animations", {})
			if anims.has(local_id):
				var frames_any: Variant = anims.get(local_id, [])
				var frames: Array = frames_any as Array
				var sane_frames := _sanitize_animation_frames(frames, cols, tex)
				if sane_frames.size() >= 2:
					var first_frame: Dictionary = sane_frames[0]
					var first_tid := int(first_frame.get("tileid", local_id))
					var frx := (first_tid % cols) * _tile_width
					var fry := int(first_tid / cols) * _tile_height
					if frx + _tile_width <= tex.get_width() and fry + _tile_height <= tex.get_height():
						spr.region_rect = Rect2(Vector2(frx, fry), Vector2(_tile_width, _tile_height))
					var start_idx := _anim_rng.randi_range(0, sane_frames.size() - 1)
					var start_frame: Dictionary = sane_frames[start_idx]
					var start_tid := int(start_frame.get("tileid", first_tid))
					var start_rx := (start_tid % cols) * _tile_width
					var start_ry := int(start_tid / cols) * _tile_height
					if start_rx + _tile_width <= tex.get_width() and start_ry + _tile_height <= tex.get_height():
						spr.region_rect = Rect2(Vector2(start_rx, start_ry), Vector2(_tile_width, _tile_height))
					var start_dur := maxf(0.03, float(start_frame.get("duration", 0.12)))
					_animated_props.append({
						"sprite": spr,
						"texture": tex,
						"frames": sane_frames,
						"columns": cols,
						"frame_idx": start_idx,
						"current_tid": start_tid,
						"timer": _anim_rng.randf_range(0.02, start_dur)
					})
		group_index += 1

func _tick_layer_animations(delta: float, visible_rect: Rect2) -> void:
	for rec in _animated_layer_cells:
		var tm := rec.get("layer", null) as TileMapLayer
		if tm == null or not is_instance_valid(tm):
			continue
		var frames: Array = rec.get("frames", [])
		if frames.size() < 2:
			continue
		var idx := int(rec.get("frame_idx", 0))
		var t := float(rec.get("timer", 0.0)) - delta
		var last_tid := int(rec.get("current_tid", -1))
		var changed := false
		while t <= 0.0:
			idx = (idx + 1) % frames.size()
			var f: Dictionary = frames[idx]
			t += float(f.get("duration", 0.12))
			var tid := int(f.get("tileid", -1))
			if tid < 0:
				continue
			if tid != last_tid:
				last_tid = tid
				changed = true
		rec["frame_idx"] = idx
		rec["timer"] = t
		rec["current_tid"] = last_tid
		if not changed:
			continue
		var center := rec.get("world_center", Vector2.ZERO) as Vector2
		if not visible_rect.has_point(center):
			continue
		var source_id := int(rec.get("source_id", -1))
		if source_id < 0:
			continue
		var cols := maxi(1, int(rec.get("columns", 1)))
		var atlas := _tile_id_to_coords(last_tid, tm.tile_set, source_id, cols)
		if atlas.x < 0:
			continue
		var cell := rec.get("cell", Vector2i.ZERO) as Vector2i
		var alt := int(rec.get("alt", 0))
		tm.set_cell(cell, source_id, atlas, alt)

func _tick_prop_animations(delta: float, visible_rect: Rect2) -> void:
	for rec in _animated_props:
		var spr := rec.get("sprite", null) as Sprite2D
		var tex := rec.get("texture", null) as Texture2D
		if spr == null or not is_instance_valid(spr) or tex == null:
			continue
		var frames: Array = rec.get("frames", [])
		if frames.size() < 2:
			continue
		var cols := maxi(1, int(rec.get("columns", 1)))
		var idx := int(rec.get("frame_idx", 0))
		var t := float(rec.get("timer", 0.0)) - delta
		var last_tid := int(rec.get("current_tid", -1))
		var changed := false
		while t <= 0.0:
			idx = (idx + 1) % frames.size()
			var f: Dictionary = frames[idx]
			t += float(f.get("duration", 0.12))
			var tid := int(f.get("tileid", -1))
			if tid < 0:
				continue
			if tid != last_tid:
				last_tid = tid
				changed = true
		rec["frame_idx"] = idx
		rec["timer"] = t
		rec["current_tid"] = last_tid
		if not changed:
			continue
		if not visible_rect.has_point(spr.global_position):
			continue
		var rx := (last_tid % cols) * _tile_width
		var ry := int(last_tid / cols) * _tile_height
		if rx + _tile_width > tex.get_width() or ry + _tile_height > tex.get_height():
			continue
		spr.region_rect = Rect2(Vector2(rx, ry), Vector2(_tile_width, _tile_height))

func _sanitize_animation_frames(frames: Array, columns: int, tex: Texture2D) -> Array:
	var out: Array = []
	for f in frames:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = f
		var tid := int(d.get("tileid", -1))
		var dur := maxf(0.03, float(d.get("duration", 0.12)))
		if tid < 0:
			continue
		if not _is_tileid_usable(tex, tid, columns):
			continue
		out.append({"tileid": tid, "duration": dur})
	# If TSX points to stale frames for a mismatched sheet, disable that animation
	# instead of cycling invalid frame IDs (which produces black/incorrect tiles).
	if out.is_empty():
		return []
	return out

func _is_tileid_usable(tex: Texture2D, tile_id: int, columns: int) -> bool:
	if tex == null:
		return false
	var cols := maxi(1, columns)
	var key := "%s|%d|%d" % [str(tex.get_instance_id()), tile_id, cols]
	if _tile_visible_cache.has(key):
		return bool(_tile_visible_cache[key])
	var tx := tile_id % cols
	var ty := int(tile_id / cols)
	var rx := tx * _tile_width
	var ry := ty * _tile_height
	if rx + _tile_width > tex.get_width() or ry + _tile_height > tex.get_height():
		_tile_visible_cache[key] = false
		return false
	var img := _texture_image_cache.get(str(tex.get_instance_id()), null) as Image
	if img == null:
		img = tex.get_image()
		_texture_image_cache[str(tex.get_instance_id())] = img
	if img == null:
		_tile_visible_cache[key] = true
		return true
	var opaque_px := 0
	for yy in range(ry, ry + _tile_height):
		for xx in range(rx, rx + _tile_width):
			if img.get_pixel(xx, yy).a > 0.01:
				opaque_px += 1
				if opaque_px >= 8:
					_tile_visible_cache[key] = true
					return true
	_tile_visible_cache[key] = false
	return false

func _godot_alt_from_tmx_raw_gid(raw_gid: int) -> int:
	var alt := 0
	if (raw_gid & TMX_FLAG_H) != 0:
		alt |= TileSetAtlasSource.TRANSFORM_FLIP_H
	if (raw_gid & TMX_FLAG_V) != 0:
		alt |= TileSetAtlasSource.TRANSFORM_FLIP_V
	if (raw_gid & TMX_FLAG_D) != 0:
		alt |= TileSetAtlasSource.TRANSFORM_TRANSPOSE
	return alt

func _apply_tmx_object_flip_to_sprite(spr: Sprite2D, raw_gid: int) -> void:
	if spr == null:
		return
	spr.flip_h = (raw_gid & TMX_FLAG_H) != 0
	spr.flip_v = (raw_gid & TMX_FLAG_V) != 0

func _current_camera_world_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(Vector2(-1e9, -1e9), Vector2(2e9, 2e9))
	var vp_size := get_viewport().get_visible_rect().size
	var z := cam.zoom
	var half := Vector2(vp_size.x * z.x * 0.5, vp_size.y * z.y * 0.5)
	return Rect2(cam.global_position - half, half * 2.0)

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
	var animations: Dictionary = {}
	var current_tile_id := -1
	var in_animation := false
	var current_frames: Array = []
	while parser.read() == OK:
		var ntype := parser.get_node_type()
		if ntype == XMLParser.NODE_ELEMENT:
			var n := parser.get_node_name()
			if n == "tileset":
				out["columns"] = int(parser.get_named_attribute_value_safe("columns"))
				out["tilecount"] = int(parser.get_named_attribute_value_safe("tilecount"))
			elif n == "image":
				var rel := String(parser.get_named_attribute_value_safe("source"))
				out["image_path"] = _resolve_rel_path(tsx_path, rel)
			elif n == "tile":
				current_tile_id = int(parser.get_named_attribute_value_safe("id"))
				current_frames = []
			elif n == "animation":
				in_animation = true
				current_frames = []
			elif n == "frame" and in_animation and current_tile_id >= 0:
				var tid := int(parser.get_named_attribute_value_safe("tileid"))
				var dur_ms := maxi(1, int(parser.get_named_attribute_value_safe("duration")))
				current_frames.append({"tileid": tid, "duration": float(dur_ms) / 1000.0})
		elif ntype == XMLParser.NODE_ELEMENT_END:
			var en := parser.get_node_name()
			if en == "animation":
				in_animation = false
			elif en == "tile":
				if current_tile_id >= 0 and current_frames.size() >= 2:
					animations[current_tile_id] = current_frames.duplicate(true)
				current_tile_id = -1
				current_frames = []
	out["animations"] = animations
	return out

func _find_tileset_for_gid(arr: Array[Dictionary], gid: int) -> Dictionary:
	for i in range(arr.size() - 1, -1, -1):
		var t := arr[i]
		var first := int(t.get("firstgid", 0))
		var count := int(t.get("tilecount", 0))
		if gid >= first and gid < first + count:
			return t
	return {}

func _tile_id_to_coords(tile_id: int, tile_set: TileSet, source_id: int, columns: int) -> Vector2i:
	if tile_set == null:
		return Vector2i(-1, -1)
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	if src == null:
		return Vector2i(-1, -1)
	var cols := maxi(1, columns)
	var coords := Vector2i(tile_id % cols, int(tile_id / cols))
	if not src.has_tile(coords):
		return Vector2i(-1, -1)
	return coords

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
