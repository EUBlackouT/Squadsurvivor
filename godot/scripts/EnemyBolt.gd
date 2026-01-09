class_name EnemyBolt
extends Node2D

# Enemy projectile (no collision shapes). Hits squad units with take_damage(int).

@export var speed: float = 520.0
@export var damage: int = 6
@export var hit_radius: float = 12.0

var target: Node2D = null
var _main: Node2D = null
var hit_chance: float = 1.0 # 0..1 (used by Rogue smoke)

@onready var sprite: Sprite2D = null
var _flipbook: VfxFlipbook2D = null
var _tint: Color = Color(1, 1, 1, 1)
var _flipbook_rot_offset: float = 0.0

func _ready() -> void:
	add_to_group("enemy_projectiles")
	_main = get_tree().get_first_node_in_group("main") as Node2D

	# Prefer EffectBlocks-exported flipbook projectile if available.
	var vfx := get_node_or_null("/root/VfxSystem")
	var used_flipbook := false
	if vfx and is_instance_valid(vfx) and vfx.has_method("get_event_cfg") and vfx.has_method("get_frames_for_key"):
		var cfg: Dictionary = vfx.get_event_cfg("proj.enemy") as Dictionary
		var key := String(cfg.get("effect_key", ""))
		var frames: Array = vfx.get_frames_for_key(key) as Array
		if not frames.is_empty():
			_flipbook = VfxFlipbook2D.new()
			_flipbook.name = "EnemyProjFlipbook"
			add_child(_flipbook)
			_flipbook.z_index = int(cfg.get("z", 22))
			var fps := float(cfg.get("fps", 14))
			var sc := float(cfg.get("scale", 0.55))
			_flipbook_rot_offset = deg_to_rad(float(cfg.get("rot_deg", 0.0)))
			_flipbook.setup(frames as Array[Texture2D], fps, true, _tint, sc)
			_flipbook.rotation = _flipbook_rot_offset
			used_flipbook = true

	if not used_flipbook:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		sprite.texture = ImageTexture.create_from_image(img)
		sprite.scale = Vector2(1.6, 1.6)
		sprite.z_index = 22
		sprite.modulate = _tint

	# Auto cleanup
	await get_tree().create_timer(2.2).timeout
	queue_free()

func setup_target(t: Node2D, dmg: int, tint: Color, p_speed: float = 520.0, p_hit_chance: float = 1.0) -> void:
	target = t
	damage = dmg
	speed = p_speed
	hit_chance = clampf(p_hit_chance, 0.0, 1.0)
	_tint = tint
	if _flipbook != null and is_instance_valid(_flipbook):
		_flipbook.set_tint(tint)
	if sprite != null:
		sprite.modulate = tint

func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	var dir := (target.global_position - global_position)
	var dist := dir.length()
	if dist <= 1.0:
		queue_free()
		return
	dir = dir / dist
	global_position += dir * speed * delta
	rotation = dir.angle()
	_manual_hit_check()

func _manual_hit_check() -> void:
	var r2 := hit_radius * hit_radius
	var squad: Array = []
	if _main and is_instance_valid(_main) and _main.has_method("get_cached_squad_units"):
		squad = _main.get_cached_squad_units()
	else:
		squad = get_tree().get_nodes_in_group("squad_units")
	for u in squad:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(global_position) <= r2:
			# Smoke blind can cause a miss. Keep it simple: miss = no damage, projectile fizzles.
			if randf() <= hit_chance:
				if n2.has_method("take_damage"):
					n2.take_damage(damage)
				# VFX: enemy ranged impact (EffectBlocks if exported)
				var world := _main if _main != null else get_tree().get_first_node_in_group("main") as Node2D
				if world != null:
					# SFX: enemy ranged hit (throttled)
					var s := world.get_node_or_null("/root/SfxSystem")
					if s and is_instance_valid(s) and s.has_method("play_event"):
						s.play_event("hit.enemy_ranged", n2.global_position, self)
					var v := world.get_node_or_null("/root/VfxSystem")
					if v and is_instance_valid(v) and v.has_method("play_event"):
						v.play_event("hit.enemy_ranged", n2.global_position, world, Color(1, 0.7, 0.7, 1), 1.0)
			queue_free()
			return


