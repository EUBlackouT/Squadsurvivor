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
var _last_facing: Vector2 = Vector2(0, 1)
var _anim_base_pos: Vector2 = Vector2.ZERO
var _anim_base_scale: Vector2 = Vector2.ONE
var _walk_bob_t: float = 0.0
var _retarget_t: float = 0.0
var _contact_t: float = 0.0
var _attack_t: float = 0.0
var _dash_t: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _dash_cd: float = 0.0
var _charge_windup_t: float = 0.0
var _charge_dir: Vector2 = Vector2.ZERO
var _charge_target_pos: Vector2 = Vector2.ZERO
var _charge_line: Line2D = null
static var _charge_line_tex: Texture2D = null
var _volatile_on_death: bool = false
var _vampiric: bool = false
var _arcane: bool = false

static func _make_charge_line_tex() -> Texture2D:
	# Repeating hazard stripe texture for Line2D (tiled).
	# This replaces the “solid red beam” with a readable telegraph.
	var w := 64
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Draw a few diagonal stripes (alpha only; color comes from Line2D.default_color)
	for x in range(w):
		# Use integer math (avoid float % int parse error).
		var y0 := (int(x * 3) / 5) % h
		for dy in range(3):
			var y := (y0 + dy) % h
			img.set_pixel(x, y, Color(1, 1, 1, 0.75))
		# A second stripe offset for density
		var y1 := int((y0 + 8) % h)
		for dy2 in range(2):
			var yb := (y1 + dy2) % h
			img.set_pixel(x, yb, Color(1, 1, 1, 0.35))
	return ImageTexture.create_from_image(img)
var _arcane_cd: float = 0.0
var _move_speed_mult: float = 1.0
var _dmg_mult: float = 1.0
var _hp_mult: float = 1.0
var _scale_mult: float = 1.0
const TARGET_SPRITE_HEIGHT: float = 26.0
const ENEMY_WORLD_SPEED_MULT: float = 0.20
const TARGET_SEPARATION_RADIUS: float = 26.0
const ACTOR_SEPARATION_RADIUS: float = 24.0

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

# Rogue callout: smoke blind reduces hit chance for a short time.
var _smoke_hit_chance: float = 1.0
var _smoke_time_left: float = 0.0

var _target: Node2D = null
var _pulse_tw: Tween = null

func _ready() -> void:
	add_to_group("enemies")
	_main = get_tree().get_first_node_in_group("main") as Node2D
	if _main and is_instance_valid(_main) and _main.has_method("register_enemy"):
		_main.register_enemy(self)

	# Physics layers: enemies = 2.
	# Keep hard body collision only against enemies to avoid player "rubberband"/stuck feeling.
	# Player/squad separation is handled manually in _resolve_actor_overlap().
	collision_layer = 2
	collision_mask = 0
	collision_mask |= 1 << 1 # layer 2 (enemy-enemy body collision)
	collision_mask |= 1 << 0 # layer 1 (map blockers from authored TMX)

	# Apply archetype + affixes before stats/visuals.
	_apply_archetype_and_affixes()

	if character_data != null:
		current_hp = int(round(float(character_data.max_hp) * _hp_mult))
		# IMPORTANT: squad units have real HP; enemies must meaningfully threaten them.
		# This is the baseline "melee/contact" hit. (Projectiles/explosions scale from this too.)
		contact_damage = maxi(1, int(round(float(character_data.attack_damage) * 0.45 * _dmg_mult)))
	else:
		current_hp = int(round(30.0 * _hp_mult))

	_apply_visuals()

func _exit_tree() -> void:
	if _main and is_instance_valid(_main) and _main.has_method("unregister_enemy"):
		_main.unregister_enemy(self)

func _apply_visuals() -> void:
	if anim == null:
		return
	var is_boss := bool(get_meta("boss", false))
	if pixellab_south_path == "" and character_data != null:
		pixellab_south_path = character_data.sprite_path
	var frames := PixellabUtil.walk_frames_from_south_path(pixellab_south_path)
	if frames != null:
		var base_scale := anim.scale
		var scale_mult := PixellabUtil.scale_for_target_height(frames, TARGET_SPRITE_HEIGHT, 0.6, 1.05)
		anim.scale = base_scale * scale_mult
		anim.sprite_frames = frames
	_current_anim = "walk_south"
	anim.animation = _current_anim
	# NOTE: Our SpriteFrames already include real east/west animations.
	# Flipping here (or in _update_anim) will mirror the already-correct west frames and make enemies face the wrong way.
	anim.flip_h = false
	anim.play()
	_anim_base_pos = anim.position
	_anim_base_scale = anim.scale
	# Elites/bosses are larger for readability + threat presence.
	var base := 1.0
	if is_boss:
		base = 1.42
	elif is_elite:
		base = 1.10
	anim.scale = _anim_base_scale * base * _scale_mult
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
	if is_boss:
		anim.modulate = anim.modulate.lerp(Color(1.0, 0.78, 0.62, 1.0), 0.22)
	# Team readability: enemy-specific warm outline (cleaner than floor circles).
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/pixel_outline.gdshader")
	var enemy_outline := Color(1.0, 0.26, 0.20, 0.95)
	if is_elite:
		enemy_outline = Color(1.0, 0.48, 0.20, 0.98)
	if is_boss:
		enemy_outline = Color(1.0, 0.70, 0.35, 1.0)
	mat.set_shader_parameter("outline_color", enemy_outline)
	mat.set_shader_parameter("outline_px", 2.2 if is_boss else 1.4)
	anim.material = mat

func _physics_process(delta: float) -> void:
	_anim_cooldown = maxf(_anim_cooldown - delta, 0.0)
	_retarget_t -= delta
	_contact_t = maxf(_contact_t - delta, 0.0)
	_attack_t = maxf(_attack_t - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_charge_windup_t = maxf(_charge_windup_t - delta, 0.0)
	_arcane_cd = maxf(_arcane_cd - delta, 0.0)
	_smoke_time_left = maxf(_smoke_time_left - delta, 0.0)
	if _smoke_time_left <= 0.0:
		_smoke_hit_chance = 1.0

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

	# Use real motion for walking direction; when idle (e.g. spitter holds distance),
	# face the target without playing the walk cycle.
	_update_anim_from_motion(velocity, dir)

	# Contact damage when close; use soft separation instead of hard body blocking.
	_resolve_actor_overlap()
	_resolve_target_overlap()
	if dist <= 28.0 and _contact_t <= 0.0:
		if _target.has_method("take_damage"):
			# Smoke blind can cause contact attacks to miss.
			if randf() <= _smoke_hit_chance:
				_target.take_damage(contact_damage)
				# VFX: enemy melee hit (EffectBlocks if exported)
				var world := _main if _main != null else get_tree().get_first_node_in_group("main") as Node2D
				if world != null:
					# SFX: enemy melee hit tick/thump (throttled)
					var s := world.get_node_or_null("/root/SfxSystem")
					if s and is_instance_valid(s) and s.has_method("play_event"):
						s.play_event("hit.enemy_melee", (_target as Node2D).global_position, self)
					var v := world.get_node_or_null("/root/VfxSystem")
					if v and is_instance_valid(v) and v.has_method("play_event"):
						v.play_event("hit.enemy_melee", (_target as Node2D).global_position, world, Color(1, 0.7, 0.7, 1), 1.0)
				if _vampiric:
					_heal_from_hit(contact_damage)
		_contact_t = contact_cooldown

	# Arcane affix: periodic zap to nearest squad unit.
	if _arcane and _arcane_cd <= 0.0:
		_arcane_cd = 1.55
		_arcane_zap()

func _resolve_target_overlap() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var to_target := (_target.global_position - global_position)
	var dist := to_target.length()
	if dist < 0.001:
		return
	if dist >= TARGET_SEPARATION_RADIUS:
		return
	# Soft positional pushback so enemies don't sit inside player/squad bodies.
	var push := (TARGET_SEPARATION_RADIUS - dist) * 0.65
	global_position -= to_target.normalized() * push

func _resolve_actor_overlap() -> void:
	if _main == null or not is_instance_valid(_main):
		return
	var r2 := ACTOR_SEPARATION_RADIUS * ACTOR_SEPARATION_RADIUS
	# Player first
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and is_instance_valid(player):
		var d := global_position - player.global_position
		var d2 := d.length_squared()
		if d2 > 0.0001 and d2 < r2:
			global_position = player.global_position + d.normalized() * ACTOR_SEPARATION_RADIUS
	# Squad units
	var squad: Array = []
	if _main.has_method("get_cached_squad_units"):
		squad = _main.get_cached_squad_units()
	for u in squad:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		var dsu := global_position - n2.global_position
		var dsu2 := dsu.length_squared()
		if dsu2 > 0.0001 and dsu2 < r2:
			global_position = n2.global_position + dsu.normalized() * ACTOR_SEPARATION_RADIUS

func _base_move_speed() -> float:
	return (character_data.move_speed if character_data != null else 90.0) * _slow_mult * _move_speed_mult * ENEMY_WORLD_SPEED_MULT

func _melee_step(_delta: float, _dist: float, dir: Vector2) -> void:
	var spd := _base_move_speed()
	velocity = dir * spd
	move_and_slide()

func _charger_step(delta: float, dist: float, dir: Vector2) -> void:
	# Occasional dash toward target, otherwise normal chase.
	# Wind-up telegraph so the player can react (dash away / rally reposition).
	if _charge_windup_t > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_charge_telegraph()
		# When windup ends, start dash using stored dir (target may have moved).
		if _charge_windup_t <= 0.0:
			_end_charge_telegraph()
			_dash_t = 0.22
			_dash_dir = _charge_dir
		return

	if _dash_t > 0.0:
		_dash_t -= delta
		velocity = _dash_dir * (_base_move_speed() * 3.2)
		move_and_slide()
		return
	if dist < 320.0 and dist > 110.0 and _dash_cd <= 0.0:
		_dash_cd = 2.4
		_charge_windup_t = 0.42
		_charge_dir = dir
		_charge_target_pos = _target.global_position
		_begin_charge_telegraph()
		# Audible/visual tell
		var world := _main if _main != null else get_tree().get_first_node_in_group("main") as Node2D
		if world:
			var sw := VfxShockwave.new()
			sw.setup(global_position, Color(1.0, 0.65, 0.35, 1.0), 10.0, 68.0, 3.0, 0.22)
			world.add_child(sw)
			var s := world.get_node_or_null("/root/SfxSystem")
			if s and s.has_method("play_event"):
				s.play_event("enemy.dash", global_position, self)
			var v := world.get_node_or_null("/root/VfxSystem")
			if v and is_instance_valid(v) and v.has_method("play_event"):
				v.play_event("enemy.dash", global_position, world)
		return
	_melee_step(delta, dist, dir)

func _begin_charge_telegraph() -> void:
	if _charge_line != null and is_instance_valid(_charge_line):
		_charge_line.queue_free()
		_charge_line = null
	_charge_line = Line2D.new()
	# Replace ugly solid red line with a soft, patterned telegraph.
	_charge_line.width = 7.0
	_charge_line.default_color = Color(1.0, 0.55, 0.25, 0.42)
	_charge_line.z_index = 50
	_charge_line.antialiased = true
	# Texture-tiled hazard stripe
	if _charge_line_tex == null:
		_charge_line_tex = _make_charge_line_tex()
	_charge_line.texture = _charge_line_tex
	_charge_line.texture_mode = Line2D.LINE_TEXTURE_TILE
	# Fade ends slightly so it doesn't look like a hitscan beam.
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_charge_line.gradient = g
	add_child(_charge_line)
	_update_charge_telegraph()
	# Mark the intended endpoint (so dodging feels fair).
	var world := _main if _main != null else get_tree().get_first_node_in_group("main") as Node2D
	if world:
		# SFX: short telegraph tick (throttled per-emitter)
		var s := world.get_node_or_null("/root/SfxSystem")
		if s and is_instance_valid(s) and s.has_method("play_event"):
			s.play_event("telegraph.charge", _charge_target_pos, self)
		# Prefer EffectBlocks telegraph marker if exported.
		var v := world.get_node_or_null("/root/VfxSystem")
		var ok := false
		if v and is_instance_valid(v) and v.has_method("play_event"):
			ok = bool(v.play_event("telegraph.charge", _charge_target_pos, world, Color(1, 1, 1, 1), 1.0))
		if not ok:
			var fm := VfxFocusMark.new()
			fm.setup(_charge_target_pos, Color(1.0, 0.35, 0.25, 0.95), 16.0, 0, 0.40)
			world.add_child(fm)

func _update_charge_telegraph() -> void:
	if _charge_line == null or not is_instance_valid(_charge_line):
		return
	# local line in Enemy space: from origin to target dir
	var a := Vector2.ZERO
	var b := to_local(_charge_target_pos)
	_charge_line.clear_points()
	_charge_line.add_point(a)
	_charge_line.add_point(b)
	# Pulse a bit (subtle; keep it “warning”, not “laser”)
	var t := float(Time.get_ticks_msec()) / 1000.0
	_charge_line.default_color.a = 0.28 + 0.22 * absf(sin(t * 8.0))

func _end_charge_telegraph() -> void:
	if _charge_line != null and is_instance_valid(_charge_line):
		_charge_line.queue_free()
	_charge_line = null

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
	bolt.setup_target(tgt, maxi(1, dmg), tint, 560.0, _smoke_hit_chance)
	var s := world.get_node_or_null("/root/SfxSystem")
	if s and s.has_method("play_event"):
		s.play_event("enemy.spit", global_position, self)
	var v := world.get_node_or_null("/root/VfxSystem")
	if v and is_instance_valid(v) and v.has_method("play_event"):
		v.play_event("enemy.spit", global_position, world)

func apply_smoke_blind(hit_chance: float, duration: float) -> void:
	_smoke_hit_chance = clampf(hit_chance, 0.10, 1.0)
	_smoke_time_left = maxf(_smoke_time_left, maxf(0.05, duration))
	if anim != null:
		anim.modulate = anim.modulate.lerp(Color(0.70, 0.78, 0.90, 1.0), 0.25)

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
		var v := world.get_node_or_null("/root/VfxSystem")
		if v and is_instance_valid(v) and v.has_method("play_event"):
			v.play_event("enemy.explode", global_position, world)
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
	var v := world.get_node_or_null("/root/VfxSystem")
	if v and is_instance_valid(v) and v.has_method("play_event"):
		v.play_event("enemy.arcane", global_position, world)
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
		var s := world.get_node_or_null("/root/SfxSystem")
		if s and is_instance_valid(s) and s.has_method("play_event"):
			s.play_event("enemy.vampiric_heal", global_position, self)
		# Prefer EffectBlocks VFX if available.
		var v := world.get_node_or_null("/root/VfxSystem")
		var ok := false
		if v and is_instance_valid(v) and v.has_method("play_event"):
			ok = bool(v.play_event("enemy.vampiric_heal", global_position, world, Color(1, 1, 1, 1), 1.0))
		if not ok:
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

func _update_anim_from_motion(motion: Vector2, look_dir: Vector2) -> void:
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
		_anim_cooldown = 0.12

	_apply_directional_flip(_current_anim)

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
	# For enemies that don't have real walking frames (rare, but happens in Pixellab exports),
	# add a subtle bob so they don't look frozen while sliding.
	if anim == null or anim.sprite_frames == null:
		return
	var sf := anim.sprite_frames
	var frames_n := 0
	if sf.has_animation(_current_anim):
		frames_n = sf.get_frame_count(_current_anim)
	var has_real_walk := frames_n >= 2

	if moving and (not has_real_walk):
		_walk_bob_t += get_physics_process_delta_time() * 9.0
		var bob := sin(_walk_bob_t) * 1.15
		anim.position = _anim_base_pos + Vector2(0, bob)
		anim.scale = _anim_base_scale * (1.0 + 0.012 * sin(_walk_bob_t * 2.0))
	else:
		_walk_bob_t = 0.0
		anim.position = _anim_base_pos
		anim.scale = _anim_base_scale

func _pick_walk_anim(dir: Vector2) -> String:
	var d := dir.normalized()
	var ax := absf(d.x)
	var ay := absf(d.y)
	var desired := _current_anim
	var threshold := 0.10
	if ax > ay + threshold:
		desired = "walk_east" if d.x >= 0.0 else "walk_west"
	elif ay > ax + threshold:
		desired = "walk_south" if d.y > 0.0 else "walk_north"

	var sf := anim.sprite_frames
	if sf.has_animation(desired) and sf.get_frame_count(desired) > 0:
		return desired
	if sf.has_animation("walk_south") and sf.get_frame_count("walk_south") > 0:
		return "walk_south"
	return desired

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
		var v := world.get_node_or_null("/root/VfxSystem")
		if v and is_instance_valid(v) and v.has_method("play_event"):
			v.play_event("enemy.die", global_position, world)
	var main := get_tree().get_first_node_in_group("main") as Node2D
	if main and is_instance_valid(main) and main.has_method("on_enemy_killed"):
		main.on_enemy_killed(is_elite, character_data, bool(get_meta("rift", false)), bool(get_meta("boss", false)))
	queue_free()

func _process_death_tags() -> void:
	var now_ms: int = int(Time.get_ticks_msec())
	var main := _main
	if main == null or not is_instance_valid(main):
		main = get_tree().get_first_node_in_group("main") as Node2D

	var enemies: Array = []
	if main and is_instance_valid(main) and main.has_method("get_cached_enemies"):
		enemies = main.get_cached_enemies()
	else:
		enemies = get_tree().get_nodes_in_group("enemies")

	# Chain Reaction passive
	if has_meta("_chain_reaction_dmg"):
		PassiveSystem.trigger_chain_reaction(self)

	# Reaper's Hunger: kill heal
	if has_meta("_reaper_hunger_kill_heal"):
		var heal_amt := int(get_meta("_reaper_hunger_kill_heal", 0))
		var attacker: Node2D = get_meta("_reaper_hunger_attacker", null) as Node2D
		if heal_amt > 0 and attacker != null and is_instance_valid(attacker) and attacker.has_method("heal"):
			attacker.heal(heal_amt)
			if attacker.has_method("pulse_vfx"):
				attacker.pulse_vfx(Color(0.55, 1.0, 0.65, 1.0))
			if main != null and is_instance_valid(main):
				var hp := VfxHolyPulse.new()
				hp.setup(attacker.global_position + Vector2(0, -18), Color(0.85, 0.35, 0.45, 1.0), 12.0, 32.0, 0.20)
				main.add_child(hp)
				var s2 := main.get_node_or_null("/root/SfxSystem")
				if s2 and is_instance_valid(s2) and s2.has_method("play_event"):
					s2.play_event("passive.reaper_hunger", attacker.global_position, attacker)

	# Frost Mastery: shatter on death
	if has_meta("_frost_shatter_until_ms"):
		var until_shatter: int = int(get_meta("_frost_shatter_until_ms", 0))
		if now_ms <= until_shatter:
			var rad_f: float = float(get_meta("_frost_shatter_radius", 0.0))
			var dmg_f: int = int(get_meta("_frost_shatter_dmg", 0))
			if rad_f > 0.0 and dmg_f > 0:
				if main != null and is_instance_valid(main):
					var fn := VfxFrostNova.new()
					fn.setup(global_position, Color(0.55, 0.85, 1.0, 1.0), rad_f, 10, 0.28)
					main.add_child(fn)
					var s3 := main.get_node_or_null("/root/SfxSystem")
					if s3 and is_instance_valid(s3) and s3.has_method("play_event"):
						s3.play_event("passive.frost_mastery", global_position, self)
				var r2f := rad_f * rad_f
				for e in enemies:
					if not is_instance_valid(e):
						continue
					var n2 := e as Node2D
					if n2 == null or n2 == self:
						continue
					if n2.global_position.distance_squared_to(global_position) <= r2f:
						if n2.has_method("take_damage"):
							n2.take_damage(dmg_f, false, "frost")
						if n2.has_method("pulse_vfx"):
							n2.pulse_vfx(Color(0.55, 0.85, 1.0, 1.0))

	# Poison Mastery: spread on death
	if has_meta("_poison_spread_until_ms"):
		var until_p: int = int(get_meta("_poison_spread_until_ms", 0))
		if now_ms <= until_p:
			var rad_p: float = float(get_meta("_poison_spread_radius", 0.0))
			var dps_p: float = float(get_meta("_poison_spread_dps", 0.0))
			var dur_p: float = float(get_meta("_poison_spread_dur", 0.0))
			var tick_p: float = float(get_meta("_poison_spread_tick", 0.5))
			var count_p: int = int(get_meta("_poison_spread_count", 2))
			if rad_p > 0.0 and dps_p > 0.0 and count_p > 0:
				if main != null and is_instance_valid(main):
					var sf := VfxSmokeField.new()
					sf.setup(global_position, Color(0.35, 0.95, 0.35, 0.55), rad_p * 0.55, 0.6)
					main.add_child(sf)
					var s4 := main.get_node_or_null("/root/SfxSystem")
					if s4 and is_instance_valid(s4) and s4.has_method("play_event"):
						s4.play_event("passive.poison_mastery", global_position, self)
				var r2p := rad_p * rad_p
				var picked := 0
				for e in enemies:
					if picked >= count_p:
						break
					if not is_instance_valid(e):
						continue
					var n2 := e as Node2D
					if n2 == null or n2 == self:
						continue
					if n2.global_position.distance_squared_to(global_position) <= r2p:
						if n2.has_method("apply_burn"):
							n2.apply_burn(dps_p, dur_p, tick_p)
						if n2.has_method("pulse_vfx"):
							n2.pulse_vfx(Color(0.35, 0.95, 0.25, 1.0))
						picked += 1

	# Fire Mastery: spread burn on death
	if has_meta("_fire_spread_until_ms"):
		var until_f: int = int(get_meta("_fire_spread_until_ms", 0))
		if now_ms <= until_f:
			var rad_fi: float = float(get_meta("_fire_spread_radius", 0.0))
			var dps_fi: float = float(get_meta("_fire_spread_dps", 0.0))
			var dur_fi: float = float(get_meta("_fire_spread_dur", 0.0))
			var tick_fi: float = float(get_meta("_fire_spread_tick", 0.5))
			var count_fi: int = int(get_meta("_fire_spread_count", 2))
			if rad_fi > 0.0 and dps_fi > 0.0 and count_fi > 0:
				if main != null and is_instance_valid(main):
					var fb := VfxFlameBurst.new()
					fb.setup(global_position, Color(1.0, 0.55, 0.2, 1.0), rad_fi * 0.45, 12, 0.20, Vector2.ZERO)
					main.add_child(fb)
					var s5 := main.get_node_or_null("/root/SfxSystem")
					if s5 and is_instance_valid(s5) and s5.has_method("play_event"):
						s5.play_event("passive.fire_mastery", global_position, self)
				var r2fi := rad_fi * rad_fi
				var picked_f := 0
				for e in enemies:
					if picked_f >= count_fi:
						break
					if not is_instance_valid(e):
						continue
					var n2 := e as Node2D
					if n2 == null or n2 == self:
						continue
					if n2.global_position.distance_squared_to(global_position) <= r2fi:
						if n2.has_method("apply_burn"):
							n2.apply_burn(dps_fi, dur_fi, tick_fi)
							PassiveSystem.mark_burn(n2, dur_fi)
						if n2.has_method("pulse_vfx"):
							n2.pulse_vfx(Color(1.0, 0.55, 0.25, 1.0))
						picked_f += 1

	# Hex Bomb: if armed recently, explode on death.
	if has_meta("_hex_bomb_until_ms"):
		var until_ms: int = int(get_meta("_hex_bomb_until_ms", 0))
		if now_ms <= until_ms:
			var dmg: int = int(get_meta("_hex_bomb_dmg", 0))
			var radius: float = float(get_meta("_hex_bomb_radius", 140.0))
			if dmg > 0:
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
	_pulse_tw = create_tween()
	_pulse_tw.set_trans(Tween.TRANS_SINE)
	_pulse_tw.set_ease(Tween.EASE_OUT)
	# Brief tint + scale pop, then return to normal.
	anim.modulate = Color(1, 1, 1, 1)
	_pulse_tw.parallel().tween_property(anim, "modulate", tint, 0.06)
	_pulse_tw.tween_property(anim, "modulate", Color(1, 1, 1, 1), 0.10)

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
