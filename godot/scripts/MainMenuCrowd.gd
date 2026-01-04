extends Node2D

# Background crowd for MainMenu: lots of characters wandering to make the menu feel alive.
# - Lightweight: AnimatedSprite2D only (no physics).
# - Safe: top_level + negative z_index, never blocks UI.
# - Robust: works even if some Pixellab entries have only rotations (adds bob so they don't feel frozen).

@export var enabled: bool = true
@export var crowd_count: int = 220
@export var margin_px: float = 120.0
@export var avoid_card_padding_px: float = 55.0
@export var ring_bias: float = 0.75 # 0=uniform spawn, 1=mostly spawn near the modal ring
@export var speed_min: float = 42.0
@export var speed_max: float = 98.0
@export var turn_jitter_s: float = 0.9
@export var alpha_min: float = 0.55
@export var alpha_max: float = 0.90

var _rng: RandomNumberGenerator
var _actors: Array[Dictionary] = []
var _vp_size: Vector2 = Vector2(1280, 720)
var _avoid_rect: Rect2 = Rect2()
var _t: float = 0.0

func _ready() -> void:
	if not enabled:
		queue_free()
		return
	top_level = true
	z_index = -50
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_process_input(false)
	set_process_unhandled_input(false)

	_rng = RandomNumberGenerator.new()
	_rng.seed = int(Time.get_ticks_usec())

	PixellabUtil.ensure_loaded()
	_update_viewport_metrics()
	_spawn_crowd()

func _process(delta: float) -> void:
	_t += delta
	_update_viewport_metrics()
	_tick(delta)

func _update_viewport_metrics() -> void:
	var r := get_viewport().get_visible_rect()
	_vp_size = r.size
	var c := _vp_size * 0.5
	# Approximate the main menu card bounds: 560x500 centered, plus padding.
	var w := 560.0 + avoid_card_padding_px * 2.0
	var h := 500.0 + avoid_card_padding_px * 2.0
	_avoid_rect = Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))

func _spawn_crowd() -> void:
	_actors.clear()
	for ch in get_children():
		if is_instance_valid(ch):
			ch.queue_free()

	# Higher cap is OK here because these are just AnimatedSprite2D draws (no physics),
	# but keep it bounded for older GPUs.
	var n := clampi(crowd_count, 0, 260)
	for i in range(n):
		var spr := AnimatedSprite2D.new()
		spr.name = "CrowdActor_%d" % i
		spr.centered = true
		spr.z_index = -50 + i

		var south := PixellabUtil.pick_random_south_path(_rng)
		var frames := PixellabUtil.walk_frames_from_south_path(south)
		if frames != null:
			spr.sprite_frames = frames
		spr.animation = "walk_south"
		spr.play()

		# Depth / variety
		# Smaller silhouettes so we can fit more on-screen without feeling messy.
		var depth := _rng.randf_range(0.42, 0.78)
		spr.scale = Vector2.ONE * (1.05 * depth)
		spr.modulate = Color(1, 1, 1, _rng.randf_range(alpha_min, alpha_max))

		# Start position (avoid the main card)
		var p := _pick_spawn_pos()
		spr.position = p

		# Velocity / turn timer
		var dir := _random_dir()
		var spd := _rng.randf_range(speed_min, speed_max) / depth
		var vel := dir * spd
		var turn_cd := _rng.randf_range(0.2, turn_jitter_s)

		add_child(spr)

		_actors.append({
			"spr": spr,
			"vel": vel,
			"depth": depth,
			"turn_cd": turn_cd,
			"bob_phase": _rng.randf_range(0.0, TAU),
			"last_anim": "walk_south"
		})

func _pick_spawn_pos() -> Vector2:
	var tries := 0
	while tries < 40:
		tries += 1
		var p := Vector2.ZERO
		var use_ring := _rng.randf() < clampf(ring_bias, 0.0, 1.0)
		if use_ring:
			# Spawn near the "ring" around the avoid rect (cluttered around the modal).
			var c := _vp_size * 0.5
			var ring_pad := _rng.randf_range(12.0, 110.0)
			var ring_w := (_avoid_rect.size.x * 0.5) + ring_pad
			var ring_h := (_avoid_rect.size.y * 0.5) + ring_pad
			var side := _rng.randi_range(0, 3)
			match side:
				0:
					p = c + Vector2(_rng.randf_range(-ring_w, ring_w), -ring_h)
				1:
					p = c + Vector2(_rng.randf_range(-ring_w, ring_w), ring_h)
				2:
					p = c + Vector2(-ring_w, _rng.randf_range(-ring_h, ring_h))
				_:
					p = c + Vector2(ring_w, _rng.randf_range(-ring_h, ring_h))
			# small jitter so it doesn't look grid-aligned
			p += Vector2(_rng.randf_range(-24, 24), _rng.randf_range(-18, 18))
		else:
			p = Vector2(
				_rng.randf_range(-margin_px, _vp_size.x + margin_px),
				_rng.randf_range(-margin_px, _vp_size.y + margin_px)
			)
		if not _avoid_rect.has_point(p):
			return p
	# fallback: just outside the card
	return _avoid_rect.position + Vector2(-30, _rng.randf_range(0, _avoid_rect.size.y))

func _random_dir() -> Vector2:
	# Prefer mostly-horizontal motion (looks lively and avoids vertical stacking).
	var ang := _rng.randf_range(-0.45, 0.45)
	if _rng.randf() < 0.35:
		ang = _rng.randf_range(1.2, 1.9) if _rng.randf() < 0.5 else _rng.randf_range(-1.9, -1.2)
	return Vector2(cos(ang), sin(ang)).normalized()

func _tick(delta: float) -> void:
	var w := _vp_size.x
	var h := _vp_size.y
	var c := _vp_size * 0.5

	for a in _actors:
		var spr := a["spr"] as AnimatedSprite2D
		if spr == null or not is_instance_valid(spr):
			continue

		var vel: Vector2 = a["vel"]
		var depth: float = float(a["depth"])

		# Occasionally turn a bit (keeps things from feeling robotic)
		var cd: float = float(a["turn_cd"]) - delta
		if cd <= 0.0:
			cd = _rng.randf_range(0.25, turn_jitter_s)
			var turn := _rng.randf_range(-0.8, 0.8)
			vel = vel.rotated(turn)
			# Clamp speed
			var spd := clampf(vel.length(), speed_min / depth, speed_max / depth)
			vel = vel.normalized() * spd
		a["turn_cd"] = cd

		# Avoid the center card: push outward smoothly if inside the avoid rect
		var p := spr.position
		if _avoid_rect.has_point(p):
			var away := (p - c)
			if away.length() < 1.0:
				away = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
			vel = vel.lerp(away.normalized() * vel.length(), 0.25)

		p += vel * delta

		# Wrap around edges
		if p.x < -margin_px:
			p.x = w + margin_px
		elif p.x > w + margin_px:
			p.x = -margin_px
		if p.y < -margin_px:
			p.y = h + margin_px
		elif p.y > h + margin_px:
			p.y = -margin_px
		spr.position = p

		# Apply animation direction from velocity (with PixellabUtil flip meta support)
		_apply_walk_anim(spr, vel, a)

		# If the current anim is effectively static (1 frame), add a subtle bob.
		var bob := sin(_t * 6.0 + float(a["bob_phase"])) * 1.2
		spr.position.y += bob

		a["vel"] = vel

func _apply_walk_anim(spr: AnimatedSprite2D, vel: Vector2, a: Dictionary) -> void:
	if spr.sprite_frames == null:
		return
	var sf := spr.sprite_frames
	var dir := vel.normalized()
	var ax := absf(dir.x)
	var ay := absf(dir.y)
	var desired := String(a.get("last_anim", "walk_south"))
	var threshold := 0.10
	if ax > ay + threshold:
		desired = "walk_east" if dir.x >= 0.0 else "walk_west"
	elif ay > ax + threshold:
		desired = "walk_south" if dir.y > 0.0 else "walk_north"

	if sf.has_animation(desired) and sf.get_frame_count(desired) > 0:
		if spr.animation != desired:
			spr.animation = desired
			spr.play()
	else:
		# conservative fallback
		if sf.has_animation("walk_south") and sf.get_frame_count("walk_south") > 0:
			if spr.animation != "walk_south":
				spr.animation = "walk_south"
				spr.play()

	# Apply flip if this SpriteFrames requested mirroring for missing east/west.
	var flip := false
	if spr.animation == "walk_east" and bool(sf.get_meta("flip_h_for_walk_east", false)):
		flip = true
	elif spr.animation == "walk_west" and bool(sf.get_meta("flip_h_for_walk_west", false)):
		flip = true
	spr.flip_h = flip
	a["last_anim"] = spr.animation


