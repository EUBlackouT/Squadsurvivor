extends Area2D

@export var speed: float = 520.0
@export var damage: int = 10
@export var pierce_count: int = 0
@export var hit_radius: float = 14.0

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

static var _bullet_tex: Texture2D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	add_to_group("projectiles")
	_main = get_tree().get_first_node_in_group("main") as Node2D

	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)
	# Better bullet: capsule w/ outline + glow + short trail (still ultra-lightweight).
	if _bullet_tex == null:
		_bullet_tex = _make_bullet_tex()
	sprite.texture = _bullet_tex
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2(1.15, 1.15)
	sprite.z_index = 20

	_glow = Sprite2D.new()
	_glow.name = "Glow"
	_glow.texture = _bullet_tex
	_glow.centered = true
	_glow.z_index = 19
	_glow.scale = Vector2(2.2, 2.2)
	_glow.modulate = Color(1, 1, 1, 0.35)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	add_child(_glow)

	_trail = Line2D.new()
	_trail.name = "Trail"
	_trail.top_level = true
	_trail.z_index = 18
	_trail.width = 3.0
	_trail.antialiased = true
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_trail)

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
	pierce_count += PassiveSystem.extra_pierce_count(passive_ids)
	_update_rotation()

func add_pierce(n: int) -> void:
	if n > 0:
		pierce_count += n

func _physics_process(delta: float) -> void:
	if has_hit and pierce_count <= 0:
		return
	if target != null and is_instance_valid(target):
		target_pos = target.global_position
	var dir := (target_pos - global_position)
	var dist := dir.length()
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
		enemy.take_damage(damage, is_crit, "ranged")
		_spawn_hit_vfx(enemy)
	_pierced_enemies.append(enemy)
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

	# Crisp impact flash (reads as "hit" even on dark maps)
	var c0 := sprite.modulate if sprite != null else Color(0.85, 0.92, 1.0, 1.0)
	var flash := VfxImpactFlash.new()
	flash.setup(pos, Color(c0.r, c0.g, c0.b, 1.0), 16.0, 0.10)
	main.add_child(flash)

	# Small impact spark (uses FlameBurst as generic spark burst)
	var c := c0
	var fb := VfxFlameBurst.new()
	fb.setup(pos, Color(c.r, c.g, c.b, 0.9), 18.0, 7, 0.16, dir)
	main.add_child(fb)

	# Crit marker
	if is_crit:
		var fm := VfxFocusMark.new()
		fm.setup(pos, Color(1.0, 0.85, 0.30, 1.0), 16.0, 0, 0.16)
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
	var max_pts := 9
	while _trail_points.size() > max_pts:
		_trail_points.remove_at(0)
	_trail.points = _trail_points

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
