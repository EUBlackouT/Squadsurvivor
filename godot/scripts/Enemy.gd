extends CharacterBody2D

# DamageNumbersLayer styles (mirrors res://scripts/DamageNumbersLayer.gd)
const DM_STYLE_DEFAULT := 0
const DM_STYLE_CRIT := 1
const DM_STYLE_DOT := 2
const DM_STYLE_ARC := 3
const DM_STYLE_ECHO := 4

@export var is_elite: bool = false
@export var pixellab_south_path: String = ""
@export var character_data: CharacterData

# AI archetype + elite affixes (data-driven)
@export var ai_id: String = "brute"
@export var affix_ids: PackedStringArray = PackedStringArray()

@export var contact_damage: int = 5
@export var contact_cooldown: float = 0.8
@export var aggression_radius: float = 1100.0
@export var retarget_interval: float = 0.25

@onready var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

var _main: Node2D = null
var _current_anim: String = "walk_south"
var _anim_cooldown: float = 0.0
var _retarget_t: float = 0.0
var _contact_t: float = 0.0
var _attack_t: float = 0.0
var _dash_t: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _dash_cd: float = 0.0
var _volatile_on_death: bool = false
var _vampiric: bool = false
var _arcane: bool = false
var _arcane_cd: float = 0.0
var _move_speed_mult: float = 1.0
var _dmg_mult: float = 1.0
var _hp_mult: float = 1.0
var _scale_mult: float = 1.0

var current_hp: int = 30

# Status from passives
var _bleed_amount: float = 0.0
var _bleed_cd: float = 0.0
var _bleed_time_left: float = 0.0
var _bleed_tick: float = 0.5
var _bleed_accum: float = 0.0
var _bleed_show_cd: float = 0.0

var _slow_mult: float = 1.0
var _slow_cd: float = 0.0

# Burn (synergy / future passives)
var _burn_amount: float = 0.0
var _burn_cd: float = 0.0
var _burn_time_left: float = 0.0
var _burn_tick: float = 0.5
var _burn_accum: float = 0.0
var _burn_show_cd: float = 0.0

var _target: Node2D = null
var _pulse_tw: Tween = null

func _ready() -> void:
	add_to_group("enemies")
	_main = get_tree().get_first_node_in_group("main") as Node2D
	if _main and is_instance_valid(_main) and _main.has_method("register_enemy"):
		_main.register_enemy(self)

	# Physics layers: enemies = 2, collide with squad(3) + player(4)
	collision_layer = 2
	collision_mask = 0
	collision_mask |= 1 << 2 # layer 3
	collision_mask |= 1 << 3 # layer 4

	# Apply archetype + affixes before stats/visuals.
	_apply_archetype_and_affixes()

	if character_data != null:
		current_hp = int(round(float(character_data.max_hp) * _hp_mult))
		# Tuned down: early swarm should be about count/positioning, not instant melting.
		contact_damage = maxi(1, int(round(float(character_data.attack_damage) * 0.22 * _dmg_mult)))
	else:
		current_hp = int(round(30.0 * _hp_mult))

	_apply_visuals()

func _exit_tree() -> void:
	if _main and is_instance_valid(_main) and _main.has_method("unregister_enemy"):
		_main.unregister_enemy(self)

func _apply_visuals() -> void:
	if anim == null:
		return
	if pixellab_south_path == "" and character_data != null:
		pixellab_south_path = character_data.sprite_path
	var frames := PixellabUtil.walk_frames_from_south_path(pixellab_south_path)
	if frames != null:
		anim.sprite_frames = frames
	_current_anim = "walk_south"
	anim.animation = _current_anim
	# NOTE: Our SpriteFrames already include real east/west animations.
	# Flipping here (or in _update_anim) will mirror the already-correct west frames and make enemies face the wrong way.
	anim.flip_h = false
	anim.play()
	# Elites slightly larger
	var base := 1.08 if is_elite else 1.0
	anim.scale = Vector2(base, base) * _scale_mult
	# Mild tint for readability by archetype/affix
	if ai_id == "swarmer":
		anim.modulate = Color(0.85, 0.95, 0.90, 1.0)
	elif ai_id == "spitter":
		anim.modulate = Color(0.85, 0.90, 1.0, 1.0)
	elif ai_id == "bomber":
		anim.modulate = Color(1.0, 0.85, 0.75, 1.0)
	elif ai_id == "charger":
		anim.modulate = Color(1.0, 0.90, 0.85, 1.0)
	if _arcane:
		anim.modulate = anim.modulate.lerp(Color(0.75, 0.55, 1.0, 1.0), 0.35)

func _physics_process(delta: float) -> void:
	_anim_cooldown = maxf(_anim_cooldown - delta, 0.0)
	_retarget_t -= delta
	_contact_t = maxf(_contact_t - delta, 0.0)
	_attack_t = maxf(_attack_t - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_arcane_cd = maxf(_arcane_cd - delta, 0.0)

	# Status tick
	_tick_status(delta)

	if _retarget_t <= 0.0 or _target == null or not is_instance_valid(_target):
		_target = _find_target()
		_retarget_t = retarget_interval

	if _target == null or not is_instance_valid(_target):
		velocity = Vector2.ZERO
		if anim and anim.is_playing():
			anim.stop()
		return

	var to_target := (_target.global_position - global_position)
	var dist := to_target.length()
	var dir := to_target.normalized() if dist > 0.001 else Vector2.ZERO

	# Archetype movement/attacks
	if ai_id == "charger":
		_charger_step(delta, dist, dir)
	elif ai_id == "spitter":
		_spitter_step(delta, dist, dir)
	elif ai_id == "bomber":
		_bomber_step(delta, dist, dir)
	else:
		_melee_step(delta, dist, dir)

	_update_anim(dir)

	# Contact damage when close (no pushing "inside")
	if dist <= 28.0 and _contact_t <= 0.0:
		if _target.has_method("take_damage"):
			_target.take_damage(contact_damage)
			if _vampiric:
				_heal_from_hit(contact_damage)
		_contact_t = contact_cooldown

	# Arcane affix: periodic zap to nearest squad unit.
	if _arcane and _arcane_cd <= 0.0:
		_arcane_cd = 1.55
		_arcane_zap()

func _base_move_speed() -> float:
	return (character_data.move_speed if character_data != null else 90.0) * _slow_mult * _move_speed_mult

func _melee_step(_delta: float, _dist: float, dir: Vector2) -> void:
	var spd := _base_move_speed()
	velocity = dir * spd
	move_and_slide()

func _charger_step(delta: float, dist: float, dir: Vector2) -> void:
	# Occasional dash toward target, otherwise normal chase.
	if _dash_t > 0.0:
		_dash_t -= delta
		velocity = _dash_dir * (_base_move_speed() * 3.2)
		move_and_slide()
		return
	if dist < 320.0 and dist > 110.0 and _dash_cd <= 0.0:
		_dash_cd = 2.4
		_dash_t = 0.22
		_dash_dir = dir
		# Loud dash tell
		var world := _main if _main != null else get_tree().get_first_node_in_group("main") as Node2D
		if world:
			var sw := VfxShockwave.new()
			sw.setup(global_position, Color(1.0, 0.85, 0.55, 1.0), 14.0, 64.0, 4.0, 0.18)
			world.add_child(sw)
			var s := world.get_node_or_null("/root/SfxSystem")
			if s and s.has_method("play_event"):
				s.play_event("enemy.dash", global_position, self)
		return
	_melee_step(delta, dist, dir)

func _spitter_step(delta: float, dist: float, dir: Vector2) -> void:
	# Keep distance, shoot bolts.
	var spd := _base_move_speed()
	var desired := 240.0
	if dist < desired * 0.85:
		velocity = -dir * (spd * 0.65)
		move_and_slide()
	elif dist > desired * 1.25:
		velocity = dir * (spd * 0.85)
		move_and_slide()
	else:
		velocity = Vector2.ZERO

	if _attack_t <= 0.0 and dist < 560.0 and _main != null:
		_attack_t = 1.15
		_fire_bolt(_target, Color(0.75, 0.90, 1.0, 1.0), 0.75)

func _bomber_step(delta: float, dist: float, dir: Vector2) -> void:
	# Slow chase, explode when close.
	var spd := _base_move_speed() * 0.85
	velocity = dir * spd
	move_and_slide()
	if dist <= 66.0 and _attack_t <= 0.0:
		_attack_t = 999.0
		_explode(120.0, maxi(4, int(round(float(contact_damage) * 2.4))))
		_die()

func _fire_bolt(tgt: Node2D, tint: Color, dmg_mult: float) -> void:
	if tgt == null or not is_instance_valid(tgt):
		return
	var world := _main
	if world == null:
		world = get_tree().get_first_node_in_group("main") as Node2D
	if world == null:
		return
	var bolt := EnemyBolt.new()
	world.add_child(bolt)
	bolt.global_position = global_position
	var dmg := int(round(float(contact_damage) * 1.15 * dmg_mult))
	bolt.setup_target(tgt, maxi(1, dmg), tint, 560.0)
	var s := world.get_node_or_null("/root/SfxSystem")
	if s and s.has_method("play_event"):
		s.play_event("enemy.spit", global_position, self)

func _explode(radius: float, dmg: int) -> void:
	var world := _main
	if world == null:
		world = get_tree().get_first_node_in_group("main") as Node2D
	if world != null:
		var fb := VfxFlameBurst.new()
		fb.setup(global_position, Color(1.0, 0.45, 0.25, 1.0), radius * 0.30, 16, 0.24)
		world.add_child(fb)
		var s := world.get_node_or_null("/root/SfxSystem")
		if s and s.has_method("play_event"):
			s.play_event("enemy.explode", global_position, self)
	# Damage nearby squad units (player optional)
	var squad: Array = []
	if world != null and world.has_method("get_cached_squad_units"):
		squad = world.get_cached_squad_units()
	else:
		squad = get_tree().get_nodes_in_group("squad_units")
	var r2 := radius * radius
	for u in squad:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(global_position) <= r2 and n2.has_method("take_damage"):
			n2.take_damage(dmg)

func _arcane_zap() -> void:
	var world := _main
	if world == null:
		world = get_tree().get_first_node_in_group("main") as Node2D
	if world == null:
		return
	# Nearest squad unit
	var squad: Array = []
	if world.has_method("get_cached_squad_units"):
		squad = world.get_cached_squad_units()
	else:
		squad = get_tree().get_nodes_in_group("squad_units")
	var best: Node2D = null
	var best_d2: float = INF
	for u in squad:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		var d2 := n2.global_position.distance_squared_to(global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = n2
	if best == null:
		return
	# Visual line zap
	var arc := preload("res://scenes/VfxArcLightning.tscn").instantiate()
	world.add_child(arc)
	if arc.has_method("setup"):
		arc.setup(global_position, best.global_position, Color(0.75, 0.55, 1.0, 0.95))
	var s := world.get_node_or_null("/root/SfxSystem")
	if s and s.has_method("play_event"):
		s.play_event("enemy.arcane", global_position, self)
	if best.has_method("take_damage"):
		best.take_damage(maxi(1, int(round(float(contact_damage) * 0.85))))

func _heal_from_hit(dmg: int) -> void:
	if dmg <= 0:
		return
	var amt := int(round(float(dmg) * 0.35))
	if amt <= 0:
		return
	current_hp = mini(current_hp + amt, int(round(float(character_data.max_hp) * _hp_mult)) if character_data != null else current_hp + amt)
	var world := _main
	if world != null:
		var hp := VfxHolyPulse.new()
		hp.setup(global_position, Color(1.0, 0.35, 0.55, 1.0), 10.0, 36.0, 0.18)
		world.add_child(hp)

func _apply_archetype_and_affixes() -> void:
	# Archetype mods
	var mods := EnemyFactory.archetype_mods(ai_id)
	_hp_mult *= float(mods.get("hp_mult", 1.0))
	_dmg_mult *= float(mods.get("dmg_mult", 1.0))
	_move_speed_mult *= float(mods.get("speed_mult", 1.0))
	_scale_mult *= float(mods.get("scale", 1.0))

	# Affix mods (elites)
	for a in affix_ids:
		match String(a):
			"hasty":
				_move_speed_mult *= 1.18
				contact_cooldown *= 0.92
			"bulwark":
				_hp_mult *= 1.35
				_scale_mult *= 1.06
			"volatile":
				_volatile_on_death = true
			"vampiric":
				_vampiric = true
			"arcane":
				_arcane = true
			_:
				pass

func _find_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := aggression_radius

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
		var d := global_position.distance_to(n2.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = n2

	if nearest != null:
		return nearest

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and is_instance_valid(player):
		var d2 := global_position.distance_to(player.global_position)
		if d2 < aggression_radius:
			return player
	return null

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
		# Do not flip: we have dedicated frames per direction.
		anim.flip_h = false
		anim.play()
		_anim_cooldown = 0.5
	elif not anim.is_playing():
		anim.play()

func take_damage(amount: int, is_crit: bool = false, source: String = "") -> void:
	var prev := current_hp
	current_hp = maxi(0, current_hp - amount)

	# Damage numbers (delegated to Main's DamageNumbersLayer)
	var main := _main
	if main == null or not is_instance_valid(main):
		main = get_tree().get_first_node_in_group("main") as Node2D
	if main and is_instance_valid(main) and main.has_method("show_damage_number"):
		var style: int = DM_STYLE_DEFAULT
		if source == "bleed" or source == "dot":
			style = DM_STYLE_DOT
		elif source == "arc":
			style = DM_STYLE_ARC
		elif source == "echo":
			style = DM_STYLE_ECHO
		main.show_damage_number(get_instance_id(), source, amount, global_position + Vector2(0, -26), style, is_crit)

	if current_hp <= 0:
		_die()

	# Local feedback pulse (non-circular; avoids spawning extra VFX nodes)
	if amount > 0:
		var tint: Color = Color(1.0, 1.0, 1.0, 1.0)
		if source == "bleed" or source == "dot":
			tint = Color(1.0, 0.25, 0.35, 1.0)
		elif source == "arc":
			tint = Color(0.55, 0.95, 1.0, 1.0)
		elif source == "echo":
			tint = Color(1.0, 0.85, 0.30, 1.0)
		elif is_crit:
			tint = Color(1.0, 0.85, 0.30, 1.0)
		pulse_vfx(tint)

func get_hp_ratio() -> float:
	var m := float(character_data.max_hp) if character_data != null else 30.0
	return float(current_hp) / maxf(1.0, m)

func _die() -> void:
	# Optional: explode if tagged by a passive (e.g., Hex Bomb)
	_process_death_tags()
	# Volatile elites explode on death.
	if _volatile_on_death:
		_explode(92.0, maxi(3, int(round(float(contact_damage) * 1.8))))
	# Death pop sound (global throttled)
	var world := _main
	if world == null:
		world = get_tree().get_first_node_in_group("main") as Node2D
	if world != null:
		var s := world.get_node_or_null("/root/SfxSystem")
		if s and s.has_method("play_event"):
			s.play_event("enemy.die", global_position, self)
	var main := get_tree().get_first_node_in_group("main") as Node2D
	if main and is_instance_valid(main) and main.has_method("on_enemy_killed"):
		main.on_enemy_killed(is_elite, character_data, bool(get_meta("rift", false)), bool(get_meta("boss", false)))
	queue_free()

func _process_death_tags() -> void:
	# Hex Bomb: if armed recently, explode on death.
	if not has_meta("_hex_bomb_until_ms"):
		return
	var until_ms: int = int(get_meta("_hex_bomb_until_ms", 0))
	var now_ms: int = int(Time.get_ticks_msec())
	if now_ms > until_ms:
		return
	var dmg: int = int(get_meta("_hex_bomb_dmg", 0))
	var radius: float = float(get_meta("_hex_bomb_radius", 140.0))
	if dmg <= 0:
		return
	var main := _main
	if main == null or not is_instance_valid(main):
		main = get_tree().get_first_node_in_group("main") as Node2D
	var enemies: Array = []
	if main and is_instance_valid(main) and main.has_method("get_cached_enemies"):
		enemies = main.get_cached_enemies()
	else:
		enemies = get_tree().get_nodes_in_group("enemies")
	var r2 := radius * radius
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null or n2 == self:
			continue
		if n2.global_position.distance_squared_to(global_position) <= r2:
			if n2.has_method("take_damage"):
				n2.take_damage(dmg, false, "blast")
			# quick feedback pulse (non-circular)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.75, 0.45, 1.0, 1.0))

# Non-circular on-hit pulse for passive feedback.
func pulse_vfx(tint: Color) -> void:
	if anim == null:
		return
	if _pulse_tw != null and is_instance_valid(_pulse_tw):
		_pulse_tw.kill()
	var base_scale: Vector2 = Vector2(1.08, 1.08) if is_elite else Vector2(1.0, 1.0)
	var bump_scale: Vector2 = base_scale * 1.06
	_pulse_tw = create_tween()
	_pulse_tw.set_trans(Tween.TRANS_SINE)
	_pulse_tw.set_ease(Tween.EASE_OUT)
	# Brief tint + scale pop, then return to normal.
	anim.modulate = Color(1, 1, 1, 1)
	_pulse_tw.parallel().tween_property(anim, "modulate", tint, 0.06)
	_pulse_tw.parallel().tween_property(anim, "scale", bump_scale, 0.06)
	_pulse_tw.tween_property(anim, "modulate", Color(1, 1, 1, 1), 0.10)
	_pulse_tw.parallel().tween_property(anim, "scale", base_scale, 0.10)

# --- Status API for PassiveSystem ---

func apply_bleed(dps: float, duration: float, tick_interval: float) -> void:
	_bleed_amount = maxf(_bleed_amount, dps)
	_bleed_time_left = maxf(_bleed_time_left, duration)
	_bleed_tick = tick_interval
	_bleed_cd = minf(_bleed_cd, _bleed_tick)

func apply_slow(mult: float, duration: float) -> void:
	_slow_mult = minf(_slow_mult, mult)
	_slow_cd = maxf(_slow_cd, duration)

func apply_burn(dps: float, duration: float, tick_interval: float) -> void:
	_burn_amount = maxf(_burn_amount, dps)
	_burn_time_left = maxf(_burn_time_left, duration)
	_burn_tick = tick_interval
	_burn_cd = minf(_burn_cd, _burn_tick)

func _tick_status(delta: float) -> void:
	# Slow duration
	if _slow_cd > 0.0:
		_slow_cd -= delta
		if _slow_cd <= 0.0:
			_slow_cd = 0.0
			_slow_mult = 1.0

	# Bleed
	if _bleed_time_left > 0.0 and _bleed_amount > 0.0:
		_bleed_time_left -= delta
		_bleed_cd -= delta
		_bleed_show_cd = maxf(_bleed_show_cd - delta, 0.0)
		if _bleed_cd <= 0.0:
			_bleed_cd = _bleed_tick
			var dmg := _bleed_amount * _bleed_tick
			_bleed_accum += dmg
			current_hp = maxi(0, current_hp - int(round(dmg)))
			if current_hp <= 0:
				_die()
				return
		# Aggregate number every ~0.6s
		if _bleed_show_cd <= 0.0 and _bleed_accum >= 1.0 and _main and is_instance_valid(_main) and _main.has_method("show_damage_number"):
			var shown: int = int(round(_bleed_accum))
			_bleed_accum = 0.0
			_bleed_show_cd = 0.6
			_main.show_damage_number(get_instance_id(), "bleed", shown, global_position + Vector2(0, -26), DM_STYLE_DOT, false)

	if _bleed_time_left <= 0.0:
		_bleed_amount = 0.0
		_bleed_cd = 0.0

	# Burn (same aggregation strategy as bleed)
	if _burn_time_left > 0.0 and _burn_amount > 0.0:
		_burn_time_left -= delta
		_burn_cd -= delta
		_burn_show_cd = maxf(_burn_show_cd - delta, 0.0)
		if _burn_cd <= 0.0:
			_burn_cd = _burn_tick
			var dmg2 := _burn_amount * _burn_tick
			_burn_accum += dmg2
			current_hp = maxi(0, current_hp - int(round(dmg2)))
			if current_hp <= 0:
				_die()
				return
		if _burn_show_cd <= 0.0 and _burn_accum >= 1.0 and _main and is_instance_valid(_main) and _main.has_method("show_damage_number"):
			var shown2: int = int(round(_burn_accum))
			_burn_accum = 0.0
			_burn_show_cd = 0.6
			_main.show_damage_number(get_instance_id(), "burn", shown2, global_position + Vector2(0, -26), DM_STYLE_DOT, false)

	if _burn_time_left <= 0.0:
		_burn_amount = 0.0
		_burn_cd = 0.0
