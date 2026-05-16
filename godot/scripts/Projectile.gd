extends Area2D

@export var speed: float = 560.0  # Slightly slower so in-flight shots read clearly
@export var damage: int = 10
@export var pierce_count: int = 0
@export var hit_radius: float = 16.0  # Slightly easier to hit

var target: Node2D = null
var target_pos: Vector2 = Vector2.ZERO
var has_hit: bool = false
var is_crit: bool = false
var passive_ids: PackedStringArray = PackedStringArray()
var source_cd: CharacterData = null
var source_unit: Node2D = null
var _pierced_enemies: Array[Node2D] = []
var _main: Node2D = null

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
var _glow: Sprite2D = null
var _trail: Line2D = null
var _trail_points: PackedVector2Array = PackedVector2Array()
var _trail_last: Vector2 = Vector2.INF
var _flipbook: VfxFlipbook2D = null
var _flipbook_rot_offset: float = 0.0
var _direction_mode: bool = false
var _direction: Vector2 = Vector2.ZERO
var _trail_max_points: int = 14
var _visual_profile: String = "bolt"
var _impact_scale: float = 1.0
var _pierce_hits: int = 0

static var _bullet_tex: Texture2D = null
static var _profile_tex_cache: Dictionary = {} # profile -> Texture2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	add_to_group("projectiles")
	_main = get_tree().get_first_node_in_group("main") as Node2D

	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)
	# Prefer custom projectile sprite by default; flipbook can be enabled per-event.
	# This avoids "sheet-looking" projectiles when a generic atlas effect is configured.
	var vfx := get_node_or_null("/root/VfxSystem")
	var used_flipbook := false
	if vfx and is_instance_valid(vfx) and vfx.has_method("get_event_cfg") and vfx.has_method("get_frames_for_key"):
		var cfg: Dictionary = vfx.get_event_cfg("proj.player") as Dictionary
		var use_flipbook := bool(cfg.get("use_flipbook", false))
		if use_flipbook:
			var key := String(cfg.get("effect_key", ""))
			var frames: Array = vfx.get_frames_for_key(key) as Array
			if not frames.is_empty():
				_flipbook = VfxFlipbook2D.new()
				_flipbook.name = "ProjFlipbook"
				add_child(_flipbook)
				_flipbook.z_index = int(cfg.get("z", 20))
				var fps := float(cfg.get("fps", 16))
				var sc := float(cfg.get("scale", 0.55))
				_flipbook_rot_offset = deg_to_rad(float(cfg.get("rot_deg", 0.0)))
				_flipbook.setup(frames as Array[Texture2D], fps, true, Color(1, 1, 1, 1), sc)
				_flipbook.rotation = _flipbook_rot_offset
				used_flipbook = true

	if used_flipbook:
		if sprite: sprite.visible = false
		return

	# Fallback bullet: capsule w/ outline + glow + short trail (still ultra-lightweight).
	if _bullet_tex == null:
		_bullet_tex = _make_bullet_tex()
	sprite.texture = _bullet_tex
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2(2.35, 2.35)
	sprite.z_index = 20

	_glow = Sprite2D.new()
	_glow.name = "Glow"
	_glow.texture = _bullet_tex
	_glow.centered = true
	_glow.z_index = 19
	_glow.scale = Vector2(3.6, 3.6)
	_glow.modulate = Color(1, 1, 1, 0.35)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	add_child(_glow)

	_trail = Line2D.new()
	_trail.name = "Trail"
	_trail.top_level = true
	_trail.z_index = 18
	_trail.width = 6.0
	_trail.antialiased = true
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_trail)
	_apply_visual_profile("bolt")

	# IMPORTANT:
	# We do NOT use physics collision shapes for projectiles.
	# The "orb" visuals the user sees match collision debug rendering, so we avoid it entirely.
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	# (Projectile.tscn no longer includes a CollisionShape2D.)

	# Auto cleanup
	await get_tree().create_timer(4.0).timeout
	queue_free()

func set_vfx_color(c: Color) -> void:
	if _flipbook != null and is_instance_valid(_flipbook):
		_flipbook.set_tint(c)
	if sprite:
		sprite.modulate = c
	if _glow:
		_glow.modulate = Color(c.r, c.g, c.b, 0.35)
	if _trail:
		# fade to transparent behind
		var g := Gradient.new()
		g.colors = PackedColorArray([
			Color(c.r, c.g, c.b, 0.0),
			Color(c.r, c.g, c.b, 0.28),
			Color(1, 1, 1, 0.12)
		])
		g.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
		_trail.gradient = g

func set_speed(v: float) -> void:
	speed = maxf(60.0, v)

func set_visual_profile(profile: String) -> void:
	_apply_visual_profile(profile)

func setup_direction(dir: Vector2, dmg: int, p_is_crit: bool = false, p_source_cd: CharacterData = null, p_source_unit: Node2D = null) -> void:
	_direction_mode = true
	_direction = dir.normalized()
	if _direction.length_squared() <= 0.0001:
		_direction = Vector2.RIGHT
	target = null
	target_pos = global_position + _direction * 1200.0
	damage = dmg
	is_crit = p_is_crit
	source_cd = p_source_cd
	source_unit = p_source_unit
	_apply_pack_flipbook_for_source()
	_update_rotation()

func setup(dest: Vector2, dmg: int) -> void:
	target = null
	target_pos = dest
	damage = dmg
	_update_rotation()

func setup_target(t: Node2D, dmg: int, p_is_crit: bool, p_passive_ids: PackedStringArray, p_source_cd: CharacterData = null, p_source_unit: Node2D = null) -> void:
	target = t
	target_pos = t.global_position if t != null and is_instance_valid(t) else target_pos
	damage = dmg
	is_crit = p_is_crit
	passive_ids = p_passive_ids
	source_cd = p_source_cd
	source_unit = p_source_unit
	_direction_mode = false
	_apply_pack_flipbook_for_source()
	pierce_count += PassiveSystem.extra_pierce_count(passive_ids)
	_update_rotation()

func _apply_pack_flipbook_for_source() -> void:
	if source_cd == null:
		return
	var wid := String(source_cd.weapon_id).to_lower()
	var profile := _profile_for_weapon_id(wid)
	_apply_visual_profile(profile)
	var evt := ""
	if wid.find("frost") >= 0 or wid.find("ice") >= 0:
		evt = "weapon.frost_trail"
	elif wid.find("poison") >= 0:
		evt = "weapon.poison"
	elif wid.find("spirit") >= 0:
		evt = "weapon.spirit"
	elif wid.find("fire") >= 0 or wid.find("flame") >= 0:
		evt = "passive.fire_mastery"
	if evt == "":
		return
	var vfx := get_node_or_null("/root/VfxSystem")
	if vfx == null or not is_instance_valid(vfx):
		return
	if not vfx.has_method("get_event_cfg") or not vfx.has_method("get_frames_for_key"):
		return
	var cfg: Dictionary = vfx.get_event_cfg(evt) as Dictionary
	var key := String(cfg.get("effect_key", ""))
	if key == "":
		return
	var frames: Array = vfx.get_frames_for_key(key) as Array
	if frames.is_empty():
		return
	if _flipbook != null and is_instance_valid(_flipbook):
		_flipbook.queue_free()
		_flipbook = null
	_flipbook = VfxFlipbook2D.new()
	_flipbook.name = "ProjFlipbook"
	add_child(_flipbook)
	_flipbook.z_index = int(cfg.get("z", 20))
	var fps := float(cfg.get("fps", 16))
	var sc := float(cfg.get("scale", 0.42))
	_flipbook_rot_offset = deg_to_rad(float(cfg.get("rot_deg", 0.0)))
	_flipbook.setup(frames as Array[Texture2D], fps, true, Color(1, 1, 1, 1), sc)
	_flipbook.rotation = _flipbook_rot_offset
	if sprite != null:
		sprite.visible = false
	if _glow != null and is_instance_valid(_glow):
		_glow.visible = false
	if _trail != null and is_instance_valid(_trail):
		_trail.visible = false

func add_pierce(n: int) -> void:
	if n > 0:
		pierce_count += n

func _physics_process(delta: float) -> void:
	if has_hit and pierce_count <= 0:
		return
	if target != null and is_instance_valid(target):
		target_pos = target.global_position
	var dir := Vector2.ZERO
	var dist := INF
	if _direction_mode:
		dir = _direction
		dist = 9999.0
	else:
		dir = (target_pos - global_position)
		dist = dir.length()
		if dist <= 1.0:
			_explode()
			return
		dir = dir / dist
	global_position += dir * speed * delta
	rotation = dir.angle()
	_tick_trail()
	_manual_hit_check()
	if dist < 12.0:
		_explode()

func _hit_enemy(enemy: Node2D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if has_hit and pierce_count <= 0:
		return
	if _pierced_enemies.has(enemy):
		return

	if enemy.has_method("take_damage"):
		var dealt := damage
		if _visual_profile == "pierce":
			var mp := _main.get_node_or_null("/root/MetaProgression") if _main != null else null
			if mp and is_instance_valid(mp):
				if mp.has_method("get_add"):
					var per := maxf(0.0, float(mp.get_add("pierce_damage_per_enemy_hit_add", 0.0)))
					if per > 0.0:
						dealt = maxi(1, int(round(float(dealt) * (1.0 + float(_pierce_hits) * per))))
					if float(mp.get_add("piercing_hits_can_execute", 0.0)) >= 1.0 and enemy.has_method("get_hp_ratio"):
						var ex := clampf(float(mp.get_add("execute_threshold_add", 0.0)), 0.0, 0.95)
						if float(enemy.get_hp_ratio()) <= ex:
							dealt = maxi(dealt, 999999)
		enemy.take_damage(dealt, is_crit, "ranged")
		_spawn_hit_vfx(enemy)
	_pierced_enemies.append(enemy)
	_pierce_hits += 1
	PassiveSystem.on_projectile_hit(passive_ids, self, enemy, damage, is_crit)
	if source_cd != null:
		SynergySystem.on_projectile_hit(source_cd, self, enemy, damage, is_crit)

	if pierce_count > 0:
		pierce_count -= 1
		if pierce_count <= 0:
			_explode()
	else:
		_explode()

func _spawn_hit_vfx(enemy: Node2D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var main := _main
	if main == null or not is_instance_valid(main):
		main = get_tree().get_first_node_in_group("main") as Node2D
	if main == null:
		return
	var pos := enemy.global_position + Vector2(0, -18)
	var dir := (enemy.global_position - global_position).normalized()

	# SFX: hit impact (throttled by emitter)
	var s := main.get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_event"):
		s.play_event("hit.crit" if is_crit else "hit.ranged", pos, self)

	# Prefer exported EffectBlocks flipbook VFX if available.
	var v := main.get_node_or_null("/root/VfxSystem")
	if v and is_instance_valid(v) and v.has_method("play_event"):
		var ok := bool(v.play_event("hit.crit" if is_crit else "hit.ranged", pos, main, Color(1, 1, 1, 1), 1.0))
		if ok:
			return

	# Crisp impact flash (reads as "hit" even on dark maps)
	var c0 := sprite.modulate if sprite != null else Color(0.85, 0.92, 1.0, 1.0)
	var flash := VfxImpactFlash.new()
	flash.setup(pos, Color(c0.r, c0.g, c0.b, 1.0), 24.0 * _impact_scale, 0.12)
	main.add_child(flash)

	# Small impact spark (uses FlameBurst as generic spark burst)
	var c := c0
	var fb := VfxFlameBurst.new()
	fb.setup(pos, Color(c.r, c.g, c.b, 0.9), 28.0 * _impact_scale, 10, 0.18, dir)
	main.add_child(fb)

	# Crit marker
	if is_crit:
		var fm := VfxFocusMark.new()
		fm.setup(pos, Color(1.0, 0.85, 0.30, 1.0), 16.0 * _impact_scale, 0, 0.16)
		main.add_child(fm)

func _explode() -> void:
	queue_free()

func _update_rotation() -> void:
	var dir := (target_pos - global_position)
	if dir.length() > 0.0:
		rotation = dir.angle()

func _manual_hit_check() -> void:
	# Check enemies within radius (fast enough for our current enemy counts).
	var r2 := hit_radius * hit_radius
	var enemies: Array = []
	if _main and is_instance_valid(_main) and _main.has_method("get_cached_enemies"):
		enemies = _main.get_cached_enemies()
	else:
		enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		if _pierced_enemies.has(n2):
			continue
		if n2.global_position.distance_squared_to(global_position) <= r2:
			_hit_enemy(n2)
			return

func _tick_trail() -> void:
	if _trail == null:
		return
	# Keep a short, smooth trail behind the bullet. Points are in global space (trail is top_level).
	var gp := global_position
	if _trail_last == Vector2.INF:
		_trail_last = gp
		_trail_points = PackedVector2Array([gp])
		_trail.points = _trail_points
		return
	if gp.distance_squared_to(_trail_last) < 64.0: # 8px
		return
	_trail_last = gp
	_trail_points.append(gp)
	while _trail_points.size() > _trail_max_points:
		_trail_points.remove_at(0)
	_trail.points = _trail_points

func _profile_for_weapon_id(wid: String) -> String:
	if wid.find("pierc") >= 0:
		return "pierce"
	if wid.find("scatter") >= 0:
		return "scatter"
	if wid.find("poison") >= 0 or wid.find("toxic") >= 0:
		return "poison"
	if wid.find("frost") >= 0 or wid.find("ice") >= 0:
		return "frost"
	if wid.find("spirit") >= 0 or wid.find("lance") >= 0:
		return "spirit"
	if wid.find("ricochet") >= 0:
		return "ricochet"
	if wid.find("fire") >= 0 or wid.find("flame") >= 0:
		return "fire"
	if wid.find("chain") >= 0 or wid.find("lightning") >= 0:
		return "arc"
	return "bolt"

func _apply_visual_profile(profile: String) -> void:
	_visual_profile = profile
	if sprite == null:
		return
	if _profile_tex_cache.has(profile):
		sprite.texture = _profile_tex_cache.get(profile) as Texture2D
	else:
		var t := _make_profile_tex(profile)
		_profile_tex_cache[profile] = t
		sprite.texture = t
	match profile:
		"pierce":
			sprite.scale = Vector2(2.8, 2.1)
			_trail_max_points = 16
			_impact_scale = 1.15
			set_vfx_color(Color(1.0, 0.92, 0.70, 1.0))
		"scatter":
			sprite.scale = Vector2(1.85, 1.85)
			_trail_max_points = 10
			_impact_scale = 0.85
			set_vfx_color(Color(1.0, 0.82, 0.45, 1.0))
		"poison":
			sprite.scale = Vector2(2.0, 2.0)
			_trail_max_points = 13
			_impact_scale = 1.0
			set_vfx_color(Color(0.45, 1.0, 0.45, 1.0))
		"frost":
			sprite.scale = Vector2(2.25, 2.25)
			_trail_max_points = 12
			_impact_scale = 1.05
			set_vfx_color(Color(0.70, 0.92, 1.0, 1.0))
		"spirit":
			sprite.scale = Vector2(2.5, 2.5)
			_trail_max_points = 15
			_impact_scale = 1.2
			set_vfx_color(Color(0.88, 0.68, 1.0, 1.0))
		"ricochet":
			sprite.scale = Vector2(2.15, 2.15)
			_trail_max_points = 11
			_impact_scale = 0.95
			set_vfx_color(Color(1.0, 0.88, 0.55, 1.0))
		"fire":
			sprite.scale = Vector2(2.35, 2.35)
			_trail_max_points = 13
			_impact_scale = 1.15
			set_vfx_color(Color(1.0, 0.55, 0.22, 1.0))
		"arc":
			sprite.scale = Vector2(2.0, 2.0)
			_trail_max_points = 11
			_impact_scale = 0.92
			set_vfx_color(Color(0.65, 0.88, 1.0, 1.0))
		_:
			sprite.scale = Vector2(2.35, 2.35)
			_trail_max_points = 14
			_impact_scale = 1.0
			set_vfx_color(Color(0.9, 0.95, 1.0, 1.0))
	if _trail != null and is_instance_valid(_trail):
		match profile:
			"pierce":
				_trail.width = 6.8
			"scatter":
				_trail.width = 4.2
			"spirit":
				_trail.width = 7.2
			_:
				_trail.width = 6.0
	if _glow != null and is_instance_valid(_glow):
		_glow.scale = sprite.scale * 1.55

func _make_profile_tex(profile: String) -> Texture2D:
	match profile:
		"pierce":
			return _make_needle_tex(30, 10, Color(1.0, 0.93, 0.72, 1.0))
		"scatter":
			return _make_shard_tex(16, Color(1.0, 0.82, 0.45, 1.0))
		"poison":
			return _make_needle_tex(22, 9, Color(0.45, 1.0, 0.45, 1.0))
		"frost":
			return _make_diamond_tex(16, Color(0.70, 0.92, 1.0, 1.0))
		"spirit":
			return _make_rune_lance_tex(16, 24, Color(0.88, 0.68, 1.0, 1.0))
		"ricochet":
			return _make_ring_tex(16, Color(1.0, 0.88, 0.55, 1.0))
		"fire":
			return _make_ember_tex(16, Color(1.0, 0.55, 0.22, 1.0))
		"arc":
			return _make_diamond_tex(14, Color(0.65, 0.88, 1.0, 1.0))
		_:
			return _make_bullet_tex()

func _make_needle_tex(w: int, h: int, col: Color) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy: int = h / 2
	for x in range(w):
		var t := float(x) / maxf(1.0, float(w - 1))
		var hw := int(round(lerpf(1.0, float(h) * 0.42, 1.0 - t)))
		for y in range(maxi(0, cy - hw), mini(h, cy + hw + 1)):
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _make_shard_tex(s: int, col: Color) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := s / 2
	for y in range(s):
		for x in range(s):
			if x >= c - y / 2 and x <= c + y / 3 and y <= s - 2:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _make_diamond_tex(s: int, col: Color) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(float(s) * 0.5, float(s) * 0.5)
	for y in range(s):
		for x in range(s):
			var p := Vector2(float(x), float(y))
			var d := absf(p.x - c.x) + absf(p.y - c.y)
			if d <= float(s) * 0.42:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _make_ring_tex(s: int, col: Color) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(float(s) * 0.5, float(s) * 0.5)
	for y in range(s):
		for x in range(s):
			var d := Vector2(float(x), float(y)).distance_to(c)
			if d >= float(s) * 0.28 and d <= float(s) * 0.44:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _make_ember_tex(s: int, col: Color) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(float(s) * 0.5, float(s) * 0.55)
	for y in range(s):
		for x in range(s):
			var p := Vector2(float(x), float(y))
			var d := p.distance_to(c)
			if d <= float(s) * 0.32:
				img.set_pixel(x, y, col)
			elif y < int(float(s) * 0.45) and absf(float(x) - c.x) < float(s) * 0.13:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _make_rune_lance_tex(w: int, h: int, col: Color) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: int = w / 2
	for y in range(h):
		var hw := 1 if y > h / 3 else 2
		for x in range(maxi(0, cx - hw), mini(w, cx + hw + 1)):
			img.set_pixel(x, y, col)
	for i in range(4):
		var yy := int(float(h) * (0.30 + float(i) * 0.15))
		for x in range(maxi(0, cx - 4), mini(w, cx + 5)):
			img.set_pixel(x, yy, Color(col.r, col.g, col.b, 0.85))
	return ImageTexture.create_from_image(img)

func _make_bullet_tex() -> Texture2D:
	# White capsule with subtle outline and hot core.
	var w: int = 26
	var h: int = 14
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(w) * 0.5
	var cy := float(h) * 0.5
	var rx := float(w) * 0.45
	var ry := float(h) * 0.28

	for y in range(h):
		for x in range(w):
			var px := (float(x) + 0.5 - cx) / maxf(0.001, rx)
			var py := (float(y) + 0.5 - cy) / maxf(0.001, ry)
			# Capsule-ish SDF: ellipse with softened ends (good enough at this scale)
			var d := px * px + py * py
			if d > 1.05:
				continue
			var a := clampf(1.0 - (d - 0.25) / 0.80, 0.0, 1.0)
			# darker edge for outline-ish look
			var edge := clampf((d - 0.55) / 0.45, 0.0, 1.0)
			var col := Color(1, 1, 1, a)
			col.a = a
			# bake a little outline by reducing alpha near edges (outline via contrast, not black ring)
			col.r = 1.0
			col.g = 1.0
			col.b = 1.0
			col.a *= lerpf(1.0, 0.72, edge)
			img.set_pixel(x, y, col)

	# A couple darker pixels at the perimeter to imply outline
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			if c.a <= 0.01:
				continue
			# if neighbor is transparent, darken this pixel slightly
			var near_empty := false
			for oy in [-1, 0, 1]:
				for ox in [-1, 0, 1]:
					if ox == 0 and oy == 0:
						continue
					var nx := clampi(x + ox, 0, w - 1)
					var ny := clampi(y + oy, 0, h - 1)
					if img.get_pixel(nx, ny).a <= 0.01:
						near_empty = true
						break
				if near_empty:
					break
			if near_empty:
				img.set_pixel(x, y, Color(0, 0, 0, minf(0.55, c.a)))

	return ImageTexture.create_from_image(img)
