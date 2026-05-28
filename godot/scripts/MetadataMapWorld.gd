extends Node2D
class_name MetadataMapWorld

@export_file("*.json") var metadata_path: String = ""
@export_file("*.png", "*.webp") var metadata_image_override: String = ""
@export var map_size: Vector2 = Vector2(1600, 1200)
@export var sample_step_px: float = 28.0
@export var metadata_points_scale_mult: float = 1.0
@export var perf_trace_enabled: bool = true

var _built: bool = false
var _world_rect: Rect2 = Rect2(Vector2(-800, -600), Vector2(1600, 1200))
var _source_size: Vector2 = Vector2(1600, 1200)
var _source_to_world_scale: Vector2 = Vector2.ONE
var _use_normalized_coords: bool = false
var _spawn_point: Vector2 = Vector2.ZERO
var _walkable_points: Array[Vector2] = []
var _hard_blockers: Array[PackedVector2Array] = []
var _bounds_poly: PackedVector2Array = PackedVector2Array()
var _spawn_zone_polys: Array[PackedVector2Array] = []
var _spawn_zone_weights: Array[float] = []
var _bg_sprite: Sprite2D = null
var _bg_pending_path: String = ""

func _ready() -> void:
	build_if_needed()

func _process(_delta: float) -> void:
	if _bg_pending_path == "":
		return
	var prog := []
	var st := ResourceLoader.load_threaded_get_status(_bg_pending_path, prog)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		var tex := ResourceLoader.load_threaded_get(_bg_pending_path) as Texture2D
		if tex != null:
			_assign_background_texture(tex)
			if perf_trace_enabled:
				print("MAP_BG_TRACE async_loaded path=%s size=%dx%d" % [_bg_pending_path, tex.get_width(), tex.get_height()])
		_bg_pending_path = ""
	elif st == ResourceLoader.THREAD_LOAD_FAILED:
		if perf_trace_enabled:
			print("MAP_BG_TRACE async_failed path=%s" % _bg_pending_path)
		_bg_pending_path = ""

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

func get_camera_rect() -> Rect2:
	if _bounds_poly.size() >= 3:
		return _bounds_bbox(_bounds_poly)
	return _world_rect

func get_random_walkable_point(rng: RandomNumberGenerator) -> Vector2:
	if _walkable_points.is_empty():
		var bb := get_camera_rect()
		for _i in range(72):
			var p := Vector2(
				rng.randf_range(bb.position.x, bb.position.x + bb.size.x),
				rng.randf_range(bb.position.y, bb.position.y + bb.size.y)
			)
			if _is_point_walkable(p):
				return p
		return _spawn_point
	for _i in range(96):
		var p := _walkable_points[rng.randi_range(0, _walkable_points.size() - 1)]
		if _is_point_walkable(p):
			return p
	return _spawn_point

func get_random_spawn_around(center: Vector2, min_radius: float, max_radius: float, rng: RandomNumberGenerator) -> Vector2:
	var lo := minf(min_radius, max_radius)
	var hi := maxf(min_radius, max_radius)
	var lo2 := lo * lo
	var hi2 := hi * hi
	for _i in range(96):
		var p := _random_spawn_zone_point(rng)
		if p == Vector2.INF:
			break
		var d2 := p.distance_squared_to(center)
		if d2 >= lo2 and d2 <= hi2 and _is_point_walkable(p):
			return p
	if _walkable_points.is_empty():
		return center
	for _j in range(128):
		var p2 := _walkable_points[rng.randi_range(0, _walkable_points.size() - 1)]
		var d22 := p2.distance_squared_to(center)
		if d22 >= lo2 and d22 <= hi2 and _is_point_walkable(p2):
			return p2
	for _k in range(64):
		var p3 := _walkable_points[rng.randi_range(0, _walkable_points.size() - 1)]
		if _is_point_walkable(p3):
			return p3
	return center

func _build() -> void:
	var t0_us := int(Time.get_ticks_usec())
	if metadata_path.is_empty() or not FileAccess.file_exists(metadata_path):
		push_warning("MetadataMapWorld: missing metadata at %s" % metadata_path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MetadataMapWorld: invalid metadata JSON at %s" % metadata_path)
		return
	var root := parsed as Dictionary
	_use_normalized_coords = bool(root.get("normalized_coordinates", false))
	var image_size: Array = root.get("image_size_px", [1600, 1200]) as Array
	var w := maxf(64.0, float(image_size[0]) if image_size.size() > 0 else 1600.0)
	var h := maxf(64.0, float(image_size[1]) if image_size.size() > 1 else 1200.0)
	_source_size = Vector2(w, h)
	if map_size.x < 64.0 or map_size.y < 64.0:
		map_size = _source_size
	_source_to_world_scale = Vector2(
		map_size.x / maxf(1.0, _source_size.x * metadata_points_scale_mult),
		map_size.y / maxf(1.0, _source_size.y * metadata_points_scale_mult)
	)
	var half := map_size * 0.5
	_world_rect = Rect2(-half, map_size)
	_spawn_point = Vector2.ZERO

	var s0_us := int(Time.get_ticks_usec())
	_add_background(root)
	_perf_log_stage("add_background", s0_us, t0_us)
	s0_us = int(Time.get_ticks_usec())
	_build_bounds(root)
	_perf_log_stage("build_bounds", s0_us, t0_us)
	s0_us = int(Time.get_ticks_usec())
	_build_collisions(root)
	_perf_log_stage("build_collisions", s0_us, t0_us)
	s0_us = int(Time.get_ticks_usec())
	_build_spawn_zones(root)
	_perf_log_stage("build_spawn_zones", s0_us, t0_us)
	_ensure_spawn_point_walkable()
	s0_us = int(Time.get_ticks_usec())
	_build_metadata_layers(root)
	_perf_log_stage("build_metadata_layers", s0_us, t0_us)
	# Build walkable cache after first frame so deploy is responsive.
	call_deferred("_build_walkable_points")
	if perf_trace_enabled:
		var total_ms := float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
		print("MAP_BUILD_TRACE_DONE map_size=%s world_rect=%s layers_done_ms=%.2f" % [str(map_size), str(_world_rect), total_ms])

func _add_background(root: Dictionary) -> void:
	var rel_image := String(root.get("source_image", ""))
	var base_dir := metadata_path.get_base_dir()
	var image_path := ""
	if not metadata_image_override.is_empty():
		image_path = metadata_image_override
	elif not rel_image.is_empty():
		image_path = base_dir.path_join(rel_image)
	var tex: Texture2D = null
	if not image_path.is_empty():
		tex = _try_load_texture(image_path)
	if tex == null and _bg_pending_path != "":
		if _bg_sprite == null or not is_instance_valid(_bg_sprite):
			_bg_sprite = Sprite2D.new()
			_bg_sprite.name = "MapBackground"
			_bg_sprite.centered = false
			_bg_sprite.position = _world_rect.position
			_bg_sprite.z_index = -100
			add_child(_bg_sprite)
		return
	if tex == null:
		var guessed := _guess_main_map_image(base_dir)
		if not guessed.is_empty():
			image_path = guessed
			tex = _try_load_texture(image_path)
	if tex == null and _bg_pending_path != "":
		if _bg_sprite == null or not is_instance_valid(_bg_sprite):
			_bg_sprite = Sprite2D.new()
			_bg_sprite.name = "MapBackground"
			_bg_sprite.centered = false
			_bg_sprite.position = _world_rect.position
			_bg_sprite.z_index = -100
			add_child(_bg_sprite)
		return
	if tex == null:
		push_warning("MetadataMapWorld: source image missing at %s" % image_path)
		return
	if _bg_sprite == null or not is_instance_valid(_bg_sprite):
		_bg_sprite = Sprite2D.new()
		_bg_sprite.name = "MapBackground"
		_bg_sprite.centered = false
		_bg_sprite.position = _world_rect.position
		_bg_sprite.z_index = -100
		add_child(_bg_sprite)
	_assign_background_texture(tex)
	return

func _assign_background_texture(tex: Texture2D) -> void:
	if tex == null:
		return
	if _bg_sprite == null or not is_instance_valid(_bg_sprite):
		_bg_sprite = Sprite2D.new()
		_bg_sprite.name = "MapBackground"
		_bg_sprite.centered = false
		_bg_sprite.position = _world_rect.position
		_bg_sprite.z_index = -100
		add_child(_bg_sprite)
	_bg_sprite.texture = tex
	_bg_sprite.scale = Vector2(
		map_size.x / maxf(1.0, float(tex.get_width())),
		map_size.y / maxf(1.0, float(tex.get_height()))
	)

func _try_load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var req := ResourceLoader.load_threaded_request(path)
		if req == OK:
			_bg_pending_path = path
			if perf_trace_enabled:
				print("MAP_BG_TRACE async_request path=%s" % path)
			return null
		return load(path) as Texture2D
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	var img := Image.new()
	var err := img.load(abs_path)
	if err == OK:
		return ImageTexture.create_from_image(img)
	return null

func _guess_main_map_image(base_dir: String) -> String:
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return ""
	var best_path := ""
	var best_score := -9999
	for f in dir.get_files():
		var low := f.to_lower()
		if not (low.ends_with(".png") or low.ends_with(".webp")):
			continue
		var score := 0
		if low.find("mask") >= 0:
			score -= 30
		if low.find("overlay") >= 0:
			score -= 25
		if low.find("metadata") >= 0:
			score -= 20
		if low.find("zone") >= 0:
			score -= 10
		if low.find("collision") >= 0:
			score -= 10
		if low.find("clean") >= 0:
			score += 30
		if low.find("upscaled") >= 0:
			score += 15
		if low.find("chatgpt") >= 0:
			score += 6
		if score > best_score:
			best_score = score
			best_path = base_dir.path_join(f)
	return best_path

func _build_bounds(root: Dictionary) -> void:
	var cb: Dictionary = root.get("camera_bounds", {}) as Dictionary
	if cb.is_empty():
		_bounds_poly = PackedVector2Array([
			_world_rect.position,
			Vector2(_world_rect.position.x + _world_rect.size.x, _world_rect.position.y),
			_world_rect.position + _world_rect.size,
			Vector2(_world_rect.position.x, _world_rect.position.y + _world_rect.size.y)
		])
		return
	var points: Array = cb.get("points", []) as Array
	_bounds_poly = _item_polygon(cb)
	if _bounds_poly.size() >= 3:
		var area := Area2D.new()
		area.name = "CameraBounds"
		var poly := CollisionPolygon2D.new()
		poly.polygon = _bounds_poly
		area.add_child(poly)
		add_child(area)
	var centroid_arr: Array = cb.get("centroid", []) as Array
	if _use_normalized_coords and cb.has("centroid_norm"):
		_spawn_point = _item_point(cb, "centroid")
	elif centroid_arr.size() >= 2:
		_spawn_point = _point_from_pair(centroid_arr)

func _build_collisions(root: Dictionary) -> void:
	var layers: Dictionary = root.get("layers", {}) as Dictionary
	var statics: Array = layers.get("Collision_Static", []) as Array
	if statics.is_empty():
		return
	var root_node := Node2D.new()
	root_node.name = "CollisionStatic"
	add_child(root_node)
	for item in statics:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d := item as Dictionary
		var pts: PackedVector2Array = _sanitize_polygon(_item_polygon(d))
		if pts.size() < 3:
			continue
		var body := StaticBody2D.new()
		body.name = String(d.get("id", "collision"))
		body.set_meta("kind", String(d.get("kind", "solid")))
		# World blockers live on layer 1 (bit 0).
		body.collision_layer = 1
		body.collision_mask = 0
		_add_collision_polys(body, pts)
		root_node.add_child(body)
		_hard_blockers.append(pts)

func _build_spawn_zones(root: Dictionary) -> void:
	_spawn_zone_polys.clear()
	_spawn_zone_weights.clear()
	var layers: Dictionary = root.get("layers", {}) as Dictionary
	var zones: Array = layers.get("Spawn_Zones", []) as Array
	if zones.is_empty():
		return
	for z in zones:
		if typeof(z) != TYPE_DICTIONARY:
			continue
		var d := z as Dictionary
		var pts := _item_polygon(d)
		if pts.size() < 3:
			continue
		_spawn_zone_polys.append(pts)
		_spawn_zone_weights.append(maxf(0.01, float(d.get("weight", 1.0))))

func _ensure_spawn_point_walkable() -> void:
	if _is_point_walkable(_spawn_point):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	# Prefer authored spawn zones first.
	for _i in range(220):
		var z := _random_spawn_zone_point(rng)
		if z != Vector2.INF and _is_point_walkable(z):
			_spawn_point = z
			if perf_trace_enabled:
				print("MAP_SPAWN_TRACE source=spawn_zone point=%s" % str(_spawn_point))
			return
	# Fallback: sample camera rect.
	var bb := get_camera_rect()
	for _j in range(360):
		var p := Vector2(
			rng.randf_range(bb.position.x, bb.position.x + bb.size.x),
			rng.randf_range(bb.position.y, bb.position.y + bb.size.y)
		)
		if _is_point_walkable(p):
			_spawn_point = p
			if perf_trace_enabled:
				print("MAP_SPAWN_TRACE source=camera_rect point=%s" % str(_spawn_point))
			return
	# Last-resort deterministic scan from camera center.
	var center := bb.position + bb.size * 0.5
	var step := maxf(24.0, sample_step_px)
	for r in range(1, 120):
		var radius := float(r) * step
		for k in range(12):
			var a := TAU * float(k) / 12.0
			var p2 := center + Vector2.from_angle(a) * radius
			if _is_point_walkable(p2):
				_spawn_point = p2
				if perf_trace_enabled:
					print("MAP_SPAWN_TRACE source=radial_scan point=%s" % str(_spawn_point))
				return
	# Keep previous spawn if no valid point found, but report it loudly for diagnosis.
	if perf_trace_enabled:
		print("MAP_SPAWN_TRACE source=fallback_unresolved point=%s" % str(_spawn_point))

func _build_metadata_layers(root: Dictionary) -> void:
	var layers: Dictionary = root.get("layers", {}) as Dictionary
	_build_area_layer("CollisionSoft", layers.get("Collision_Soft", []) as Array, false)
	_build_area_layer("DistrictZones", layers.get("District_Zones", []) as Array, false)
	_build_lane_layer(layers.get("Enemy_Lanes", []) as Array)
	_build_props_layer(layers.get("Interactable_Props", []) as Array)

func _build_area_layer(root_name: String, items: Array, monitorable: bool) -> void:
	if items.is_empty():
		return
	var root_node := Node2D.new()
	root_node.name = root_name
	add_child(root_node)
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d := item as Dictionary
		var pts := _item_polygon(d)
		if pts.size() < 3:
			continue
		var area := Area2D.new()
		area.name = String(d.get("id", "zone"))
		area.monitoring = monitorable
		area.monitorable = monitorable
		for k in d.keys():
			if String(k) == "points":
				continue
			area.set_meta(String(k), d.get(k))
		var poly := CollisionPolygon2D.new()
		poly.polygon = pts
		area.add_child(poly)
		root_node.add_child(area)

func _build_lane_layer(items: Array) -> void:
	if items.is_empty():
		return
	var root_node := Node2D.new()
	root_node.name = "EnemyLanes"
	add_child(root_node)
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d := item as Dictionary
		var pts := _item_polygon(d)
		if pts.size() < 2:
			continue
		var path := Path2D.new()
		path.name = String(d.get("id", "lane"))
		path.set_meta("role", String(d.get("role", "district")))
		var curve := Curve2D.new()
		for p in pts:
			curve.add_point(p)
		path.curve = curve
		root_node.add_child(path)

func _build_props_layer(items: Array) -> void:
	if items.is_empty():
		return
	var root_node := Node2D.new()
	root_node.name = "InteractableProps"
	add_child(root_node)
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d := item as Dictionary
		var pos := _item_point(d, "position")
		if pos == Vector2.INF:
			continue
		var marker := Marker2D.new()
		marker.name = String(d.get("id", "prop"))
		marker.position = pos
		for k in d.keys():
			if String(k) == "position":
				continue
			marker.set_meta(String(k), d.get(k))
		root_node.add_child(marker)

func _build_walkable_points() -> void:
	var t0_us := int(Time.get_ticks_usec())
	_walkable_points.clear()
	var bb := _bounds_bbox(_bounds_poly)
	# Keep map-load smooth on very large metadata maps by sampling adaptively.
	var adaptive := maxf(bb.size.x, bb.size.y) / 84.0
	var step := clampf(maxf(sample_step_px, adaptive), 18.0, 96.0)
	var max_points := 7000
	var y := bb.position.y
	while y <= bb.position.y + bb.size.y:
		var x := bb.position.x
		while x <= bb.position.x + bb.size.x:
			var p := Vector2(x, y)
			if _is_point_walkable(p):
				_walkable_points.append(p)
				if _walkable_points.size() >= max_points:
					_perf_walkable_done(t0_us, step, true)
					return
			x += step
		y += step
	if _walkable_points.is_empty():
		_walkable_points.append(_spawn_point)
	_perf_walkable_done(t0_us, step, false)

func _perf_log_stage(stage: String, stage_start_us: int, total_start_us: int) -> void:
	if not perf_trace_enabled:
		return
	var now_us := int(Time.get_ticks_usec())
	var seg_ms := float(now_us - stage_start_us) / 1000.0
	var total_ms := float(now_us - total_start_us) / 1000.0
	print("MAP_BUILD_TRACE stage=%s seg_ms=%.2f total_ms=%.2f collisions=%d spawn_zones=%d" % [stage, seg_ms, total_ms, _hard_blockers.size(), _spawn_zone_polys.size()])

func _perf_walkable_done(start_us: int, step: float, capped: bool) -> void:
	if not perf_trace_enabled:
		return
	var ms := float(int(Time.get_ticks_usec()) - start_us) / 1000.0
	print("MAP_WALKABLE_TRACE points=%d step=%.1f capped=%s ms=%.2f" % [_walkable_points.size(), step, ("1" if capped else "0"), ms])

func _is_point_walkable(p: Vector2) -> bool:
	if _bounds_poly.size() >= 3 and not Geometry2D.is_point_in_polygon(p, _bounds_poly):
		return false
	for poly in _hard_blockers:
		if poly.size() >= 3 and Geometry2D.is_point_in_polygon(p, poly):
			return false
	return true

func _random_spawn_zone_point(rng: RandomNumberGenerator) -> Vector2:
	if _spawn_zone_polys.is_empty():
		return Vector2.INF
	var total_w := 0.0
	for w in _spawn_zone_weights:
		total_w += maxf(0.01, w)
	if total_w <= 0.0:
		return Vector2.INF
	var pick := rng.randf() * total_w
	var idx := 0
	var acc := 0.0
	for i in range(_spawn_zone_weights.size()):
		acc += maxf(0.01, _spawn_zone_weights[i])
		if pick <= acc:
			idx = i
			break
	var poly := _spawn_zone_polys[idx]
	var bb := _bounds_bbox(poly)
	for _i in range(64):
		var p := Vector2(
			rng.randf_range(bb.position.x, bb.position.x + bb.size.x),
			rng.randf_range(bb.position.y, bb.position.y + bb.size.y)
		)
		if Geometry2D.is_point_in_polygon(p, poly):
			return p
	return Vector2.INF

func _points_from_any(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		if typeof(p) == TYPE_VECTOR2:
			out.append(_source_to_world(p as Vector2))
		elif typeof(p) == TYPE_ARRAY:
			var a := p as Array
			if a.size() >= 2:
				out.append(_point_from_pair(a))
		elif typeof(p) == TYPE_DICTIONARY:
			var d := p as Dictionary
			if d.has("x") and d.has("y"):
				out.append(_source_to_world(Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))))
	return out

func _item_polygon(item: Dictionary) -> PackedVector2Array:
	if _use_normalized_coords and item.has("points_norm"):
		var pn := item.get("points_norm", []) as Array
		if not pn.is_empty():
			return _points_from_norm(pn)
	var pts := item.get("points", []) as Array
	if not pts.is_empty():
		return _points_from_any(pts)
	return PackedVector2Array()

func _item_point(item: Dictionary, base_key: String) -> Vector2:
	if _use_normalized_coords:
		var nk := base_key + "_norm"
		if item.has(nk):
			var arr_n := item.get(nk, []) as Array
			if arr_n.size() >= 2:
				return _point_from_norm_pair(arr_n)
	var arr := item.get(base_key, []) as Array
	if arr.size() >= 2:
		return _point_from_pair(arr)
	return Vector2.INF

func _points_from_norm(points_norm: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points_norm:
		if typeof(p) != TYPE_ARRAY:
			continue
		var a := p as Array
		if a.size() < 2:
			continue
		out.append(_point_from_norm_pair(a))
	return out

func _point_from_norm_pair(a: Array) -> Vector2:
	var nx := clampf(float(a[0]), 0.0, 1.0)
	var ny := clampf(float(a[1]), 0.0, 1.0)
	return Vector2((nx - 0.5) * map_size.x, (ny - 0.5) * map_size.y)

func _point_from_pair(a: Array) -> Vector2:
	return _source_to_world(Vector2(float(a[0]), float(a[1])))

func _source_to_world(p: Vector2) -> Vector2:
	var source_scaled := _source_size * metadata_points_scale_mult
	var centered := (p * metadata_points_scale_mult) - source_scaled * 0.5
	return Vector2(centered.x * _source_to_world_scale.x, centered.y * _source_to_world_scale.y)

func _sanitize_polygon(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if poly.size() < 3:
		return out
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.5:
			out.append(p)
	if out.size() >= 3 and out[0].distance_to(out[out.size() - 1]) <= 0.5:
		out.remove_at(out.size() - 1)
	return out

func _add_collision_polys(body: StaticBody2D, poly: PackedVector2Array) -> void:
	if poly.size() < 3:
		return
	var tri_idx: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	var use_poly := poly
	if tri_idx.is_empty():
		var hull := Geometry2D.convex_hull(poly)
		if hull.size() >= 3:
			use_poly = hull
			tri_idx = Geometry2D.triangulate_polygon(use_poly)
	if tri_idx.is_empty():
		var fallback := CollisionPolygon2D.new()
		fallback.polygon = use_poly
		body.add_child(fallback)
		return
	var i := 0
	while i + 2 < tri_idx.size():
		var a := tri_idx[i]
		var b := tri_idx[i + 1]
		var c := tri_idx[i + 2]
		i += 3
		if a < 0 or b < 0 or c < 0:
			continue
		if a >= use_poly.size() or b >= use_poly.size() or c >= use_poly.size():
			continue
		var tri := CollisionPolygon2D.new()
		tri.polygon = PackedVector2Array([use_poly[a], use_poly[b], use_poly[c]])
		body.add_child(tri)

func _bounds_bbox(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return _world_rect
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for p in poly:
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	return Rect2(Vector2(min_x, min_y), Vector2(maxf(1.0, max_x - min_x), maxf(1.0, max_y - min_y)))
