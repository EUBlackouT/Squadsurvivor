extends CharacterBody2D

@export var character_data: CharacterData
@export var melee_cleave_radius: float = 46.0
@export var melee_cleave_mult: float = 0.35
@export var retarget_interval: float = 0.22

@onready var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var sprite_fallback: Sprite2D = get_node_or_null("Sprite2D")
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")

const PROJ_SCENE: PackedScene = preload("res://scenes/Projectile.tscn")
const SLASH_SCENE: PackedScene = preload("res://scenes/VfxSlash.tscn")

var _main: Node2D = null
var _attack_timer: float = 0.0
var _retarget_t: float = 0.0
var _target_enemy: Node2D = null

var _leader: Node2D = null
var _offset: Vector2 = Vector2.ZERO

var current_hp: int = 100
var _max_hp_effective: int = 100

enum FormationMode { TIGHT, SPREAD, WEDGE, RING }
enum TargetMode { NEAREST, LOWEST_HP, ELITES_FIRST }
var _formation_mode: int = FormationMode.TIGHT
var _target_mode: int = TargetMode.NEAREST
const TARGET_MODE_COUNT: int = 3

var _current_anim: String = "walk_south"
var _anim_cooldown: float = 0.0

var _pulse_tw: Tween = null

func _ready() -> void:
	add_to_group("squad_units")
	_main = get_tree().get_first_node_in_group("main") as Node2D
	if _main and is_instance_valid(_main) and _main.has_method("register_squad_unit"):
		_main.register_squad_unit(self)

	# Physics layers: squad = 3, collide with enemies(2) only
	collision_layer = 1 << 2
	collision_mask = 1 << 1

	if character_data != null:
		_apply_from_data()
	else:
		_apply_placeholder()

	_apply_visuals()

func _exit_tree() -> void:
	if _main and is_instance_valid(_main) and _main.has_method("unregister_squad_unit"):
		_main.unregister_squad_unit(self)

func _apply_from_data() -> void:
	_attack_timer = 0.0
	var mods := SynergySystem.mods_for_cd(character_data)
	_max_hp_effective = int(round(float(character_data.max_hp) * float(mods.get("max_hp_mult", 1.0))))
	_max_hp_effective = maxi(1, _max_hp_effective)
	current_hp = _max_hp_effective

func _apply_placeholder() -> void:
	_max_hp_effective = 120
	current_hp = 120

func _apply_visuals() -> void:
	# Prefer AnimatedSprite2D with PixelLab walk frames, fallback to Sprite2D
	PixellabUtil.ensure_loaded()
	if anim == null:
		anim = AnimatedSprite2D.new()
		anim.name = "AnimatedSprite2D"
		add_child(anim)
		anim.position = Vector2.ZERO
	anim.z_index = 10

	if character_data != null and character_data.sprite_path != "":
		var frames := PixellabUtil.walk_frames_from_south_path(character_data.sprite_path)
		if frames != null:
			anim.sprite_frames = frames
			_current_anim = "walk_south"
			anim.animation = _current_anim
			anim.play()
	# Outline for readability
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/pixel_outline.gdshader")
	mat.set_shader_parameter("outline_color", Color(0, 0, 0, 1))
	mat.set_shader_parameter("outline_px", 1.5)
	anim.material = mat

	# Hide fallback sprite if present
	if sprite_fallback != null:
		sprite_fallback.visible = false

func set_squad_leader(leader: Node2D, offset: Vector2) -> void:
	_leader = leader
	_offset = offset

func set_formation_mode(mode: int) -> void:
	_formation_mode = mode

func set_target_mode(mode: int) -> void:
	_target_mode = mode

func _physics_process(delta: float) -> void:
	_anim_cooldown = maxf(_anim_cooldown - delta, 0.0)
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_retarget_t -= delta

	# Synergy tick (auras/procs with cooldown gating)
	if character_data != null:
		SynergySystem.tick_unit(character_data, self)

	if _retarget_t <= 0.0 or _target_enemy == null or not is_instance_valid(_target_enemy):
		_target_enemy = _find_target()
		_retarget_t = retarget_interval

	if _target_enemy != null and is_instance_valid(_target_enemy):
		_combat_step(delta)
	else:
		_follow_leader(delta)

	_update_health_bar()

func _combat_step(_delta: float) -> void:
	var tgt := _target_enemy
	var dist := global_position.distance_to(tgt.global_position)
	var attack_range := character_data.attack_range if character_data != null else 300.0
	var move_speed := character_data.move_speed if character_data != null else 120.0
	if character_data != null:
		var mods := SynergySystem.mods_for_cd(character_data)
		move_speed *= float(mods.get("move_speed_mult", 1.0))

	var is_melee := character_data != null and character_data.attack_style == CharacterData.AttackStyle.MELEE
	var desired_range := 26.0 if is_melee else attack_range * 0.70

	# Movement: melee sticks, ranged kites slightly
	if dist > attack_range:
		velocity = (tgt.global_position - global_position).normalized() * move_speed
		move_and_slide()
		_update_anim((tgt.global_position - global_position).normalized())
	elif is_melee and dist > desired_range:
		velocity = (tgt.global_position - global_position).normalized() * (move_speed * 1.05)
		move_and_slide()
		_update_anim((tgt.global_position - global_position).normalized())
	elif (not is_melee) and dist < desired_range * 0.75:
		velocity = (global_position - tgt.global_position).normalized() * (move_speed * 0.55)
		move_and_slide()
		_update_anim((tgt.global_position - global_position).normalized())
	else:
		velocity = Vector2.ZERO

	# Attack
	if dist <= attack_range and _attack_timer <= 0.0:
		_attack(tgt)
		var cd_s := character_data.attack_cooldown if character_data != null else 1.0
		if character_data != null:
			var mods := SynergySystem.mods_for_cd(character_data)
			cd_s *= float(mods.get("attack_cooldown_mult", 1.0))
		_attack_timer = cd_s

func _follow_leader(_delta: float) -> void:
	if _leader == null or not is_instance_valid(_leader):
		velocity = Vector2.ZERO
		return
	var target_pos := _leader.global_position + _formation_offset_world()
	var to := target_pos - global_position
	if to.length() > 18.0:
		var move_speed := character_data.move_speed if character_data != null else 120.0
		if character_data != null:
			var mods := SynergySystem.mods_for_cd(character_data)
			move_speed *= float(mods.get("move_speed_mult", 1.0))
		velocity = to.normalized() * move_speed
		move_and_slide()
		_update_anim(to.normalized())
	else:
		velocity = Vector2.ZERO

func _formation_offset_world() -> Vector2:
	match _formation_mode:
		FormationMode.SPREAD:
			return _offset * 1.65
		FormationMode.WEDGE:
			return Vector2(_offset.x * 1.15, _offset.y * 1.85)
		FormationMode.RING:
			# rotate offsets into a ring-ish pattern
			var ang := atan2(_offset.y, _offset.x)
			return Vector2(cos(ang), sin(ang)) * 86.0
		_:
			return _offset

func _find_target() -> Node2D:
	var enemies: Array = []
	if _main and is_instance_valid(_main) and _main.has_method("get_cached_enemies"):
		enemies = _main.get_cached_enemies()
	else:
		enemies = get_tree().get_nodes_in_group("enemies")

	var best: Node2D = null
	var best_score: float = INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		var dist2 := global_position.distance_squared_to(n2.global_position)
		var score := dist2
		if _target_mode == TargetMode.ELITES_FIRST and bool(n2.is_elite):
			score *= 0.65
		if _target_mode == TargetMode.LOWEST_HP and n2.has_method("get_hp_ratio"):
			score *= 0.6 + float(n2.get_hp_ratio())
		if score < best_score:
			best_score = score
			best = n2
	return best

func _attack(target: Node2D) -> void:
	if not is_instance_valid(target):
		return

	var is_crit: bool = false
	var final_damage := character_data.attack_damage if character_data != null else 10
	if character_data != null:
		var mods := SynergySystem.mods_for_cd(character_data)
		final_damage = int(round(float(final_damage) * float(mods.get("attack_damage_mult", 1.0))))
	if character_data != null and character_data.crit_chance > 0.0 and randf() < character_data.crit_chance:
		is_crit = true
		final_damage = int(round(float(final_damage) * character_data.crit_mult))

	var is_melee := character_data != null and character_data.attack_style == CharacterData.AttackStyle.MELEE

	if is_melee:
		var dir := (target.global_position - global_position).normalized()
		_spawn_slash_vfx(target.global_position, dir, _projectile_color_for_unit())
		if target.has_method("take_damage"):
			target.take_damage(final_damage, is_crit, "melee")
		# tiny cleave
		if melee_cleave_radius > 0.0 and melee_cleave_mult > 0.0:
			var enemies: Array = []
			if _main and is_instance_valid(_main) and _main.has_method("get_cached_enemies"):
				enemies = _main.get_cached_enemies()
			var r2 := melee_cleave_radius * melee_cleave_radius
			for e in enemies:
				if not is_instance_valid(e) or e == target:
					continue
				var n2 := e as Node2D
				if n2 == null:
					continue
				if n2.global_position.distance_squared_to(target.global_position) <= r2:
					if n2.has_method("take_damage"):
						n2.take_damage(int(round(float(final_damage) * melee_cleave_mult)), false, "melee_cleave")
		PassiveSystem.on_unit_attack(character_data, self, target, final_damage, is_crit, true)
		SynergySystem.on_unit_attack(character_data, self, target, final_damage, is_crit, true)
		return

	# Ranged projectile
	if _main == null or not is_instance_valid(_main):
		_main = get_tree().get_first_node_in_group("main") as Node2D
	if _main == null:
		return
	var proj := PROJ_SCENE.instantiate()
	_main.add_child(proj)
	proj.global_position = global_position
	if proj.has_method("set_vfx_color"):
		proj.set_vfx_color(_projectile_color_for_unit())
	if proj.has_method("setup_target"):
		# Synergy may add extra pierce (in addition to passives).
		if proj.has_method("add_pierce"):
			proj.add_pierce(SynergySystem.extra_pierce_for_cd(character_data))
		proj.setup_target(target, final_damage, is_crit, character_data.passive_ids, character_data)
	else:
		proj.setup(target.global_position, final_damage)
	var s := _main.get_node_or_null("/root/SfxSystem")
	if s and s.has_method("play_event"):
		s.play_event("player.shot", global_position, self)
	PassiveSystem.on_unit_attack(character_data, self, target, final_damage, is_crit, false)
	SynergySystem.on_unit_attack(character_data, self, target, final_damage, is_crit, false)

func _spawn_slash_vfx(pos: Vector2, dir: Vector2, tint: Color) -> void:
	if _main == null or not is_instance_valid(_main):
		_main = get_tree().get_first_node_in_group("main") as Node2D
	if _main == null or SLASH_SCENE == null:
		return
	var v := SLASH_SCENE.instantiate()
	_main.add_child(v)
	if v.has_method("setup"):
		v.setup(pos, dir, tint)
	var s := _main.get_node_or_null("/root/SfxSystem")
	if s and s.has_method("play_event"):
		s.play_event("player.slash", pos, self)

func _update_anim(dir: Vector2) -> void:
	if anim == null:
		return
	var ax: float = absf(dir.x)
	var ay: float = absf(dir.y)
	var desired: String = _current_anim
	var threshold: float = 0.15
	if ax > ay + threshold:
		desired = "walk_east" if dir.x >= 0.0 else "walk_west"
	elif ay > ax + threshold:
		desired = "walk_south" if dir.y > 0.0 else "walk_north"
	if desired != _current_anim and _anim_cooldown <= 0.0:
		_current_anim = desired
		anim.animation = _current_anim
	anim.play()
	_anim_cooldown = 0.35

func _update_health_bar() -> void:
	if health_bar == null:
		return
	var max_hp_val := _max_hp_effective if _max_hp_effective > 0 else (character_data.max_hp if character_data != null else 100)
	health_bar.value = float(current_hp) / maxf(1.0, float(max_hp_val)) * 100.0

func take_damage(amount: int) -> void:
	current_hp = max(0, current_hp - amount)
	if current_hp <= 0:
		queue_free()

func heal(amount: int) -> void:
	if amount <= 0:
		return
	var max_hp_val := _max_hp_effective if _max_hp_effective > 0 else (character_data.max_hp if character_data != null else 100)
	current_hp = min(max_hp_val, current_hp + amount)
	pulse_vfx(Color(0.55, 1.0, 0.65, 1.0))

func get_max_hp() -> int:
	return _max_hp_effective if _max_hp_effective > 0 else (character_data.max_hp if character_data != null else 100)

func get_hp_ratio() -> float:
	var mh := float(get_max_hp())
	return float(current_hp) / maxf(1.0, mh)

func pulse_vfx(tint: Color) -> void:
	if anim == null:
		return
	if _pulse_tw != null and is_instance_valid(_pulse_tw):
		_pulse_tw.kill()
	_pulse_tw = create_tween()
	_pulse_tw.set_trans(Tween.TRANS_SINE)
	_pulse_tw.set_ease(Tween.EASE_OUT)
	var base := Vector2(1.0, 1.0)
	var bump := base * 1.05
	anim.modulate = Color(1, 1, 1, 1)
	_pulse_tw.parallel().tween_property(anim, "modulate", tint, 0.06)
	_pulse_tw.parallel().tween_property(anim, "scale", bump, 0.06)
	_pulse_tw.tween_property(anim, "modulate", Color(1, 1, 1, 1), 0.10)
	_pulse_tw.parallel().tween_property(anim, "scale", base, 0.10)

func _projectile_color_for_unit() -> Color:
	if character_data == null:
		return Color(0.75, 0.85, 1.0, 1.0)
	match character_data.class_type:
		CharacterData.Class.WARRIOR:
			return Color(1.0, 0.35, 0.35, 1.0)
		CharacterData.Class.MAGE:
			return Color(0.85, 0.45, 1.0, 1.0)
		CharacterData.Class.ROGUE:
			return Color(1.0, 0.90, 0.35, 1.0)
		CharacterData.Class.GUARDIAN:
			return Color(0.40, 1.0, 0.55, 1.0)
		CharacterData.Class.HEALER:
			return Color(0.65, 0.85, 1.0, 1.0)
		CharacterData.Class.SUMMONER:
			return Color(0.95, 0.35, 0.95, 1.0)
		_:
			return Color(0.75, 0.85, 1.0, 1.0)
