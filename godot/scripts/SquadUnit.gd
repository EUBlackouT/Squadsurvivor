extends CharacterBody2D

@export var character_data: CharacterData
@export var melee_cleave_radius: float = 65.0  # Bigger cleave radius - more satisfying
@export var melee_cleave_mult: float = 0.50    # Cleave hits harder
@export var retarget_interval: float = 0.18    # Faster retargeting

@onready var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var sprite_fallback: Sprite2D = get_node_or_null("Sprite2D")
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")

const PROJ_SCENE: PackedScene = preload("res://scenes/Projectile.tscn")

var _main: Node2D = null
var _attack_timer: float = 0.0
var _retarget_t: float = 0.0
var _target_enemy: Node2D = null

var _leader: Node2D = null
var _offset: Vector2 = Vector2.ZERO

var current_hp: int = 100
var _max_hp_effective: int = 100
var _overheal_shield: int = 0

# Temporary defensive buff (Guardian callout): reduces incoming damage.
var _aegis_until_s: float = 0.0
var _aegis_dmg_mult: float = 1.0

# Damage number styles (mirrors res://scripts/DamageNumbersLayer.gd)
const DM_STYLE_DEFAULT := 0
const DM_STYLE_CRIT := 1
const DM_STYLE_DOT := 2
const DM_STYLE_ARC := 3
const DM_STYLE_ECHO := 4

enum FormationMode { TIGHT, SPREAD, WEDGE, RING }
enum TargetMode { NEAREST, LOWEST_HP, ELITES_FIRST }
var _formation_mode: int = FormationMode.TIGHT
var _target_mode: int = TargetMode.NEAREST
const TARGET_MODE_COUNT: int = 3
const TARGET_SPRITE_HEIGHT: float = 52.0

var _current_anim: String = "walk_south"
var _anim_cooldown: float = 0.0
var _last_facing: Vector2 = Vector2(0, 1)
var _anim_base_pos: Vector2 = Vector2.ZERO
var _anim_base_scale: Vector2 = Vector2.ONE
var _walk_bob_t: float = 0.0

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
	
	# Apply meta progression HP bonus
	var meta_hp_mult := 1.0
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		meta_hp_mult = float(mp.get_mod("squad_hp_mult", 1.0))
	
	_max_hp_effective = int(round(float(character_data.max_hp) * float(mods.get("max_hp_mult", 1.0)) * meta_hp_mult))
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
			var base_scale := anim.scale
			var scale_mult := PixellabUtil.scale_for_target_height(frames, TARGET_SPRITE_HEIGHT, 0.6, 1.05)
			anim.scale = base_scale * scale_mult
			anim.sprite_frames = frames
			_current_anim = "walk_south"
			anim.animation = _current_anim
			anim.play()
	_anim_base_pos = anim.position
	_anim_base_scale = anim.scale
	# Outline for readability
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/pixel_outline.gdshader")
	mat.set_shader_parameter("outline_color", Color(0, 0, 0, 1))
	mat.set_shader_parameter("outline_px", 1.5)
	anim.material = mat

	# Hide fallback sprite if present
	if sprite_fallback != null:
		sprite_fallback.visible = false

	# Health bar polish (kept tiny, but readable)
	if health_bar != null:
		health_bar.show_percentage = false
		health_bar.min_value = 0
		health_bar.max_value = 100
		health_bar.position = Vector2(-24, -50)
		health_bar.custom_minimum_size = Vector2(48, 6)
		# Slightly brighter so it reads on dark maps.
		health_bar.modulate = Color(1.0, 1.0, 1.0, 0.92)

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
	_aegis_until_s = maxf(0.0, _aegis_until_s - delta)

	# Synergy tick (auras/procs with cooldown gating)
	if character_data != null:
		SynergySystem.tick_unit(character_data, self)

	# Rally command overrides combat briefly (reposition moment).
	if _main and is_instance_valid(_main) and _main.has_method("get_rally_time_left") and float(_main.get_rally_time_left()) > 0.0:
		_target_enemy = null
		_retarget_t = retarget_interval
	elif _retarget_t <= 0.0 or _target_enemy == null or not is_instance_valid(_target_enemy):
		_target_enemy = _find_target()
		_retarget_t = retarget_interval

	if _target_enemy != null and is_instance_valid(_target_enemy):
		_combat_step(delta)
	else:
		_follow_leader(delta)

	# Centralized: animation direction should come from actual motion, not target direction.
	# (Fixes ranged kiting/backpedal cases and makes it consistent.)
	var look := Vector2.ZERO
	if _target_enemy != null and is_instance_valid(_target_enemy):
		look = (_target_enemy.global_position - global_position)
	elif _leader != null and is_instance_valid(_leader):
		look = (_leader.global_position - global_position)
	_update_anim_from_motion(velocity, look)

	_update_health_bar()

func _combat_step(_delta: float) -> void:
	var tgt := _target_enemy
	var dist := global_position.distance_to(tgt.global_position)
	var attack_range := character_data.attack_range if character_data != null else 300.0
	var move_speed := _get_effective_move_speed()
	# Overclock: speed burst (meta ability)
	if _main and is_instance_valid(_main) and _main.has_method("get_overclock_move_speed_mult"):
		move_speed *= float(_main.get_overclock_move_speed_mult())

	var is_melee := character_data != null and character_data.attack_style == CharacterData.AttackStyle.MELEE
	var desired_range := 26.0 if is_melee else attack_range * 0.70

	# Movement: melee sticks, ranged kites slightly
	if dist > attack_range:
		velocity = (tgt.global_position - global_position).normalized() * move_speed
		move_and_slide()
	elif is_melee and dist > desired_range:
		velocity = (tgt.global_position - global_position).normalized() * (move_speed * 1.05)
		move_and_slide()
	elif (not is_melee) and dist < desired_range * 0.75:
		velocity = (global_position - tgt.global_position).normalized() * (move_speed * 0.55)
		move_and_slide()
	else:
		velocity = Vector2.ZERO

	# Attack
	if dist <= attack_range and _attack_timer <= 0.0:
		_attack(tgt)
		var cd_s := character_data.attack_cooldown if character_data != null else 1.0
		if character_data != null:
			var mods := SynergySystem.mods_for_cd(character_data)
			cd_s *= float(mods.get("attack_cooldown_mult", 1.0))
		# Overclock increases attack rate by reducing cooldown.
		if _main and is_instance_valid(_main) and _main.has_method("get_overclock_rate_mult"):
			var rate := float(_main.get_overclock_rate_mult())
			if rate > 0.01:
				cd_s /= rate
		_attack_timer = cd_s

func _follow_leader(_delta: float) -> void:
	# Rally: follow a command point instead of leader for a short burst.
	if _main and is_instance_valid(_main) and _main.has_method("get_rally_time_left") and float(_main.get_rally_time_left()) > 0.0 and _main.has_method("get_rally_pos"):
		var rp: Vector2 = _main.get_rally_pos()
		var target_pos := rp + _formation_offset_world()
		var to := target_pos - global_position
		if to.length() > 14.0:
			var move_speed := _get_effective_move_speed()
			var mp := get_node_or_null("/root/MetaProgression")
			var follow_mult := 1.15
			var speed_mult := 1.0
			if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
				follow_mult *= float(mp.get_mod("rally_follow_mult", 1.0))
				speed_mult *= float(mp.get_mod("rally_speed_mult", 1.0))
			velocity = to.normalized() * (move_speed * follow_mult * speed_mult)
			move_and_slide()
		else:
			velocity = Vector2.ZERO
		return

	if _leader == null or not is_instance_valid(_leader):
		velocity = Vector2.ZERO
		return
	var target_pos := _leader.global_position + _formation_offset_world()
	var to := target_pos - global_position
	var follow_threshold := 18.0
	var follow_mult := 1.0
	# If leader is dashing, surge to keep up (prevents "camera dash without squad").
	if _leader != null and is_instance_valid(_leader) and _leader.has_method("is_dashing") and bool(_leader.is_dashing()):
		follow_threshold = 8.0
		follow_mult = 3.0
		var mp := get_node_or_null("/root/MetaProgression")
		if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
			follow_mult *= float(mp.get_mod("dash_follow_mult", 1.0))
	if to.length() > follow_threshold:
		var move_speed := _get_effective_move_speed()
		if _main and is_instance_valid(_main) and _main.has_method("get_overclock_move_speed_mult"):
			move_speed *= float(_main.get_overclock_move_speed_mult())
		velocity = to.normalized() * (move_speed * follow_mult)
		move_and_slide()
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

	# Focus-fire command: bias target selection toward the marked enemy (still distance-aware).
	var focus: Node2D = null
	if _main and is_instance_valid(_main) and _main.has_method("get_focus_target"):
		focus = _main.get_focus_target()

	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		var dist2 := global_position.distance_squared_to(n2.global_position)
		var score := dist2
		if focus != null and n2 == focus:
			score *= 0.03
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
	
	# Meta progression bonuses
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		var meta_dmg_mult := float(mp.get_mod("squad_damage_mult", 1.0))
		final_damage = int(round(float(final_damage) * meta_dmg_mult))
	
	# Overclock: damage multiplier (meta buildcraft)
	if _main and is_instance_valid(_main) and _main.has_method("get_overclock_damage_mult"):
		final_damage = int(round(float(final_damage) * float(_main.get_overclock_damage_mult())))
	
	# Crit check with meta progression bonus
	var crit_chance := character_data.crit_chance if character_data != null else 0.0
	if mp and is_instance_valid(mp) and mp.has_method("get_add"):
		crit_chance += float(mp.get_add("squad_crit_add", 0.0))
	if crit_chance > 0.0 and randf() < crit_chance:
		is_crit = true
		final_damage = int(round(float(final_damage) * (character_data.crit_mult if character_data != null else 1.5)))

	# Use weapon system for attack
	if _main == null or not is_instance_valid(_main):
		_main = get_tree().get_first_node_in_group("main") as Node2D
	if _main == null:
		return
	
	var weapon_id := character_data.weapon_id if character_data != null else "standard_bolt"
	var is_melee := character_data != null and character_data.attack_style == CharacterData.AttackStyle.MELEE
	
	# Execute weapon attack
	WeaponSystem.execute_attack(weapon_id, self, target, final_damage, is_crit, _main, character_data)
	
	# Trigger passive/synergy callbacks
	PassiveSystem.on_unit_attack(character_data, self, target, final_damage, is_crit, is_melee)
	SynergySystem.on_unit_attack(character_data, self, target, final_damage, is_crit, is_melee)

func _spawn_melee_hit_vfx(target: Node2D, dir: Vector2, is_crit: bool) -> void:
	if _main == null or not is_instance_valid(_main):
		_main = get_tree().get_first_node_in_group("main") as Node2D
	if _main == null or target == null or not is_instance_valid(target):
		return
	var pos := (target as Node2D).global_position + Vector2(0, -18)
	var tint := _projectile_color_for_unit()

	# SFX: melee impact (throttled)
	var s := _main.get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_event"):
		s.play_event("hit.crit" if is_crit else "hit.melee", pos, self)

	# Prefer exported EffectBlocks flipbook VFX if available.
	var v := _main.get_node_or_null("/root/VfxSystem")
	if v and is_instance_valid(v) and v.has_method("play_event"):
		var ok := bool(v.play_event("hit.crit" if is_crit else "hit.melee", pos, _main, tint, 1.0))
		if ok:
			return

	# Primary: directional streak (reads as an actual hit, not a cube).
	var streak := VfxMeleeStreak.new()
	streak.setup(pos, dir, tint, 46.0, 10.0, 0.10)
	_main.add_child(streak)

	# Secondary: crisp flash for impact readability.
	var flash := VfxImpactFlash.new()
	flash.setup(pos, tint, 18.0, 0.10)
	_main.add_child(flash)

	# Small impact spark
	var fb := VfxFlameBurst.new()
	fb.setup(pos, Color(tint.r, tint.g, tint.b, 0.9), 16.0, 7, 0.14, dir)
	_main.add_child(fb)
	# Crit: add a shockwave for punch
	if is_crit:
		var sw := VfxShockwave.new()
		sw.setup(pos, Color(1.0, 0.85, 0.30, 1.0), 12.0, 46.0, 4.0, 0.18)
		_main.add_child(sw)

func _update_anim_from_motion(motion: Vector2, look_dir: Vector2 = Vector2.ZERO) -> void:
	if anim == null or anim.sprite_frames == null:
		return

	var moving := motion.length() > 2.0
	var ref := motion if moving else look_dir
	if ref.length() <= 0.001:
		ref = _last_facing
	else:
		_last_facing = ref.normalized()

	var desired := _pick_walk_anim(ref)
	if desired != _current_anim and _anim_cooldown <= 0.0:
		_current_anim = desired
		anim.animation = _current_anim
		_anim_cooldown = 0.10

	# Apply per-character directional flip only when needed (some Pixellab exports lack east/west).
	_apply_directional_flip(_current_anim)

	# Play only while moving; when idle, freeze on first frame (reads as "standing").
	if moving:
		if not anim.is_playing():
			anim.play()
	else:
		if anim.is_playing():
			anim.stop()
		anim.frame = 0

	_apply_walk_bob(moving)

func _apply_directional_flip(anim_name: String) -> void:
	if anim == null or anim.sprite_frames == null:
		return
	var sf := anim.sprite_frames
	var flip := false
	if anim_name == "walk_east" and bool(sf.get_meta("flip_h_for_walk_east", false)):
		flip = true
	elif anim_name == "walk_west" and bool(sf.get_meta("flip_h_for_walk_west", false)):
		flip = true
	anim.flip_h = flip

func _apply_walk_bob(moving: bool) -> void:
	# If a character lacks real walking frames (only 1 frame per direction),
	# add a subtle bob so they still feel alive while moving.
	if anim == null or anim.sprite_frames == null:
		return
	var sf := anim.sprite_frames
	var frames_n := 0
	if sf.has_animation(_current_anim):
		frames_n = sf.get_frame_count(_current_anim)
	var has_real_walk := frames_n >= 2

	if moving and (not has_real_walk):
		_walk_bob_t += get_physics_process_delta_time() * 9.0
		var bob := sin(_walk_bob_t) * 1.25
		anim.position = _anim_base_pos + Vector2(0, bob)
		anim.scale = _anim_base_scale * (1.0 + 0.015 * sin(_walk_bob_t * 2.0))
	else:
		_walk_bob_t = 0.0
		anim.position = _anim_base_pos
		anim.scale = _anim_base_scale

func _pick_walk_anim(dir: Vector2) -> String:
	# 4-way facing with deadzone; fall back if an animation is missing.
	var d := dir.normalized()
	var ax := absf(d.x)
	var ay := absf(d.y)
	var desired := _current_anim
	var threshold := 0.10
	if ax > ay + threshold:
		desired = "walk_east" if d.x >= 0.0 else "walk_west"
	elif ay > ax + threshold:
		desired = "walk_south" if d.y > 0.0 else "walk_north"

	# Ensure animation exists; PixellabUtil provides fallbacks, but be safe.
	if anim != null and anim.sprite_frames != null:
		var sf := anim.sprite_frames
		if sf.has_animation(desired) and sf.get_frame_count(desired) > 0:
			return desired
		# try south as universal fallback
		if sf.has_animation("walk_south") and sf.get_frame_count("walk_south") > 0:
			return "walk_south"
	return desired

func _update_health_bar() -> void:
	if health_bar == null:
		return
	var max_hp_val := _max_hp_effective if _max_hp_effective > 0 else (character_data.max_hp if character_data != null else 100)
	health_bar.value = float(current_hp) / maxf(1.0, float(max_hp_val)) * 100.0

func take_damage(amount: int) -> void:
	# Aegis: damage reduction window.
	if _aegis_until_s > 0.0 and _aegis_dmg_mult < 0.999:
		amount = maxi(0, int(round(float(amount) * _aegis_dmg_mult)))
	if amount <= 0:
		return
	# Overheal shield absorbs first.
	if _overheal_shield > 0:
		var absorbed := mini(amount, _overheal_shield)
		_overheal_shield -= absorbed
		amount -= absorbed
		if amount <= 0:
			pulse_vfx(Color(0.65, 0.85, 1.0, 1.0))
			return

	var prev := current_hp
	current_hp = max(0, current_hp - amount)

	# Damage numbers (delegated to Main's DamageNumbersLayer)
	var main := _main
	if main == null or not is_instance_valid(main):
		main = get_tree().get_first_node_in_group("main") as Node2D
	if main and is_instance_valid(main) and main.has_method("show_damage_number"):
		main.show_damage_number(get_instance_id(), "unit_hit", amount, global_position + Vector2(0, -26), DM_STYLE_DEFAULT, false)

	# Feedback pulse
	pulse_vfx(Color(1.0, 0.35, 0.45, 1.0))

	if current_hp <= 0 and prev > 0:
		_die()

func _die() -> void:
	# Notify systems BEFORE freeing (so lists can remove this exact instance)
	var main := _main
	if main == null or not is_instance_valid(main):
		main = get_tree().get_first_node_in_group("main") as Node2D
	if main and is_instance_valid(main) and main.has_method("on_squad_unit_died"):
		main.on_squad_unit_died(self)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and is_instance_valid(player) and player.has_method("on_squad_unit_died"):
		player.on_squad_unit_died(self)

	# Small death pop (reuses existing VFX, stays lightweight)
	if main and is_instance_valid(main):
		var pos := global_position + Vector2(0, -18)
		# SFX: unit death (throttled)
		var s := main.get_node_or_null("/root/SfxSystem")
		if s and is_instance_valid(s) and s.has_method("play_event"):
			s.play_event("unit.die", pos, self)
		# Prefer EffectBlocks flipbook VFX if available.
		var v := main.get_node_or_null("/root/VfxSystem")
		var ok := false
		if v and is_instance_valid(v) and v.has_method("play_event"):
			ok = bool(v.play_event("unit.die", pos, main, Color(1, 1, 1, 1), 1.0))
		if not ok:
			var flash := VfxImpactFlash.new()
			flash.setup(pos, Color(1.0, 0.55, 0.55, 1.0), 18.0, 0.12)
			main.add_child(flash)
			var sw := VfxShockwave.new()
			sw.setup(pos, Color(1.0, 0.45, 0.45, 1.0), 10.0, 62.0, 3.0, 0.16)
			main.add_child(sw)

	queue_free()

func apply_aegis(duration: float, dmg_mult: float) -> void:
	_aegis_until_s = maxf(_aegis_until_s, maxf(0.05, duration))
	_aegis_dmg_mult = clampf(dmg_mult, 0.15, 1.0)
	pulse_vfx(Color(0.40, 1.0, 0.65, 1.0))

func heal(amount: int) -> void:
	if amount <= 0:
		return
	var max_hp_val := _max_hp_effective if _max_hp_effective > 0 else (character_data.max_hp if character_data != null else 100)
	current_hp = min(max_hp_val, current_hp + amount)
	pulse_vfx(Color(0.55, 1.0, 0.65, 1.0))

func heal_with_overheal(amount: int, overheal_mult: float) -> void:
	if amount <= 0:
		return
	var max_hp_val := _max_hp_effective if _max_hp_effective > 0 else (character_data.max_hp if character_data != null else 100)
	var new_hp := current_hp + amount
	if new_hp > max_hp_val and overheal_mult > 0.0:
		var extra := new_hp - max_hp_val
		_overheal_shield += int(round(float(extra) * overheal_mult))
		var main := _main
		if main == null or not is_instance_valid(main):
			main = get_tree().get_first_node_in_group("main") as Node2D
		if main and is_instance_valid(main):
			var hp := VfxHolyPulse.new()
			hp.setup(global_position + Vector2(0, -18), Color(0.55, 0.85, 1.0, 1.0), 12.0, 34.0, 0.20)
			main.add_child(hp)
			var s := main.get_node_or_null("/root/SfxSystem")
			if s and is_instance_valid(s) and s.has_method("play_event"):
				s.play_event("passive.vampiric_mastery", global_position, self)
	current_hp = min(max_hp_val, new_hp)
	pulse_vfx(Color(0.65, 0.90, 1.0, 1.0))

func get_max_hp() -> int:
	return _max_hp_effective if _max_hp_effective > 0 else (character_data.max_hp if character_data != null else 100)

func get_hp_ratio() -> float:
	var mh := float(get_max_hp())
	return float(current_hp) / maxf(1.0, mh)

func _get_effective_move_speed() -> float:
	var base_speed := character_data.move_speed if character_data != null else 120.0
	
	# Synergy mods
	if character_data != null:
		var mods := SynergySystem.mods_for_cd(character_data)
		base_speed *= float(mods.get("move_speed_mult", 1.0))
	
	# Meta progression speed bonus
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		base_speed *= float(mp.get_mod("squad_speed_mult", 1.0))
	
	return base_speed

func pulse_vfx(tint: Color) -> void:
	if anim == null:
		return
	if _pulse_tw != null and is_instance_valid(_pulse_tw):
		_pulse_tw.kill()
	_pulse_tw = create_tween()
	_pulse_tw.set_trans(Tween.TRANS_SINE)
	_pulse_tw.set_ease(Tween.EASE_OUT)
	anim.modulate = Color(1, 1, 1, 1)
	_pulse_tw.parallel().tween_property(anim, "modulate", tint, 0.06)
	_pulse_tw.tween_property(anim, "modulate", Color(1, 1, 1, 1), 0.10)

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
