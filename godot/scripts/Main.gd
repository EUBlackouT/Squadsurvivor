extends Node2D

@export var map_size: Vector2 = Vector2(4800, 3600)
@export var random_seed: int = 0

# Map visuals (removable). If disabled, uses the existing checkerboard background.
@export var use_rich_map: bool = true
@export var map_theme_id: String = "graveyard" # graveyard | arcane_ruins
@export var map_prop_count: int = 42
@export var map_fog_enabled: bool = true
@export var map_fog_strength: float = 0.16

@export var initial_enemy_count: int = 5
@export var max_enemies_alive: int = 90 # legacy cap, superseded by ramp below
@export var enemy_spawn_interval: float = 1.15 # legacy interval, superseded by ramp below
@export var enemy_spawn_burst: int = 1 # legacy burst, superseded by ramp below
@export var difficulty_ramp_minutes: float = 12.0
# >1.0 makes early game chill and midgame ramp faster (e.g. 2.0–3.0 is "chill then spicy").
@export var ramp_curve_power: float = 2.85
# "Vampire Survivors" target: early minutes are cleanable, midgame starts to pressure hard.
@export var spawn_interval_start: float = 2.60
@export var spawn_interval_end: float = 0.68
@export var max_enemies_start: int = 18
@export var max_enemies_end: int = 155
@export var spawn_radius_min: float = 820.0
@export var spawn_radius_max: float = 1300.0

@export var run_timer_max_minutes: float = 18.0
@export var enable_bosses: bool = false
@export var boss_spawn_time_minutes: float = 14.0
@export var enable_rifts: bool = false
@export var debug_hud_enabled: bool = false
@export var debug_collision_cleanup_enabled: bool = false
@export var debug_perf_overlay_enabled: bool = false

# Autosave (run state)
@export var autosave_enabled: bool = true
@export var autosave_interval_seconds: float = 25.0

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const RIFT_SCENE: PackedScene = preload("res://scenes/RiftNode.tscn")

const DAMAGE_NUMBERS_LAYER_SCRIPT: Script = preload("res://scripts/DamageNumbersLayer.gd")
const MAP_RENDERER_SCENE: PackedScene = preload("res://scenes/MapRenderer.tscn")

var damage_numbers: Node = null
var toast_layer: ToastLayer

var rng: RandomNumberGenerator
var run_start_time: float = 0.0

# Performance: live lists (no get_nodes_in_group() in hot paths)
var live_enemies: Array[Node2D] = []
var live_squad_units: Array[Node2D] = []

# Recruit/trophy flow
var essence: int = 0
var reroll_cost_essence: int = 3
var _recent_trophy_pool: Array[CharacterData] = []
var _force_rift_next_draft: bool = false

# Run structure
var _boss_spawned: bool = false
var _boss_node: Node2D = null
var _game_over: bool = false
var _victory: bool = false

#
# Draft system: RNG drops (no capture meter)
#
@export var draft_drop_chance_normal: float = 0.022 # ~1 in 45 kills baseline (with pity + cooldown)
@export var draft_drop_chance_elite: float = 0.18   # elites feel exciting, but shouldn't spam drafts
@export var draft_drop_pity_add_per_kill: float = 0.0022
@export var draft_drop_pity_cap: float = 0.06
@export var draft_drop_min_seconds_between: float = 20.0

var _draft_pity: float = 0.0
var _last_draft_time_s: float = -9999.0

var _spawn_timer: float = 0.0
var _dbg_cd: float = 0.0
var _dbg_text: String = ""
var _hide_projectiles: bool = false
var _strip_cd: float = 0.0
var _dbg_reported: Dictionary = {}

var _meta_awarded: bool = false
var _run_kills: int = 0
var _run_elite_kills: int = 0
var _run_drafts: int = 0
var _hide_debug_shapes_cd: float = 0.0
var _perf_text: String = ""

# Player commands (interactive layer)
var _focus_target: Node2D = null
var _focus_until_s: float = 0.0
var _focus_lockout_t: float = 0.0
var _rally_pos: Vector2 = Vector2.ZERO
var _rally_until_s: float = 0.0

# Active ability unlocked by meta tree: Overclock (Q)
var _overclock_until_s: float = 0.0
var _overclock_cd_s: float = 0.0

# Map tuning (data-driven via RunConfig + maps.json)
var _map_mod: Dictionary = {}

# Autosave node (ticks while paused)
var _autosave_node: Node = null

func _ready() -> void:
	add_to_group("main")
	_init_rng()
	run_start_time = Time.get_ticks_msec() / 1000.0

	# Hard-disable editor debug overlays that can make gameplay unreadable.
	# (Some run configurations can keep these on even when the menu checkbox looks off.)
	get_tree().debug_collisions_hint = false
	get_tree().debug_navigation_hint = false
	# NOTE: Some PhysicsServer2D debug APIs are not available in all builds; keep this portable.

	# Ensure data systems are loaded early.
	PixellabUtil.ensure_loaded()
	UnitFactory.ensure_loaded()
	PassiveSystem.ensure_loaded()
	EnemyFactory.ensure_loaded()
	var rc := get_node_or_null("/root/RunConfig")
	if rc and is_instance_valid(rc):
		if rc.has_method("ensure_loaded"):
			rc.ensure_loaded()
		if rc.has_method("get_selected_map"):
			_map_mod = rc.get_selected_map()

	_make_background()

	# Avoid relying on global class lookup; preload is robust under strict typing.
	damage_numbers = DAMAGE_NUMBERS_LAYER_SCRIPT.new()
	add_child(damage_numbers)

	toast_layer = ToastLayer.new()
	add_child(toast_layer)

	# Safety: remove any unexpected CircleShape2D CollisionShape2D nodes (these match the "orb" visuals).
	# Keep the RiftNode trigger intact.
	_strip_circle_collision_shapes()

	# No capture meter; drafts come from RNG drops on kills.

	_spawn_player()
	_spawn_initial_enemies()
	if enable_rifts:
		_spawn_rifts()
	_setup_hud()

	# Global systems
	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm) and mm.has_method("play"):
		mm.play("combat")
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and is_instance_valid(tm) and tm.has_method("show_tip"):
		tm.show_tip("movement")

	# Resume run snapshot (if requested from Menu).
	_try_apply_run_resume()

	_setup_autosave()

func _init_rng() -> void:
	rng = RandomNumberGenerator.new()
	if random_seed == 0:
		rng.seed = int(Time.get_unix_time_from_system())
	else:
		rng.seed = random_seed

func _elapsed_minutes() -> float:
	return ((Time.get_ticks_msec() / 1000.0) - run_start_time) / 60.0

func _make_background() -> void:
	# Preferred: MapRenderer (procedural rich ground + fog + props).
	if use_rich_map and MAP_RENDERER_SCENE != null:
		var mr := MAP_RENDERER_SCENE.instantiate()
		mr.name = "MapRenderer"
		add_child(mr)
		# Best-effort optional wiring, safe in strict typing mode.
		for pd in mr.get_property_list():
			var nm := StringName(String((pd as Dictionary).get("name", "")))
			match nm:
				&"map_size":
					mr.set(nm, map_size)
				&"theme_id":
					mr.set(nm, map_theme_id)
				&"prop_count":
					mr.set(nm, map_prop_count)
				&"fog_enabled":
					mr.set(nm, map_fog_enabled)
				&"fog_strength":
					mr.set(nm, map_fog_strength)
				&"seed":
					mr.set(nm, random_seed)
		return

	var w := int(map_size.x)
	var h := int(map_size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var tile := 32
	for y in range(0, h, tile):
		for x in range(0, w, tile):
			var base := Color(0.10, 0.12, 0.16, 1.0)
			var alt := Color(0.11, 0.14, 0.18, 1.0)
			var c := base if ((x / tile + y / tile) % 2 == 0) else alt
			img.fill_rect(Rect2i(x, y, tile, tile), c)
	var tex := ImageTexture.create_from_image(img)
	var bg := Sprite2D.new()
	bg.texture = tex
	bg.centered = false
	bg.position = Vector2(-map_size.x * 0.5, -map_size.y * 0.5)
	bg.z_index = -100
	add_child(bg)

func _spawn_player() -> void:
	if PLAYER_SCENE == null:
		return
	var p := PLAYER_SCENE.instantiate()
	p.position = Vector2.ZERO
	add_child(p)
	if p.has_node("Camera2D"):
		var cam := p.get_node("Camera2D") as Camera2D
		if cam:
			# Camera limits must be in *world* coordinates. If the Main scene root is offset
			# (common when the scene is authored with a viewport-ish origin), center limits
			# around this node's global_position instead of assuming (0,0).
			var o := global_position
			cam.limit_left = int(o.x - map_size.x * 0.5)
			cam.limit_top = int(o.y - map_size.y * 0.5)
			cam.limit_right = int(o.x + map_size.x * 0.5)
			cam.limit_bottom = int(o.y + map_size.y * 0.5)

func _spawn_initial_enemies() -> void:
	var mult := float(_map_mod.get("initial_enemies_mult", 1.0))
	var count: int = maxi(1, int(round(float(initial_enemy_count) * mult)))
	for i in range(count):
		_spawn_enemy(false, false, false)

func _spawn_rifts() -> void:
	if RIFT_SCENE == null:
		return
	# 2 rifts placed far from center for mid-run agency
	for i in range(2):
		var r := RIFT_SCENE.instantiate()
		add_child(r)
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(900.0, 1400.0)
		r.global_position = Vector2(cos(ang), sin(ang)) * dist

func _physics_process(delta: float) -> void:
	if _game_over or _victory:
		return

	# Command timers
	if _focus_until_s > 0.0:
		_focus_until_s = maxf(0.0, _focus_until_s - delta)
		if _focus_until_s <= 0.0:
			_focus_target = null
	if _focus_lockout_t > 0.0:
		_focus_lockout_t = maxf(0.0, _focus_lockout_t - delta)
	if _rally_until_s > 0.0:
		_rally_until_s = maxf(0.0, _rally_until_s - delta)
	if _overclock_until_s > 0.0:
		_overclock_until_s = maxf(0.0, _overclock_until_s - delta)
	if _overclock_cd_s > 0.0:
		_overclock_cd_s = maxf(0.0, _overclock_cd_s - delta)

	var t0_us: int = 0
	if debug_perf_overlay_enabled:
		t0_us = int(Time.get_ticks_usec())

	# IMPORTANT PERFORMANCE NOTE:
	# These operations traverse the whole scene tree and can cause rhythmic stutters.
	# They are only needed for debugging the prior "orb" issue, so keep them opt-in.
	if debug_collision_cleanup_enabled:
		_strip_cd -= delta
		if _strip_cd <= 0.0:
			_strip_cd = 0.6
			_strip_circle_collision_shapes()
		_hide_debug_shapes_cd -= delta
		if _hide_debug_shapes_cd <= 0.0:
			_hide_debug_shapes_cd = 0.4
			_hide_collision_debug_visuals()

	_spawn_timer += delta
	var spawn_interval := _current_spawn_interval()
	if _spawn_timer >= spawn_interval:
		_spawn_timer = 0.0
		_tick_spawns()

	var em := _elapsed_minutes()
	if enable_bosses and (not _boss_spawned) and em >= boss_spawn_time_minutes:
		_spawn_boss()
	_update_hud_labels()

	if debug_perf_overlay_enabled:
		var total_ms: float = float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
		_perf_text = "PERF frame_logic: %.2fms  enemies:%d  squad:%d" % [
			total_ms, live_enemies.size(), live_squad_units.size()
		]

func _unhandled_input(event: InputEvent) -> void:
	# Debug helper: toggle damage number layer to verify what's drawing the "orbs".
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		# Pause toggle
		if k.keycode == KEY_ESCAPE and (not _game_over) and (not _victory):
			# Don't open pause on top of draft UI (draft already pauses).
			if has_node("RecruitDraftUI"):
				return
			_toggle_pause_menu()
			return
		# NOTE: F8 is an editor hotkey (can stop the running game). Use Ctrl+Shift+F9.
		if k.keycode == KEY_F9 and k.ctrl_pressed and k.shift_pressed and damage_numbers != null:
			damage_numbers.visible = not damage_numbers.visible
		# Debug helper: hide projectiles to confirm whether the "orbs" are projectile visuals.
		# Ctrl+Shift+F10
		if k.keycode == KEY_F10 and k.ctrl_pressed and k.shift_pressed:
			_hide_projectiles = not _hide_projectiles
			for p in get_tree().get_nodes_in_group("projectiles"):
				if not is_instance_valid(p):
					continue
				var n2 := p as Node2D
				if n2:
					n2.visible = not _hide_projectiles
		# Ctrl+Shift+F11: toggle debug HUD counters (expensive)
		if k.keycode == KEY_F11 and k.ctrl_pressed and k.shift_pressed:
			debug_hud_enabled = not debug_hud_enabled
		# Ctrl+Shift+F12: toggle collision cleanup scans (very expensive)
		if k.keycode == KEY_F12 and k.ctrl_pressed and k.shift_pressed:
			debug_collision_cleanup_enabled = not debug_collision_cleanup_enabled

		# Ability: Overclock (Q)
		if k.keycode == KEY_Q:
			_try_overclock()

	# Player command input (ignore while paused/draft/pause menu)
	if get_tree().paused:
		return
	if has_node("RecruitDraftUI") or has_node("PauseMenu"):
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_try_focus_enemy(get_global_mouse_position())
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_set_rally(get_global_mouse_position(), 0.85)

func _try_focus_enemy(world_pos: Vector2) -> void:
	_prune_invalid_lists()
	var best: Node2D = null
	var best_d2 := INF
	var r2 := 72.0 * 72.0
	for e in live_enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		var d2 := n2.global_position.distance_squared_to(world_pos)
		if d2 <= r2 and d2 < best_d2:
			best_d2 = d2
			best = n2
	if best == null:
		# click-empty clears focus
		_focus_target = null
		_focus_until_s = 0.0
		return
	_set_focus_target(best, 4.0)

func _set_focus_target(tgt: Node2D, dur: float) -> void:
	if tgt == null or not is_instance_valid(tgt):
		return
	# Optional lockout (from meta keystone) to prevent rapid focus swapping.
	var mp := get_node_or_null("/root/MetaProgression")
	var lockout_add := 0.0
	var dur_mult := 1.0
	if mp and is_instance_valid(mp):
		if mp.has_method("get_add"):
			lockout_add = float(mp.get_add("focus_lockout_s", 0.0))
		if mp.has_method("get_mod"):
			dur_mult = float(mp.get_mod("focus_duration_mult", 1.0))
	if _focus_lockout_t > 0.0 and _focus_target != null and is_instance_valid(_focus_target) and tgt != _focus_target:
		return
	_focus_target = tgt
	_focus_until_s = maxf(0.05, dur * dur_mult)
	_focus_lockout_t = maxf(_focus_lockout_t, lockout_add)
	# Feedback
	if tgt.has_method("pulse_vfx"):
		tgt.pulse_vfx(Color(0.95, 0.90, 0.25, 1.0))
	var world := self
	var fm := VfxFocusMark.new()
	fm.setup(tgt.global_position, Color(1.0, 0.85, 0.30, 1.0), 18.0, 54.0, 0.32)
	world.add_child(fm)
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui("ui.click")

func _set_rally(pos: Vector2, dur: float) -> void:
	_rally_pos = pos
	var mp := get_node_or_null("/root/MetaProgression")
	var dur_mult := 1.0
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		dur_mult = float(mp.get_mod("rally_duration_mult", 1.0))
	_rally_until_s = maxf(0.05, dur * dur_mult)
	# Feedback
	var sw := VfxShockwave.new()
	sw.setup(pos, Color(0.45, 0.90, 1.0, 1.0), 10.0, 90.0, 3.0, 0.22)
	add_child(sw)
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui("ui.confirm")

func _overclock_unlocked() -> bool:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_add"):
		return float(mp.get_add("overclock_unlocked", 0.0)) >= 1.0
	return false

func is_overclock_active() -> bool:
	return _overclock_until_s > 0.0

func get_overclock_cd_left() -> float:
	return _overclock_cd_s

func get_overclock_rate_mult() -> float:
	# Attack speed multiplier while active.
	if not is_overclock_active():
		return 1.0
	var mp := get_node_or_null("/root/MetaProgression")
	var rate_mult := 1.25
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		rate_mult *= float(mp.get_mod("overclock_attack_speed_mult", 1.0))
	return rate_mult

func get_overclock_move_speed_mult() -> float:
	if not is_overclock_active():
		return 1.0
	var mp := get_node_or_null("/root/MetaProgression")
	var ms_mult := 1.15
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		ms_mult *= float(mp.get_mod("overclock_move_speed_mult", 1.0))
	return ms_mult

func get_overclock_damage_mult() -> float:
	if not is_overclock_active():
		return 1.0
	var mp := get_node_or_null("/root/MetaProgression")
	var dmg_mult := 1.0
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		dmg_mult *= float(mp.get_mod("overclock_damage_mult", 1.0))
	return dmg_mult

func _try_overclock() -> void:
	if get_tree().paused or _game_over or _victory:
		return
	if has_node("RecruitDraftUI") or has_node("PauseMenu"):
		return
	if not _overclock_unlocked():
		return
	if _overclock_cd_s > 0.0:
		return

	var mp := get_node_or_null("/root/MetaProgression")
	var cd_mult := 1.0
	var dur_mult := 1.0
	var burst_dmg := 0
	var burst_rad := 0.0
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		cd_mult = float(mp.get_mod("overclock_cooldown_mult", 1.0))
		dur_mult = float(mp.get_mod("overclock_duration_mult", 1.0))
	if mp and is_instance_valid(mp) and mp.has_method("get_add"):
		burst_dmg = int(round(float(mp.get_add("overclock_burst_damage_add", 0.0))))
		burst_rad = float(mp.get_add("overclock_burst_radius_add", 0.0))

	var duration := 4.0 * dur_mult
	var cooldown := 18.0 * cd_mult
	_overclock_until_s = duration
	_overclock_cd_s = maxf(0.25, cooldown)

	var player := get_tree().get_first_node_in_group("player") as Node2D
	var pos := player.global_position if player and is_instance_valid(player) else Vector2.ZERO
	# Feedback: strong, readable burst.
	var sw := VfxShockwave.new()
	sw.setup(pos, Color(0.45, 0.90, 1.0, 1.0), 14.0, 160.0, 3.0, 0.28)
	add_child(sw)
	var hp := VfxHolyPulse.new()
	hp.setup(pos, Color(0.45, 0.90, 1.0, 1.0), 12.0, 110.0, 0.25)
	add_child(hp)

	# Burst damage mutator (buildcraft): zap nearby enemies on activation.
	if burst_dmg > 0 and burst_rad > 1.0:
		var r2 := burst_rad * burst_rad
		_prune_invalid_lists()
		for e in live_enemies:
			if not is_instance_valid(e):
				continue
			var n2 := e as Node2D
			if n2 == null:
				continue
			if n2.global_position.distance_squared_to(pos) <= r2 and n2.has_method("take_damage"):
				n2.take_damage(burst_dmg, false, "arc")

	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui("ui.confirm")

func get_focus_target() -> Node2D:
	if _focus_target != null and is_instance_valid(_focus_target):
		return _focus_target
	return null

func get_focus_time_left() -> float:
	return _focus_until_s

func get_rally_pos() -> Vector2:
	return _rally_pos

func get_rally_time_left() -> float:
	return _rally_until_s

func _tick_spawns() -> void:
	_prune_invalid_lists()
	var cap := _current_max_enemies()
	if live_enemies.size() >= cap:
		return
	var burst := _current_spawn_burst()
	for i in range(burst):
		if live_enemies.size() >= cap:
			break
		_spawn_enemy(false, false, false)

func _ramp01() -> float:
	var t := _elapsed_minutes()
	return clampf(t / maxf(0.001, difficulty_ramp_minutes), 0.0, 1.0)

func _ramp01_curved() -> float:
	# Ease-in: keep early minutes calmer, then accelerate.
	var r := _ramp01()
	return pow(r, maxf(0.10, ramp_curve_power))

func _current_spawn_interval() -> float:
	# Starts forgiving, ramps toward hectic.
	var a := spawn_interval_start
	var b := spawn_interval_end
	var r := _ramp01_curved()
	var base := lerpf(a, b, r)
	return base * float(_map_mod.get("spawn_interval_mult", 1.0))

func _current_max_enemies() -> int:
	var a := max_enemies_start
	var b := max_enemies_end
	var r := _ramp01_curved()
	var base := int(round(lerpf(float(a), float(b), r)))
	return maxi(1, int(round(float(base) * float(_map_mod.get("max_enemies_mult", 1.0)))))

func _current_spawn_burst() -> int:
	# Keep early game at 1, later game occasionally uses 2.
	var r := _ramp01_curved()
	return 1 if r < 0.72 else 2

func _spawn_enemy(is_elite: bool, from_rift: bool, is_boss: bool) -> void:
	if ENEMY_SCENE == null:
		return
	var e := ENEMY_SCENE.instantiate()

	var player := get_tree().get_first_node_in_group("player") as Node2D
	var center := Vector2.ZERO
	if player and is_instance_valid(player):
		center = player.global_position
	var ang := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(spawn_radius_min, spawn_radius_max)

	# Random character pool -> random enemy skin
	var south := PixellabUtil.pick_random_south_path(rng)
	var cd := UnitFactory.build_character_data("enemy", rng, _elapsed_minutes(), south, _map_mod)
	if is_elite:
		cd.max_hp = int(round(float(cd.max_hp) * 1.55))
		cd.attack_damage = int(round(float(cd.attack_damage) * 1.25))

	# Enemy archetype + affixes (behavior variety)
	var ai_id := EnemyFactory.roll_enemy_ai_id(rng, _elapsed_minutes())
	var affixes := PackedStringArray()
	if is_elite:
		affixes = EnemyFactory.roll_elite_affixes(rng, _elapsed_minutes(), 2)
	# Bosses lean toward spectacle.
	if is_boss:
		ai_id = "charger"
		if affixes.is_empty():
			affixes = PackedStringArray(["arcane", "volatile"])

	# IMPORTANT: set exported fields BEFORE add_child so Enemy._ready() sees them.
	e.set_meta("rift", from_rift)
	e.set_meta("boss", is_boss)
	e.character_data = cd
	e.is_elite = is_elite
	e.pixellab_south_path = south
	e.ai_id = ai_id
	e.affix_ids = affixes
	add_child(e)
	e.global_position = center + Vector2(cos(ang), sin(ang)) * dist
	# SFX: elite spawns read as events (throttled).
	if is_elite and (not is_boss):
		var s := get_node_or_null("/root/SfxSystem")
		if s and is_instance_valid(s) and s.has_method("play_event"):
			s.play_event("enemy.elite_spawn", e.global_position, e)

func _spawn_boss() -> void:
	_boss_spawned = true
	_spawn_enemy(true, false, true)
	# Boss entrance feedback
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_event"):
		var pos := Vector2.ZERO
		if live_enemies.size() > 0 and is_instance_valid(live_enemies[live_enemies.size() - 1]):
			pos = (live_enemies[live_enemies.size() - 1] as Node2D).global_position
		s.play_event("boss.spawn", pos, self)
	var ss := get_node_or_null("/root/ScreenShake")
	if ss and is_instance_valid(ss):
		if ss.has_method("shake"):
			ss.shake(10.0, 0.20)
		if ss.has_method("hit_stop"):
			ss.hit_stop(0.06)
	# Best-effort: last enemy spawned is boss
	if live_enemies.size() > 0:
		_boss_node = live_enemies[live_enemies.size() - 1]

func register_enemy(e: Node2D) -> void:
	live_enemies.append(e)

func unregister_enemy(e: Node2D) -> void:
	var idx := live_enemies.find(e)
	if idx >= 0:
		live_enemies.remove_at(idx)

func register_squad_unit(u: Node2D) -> void:
	live_squad_units.append(u)

func unregister_squad_unit(u: Node2D) -> void:
	var idx := live_squad_units.find(u)
	if idx >= 0:
		live_squad_units.remove_at(idx)

func _prune_invalid_lists() -> void:
	for i in range(live_enemies.size() - 1, -1, -1):
		if not is_instance_valid(live_enemies[i]):
			live_enemies.remove_at(i)
	for j in range(live_squad_units.size() - 1, -1, -1):
		if not is_instance_valid(live_squad_units[j]):
			live_squad_units.remove_at(j)

func get_cached_enemies() -> Array[Node2D]:
	_prune_invalid_lists()
	return live_enemies

func get_cached_squad_units() -> Array[Node2D]:
	_prune_invalid_lists()
	return live_squad_units

func on_enemy_killed(is_elite: bool, cd: CharacterData, from_rift: bool, was_boss: bool) -> void:
	if _game_over or _victory:
		return

	# RNG draft drops (no capture bar)
	_roll_draft_drop(is_elite, was_boss)

	# Micro feedback: small shake on kills (bigger on elites/bosses).
	var ss := get_node_or_null("/root/ScreenShake")
	if ss and is_instance_valid(ss) and ss.has_method("shake"):
		var inten := 6.0 if (is_elite or was_boss) else 1.5
		ss.shake(inten, 0.10)

	# Global synergy triggers (on-kill effects like Undying heal)
	SynergySystem.on_enemy_killed(self, is_elite, was_boss)

	# Run stats
	_run_kills += 1
	if is_elite:
		_run_elite_kills += 1

	# Essence economy for rerolls
	var base := 1 if not is_elite else 3
	var mult := float(_map_mod.get("essence_mult", 1.0))
	essence += maxi(1, int(round(float(base) * mult)))

	# Trophy pool: store recent killed character variants for unlocks
	if cd != null:
		_recent_trophy_pool.append(cd)
		if _recent_trophy_pool.size() > 18:
			_recent_trophy_pool.pop_front()

	# Boss victory
	if enable_bosses and was_boss:
		_show_victory()

func start_rift_encounter(_rift: Node) -> void:
	# Next draft offers a "Mystery Rift" option with better odds
	_force_rift_next_draft = true
	# Spawn a short elite burst
	for i in range(10):
		_spawn_enemy(rng.randf() < 0.35, true, false)

func show_damage_number(source_id: int, channel: String, amount: int, world_pos: Vector2, style: int, is_crit: bool) -> void:
	if damage_numbers == null:
		return
	damage_numbers.spawn_aggregated(source_id, channel, amount, world_pos, style, is_crit)

func _on_draft_ready() -> void:
	# Autosave immediately before pausing (so resume is reliable).
	_request_autosave("draft")
	# Pause game and show recruit draft UI
	get_tree().paused = true
	var s := get_node_or_null("/root/SfxSystem")
	if s and s.has_method("play_ui"):
		s.play_ui("ui.open")
	_run_drafts += 1
	_show_recruit_draft()

func _setup_autosave() -> void:
	if has_node("AutosaveTicker"):
		_autosave_node = get_node("AutosaveTicker")
		return
	var t := preload("res://scripts/AutosaveTicker.gd").new()
	t.name = "AutosaveTicker"
	add_child(t)
	_autosave_node = t
	if _autosave_node and is_instance_valid(_autosave_node) and _autosave_node.has_method("set_main"):
		_autosave_node.set_main(self)

func _request_autosave(reason: String = "") -> void:
	if _autosave_node == null or not is_instance_valid(_autosave_node):
		_setup_autosave()
	if _autosave_node and is_instance_valid(_autosave_node) and _autosave_node.has_method("trigger_autosave"):
		_autosave_node.trigger_autosave(reason)

func _roll_draft_drop(is_elite: bool, was_boss: bool) -> void:
	# Don't stack drafts.
	if has_node("RecruitDraftUI"):
		return

	var now_s := float(Time.get_ticks_msec()) / 1000.0
	if now_s - _last_draft_time_s < draft_drop_min_seconds_between:
		return

	# Boss: always draft (feels like a chest).
	if was_boss:
		_last_draft_time_s = now_s
		_draft_pity = 0.0
		_on_draft_ready()
		return

	var base := draft_drop_chance_elite if is_elite else draft_drop_chance_normal
	var map_bonus := float(_map_mod.get("draft_drop_bonus", 0.0)) # optional per-map tuning
	var chance := clampf(base + _draft_pity + map_bonus, 0.0, 0.85)

	if rng.randf() < chance:
		_last_draft_time_s = now_s
		_draft_pity = 0.0
		var s := get_node_or_null("/root/SfxSystem")
		if s and s.has_method("play_ui"):
			s.play_ui("ui.drop")
		_on_draft_ready()
	else:
		_draft_pity = minf(draft_drop_pity_cap, _draft_pity + draft_drop_pity_add_per_kill)

func _show_recruit_draft() -> void:
	if has_node("RecruitDraftUI"):
		return
	var draft_ui := CanvasLayer.new()
	draft_ui.name = "RecruitDraftUI"
	draft_ui.layer = 100
	draft_ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(draft_ui)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	draft_ui.add_child(backdrop)

	var backdrop_shader_mat := ShaderMaterial.new()
	backdrop_shader_mat.shader = preload("res://shaders/ui_arcane_scifi_backdrop.gdshader")
	backdrop.material = backdrop_shader_mat

	var modal := PanelContainer.new()
	modal.set_anchors_preset(Control.PRESET_CENTER)
	# Larger + calmer spacing so cards breathe and text stays readable.
	modal.offset_left = -560
	modal.offset_top = -330
	modal.offset_right = 560
	modal.offset_bottom = 330
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	draft_ui.add_child(modal)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.13, 0.98)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(1, 1, 1, 0.10)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	modal.add_theme_stylebox_override("panel", sb)

	var neon_shader_mat := ShaderMaterial.new()
	neon_shader_mat.shader = preload("res://shaders/ui_neon_frame.gdshader")
	neon_shader_mat.set_shader_parameter("base_color", Color(0.10, 0.11, 0.13, 0.98))
	neon_shader_mat.set_shader_parameter("glow_color", Color(0.4, 0.8, 1.0, 0.6))
	neon_shader_mat.set_shader_parameter("glow_width", 0.02)
	neon_shader_mat.set_shader_parameter("pulse_speed", 1.2)
	modal.material = neon_shader_mat

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 22)
	modal.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	pad.add_child(vbox)

	var title := Label.new()
	title.text = "Recruit Draft"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Choose 1 reward. Unlocks go to your Collection (not auto-added)."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 0.95))
	vbox.add_child(subtitle)

	var info := Label.new()
	info.name = "InfoLabel"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "Essence: %d   (Reroll costs %d)" % [essence, reroll_cost_essence]
	info.add_theme_font_size_override("font_size", 16)
	info.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1))
	vbox.add_child(info)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	vbox.add_child(btns)

	var reroll_btn := Button.new()
	reroll_btn.text = "Reroll (%d)" % reroll_cost_essence
	reroll_btn.add_theme_font_size_override("font_size", 18)
	reroll_btn.custom_minimum_size = Vector2(180, 46)
	btns.add_child(reroll_btn)

	reroll_btn.pressed.connect(func():
		if essence < reroll_cost_essence:
			return
		var s := get_node_or_null("/root/SfxSystem")
		if s and s.has_method("play_ui"):
			s.play_ui("ui.reroll")
		essence -= reroll_cost_essence
		for c in hbox.get_children():
			c.queue_free()
		_populate_recruit_cards(hbox, draft_ui, false)
		info.text = "Essence: %d   (Reroll costs %d)" % [essence, reroll_cost_essence]
	)

	_populate_recruit_cards(hbox, draft_ui, _force_rift_next_draft)
	_force_rift_next_draft = false

	btns.add_spacer(true)

	var close_btn := Button.new()
	close_btn.text = "Close (Select Later)"
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.custom_minimum_size = Vector2(220, 46)
	close_btn.pressed.connect(func():
		var s := get_node_or_null("/root/SfxSystem")
		if s and is_instance_valid(s) and s.has_method("play_ui"):
			s.play_ui("ui.pause_close")
		_close_draft(draft_ui)
	)
	btns.add_child(close_btn)

func _populate_recruit_cards(hbox: HBoxContainer, ui: CanvasLayer, is_rift: bool) -> void:
	var options: Array[CharacterData] = []

	# Option 1-2: trophies from recent kills
	_recent_trophy_pool.shuffle()
	for i in range(mini(2, _recent_trophy_pool.size())):
		options.append(_recent_trophy_pool[i])

	# Option 3: random recruit roll (rift improves odds via elapsed minutes bias already)
	var south := PixellabUtil.pick_random_south_path(rng)
	var cd := UnitFactory.build_character_data("recruit", rng, _elapsed_minutes() + (3.0 if is_rift else 0.0), south, _map_mod)
	options.append(cd)

	# Ensure 3 cards
	while options.size() < 3:
		var s2 := PixellabUtil.pick_random_south_path(rng)
		options.append(UnitFactory.build_character_data("recruit", rng, _elapsed_minutes(), s2, _map_mod))

	for c in options:
		hbox.add_child(_create_character_card(c, ui))

func _create_character_card(cd: CharacterData, ui: CanvasLayer) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(330, 310)
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.92)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	var rarity_col := UnitFactory.rarity_color(cd.rarity_id)
	sb.border_color = rarity_col
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 12
	card.add_theme_stylebox_override("panel", sb)

	# Subtle hover/focus feedback (keeps input simple).
	card.pivot_offset = card.custom_minimum_size * 0.5
	card.mouse_entered.connect(func():
		var tw := card.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", Vector2(1.02, 1.02), 0.10)
		sb.border_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.95)
		sb.shadow_size = 18
	)
	card.mouse_exited.connect(func():
		var tw := card.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", Vector2.ONE, 0.12)
		sb.border_color = rarity_col
		sb.shadow_size = 12
	)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	card.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)

	# Header: rarity + role
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	v.add_child(header)

	var rarity_lbl := Label.new()
	rarity_lbl.text = UnitFactory.rarity_name(cd.rarity_id).to_upper()
	rarity_lbl.add_theme_font_size_override("font_size", 14)
	rarity_lbl.add_theme_color_override("font_color", rarity_col)
	header.add_child(rarity_lbl)

	header.add_spacer(true)

	var arch := Label.new()
	arch.text = cd.archetype_id.to_upper()
	arch.add_theme_font_size_override("font_size", 14)
	arch.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 0.95))
	header.add_child(arch)

	# Portrait (PixelLab south rotation)
	var portrait_frame := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.07, 0.09, 0.65)
	psb.border_width_left = 1
	psb.border_width_right = 1
	psb.border_width_top = 1
	psb.border_width_bottom = 1
	psb.border_color = Color(1, 1, 1, 0.08)
	psb.corner_radius_top_left = 10
	psb.corner_radius_top_right = 10
	psb.corner_radius_bottom_left = 10
	psb.corner_radius_bottom_right = 10
	portrait_frame.add_theme_stylebox_override("panel", psb)
	portrait_frame.custom_minimum_size = Vector2(0, 104)
	v.add_child(portrait_frame)

	var portrait_pad := MarginContainer.new()
	portrait_pad.add_theme_constant_override("margin_left", 6)
	portrait_pad.add_theme_constant_override("margin_right", 6)
	portrait_pad.add_theme_constant_override("margin_top", 6)
	portrait_pad.add_theme_constant_override("margin_bottom", 6)
	portrait_frame.add_child(portrait_pad)

	# Animated portrait using a SubViewport so we can render AnimatedSprite2D inside UI.
	var frames := PixellabUtil.walk_frames_from_south_path(cd.sprite_path)
	if frames != null and frames.has_animation("walk_south") and frames.get_frame_count("walk_south") > 0:
		var svc := SubViewportContainer.new()
		svc.custom_minimum_size = Vector2(80, 80)
		svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		svc.stretch = true
		svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		svc.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		portrait_pad.add_child(svc)

		var vp := SubViewport.new()
		vp.size = Vector2i(110, 110)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		svc.add_child(vp)

		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames
		spr.animation = "walk_south"
		spr.play()
		spr.centered = true
		spr.position = Vector2(vp.size.x * 0.5, vp.size.y * 0.5 + 8.0)
		spr.scale = Vector2(2.0, 2.0)
		spr.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		vp.add_child(spr)
	else:
		# Fallback to static south portrait if frames missing.
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(80, 80)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex := PixellabUtil.load_rotation_texture(cd.sprite_path)
		if tex == null and cd.pixellab_id != "":
			tex = PixellabUtil.load_rotation_texture("res://assets/pixellab/%s/rotations/south.png" % cd.pixellab_id)
		portrait.texture = tex
		portrait_pad.add_child(portrait)

	var style_label := Label.new()
	style_label.text = "STYLE: %s" % ("MELEE" if cd.attack_style == CharacterData.AttackStyle.MELEE else "RANGED")
	style_label.add_theme_font_size_override("font_size", 12)
	style_label.add_theme_color_override("font_color", Color(0.78, 0.88, 1.0, 0.90))
	v.add_child(style_label)

	# Stats grid for scanability
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var s_hp := Label.new(); s_hp.text = "HP  %d" % cd.max_hp
	var s_dmg := Label.new(); s_dmg.text = "DMG  %d" % cd.attack_damage
	var s_cd := Label.new(); s_cd.text = "CD  %.2f" % cd.attack_cooldown
	var s_rng := Label.new(); s_rng.text = "RNG  %d" % int(cd.attack_range)
	for lbl in [s_hp, s_dmg, s_cd, s_rng]:
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.86, 0.90, 0.96, 0.95))
		grid.add_child(lbl)

	# Passives as compact chips (tooltip shows full description).
	var pass_title := Label.new()
	pass_title.text = "PASSIVES"
	pass_title.add_theme_font_size_override("font_size", 12)
	pass_title.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 0.85))
	v.add_child(pass_title)

	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	v.add_child(chips)

	var shown := 0
	for pid in cd.passive_ids:
		if shown >= 3:
			break
		var chip := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.06, 0.07, 0.09, 0.80)
		csb.border_width_left = 1
		csb.border_width_right = 1
		csb.border_width_top = 1
		csb.border_width_bottom = 1
		var pc := PassiveSystem.passive_color(pid)
		csb.border_color = Color(pc.r, pc.g, pc.b, 0.55)
		csb.corner_radius_top_left = 10
		csb.corner_radius_top_right = 10
		csb.corner_radius_bottom_left = 10
		csb.corner_radius_bottom_right = 10
		chip.add_theme_stylebox_override("panel", csb)
		chip.tooltip_text = "%s\n%s" % [PassiveSystem.passive_name(pid), PassiveSystem.passive_description(pid)]
		chips.add_child(chip)

		var mp := MarginContainer.new()
		mp.add_theme_constant_override("margin_left", 8)
		mp.add_theme_constant_override("margin_right", 8)
		mp.add_theme_constant_override("margin_top", 4)
		mp.add_theme_constant_override("margin_bottom", 4)
		chip.add_child(mp)
		var tl := Label.new()
		tl.text = PassiveSystem.passive_name(pid)
		tl.add_theme_font_size_override("font_size", 12)
		tl.add_theme_color_override("font_color", Color(pc.r, pc.g, pc.b, 0.95))
		mp.add_child(tl)
		shown += 1

	if cd.passive_ids.size() > shown:
		var more := Label.new()
		more.text = "+%d" % (cd.passive_ids.size() - shown)
		more.add_theme_font_size_override("font_size", 12)
		more.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 0.75))
		chips.add_child(more)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	v.add_child(btn_row)
	btn_row.add_spacer(true)

	var details := Button.new()
	details.text = "Details"
	details.custom_minimum_size = Vector2(92, 40)
	details.add_theme_font_size_override("font_size", 16)
	btn_row.add_child(details)
	details.pressed.connect(func(): _show_character_details(cd, ui))

	var unlock := Button.new()
	unlock.text = "Unlock"
	unlock.custom_minimum_size = Vector2(110, 40)
	unlock.add_theme_font_size_override("font_size", 16)
	var usb := StyleBoxFlat.new()
	usb.bg_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.18)
	usb.border_width_left = 2
	usb.border_width_right = 2
	usb.border_width_top = 2
	usb.border_width_bottom = 2
	usb.border_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.65)
	usb.corner_radius_top_left = 10
	usb.corner_radius_top_right = 10
	usb.corner_radius_bottom_left = 10
	usb.corner_radius_bottom_right = 10
	unlock.add_theme_stylebox_override("normal", usb)
	btn_row.add_child(unlock)
	unlock.pressed.connect(func(): _select_character(cd, ui))

	return card

func _show_character_details(cd: CharacterData, ui: CanvasLayer) -> void:
	if ui.has_node("CharacterDetails"):
		ui.get_node("CharacterDetails").queue_free()
	var layer := CanvasLayer.new()
	layer.name = "CharacterDetails"
	layer.layer = 110
	layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	ui.add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -360
	panel.offset_top = -240
	panel.offset_right = 360
	panel.offset_bottom = 240
	layer.add_child(panel)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.95)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = UnitFactory.rarity_color(cd.rarity_id)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	panel.add_theme_stylebox_override("panel", sb)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)

	var t := Label.new()
	t.text = "Character Sheet"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 26)
	v.add_child(t)

	var b := Label.new()
	b.text = "%s • %s • %s\nHP %d  DMG %d  CD %.2f  RNG %d\nCrit %.0f%%  x%.2f" % [
		UnitFactory.rarity_name(cd.rarity_id),
		cd.archetype_id,
		"MELEE" if cd.attack_style == CharacterData.AttackStyle.MELEE else "RANGED",
		cd.max_hp, cd.attack_damage, cd.attack_cooldown, int(cd.attack_range),
		cd.crit_chance * 100.0, cd.crit_mult
	]
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(b)

	var p := Label.new()
	var lines: Array[String] = []
	for pid in cd.passive_ids:
		lines.append("• %s\n  %s" % [PassiveSystem.passive_name(pid), PassiveSystem.passive_description(pid)])
	p.text = "Passives:\n%s" % "\n".join(lines)
	p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(p)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): layer.queue_free())
	v.add_child(close)

func _select_character(cd: CharacterData, ui: CanvasLayer) -> void:
	# Unlock into persistent collection (NOT directly into squad).
	var cm := get_node_or_null("/root/CollectionManager")
	if cm and is_instance_valid(cm) and cm.has_method("unlock_character"):
		var ok: bool = bool(cm.unlock_character(cd))
		var s := get_node_or_null("/root/SfxSystem")
		if s and s.has_method("play_ui"):
			s.play_ui("ui.pick" if ok else "ui.cancel")
		if toast_layer != null:
			var rarity := UnitFactory.rarity_name(cd.rarity_id)
			var col := UnitFactory.rarity_color(cd.rarity_id)
			if ok:
				toast_layer.show_toast("Unlocked: %s • %s" % [rarity, cd.archetype_id], col)
			else:
				toast_layer.show_toast("Already unlocked: %s • %s" % [rarity, cd.archetype_id], Color(0.7, 0.8, 0.9, 1.0))
	_close_draft(ui)

func _close_draft(ui: Node) -> void:
	if ui:
		ui.queue_free()
	get_tree().paused = false

func _setup_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	add_child(hud)

	# Tiny autosave indicator (top-right)
	var autosave_lbl := Label.new()
	autosave_lbl.name = "AutosaveLabel"
	autosave_lbl.text = "Autosaving…"
	autosave_lbl.visible = false
	autosave_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	autosave_lbl.offset_left = -170
	autosave_lbl.offset_right = -18
	autosave_lbl.offset_top = 16
	autosave_lbl.offset_bottom = 36
	autosave_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	autosave_lbl.add_theme_font_size_override("font_size", 12)
	autosave_lbl.add_theme_color_override("font_color", Color(0.78, 0.92, 1.0, 0.92))
	hud.add_child(autosave_lbl)

	var container := VBoxContainer.new()
	container.name = "HUDVBox"
	container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	container.offset_left = 18
	container.offset_top = 18
	container.add_theme_constant_override("separation", 6)
	hud.add_child(container)

	var timer := Label.new()
	timer.name = "RunTimerLabel"
	timer.text = "Time: 0:00"
	container.add_child(timer)

	var formation := Label.new()
	formation.name = "FormationLabel"
	formation.text = "Formation: TIGHT   Tactics: NEAREST"
	container.add_child(formation)

	var cmd := Label.new()
	cmd.name = "CommandLabel"
	cmd.text = "Commands: LMB Focus • RMB Rally • Shift Dash"
	cmd.add_theme_color_override("font_color", Color(0.80, 0.92, 1.0, 0.92))
	container.add_child(cmd)

	var syn := Label.new()
	syn.name = "SynergyLabel"
	syn.text = "Synergies: —"
	syn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	syn.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 0.95))
	container.add_child(syn)

	var boss := Label.new()
	boss.name = "BossLabel"
	boss.text = ""
	container.add_child(boss)

	# Debug label to identify what is drawing the "orbs"
	var dbg := Label.new()
	dbg.name = "DebugLabel"
	dbg.text = ""
	container.add_child(dbg)

	var perf := Label.new()
	perf.name = "PerfLabel"
	perf.text = ""
	container.add_child(perf)

func _update_hud_labels() -> void:
	var hud := get_node_or_null("HUD/HUDVBox") as VBoxContainer
	if hud == null:
		return

	var t := get_node_or_null("HUD/HUDVBox/RunTimerLabel") as Label
	if t:
		var secs := int(round(((Time.get_ticks_msec() / 1000.0) - run_start_time)))
		var mm := int(secs / 60)
		var ss := int(secs % 60)
		t.text = "Time: %d:%02d   Essence: %d" % [mm, ss, essence]

	var b := get_node_or_null("HUD/HUDVBox/BossLabel") as Label
	if b:
		if _boss_node and is_instance_valid(_boss_node) and _boss_node.has_method("get_hp_ratio"):
			var r := float(_boss_node.get_hp_ratio())
			b.text = "Boss: %d%%" % int(round(r * 100.0))
		else:
			b.text = ""

	var s := get_node_or_null("HUD/HUDVBox/SynergyLabel") as Label
	if s:
		s.text = SynergySystem.summary_text()

	var cmd := get_node_or_null("HUD/HUDVBox/CommandLabel") as Label
	if cmd:
		var focus_txt := "Focus: —"
		var ft := get_focus_target()
		if ft != null:
			focus_txt = "Focus: %.1fs" % maxf(0.0, _focus_until_s)
		var rally_txt := "Rally: —"
		if _rally_until_s > 0.0:
			rally_txt = "Rally: %.1fs" % maxf(0.0, _rally_until_s)
		var dash_txt := "Dash: —"
		var player := get_tree().get_first_node_in_group("player")
		if player and is_instance_valid(player) and (player as Node).has_method("get_dash_cd_left"):
			var dcl := float((player as Node).get_dash_cd_left())
			dash_txt = "Dash: READY" if dcl <= 0.0 else ("Dash: %.1fs" % dcl)
		var oc_txt := ""
		if _overclock_unlocked():
			oc_txt = "   Overclock(Q): READY" if _overclock_cd_s <= 0.0 else ("   Overclock(Q): %.1fs" % _overclock_cd_s)
		cmd.text = "Commands: LMB Focus • RMB Rally • Shift Dash%s   |   %s   %s   %s" % [oc_txt, focus_txt, rally_txt, dash_txt]

	# Debug: count collision shapes / particles to confirm source of circles.
	var dbg := get_node_or_null("HUD/HUDVBox/DebugLabel") as Label
	if dbg:
		if not debug_hud_enabled:
			dbg.text = ""
		else:
			_dbg_cd -= get_process_delta_time()
			if _dbg_cd <= 0.0:
				_dbg_cd = 0.6
				var info := _collect_debug_counts(self)
				_dbg_text = "DBG CollisionShape2D:%d  CircleShape2D:%d  Particles:%d" % [
					int(info.get("cshape2d", 0)),
					int(info.get("circle2d", 0)),
					int(info.get("particles2d", 0))
				]
				var proj_count: int = get_tree().get_nodes_in_group("projectiles").size()
				_dbg_text += "  Projectiles:%d%s" % [proj_count, " (HIDDEN)" if _hide_projectiles else ""]
				var samples_v: Variant = info.get("circle_paths", PackedStringArray())
				var samples: PackedStringArray = samples_v if samples_v is PackedStringArray else PackedStringArray()
				if samples.size() > 0:
					_dbg_text += "\nCircles: " + ", ".join(samples)
				var details_v: Variant = info.get("circle_details", PackedStringArray())
				var details: PackedStringArray = details_v if details_v is PackedStringArray else PackedStringArray()
				if details.size() > 0:
					_dbg_text += "\nCircleSrc: " + " || ".join(details)
			dbg.text = _dbg_text

	var perf := get_node_or_null("HUD/HUDVBox/PerfLabel") as Label
	if perf:
		if not debug_perf_overlay_enabled:
			perf.text = ""
		else:
			perf.text = _perf_text

func _collect_debug_counts(root: Node) -> Dictionary:
	var cshape2d: int = 0
	var circle2d: int = 0
	var particles2d: int = 0
	var circle_paths := PackedStringArray()
	var circle_details := PackedStringArray()

	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back() as Node
		if n is CollisionShape2D:
			cshape2d += 1
			var cs := n as CollisionShape2D
			var sh := cs.shape
			if sh is CircleShape2D:
				circle2d += 1
				if circle_paths.size() < 6:
					circle_paths.append(String(cs.get_path()))
					var parent := cs.get_parent()
					var ppath: String = "<no-parent>"
					var ptype: String = "<no-parent>"
					var scr_path: String = "<no-script>"
					if parent != null:
						ppath = String(parent.get_path())
						ptype = parent.get_class()
						var scr: Script = parent.get_script() as Script
						if scr != null:
							scr_path = String(scr.resource_path)
					circle_details.append("%s | %s | %s" % [ppath, ptype, scr_path])
		elif n is GPUParticles2D or n is CPUParticles2D:
			particles2d += 1
		for ch in n.get_children():
			if ch is Node:
				stack.append(ch)

	return {
		"cshape2d": cshape2d,
		"circle2d": circle2d,
		"particles2d": particles2d,
		"circle_paths": circle_paths,
		"circle_details": circle_details
	}

func _strip_circle_collision_shapes() -> void:
	# Remove all CollisionShape2D nodes that have CircleShape2D shapes, except the RiftNode trigger.
	var stack: Array[Node] = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back() as Node
		if n is CollisionShape2D:
			var cs := n as CollisionShape2D
			var sh := cs.shape
			if sh is CircleShape2D:
				var parent := cs.get_parent()
				var keep: bool = false
				if parent != null and (parent.name == "RiftNode" or parent.get_script() == preload("res://scripts/RiftNode.gd")):
					keep = true
				if not keep:
					# One-time report so we can identify the source of @Area2D@20.
					var ppath: String = "<no-parent>"
					if parent != null:
						ppath = String(parent.get_path())
					if not _dbg_reported.has(ppath):
						_dbg_reported[ppath] = true
						var scr: Script = null
						if parent != null:
							scr = parent.get_script() as Script
						var scr_path: String = "<no-script>"
						if scr != null:
							scr_path = String(scr.resource_path)
						var ptype: String = parent.get_class() if parent != null else "<no-parent>"
						print("Stripping CircleShape2D at ", cs.get_path(), " parent=", ppath, " parent_type=", ptype, " script=", scr_path)
					cs.queue_free()
					continue
		for ch in n.get_children():
			if ch is Node:
				stack.append(ch)

func _hide_collision_debug_visuals() -> void:
	# If collision debug rendering is being forced on by the editor/run instance,
	# make all CollisionShape2D debug colors transparent so they can't show as "orbs".
	var stack: Array[Node] = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back() as Node
		if n is CollisionShape2D:
			var cs := n as CollisionShape2D
			cs.debug_color = Color(0, 0, 0, 0)
		for ch in n.get_children():
			if ch is Node:
				stack.append(ch)

	# End-of-run timer
	if _elapsed_minutes() >= run_timer_max_minutes and not _victory and not _game_over:
		# Survival victory (bosses are optional / later).
		_show_victory()

func _show_game_over() -> void:
	_game_over = true
	get_tree().paused = true
	var s := get_node_or_null("/root/SfxSystem")
	if s and s.has_method("play_ui"):
		s.play_ui("ui.defeat")
	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm) and mm.has_method("play"):
		mm.play("defeat", 0.35)
	# Run is finished, don't offer resume.
	var sv := get_node_or_null("/root/SaveManager")
	if sv and is_instance_valid(sv) and sv.has_method("delete_run_save"):
		sv.delete_run_save()
	_award_meta(false)
	var ui := CanvasLayer.new()
	ui.layer = 200
	add_child(ui)
	_build_end_screen(ui, "Run Failed", false)

func _show_victory() -> void:
	_victory = true
	get_tree().paused = true
	var s := get_node_or_null("/root/SfxSystem")
	if s and s.has_method("play_ui"):
		s.play_ui("ui.victory")
	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm) and mm.has_method("play"):
		mm.play("victory", 0.35)
	# Run is finished, don't offer resume.
	var sv := get_node_or_null("/root/SaveManager")
	if sv and is_instance_valid(sv) and sv.has_method("delete_run_save"):
		sv.delete_run_save()
	_award_meta(true)
	var ui := CanvasLayer.new()
	ui.layer = 200
	add_child(ui)
	_build_end_screen(ui, "Victory", true)

func _toggle_pause_menu() -> void:
	if get_tree().paused:
		# If paused but no pause menu exists, unpause; else let the pause menu handle resume.
		if has_node("PauseMenu"):
			return
		get_tree().paused = false
		var s := get_node_or_null("/root/SfxSystem")
		if s and is_instance_valid(s) and s.has_method("play_ui"):
			s.play_ui("ui.pause_close")
		return
	# open
	get_tree().paused = true
	var s2 := get_node_or_null("/root/SfxSystem")
	if s2 and is_instance_valid(s2) and s2.has_method("play_ui"):
		s2.play_ui("ui.pause_open")
	var layer := preload("res://scripts/PauseMenu.gd").new()
	layer.name = "PauseMenu"
	add_child(layer)

func _try_apply_run_resume() -> void:
	var sv := get_node_or_null("/root/SaveManager")
	if sv == null or not is_instance_valid(sv):
		return
	if (not ("resume_next_run" in sv)) or (not bool(sv.get("resume_next_run"))):
		return
	if not sv.has_method("pop_cached_run"):
		return
	var d: Dictionary = sv.pop_cached_run()
	if d.is_empty():
		return

	# Apply timers/state first.
	var now_s := float(Time.get_ticks_msec()) / 1000.0
	var elapsed_s := float(d.get("elapsed_s", 0.0))
	run_start_time = now_s - maxf(0.0, elapsed_s)
	essence = int(d.get("essence", essence))
	_run_kills = int(d.get("kills", _run_kills))

	var want_boss := bool(d.get("boss_spawned", false))
	_boss_spawned = want_boss

	# Move player + rebuild squad.
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and is_instance_valid(player):
		var ppos_v: Variant = d.get("player_pos", Vector2.ZERO)
		if ppos_v is Vector2:
			var ppos: Vector2 = ppos_v
			player.global_position = ppos

		# Remove current squad units
		if "squad_units" in player:
			var arr: Array = player.get("squad_units")
			for u in arr:
				if is_instance_valid(u):
					(u as Node).queue_free()
			player.set("squad_units", [])

		# Spawn saved squad
		var squad: Array = d.get("squad", [])
		for cd in squad:
			if cd is CharacterData and player.has_method("add_squad_unit"):
				player.add_squad_unit(cd)

	# If boss should be present, spawn it now if needed.
	if want_boss and (_boss_node == null or not is_instance_valid(_boss_node)):
		# Ensure we don't double-trigger _boss_spawned inside _spawn_boss.
		_boss_spawned = false
		_spawn_boss()

	# Feedback: resume loaded
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui("ui.resume_load")
	if toast_layer != null:
		toast_layer.show_toast("Resumed run.", Color(0.65, 0.85, 1.0, 1.0))

func _build_end_screen(ui: CanvasLayer, title_text: String, victory: bool) -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.82)
	ui.add_child(bg)
	var bgmat := ShaderMaterial.new()
	bgmat.shader = preload("res://shaders/ui_arcane_scifi_backdrop.gdshader")
	bg.material = bgmat

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -360
	card.offset_right = 360
	card.offset_top = -230
	card.offset_bottom = 230
	ui.add_child(card)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.10, 0.96)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.4, 0.8, 1.0, 0.18) if victory else Color(1.0, 0.35, 0.35, 0.18)
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	card.add_theme_stylebox_override("panel", sb)

	var neon := ShaderMaterial.new()
	neon.shader = preload("res://shaders/ui_neon_frame.gdshader")
	neon.set_shader_parameter("base_color", sb.bg_color)
	neon.set_shader_parameter("glow_color", Color(0.4, 0.8, 1.0, 0.55) if victory else Color(1.0, 0.35, 0.35, 0.50))
	neon.set_shader_parameter("glow_width", 0.02)
	neon.set_shader_parameter("pulse_speed", 1.1)
	card.material = neon

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	card.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40 if victory else 36)
	v.add_child(title)

	var mp := get_node_or_null("/root/MetaProgression")
	var lr: Dictionary = {}
	if mp and is_instance_valid(mp) and "last_run" in mp:
		lr = mp.last_run as Dictionary

	var summary := RichTextLabel.new()
	summary.bbcode_enabled = true
	summary.scroll_active = false
	summary.fit_content = true
	summary.add_theme_font_size_override("normal_font_size", 14)
	summary.add_theme_color_override("default_color", Color(0.85, 0.90, 0.96, 0.95))
	if lr.is_empty():
		summary.text = "Run stats unavailable."
	else:
		summary.text = "[b]Map:[/b] %s\n[b]Time:[/b] %dm   [b]Kills:[/b] %d (elites %d)   [b]Drafts:[/b] %d\n[b]Sigils earned:[/b] %d   [b]Total Sigils:[/b] %d" % [
			String(lr.get("map_name", "")),
			int(lr.get("minutes", 0)),
			int(lr.get("kills", 0)),
			int(lr.get("elite_kills", 0)),
			int(lr.get("drafts", 0)),
			int(lr.get("sigils_earned", 0)),
			int(mp.sigils) if mp != null and "sigils" in mp else 0
		]
	v.add_child(summary)

	# Progress to next slot
	if mp and is_instance_valid(mp) and mp.has_method("get_next_slot_cost") and mp.has_method("get_squad_slots"):
		var cost := int(mp.get_next_slot_cost())
		if cost > 0:
			var bar := ProgressBar.new()
			bar.min_value = 0
			bar.max_value = cost
			bar.value = clampi(int(mp.sigils), 0, cost)
			bar.custom_minimum_size = Vector2(0, 18)
			v.add_child(bar)
			var t := Label.new()
			t.add_theme_font_size_override("font_size", 13)
			t.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 0.95))
			t.text = "Next Squad Slot: %d → %d   (%d/%d sigils)" % [int(mp.get_squad_slots()), int(mp.get_squad_slots()) + 1, int(mp.sigils), cost]
			v.add_child(t)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	v.add_child(btn_row)
	btn_row.add_spacer(true)
	var btn := Button.new()
	btn.text = "Return to Menu"
	btn.custom_minimum_size = Vector2(220, 46)
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Menu.tscn"))
	btn_row.add_child(btn)
	btn_row.add_spacer(true)

func _award_meta(victory: bool) -> void:
	if _meta_awarded:
		return
	_meta_awarded = true
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp) or not mp.has_method("add_sigils"):
		return
	# Hard progression: meaningful but slow.
	var mins := _elapsed_minutes()
	var base := int(floor(mins * 18.0)) # ~18 per minute survived
	var bonus := 0
	if victory:
		bonus += 220
	# Map multiplier (harder maps => faster meta progress)
	var mult := float(_map_mod.get("meta_sigils_mult", 1.0))
	var total := int(round(float(base + bonus) * mult))
	total = maxi(5, total)
	mp.add_sigils(total)

	# Persist last run summary for Menu UI.
	if mp.has_method("set_last_run"):
		var rc := get_node_or_null("/root/RunConfig")
		var map_id := ""
		if rc != null and is_instance_valid(rc):
			map_id = String(rc.get("selected_map_id"))
		var map_name := String(_map_mod.get("name", map_id))
		var summary := {
			"victory": victory,
			"minutes": int(floor(_elapsed_minutes())),
			"map_id": map_id,
			"map_name": map_name,
			"kills": _run_kills,
			"elite_kills": _run_elite_kills,
			"drafts": _run_drafts,
			"sigils_earned": total
		}
		mp.set_last_run(summary)
