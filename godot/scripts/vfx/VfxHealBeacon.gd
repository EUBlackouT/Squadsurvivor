class_name VfxHealBeacon
extends Node2D

# Healer callout: a healing zone that ticks for a short time.

var _radius: float = 220.0
var _duration: float = 4.0
var _heal_pct_per_tick: float = 0.06 # 6% max hp per second
var _tick_s: float = 1.0
var _t: float = 0.0
var _tick_accum: float = 0.0
var _color: Color = Color(0.55, 1.0, 0.65, 0.85)
var _main: Node2D = null
var _use_flipbook: bool = false
var _flipbook: VfxFlipbook2D = null

func setup(world_pos: Vector2, radius: float, duration: float, heal_pct_per_tick: float = 0.06, tick_s: float = 1.0) -> void:
	global_position = world_pos
	_radius = maxf(32.0, radius)
	_duration = maxf(0.2, duration)
	_heal_pct_per_tick = clampf(heal_pct_per_tick, 0.01, 0.20)
	_tick_s = clampf(tick_s, 0.2, 2.0)

func _ready() -> void:
	top_level = true
	z_index = 36
	_main = get_tree().get_first_node_in_group("main") as Node2D

	# Prefer EffectBlocks flipbook if exported (callout.beacon).
	var vfx := get_node_or_null("/root/VfxSystem")
	if vfx and is_instance_valid(vfx) and vfx.has_method("get_event_cfg") and vfx.has_method("get_frames_for_key"):
		var cfg: Dictionary = vfx.get_event_cfg("callout.beacon") as Dictionary
		var key := String(cfg.get("effect_key", ""))
		var frames: Array = vfx.get_frames_for_key(key) as Array
		if not frames.is_empty():
			_flipbook = VfxFlipbook2D.new()
			_flipbook.name = "BeaconFlipbook"
			add_child(_flipbook)
			_flipbook.z_index = int(cfg.get("z", z_index))
			var fps := float(cfg.get("fps", 12))
			var sc := float(cfg.get("scale", 1.0))
			var tint := Color(1, 1, 1, 1)
			var tint_cfg: Variant = cfg.get("tint", null)
			if typeof(tint_cfg) == TYPE_STRING:
				tint = tint * Color.html(String(tint_cfg))
			tint = tint * _color
			_flipbook.setup(frames as Array[Texture2D], fps, true, tint, sc)
			_use_flipbook = true

func _process(delta: float) -> void:
	_t += delta
	_tick_accum += delta
	if _t >= _duration:
		queue_free()
		return
	if _tick_accum >= _tick_s:
		_tick_accum = 0.0
		_tick_heal()
	if not _use_flipbook:
		queue_redraw()

func _tick_heal() -> void:
	var squad: Array = []
	if _main != null and is_instance_valid(_main) and _main.has_method("get_cached_squad_units"):
		squad = _main.get_cached_squad_units()
	else:
		squad = get_tree().get_nodes_in_group("squad_units")
	var r2 := _radius * _radius
	for u in squad:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(global_position) <= r2:
			if n2.has_method("get_max_hp") and n2.has_method("heal"):
				var mh := int(n2.get_max_hp())
				var amt := maxi(1, int(round(float(mh) * _heal_pct_per_tick)))
				n2.heal(amt)

func _draw() -> void:
	if _use_flipbook:
		return
	# Pulsing ring + soft fill
	var a := 1.0 - clampf(_t / maxf(0.001, _duration), 0.0, 1.0)
	var pulse := 0.75 + 0.25 * sin(_t * 6.0)
	var col := Color(_color.r, _color.g, _color.b, _color.a * a)
	draw_circle(Vector2.ZERO, _radius, Color(col.r, col.g, col.b, col.a * 0.12 * pulse))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, Color(col.r, col.g, col.b, col.a * 0.55), 3.0, true)






