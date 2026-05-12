extends Node2D

# Menu ambient layer rebuilt from scratch:
# - Uses curated roster assets from character_registry.json (assets/characters/*)
# - Actors "live" in the background with walk/idle/run behavior
# - Adds small service drones so the factory scene feels active

@export var enabled: bool = true
@export var actor_count: int = 52
@export var drone_count: int = 14
@export var margin_px: float = 100.0
@export var avoid_card_padding_px: float = 42.0
@export var walk_speed_min: float = 26.0
@export var walk_speed_max: float = 56.0
@export var run_speed_min: float = 78.0
@export var run_speed_max: float = 120.0
@export var personal_space_radius: float = 42.0
@export var personal_space_force: float = 88.0

var _rng := RandomNumberGenerator.new()
var _actors: Array[Dictionary] = []
var _drones: Array[Dictionary] = []
var _entries: Array[Dictionary] = []
var _frames_cache: Dictionary = {}
var _vp_size := Vector2(1280, 720)
var _avoid_rect := Rect2()
var _avoid_spawn_rect := Rect2()
var _t: float = 0.0

func _ready() -> void:
	if not enabled:
		queue_free()
		return
	top_level = true
	z_index = -70
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_rng.seed = int(Time.get_ticks_usec())
	_load_registry_entries()
	_update_metrics()
	_spawn_actors()
	_spawn_drones()

func _process(delta: float) -> void:
	_t += delta
	_update_metrics()
	_tick_actors(delta)
	_tick_drones(delta)

func _load_registry_entries() -> void:
	_entries.clear()
	var path := "res://data/character_registry.json"
	if not ResourceLoader.exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root := parsed as Dictionary
	var chars := root.get("characters", {}) as Dictionary
	for k in chars.keys():
		var e := chars.get(k, {}) as Dictionary
		if e.is_empty():
			continue
		var folder := String(e.get("folder", ""))
		if folder == "":
			continue
		var front_dir := "res://assets/characters/%s/frames/walk_front" % folder
		if not DirAccess.dir_exists_absolute(front_dir):
			continue
		_entries.append({
			"id": String(k),
			"folder": folder
		})

func _update_metrics() -> void:
	_vp_size = get_viewport().get_visible_rect().size
	var menu := get_parent() as Control
	var card := menu.get_node_or_null("MenuRoot/MenuCard") as Control if menu != null else null
	if card != null and is_instance_valid(card):
		_avoid_rect = card.get_global_rect().grow(avoid_card_padding_px)
		# Keep only the button panel area clear; allow movement around it.
		_avoid_spawn_rect = _avoid_rect.grow(18.0)
		return
	var c := _vp_size * 0.5
	var fallback := Vector2(620.0, 560.0)
	_avoid_rect = Rect2(c - fallback * 0.5, fallback)
	_avoid_spawn_rect = _avoid_rect.grow(18.0)

func _spawn_actors() -> void:
	_actors.clear()
	for c in get_children():
		if c is AnimatedSprite2D:
			c.queue_free()

	if _entries.is_empty():
		return
	var n := mini(actor_count, 140)
	var spawned_positions: Array[Vector2] = []
	for i in range(n):
		var entry := _entries[_rng.randi_range(0, _entries.size() - 1)]
		var frames := _frames_for_folder(String(entry.get("folder", "")))
		if frames == null:
			continue
		var spr := AnimatedSprite2D.new()
		spr.name = "AmbientActor_%d" % i
		spr.sprite_frames = frames
		spr.animation = "walk_south"
		spr.play()
		spr.position = _pick_spawn_position(spawned_positions)
		spawned_positions.append(spr.position)
		var depth := _rng.randf_range(0.58, 1.0)
		spr.scale = Vector2.ONE * (0.44 * depth)
		spr.modulate = Color(1, 1, 1, _rng.randf_range(0.78, 0.95))
		spr.z_index = int(spr.position.y)
		add_child(spr)
		_actors.append({
			"spr": spr,
			"target": _pick_spawn_position(spawned_positions),
			"state": "walk",
			"state_t": _rng.randf_range(0.6, 2.4),
			"walk_speed": _rng.randf_range(walk_speed_min, walk_speed_max),
			"run_speed": _rng.randf_range(run_speed_min, run_speed_max),
			"flip_h": false
		})

func _spawn_drones() -> void:
	_drones.clear()
	for i in range(drone_count):
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array([
			Vector2(-8, -3), Vector2(9, -3), Vector2(6, 3), Vector2(-7, 3)
		])
		p.color = Color(0.50, 0.88, 1.0, _rng.randf_range(0.36, 0.58))
		p.position = Vector2(_rng.randf_range(0, _vp_size.x), _rng.randf_range(0, _vp_size.y))
		p.z_index = -65
		add_child(p)
		_drones.append({
			"node": p,
			"vel": Vector2(_rng.randf_range(-34, 34), _rng.randf_range(-12, 12)),
			"phase": _rng.randf_range(0.0, TAU)
		})

func _tick_actors(delta: float) -> void:
	for i in range(_actors.size()):
		var a := _actors[i]
		var spr := a.get("spr") as AnimatedSprite2D
		if spr == null or not is_instance_valid(spr):
			continue
		var state := String(a.get("state", "walk"))
		var state_t := float(a.get("state_t", 0.0)) - delta
		var p := spr.position
		var tgt := a.get("target", p) as Vector2
		if state_t <= 0.0:
			var roll := _rng.randf()
			if roll < 0.16:
				state = "idle"
				state_t = _rng.randf_range(0.5, 1.8)
			elif roll < 0.36:
				state = "run"
				state_t = _rng.randf_range(0.8, 1.6)
				tgt = _pick_spawn_position()
			else:
				state = "walk"
				state_t = _rng.randf_range(1.1, 3.0)
				tgt = _pick_spawn_position()
		var to := tgt - p
		# Prevent long-lived bunches by retargeting if local density spikes.
		if _local_density(p, personal_space_radius * 1.45) >= 8:
			tgt = _pick_spawn_position()
			to = tgt - p
			if state == "idle":
				state = "walk"
				state_t = _rng.randf_range(0.7, 1.6)
		var speed := float(a.get("walk_speed", 40.0))
		if state == "run":
			speed = float(a.get("run_speed", 90.0))
		var repel := _repulsion_for_index(i, p)
		if repel != Vector2.ZERO:
			var mixed := ((to.normalized() if to.length() > 0.1 else Vector2.ZERO) + repel).normalized()
			if mixed != Vector2.ZERO:
				to = mixed * maxf(to.length(), 64.0)
				if state == "idle":
					state = "walk"
					state_t = _rng.randf_range(0.8, 1.5)
		if state == "idle" or to.length() < 8.0:
			if state != "idle":
				state = "walk"
				state_t = _rng.randf_range(1.0, 2.2)
				tgt = _pick_spawn_position()
			_set_anim_from_dir(spr, Vector2.DOWN, false)
		else:
			var dir := to.normalized()
			p += dir * speed * delta
			_set_anim_from_dir(spr, dir, state == "run")
		if _avoid_rect.has_point(p):
			p = _redirect_out_of_ui(p)
			tgt = _pick_spawn_position()
		var min_x := -margin_px
		var max_x := _vp_size.x + margin_px
		var min_y := -margin_px
		var max_y := _vp_size.y + margin_px
		var hit_edge := false
		if p.x < min_x:
			p.x = min_x
			hit_edge = true
		elif p.x > max_x:
			p.x = max_x
			hit_edge = true
		if p.y < min_y:
			p.y = min_y
			hit_edge = true
		elif p.y > max_y:
			p.y = max_y
			hit_edge = true
		if hit_edge:
			tgt = _pick_spawn_position()
			if state == "idle":
				state = "walk"
				state_t = _rng.randf_range(0.8, 1.6)
		spr.position = p
		spr.z_index = int(p.y)
		a["state"] = state
		a["state_t"] = state_t
		a["target"] = tgt
		_actors[i] = a

func _tick_drones(delta: float) -> void:
	for d in _drones:
		var n := d.get("node") as Polygon2D
		if n == null or not is_instance_valid(n):
			continue
		var vel := d.get("vel", Vector2.ZERO) as Vector2
		var p := n.position + vel * delta
		p.x = wrapf(p.x, -24, _vp_size.x + 24)
		p.y = wrapf(p.y, -24, _vp_size.y + 24)
		n.position = p
		var ph := float(d.get("phase", 0.0))
		n.modulate.a = 0.30 + 0.20 * (0.5 + 0.5 * sin(_t * 2.6 + ph))

func _set_anim_from_dir(spr: AnimatedSprite2D, dir: Vector2, is_running: bool) -> void:
	if spr.sprite_frames == null:
		return
	var anim := "walk_south"
	if absf(dir.x) > absf(dir.y):
		anim = "walk_east" if dir.x >= 0.0 else "walk_west"
	elif dir.y < 0.0:
		anim = "walk_north"
	if spr.sprite_frames.has_animation(anim) and spr.animation != anim:
		spr.animation = anim
		spr.play()
	var flip := false
	if anim == "walk_east" and bool(spr.sprite_frames.get_meta("flip_h_for_walk_east", false)):
		flip = true
	elif anim == "walk_west" and bool(spr.sprite_frames.get_meta("flip_h_for_walk_west", false)):
		flip = true
	spr.flip_h = flip
	spr.speed_scale = 1.85 if is_running else 1.0

func _pick_spawn_position(existing_positions: Array[Vector2] = []) -> Vector2:
	var zones := _movement_zones()
	if not zones.is_empty():
		for _try_zone in range(36):
			var z: Rect2 = zones[_rng.randi_range(0, zones.size() - 1)]
			if z.size.x <= 1.0 or z.size.y <= 1.0:
				continue
			var pz := Vector2(
				_rng.randf_range(z.position.x, z.position.x + z.size.x),
				_rng.randf_range(z.position.y, z.position.y + z.size.y)
			)
			if _avoid_spawn_rect.has_point(pz):
				continue
			if _local_density(pz, personal_space_radius * 1.35) >= 5:
				continue
			var blocked_zone := false
			for ep in existing_positions:
				if ep.distance_to(pz) < personal_space_radius * 0.85:
					blocked_zone = true
					break
			if not blocked_zone:
				return pz
	for _i in range(48):
		var p := Vector2(
			_rng.randf_range(-margin_px, _vp_size.x + margin_px),
			_rng.randf_range(-margin_px, _vp_size.y + margin_px)
		)
		if _avoid_spawn_rect.has_point(p):
			continue
		var blocked := false
		for ep in existing_positions:
			if ep.distance_to(p) < personal_space_radius * 0.85:
				blocked = true
				break
		if not blocked and _local_density(p, personal_space_radius * 1.3) < 5:
			return p
	return _avoid_rect.position + Vector2(-22, _rng.randf_range(0, _avoid_rect.size.y))

func _redirect_out_of_ui(p: Vector2) -> Vector2:
	# Push to the nearest edge of the panel instead of a fixed side,
	# so movement distributes around top/left/right naturally.
	var c := _avoid_rect.get_center()
	var local := p - c
	var ext := _avoid_rect.size * 0.5
	var dx := ext.x - absf(local.x)
	var dy := ext.y - absf(local.y)
	var out := p
	if dx < dy:
		# Exit left or right edge.
		var sign_x := 1.0 if local.x >= 0.0 else -1.0
		out.x = c.x + sign_x * (ext.x + 26.0 + _rng.randf_range(6.0, 70.0))
		out.y += _rng.randf_range(-64.0, 64.0)
	else:
		# Exit top or bottom edge.
		var sign_y := 1.0 if local.y >= 0.0 else -1.0
		out.y = c.y + sign_y * (ext.y + 26.0 + _rng.randf_range(6.0, 70.0))
		out.x += _rng.randf_range(-92.0, 92.0)
	out.x = clampf(out.x, -margin_px, _vp_size.x + margin_px)
	out.y = clampf(out.y, -margin_px, _vp_size.y + margin_px)
	if _avoid_spawn_rect.has_point(out):
		out = _pick_spawn_position()
	return out

func _local_density(p: Vector2, radius: float) -> int:
	var count := 0
	var r2 := radius * radius
	for a in _actors:
		var s := a.get("spr") as AnimatedSprite2D
		if s == null or not is_instance_valid(s):
			continue
		if s.position.distance_squared_to(p) <= r2:
			count += 1
	return count

func _movement_zones() -> Array[Rect2]:
	var zones: Array[Rect2] = []
	var left := _avoid_rect.position.x
	var right := _avoid_rect.position.x + _avoid_rect.size.x
	var top := _avoid_rect.position.y
	var bottom := _avoid_rect.position.y + _avoid_rect.size.y
	var x0 := -margin_px
	var x1 := _vp_size.x + margin_px
	var y0 := -margin_px
	var y1 := _vp_size.y + margin_px
	var pad := 22.0
	# Above menu panel.
	if top - y0 > 56.0:
		zones.append(Rect2(Vector2(x0, y0), Vector2(x1 - x0, top - y0 - pad)))
	# Left of panel.
	if left - x0 > 56.0:
		zones.append(Rect2(Vector2(x0, y0), Vector2(left - x0 - pad, y1 - y0)))
	# Right of panel.
	if x1 - right > 56.0:
		zones.append(Rect2(Vector2(right + pad, y0), Vector2(x1 - (right + pad), y1 - y0)))
	# Below panel.
	if y1 - bottom > 56.0:
		zones.append(Rect2(Vector2(x0, bottom + pad), Vector2(x1 - x0, y1 - (bottom + pad))))
	return zones

func _repulsion_for_index(i: int, p: Vector2) -> Vector2:
	var out := Vector2.ZERO
	var rad := personal_space_radius
	var rad_sq := rad * rad
	for j in range(_actors.size()):
		if i == j:
			continue
		var other_spr := _actors[j].get("spr") as AnimatedSprite2D
		if other_spr == null or not is_instance_valid(other_spr):
			continue
		var d := p - other_spr.position
		var dist_sq := d.length_squared()
		if dist_sq <= 0.001 or dist_sq > rad_sq:
			continue
		var dist := sqrt(dist_sq)
		var w := 1.0 - (dist / rad)
		out += d / dist * w
	if out == Vector2.ZERO:
		return out
	return out.normalized() * (personal_space_force / 100.0)

func _frames_for_folder(folder: String) -> SpriteFrames:
	if folder == "":
		return null
	if _frames_cache.has(folder):
		return _frames_cache[folder]
	var root := "res://assets/characters/%s/frames" % folder
	var sf := SpriteFrames.new()
	_add_anim_frames(sf, "walk_south", "%s/walk_front" % root)
	_add_anim_frames(sf, "walk_north", "%s/walk_back" % root)
	_add_anim_frames(sf, "walk_east", "%s/walk_side_right" % root)
	if sf.has_animation("walk_east") and sf.get_frame_count("walk_east") > 0:
		sf.add_animation("walk_west")
		sf.set_animation_speed("walk_west", sf.get_animation_speed("walk_east"))
		for i in range(sf.get_frame_count("walk_east")):
			sf.add_frame("walk_west", sf.get_frame_texture("walk_east", i))
		sf.set_meta("flip_h_for_walk_west", true)
	if not sf.has_animation("walk_south") or sf.get_frame_count("walk_south") <= 0:
		_frames_cache[folder] = null
		return null
	_frames_cache[folder] = sf
	return sf

func _add_anim_frames(sf: SpriteFrames, anim: String, dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var frames: Array[String] = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	while true:
		var n := da.get_next()
		if n == "":
			break
		if da.current_is_dir():
			continue
		if n.begins_with("frame_") and n.ends_with(".png"):
			frames.append(n)
	da.list_dir_end()
	frames.sort()
	if frames.is_empty():
		return
	sf.add_animation(anim)
	sf.set_animation_loop(anim, true)
	sf.set_animation_speed(anim, 13.0)
	for f in frames:
		var tex := load("%s/%s" % [dir_path, f]) as Texture2D
		if tex != null:
			sf.add_frame(anim, tex)
