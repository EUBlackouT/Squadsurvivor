extends Node2D

const _MenuMapPreview := preload("res://scripts/ui/MenuMapPreview.gd")
const _PixelUi := preload("res://scripts/ui/PixelUi.gd")
const _RecruitDraftUI := preload("res://scripts/run/RecruitDraftUI.gd")
const _RunHudUI := preload("res://scripts/run/RunHudUI.gd")

@export var map_size: Vector2 = Vector2(4800, 3600)
@export var random_seed: int = 0

# Map visuals (removable). If disabled, uses the existing checkerboard background.
@export var use_rich_map: bool = true
@export var map_theme_id: String = "graveyard" # graveyard | arcane_ruins
@export var map_prop_count: int = 42
@export var map_fog_enabled: bool = true
@export var map_fog_strength: float = 0.16

@export var initial_enemy_count: int = 6
@export var max_enemies_alive: int = 90 # legacy cap, superseded by ramp below
@export var enemy_spawn_interval: float = 1.15 # legacy interval, superseded by ramp below
@export var enemy_spawn_burst: int = 1 # legacy burst, superseded by ramp below
@export var difficulty_ramp_minutes: float = 9.0
# >1.0 makes early game chill and midgame ramp faster (e.g. 2.0–3.0 is "chill then spicy").
@export var ramp_curve_power: float = 1.35
# "Vampire Survivors" target: early minutes are cleanable, midgame starts to pressure hard.
@export var spawn_interval_start: float = 1.45
@export var spawn_interval_end: float = 0.55
@export var max_enemies_start: int = 28
@export var max_enemies_end: int = 170
@export var spawn_radius_min: float = 900.0
@export var spawn_radius_max: float = 1100.0
@export var enemy_visual_pool_size: int = 16

@export var run_timer_max_minutes: float = 18.0
@export var enable_bosses: bool = false # overridden by map mod if present
@export var boss_spawn_time_minutes: float = 14.0 # overridden by map mod if present
@export var enable_rifts: bool = false
@export var debug_hud_enabled: bool = false
@export var debug_collision_cleanup_enabled: bool = false
@export var debug_perf_overlay_enabled: bool = false
@export var hitch_probe_enabled: bool = true
@export var hitch_probe_threshold_ms: float = 120.0
@export var perf_trace_enabled: bool = true
@export var perf_trace_spawn_threshold_ms: float = 12.0

# Autosave (run state)
@export var autosave_enabled: bool = true
@export var autosave_interval_seconds: float = 25.0

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const RIFT_SCENE: PackedScene = preload("res://scenes/RiftNode.tscn")
const SHRINE_SCENE: PackedScene = preload("res://scenes/ShrineNode.tscn")

const DAMAGE_NUMBERS_LAYER_SCRIPT: Script = preload("res://scripts/DamageNumbersLayer.gd")
const MAP_RENDERER_SCENE: PackedScene = preload("res://scenes/MapRenderer.tscn")
const TILE_MAP_WORLD_SCRIPT: Script = preload("res://scripts/TileMapWorld.gd")
const TMX_MAP_WORLD_SCRIPT: Script = preload("res://scripts/TmxMapWorld.gd")
const METADATA_MAP_WORLD_SCRIPT: Script = preload("res://scripts/MetadataMapWorld.gd")
const VFX_ARC_SCENE: PackedScene = preload("res://scenes/VfxArcLightning.tscn")
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
var banish_cost_essence: int = 1
var _recent_trophy_pool: Array[CharacterData] = []
var _force_rift_next_draft: bool = false

# Run structure
var _boss_spawned: bool = false
var _boss_node: Node2D = null
var _boss_deadline_s: float = -1.0
var _boss_fight_active: bool = false
var _boss_wave_times: PackedFloat32Array = PackedFloat32Array()
var _boss_wave_index: int = 0
var _boss_kills: int = 0
var _multi_boss_schedule_enabled: bool = false
var _boss_test_mode: bool = false
var _game_over: bool = false
var _victory: bool = false
var _objective_event_index: int = 0
var _objective_events: PackedFloat32Array = PackedFloat32Array([2.5, 6.0, 10.0, 14.0])

#
# Draft system: RNG drops (no capture meter) - Should feel RARE and SPECIAL
#
@export var draft_drop_chance_normal: float = 0.008  # Very rare (~1 in 125 kills base)
@export var draft_drop_chance_elite: float = 0.06    # Elites give hope but not guaranteed
@export var draft_drop_pity_add_per_kill: float = 0.001  # Very slow pity buildup
@export var draft_drop_pity_cap: float = 0.03        # Low pity cap
@export var draft_drop_min_seconds_between: float = 75.0  # At least 75s between drafts!

var _draft_pity: float = 0.0
var _last_draft_time_s: float = -9999.0

var _spawn_timer: float = 0.0
var _hide_projectiles: bool = false
var _strip_cd: float = 0.0
var _dbg_reported: Dictionary = {}

var _meta_awarded: bool = false
var _run_kills: int = 0
var _run_elite_kills: int = 0
var _run_drafts: int = 0
var _hide_debug_shapes_cd: float = 0.0
var _perf_text: String = ""
var _hud_refresh_t: float = 0.0
var _hitch_probe_cd: float = 0.0
var _probe_last_spawn_ms: float = 0.0
var _probe_last_spawn_count: int = 0

# Player commands (interactive layer)
var _focus_target: Node2D = null
var _focus_until_s: float = 0.0
var _focus_lockout_t: float = 0.0
var _rally_pos: Vector2 = Vector2.ZERO
var _rally_until_s: float = 0.0
var _rts_command_mode_enabled: bool = true
var _selected_units: Array[Node2D] = []
var _drag_select_started: bool = false
var _drag_select_active: bool = false
var _drag_select_start: Vector2 = Vector2.ZERO
var _drag_select_end: Vector2 = Vector2.ZERO
var _selection_layer: CanvasLayer = null
var _selection_rect: Panel = null
const DRAG_SELECT_THRESHOLD_PX: float = 10.0
var _player_node_ref: Node2D = null
var _player_cam_ref: Camera2D = null
var _camera_unlock_mode: bool = false

# Active ability unlocked by meta tree: Overclock (Q)
var _overclock_until_s: float = 0.0
var _overclock_cd_s: float = 0.0
var _meta_kill_chain_t: float = 0.0
var _meta_kill_chain_stacks: int = 0

# Active ability (always available): Class Callout (F)
var _callout_until_s: float = 0.0
var _callout_cd_s: float = 0.0
var _callout_class: int = -1

# Mage callout state: Arc Surge (queried by PassiveSystem)
var _arc_surge_until_s: float = 0.0
var _arc_surge_dmg_mult: float = 0.22

# Map tuning (data-driven via RunConfig + maps.json)
var _map_mod: Dictionary = {}
var _authored_map_world: Node2D = null
var _map_atmo_overlay: Node2D = null
var _map_bg_texture_cache: Dictionary = {} # path -> Texture2D
var _spawned_shrines: Array[Node2D] = []
var _shrine_war_t: float = 0.0
var _shrine_greed_t: float = 0.0
var _shrine_frost_t: float = 0.0
var _shrine_frost_tick_t: float = 0.0
var _shrine_war_ultra_t: float = 0.0
var _shrine_greed_ultra_t: float = 0.0
var _shrine_frost_ultra_t: float = 0.0

# Autosave node (ticks while paused)
var _autosave_node: Node = null
var _enemy_visual_pool: PackedStringArray = PackedStringArray()
var _enemy_visual_bag: Array[String] = []
var _enemy_visual_ready: PackedStringArray = PackedStringArray()
var _enemy_visual_warmed: Dictionary = {}
var _enemy_visual_ready_target: int = 2
var _enemy_template_pool: Array[CharacterData] = []
var _enemy_template_target: int = 28
var _enemy_template_refill_budget_ms: float = 2.4
var _enemy_template_refill_per_frame: int = 3
var _perf_boot_t0_us: int = 0
var _perf_boot_last_us: int = 0
var _perf_spawn_detail: String = ""
const _LIVE_SMOKE_STARTERS: Array[String] = ["insectoid", "ion_scout", "reef_medic"]
var _live_smoke_enabled: bool = false
var _live_smoke_case: String = ""
var _live_smoke_clock_scale: float = 1.0
var _live_smoke_timeout_s: float = 180.0
var _live_smoke_started_s: float = 0.0
var _live_smoke_last_tick_s: float = 0.0
var _live_smoke_reported: bool = false

func _ready() -> void:
	_perf_boot_t0_us = int(Time.get_ticks_usec())
	_perf_boot_last_us = _perf_boot_t0_us
	UiSkin.apply_global_font()
	_perf_boot_mark("UiSkin.apply_global_font")
	add_to_group("main")
	_init_rng()
	_perf_boot_mark("_init_rng")
	run_start_time = Time.get_ticks_msec() / 1000.0
	var uargs := OS.get_cmdline_user_args()
	_boss_test_mode = uargs.has("boss_test")
	_init_live_smoke_args(uargs)

	# Hard-disable editor debug overlays that can make gameplay unreadable.
	# (Some run configurations can keep these on even when the menu checkbox looks off.)
	get_tree().debug_collisions_hint = false
	get_tree().debug_navigation_hint = false
	# NOTE: Some PhysicsServer2D debug APIs are not available in all builds; keep this portable.

	# Ensure data systems are loaded early.
	PixellabUtil.ensure_loaded()
	CharacterRegistryUtil.ensure_loaded()
	UnitFactory.ensure_loaded()
	PassiveSystem.ensure_loaded()
	EnemyFactory.ensure_loaded()
	_perf_boot_mark("ensure_loaded systems")
	call_deferred("_build_enemy_visual_pool_deferred")
	call_deferred("_prime_enemy_templates_deferred")
	var rc := get_node_or_null("/root/RunConfig")
	if rc and is_instance_valid(rc):
		if rc.has_method("ensure_loaded"):
			rc.ensure_loaded()
		if rc.has_method("get_selected_map"):
			_map_mod = rc.get_selected_map()
	_apply_map_size_override()
	_perf_boot_mark("run config + map selection")

	# Bosses: default to map-driven if available.
	if not _map_mod.is_empty():
		enable_bosses = bool(_map_mod.get("boss_enabled", enable_bosses))
		boss_spawn_time_minutes = float(_map_mod.get("boss_spawn_minutes", boss_spawn_time_minutes))
		# Align survival timer with boss spawn if the map is "boss at the end".
		run_timer_max_minutes = float(_map_mod.get("boss_spawn_minutes", run_timer_max_minutes))
		_apply_map_pacing_overrides()
		_sync_objective_event_index_from_elapsed()
		_configure_boss_schedule()
		_sync_boss_wave_index_from_elapsed()
	if _live_smoke_enabled:
		_apply_live_smoke_overrides()

	_make_background()
	_perf_boot_mark("_make_background")

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
	_spawn_map_shrines()
	call_deferred("_spawn_initial_enemies_deferred")
	call_deferred("_announce_active_synergies")
	_perf_boot_mark("spawn player/shrines/initial enemies")
	if enable_rifts:
		_spawn_rifts()
	_setup_hud()
	_setup_selection_ui()
	_perf_boot_mark("hud + selection ui")

	# Global systems - play map-specific combat music
	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm):
		# Get map theme for music selection
		var music_theme := map_theme_id
		var vv: Variant = _map_mod.get("visuals", {})
		if typeof(vv) == TYPE_DICTIONARY:
			var vis: Dictionary = vv as Dictionary
			if vis.has("theme_id"):
				music_theme = String(vis.get("theme_id"))
		if mm.has_method("play_combat_for_map"):
			mm.play_combat_for_map(music_theme)
		elif mm.has_method("play"):
			mm.play("combat")
	var tm := get_node_or_null("/root/TutorialManager")
	if tm and is_instance_valid(tm) and tm.has_method("show_tip"):
		tm.show_tip("movement")

	# Resume run snapshot (if requested from Menu).
	_try_apply_run_resume()
	_perf_boot_mark("_try_apply_run_resume")

	_setup_autosave()
	_perf_boot_mark("_setup_autosave")
	_perf_boot_done()

func _process(_delta: float) -> void:
	if _enemy_runtime_warm_enabled():
		_warm_enemy_visuals_incremental()
	_refill_enemy_templates()

func _enemy_runtime_warm_enabled() -> bool:
	# Runtime warm can cause frame hitches on large sprite sets.
	# Keep it opt-in per map.
	return bool(_map_mod.get("enemy_runtime_warm", false))

func _enemy_startup_warm_count() -> int:
	if bool(_map_mod.get("enemy_startup_warm_all", false)):
		return maxi(1, _enemy_visual_pool.size())
	var target := int(_map_mod.get("enemy_startup_warm_count", 4))
	return clampi(target, 1, 64)

func _init_rng() -> void:
	rng = RandomNumberGenerator.new()
	if random_seed == 0:
		rng.seed = int(Time.get_unix_time_from_system())
	else:
		rng.seed = random_seed

func _perf_boot_mark(stage: String) -> void:
	if not perf_trace_enabled:
		return
	var now_us := int(Time.get_ticks_usec())
	var seg_ms := float(now_us - _perf_boot_last_us) / 1000.0
	var total_ms := float(now_us - _perf_boot_t0_us) / 1000.0
	_perf_boot_last_us = now_us
	print("BOOT_TRACE stage=%s seg_ms=%.2f total_ms=%.2f map=%s" % [stage, seg_ms, total_ms, String(_map_mod.get("id", "unknown"))])

func _perf_boot_done() -> void:
	if not perf_trace_enabled:
		return
	var total_ms := float(int(Time.get_ticks_usec()) - _perf_boot_t0_us) / 1000.0
	print("BOOT_TRACE_DONE total_ms=%.2f map=%s enemy_templates=%d enemy_visuals=%d" % [total_ms, String(_map_mod.get("id", "unknown")), _enemy_template_pool.size(), _enemy_visual_pool.size()])

func _prime_enemy_templates_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_refill_enemy_templates()

func _refill_enemy_templates() -> void:
	if rng == null:
		return
	if _enemy_template_pool.size() >= _enemy_template_target:
		return
	var t0_us := int(Time.get_ticks_usec())
	var built := 0
	while _enemy_template_pool.size() < _enemy_template_target and built < _enemy_template_refill_per_frame:
		var elapsed_ms := float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
		if elapsed_ms >= _enemy_template_refill_budget_ms:
			break
		var south := _pick_enemy_visual_path()
		if south == "":
			break
		var cd := UnitFactory.build_character_data("enemy", rng, _elapsed_minutes(), south, _map_mod)
		if cd == null:
			break
		_enemy_template_pool.append(cd)
		built += 1
	if perf_trace_enabled and built > 0:
		var spent_ms := float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
		if spent_ms >= perf_trace_spawn_threshold_ms:
			print("SPAWN_TEMPLATE_REFILL built=%d pool=%d/%d spent_ms=%.2f map=%s" % [built, _enemy_template_pool.size(), _enemy_template_target, spent_ms, String(_map_mod.get("id", "unknown"))])

func _init_live_smoke_args(uargs: PackedStringArray) -> void:
	var case_id := _arg_value(uargs, "live_smoke_case", "")
	if case_id == "":
		return
	_live_smoke_enabled = true
	_live_smoke_case = case_id
	_live_smoke_clock_scale = maxf(1.0, _arg_float(uargs, "live_smoke_clock_scale", 8.0))
	_live_smoke_timeout_s = maxf(10.0, _arg_float(uargs, "live_smoke_timeout_s", 210.0))
	print("LIVE_SMOKE start case=%s clock_scale=%.2f timeout=%.1fs" % [_live_smoke_case, _live_smoke_clock_scale, _live_smoke_timeout_s])

func _apply_live_smoke_overrides() -> void:
	# Force a deterministic 10-minute survival harness and disable draft pauses.
	enable_bosses = false
	enable_rifts = false
	run_timer_max_minutes = 10.0
	difficulty_ramp_minutes = 10.5
	ramp_curve_power = 2.1
	spawn_interval_start = 1.95
	spawn_interval_end = 0.58
	max_enemies_start = 20
	max_enemies_end = 154
	autosave_enabled = false
	draft_drop_chance_normal = 0.0
	draft_drop_chance_elite = 0.0
	draft_drop_pity_add_per_kill = 0.0
	draft_drop_pity_cap = 0.0
	draft_drop_min_seconds_between = 9999.0
	_objective_events = PackedFloat32Array()
	_objective_event_index = 0
	_write_live_smoke_roster(_build_live_smoke_roster(_live_smoke_case))

func _build_live_smoke_roster(case_id: String) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	var rr := RandomNumberGenerator.new()
	rr.seed = 1337 if case_id == "starter" else 9001
	var map_mod := _map_mod
	if case_id == "starter":
		for sid in _LIVE_SMOKE_STARTERS:
			var cd := CharacterRegistryUtil.build_character_data_by_id(sid, "recruit", rr, 0.0, map_mod)
			if cd == null:
				continue
			_apply_live_smoke_starter_nerf(cd)
			out.append(cd)
		return out

	for _i in range(3):
		var best: CharacterData = null
		var best_sc := -1e18
		for _j in range(24):
			var c := CharacterRegistryUtil.build_random_character_data("recruit", rr, 9.5, map_mod)
			if c == null:
				continue
			var sc := _live_smoke_power_score(c)
			if sc > best_sc:
				best_sc = sc
				best = c
		if best != null:
			_apply_live_smoke_upgrade_bonus(best)
			out.append(best)
	if out.size() < 3:
		return _build_live_smoke_roster("starter")
	return out

func _write_live_smoke_roster(roster: Array[CharacterData]) -> void:
	var cm := get_node_or_null("/root/CollectionManager")
	if cm == null or not is_instance_valid(cm):
		return
	var unlocked: Array[Dictionary] = []
	var active: Array[Dictionary] = []
	for cd in roster:
		if cd == null:
			continue
		var uid := ""
		var data: Dictionary = {}
		if cm.has_method("_make_unlock_id"):
			uid = String(cm._make_unlock_id(cd))
		if cm.has_method("_cd_to_dict"):
			data = cm._cd_to_dict(cd) as Dictionary
		unlocked.append({"id": uid, "data": data})
		active.append(data)
	if "unlocked" in cm:
		cm.unlocked = unlocked
	if "active_roster" in cm:
		cm.active_roster = active
	if cm.has_method("save"):
		cm.save()

func _apply_live_smoke_starter_nerf(cd: CharacterData) -> void:
	cd.max_hp = maxi(1, int(round(float(cd.max_hp) * 0.74)))
	cd.attack_damage = maxi(1, int(round(float(cd.attack_damage) * 0.60)))
	cd.attack_range = maxf(110.0, cd.attack_range * 0.82)
	cd.attack_cooldown = maxf(0.45, cd.attack_cooldown * 1.24)
	cd.move_speed = maxf(78.0, cd.move_speed * 0.90)
	cd.crit_chance = minf(cd.crit_chance, 0.03)
	if cd.passive_ids.size() > 1:
		cd.passive_ids = PackedStringArray([String(cd.passive_ids[0])])

func _apply_live_smoke_upgrade_bonus(cd: CharacterData) -> void:
	cd.max_hp = int(round(float(cd.max_hp) * 1.34))
	cd.attack_damage = int(round(float(cd.attack_damage) * 1.36))
	cd.attack_cooldown = maxf(0.20, float(cd.attack_cooldown) * 0.84)
	cd.attack_range = minf(760.0, float(cd.attack_range) * 1.14)
	cd.move_speed = float(cd.move_speed) * 1.08
	cd.crit_chance = clampf(cd.crit_chance + 0.08, 0.0, 0.55)
	if cd.passive_ids.size() > 3:
		var keep := PackedStringArray()
		for i in range(3):
			keep.append(String(cd.passive_ids[i]))
		cd.passive_ids = keep

func _live_smoke_power_score(cd: CharacterData) -> float:
	var hp := float(cd.max_hp)
	var dmg := float(cd.attack_damage)
	var aps := 1.0 / maxf(0.15, float(cd.attack_cooldown))
	var range_v := float(cd.attack_range)
	var speed := float(cd.move_speed)
	var crit := float(cd.crit_chance)
	var crit_m := float(cd.crit_mult)
	var crit_factor := 1.0 + crit * maxf(0.0, crit_m - 1.0)
	var score := hp * 0.20 + dmg * aps * crit_factor * 14.0 + range_v * 0.07 + speed * 0.35
	for pid in cd.passive_ids:
		var tags := PassiveSystem.passive_tags(String(pid))
		if tags.has("burst") or tags.has("execute"):
			score += 14.0
		if tags.has("sustain"):
			score += 12.0
		if tags.has("control") or tags.has("slow"):
			score += 11.0
		if tags.has("aoe"):
			score += 8.0
	return score

func _arg_value(uargs: PackedStringArray, key: String, default_v: String = "") -> String:
	var prefix := key + "="
	for a in uargs:
		var s := String(a)
		if s.begins_with(prefix):
			return s.substr(prefix.length())
	return default_v

func _arg_float(uargs: PackedStringArray, key: String, default_v: float) -> float:
	var v := _arg_value(uargs, key, "")
	if v == "":
		return default_v
	return float(v)

func _elapsed_minutes() -> float:
	return ((Time.get_ticks_msec() / 1000.0) - run_start_time) / 60.0

func _tick_live_smoke(_delta: float) -> void:
	var now_s := float(Time.get_ticks_msec()) / 1000.0
	if _live_smoke_started_s <= 0.0:
		_live_smoke_started_s = now_s
		_live_smoke_last_tick_s = now_s
	var dt := maxf(0.0, now_s - _live_smoke_last_tick_s)
	_live_smoke_last_tick_s = now_s
	if _live_smoke_clock_scale > 1.0:
		run_start_time -= dt * (_live_smoke_clock_scale - 1.0)
	if get_tree().paused:
		get_tree().paused = false

	if (_game_over or _victory) and not _live_smoke_reported:
		_live_smoke_reported = true
		var status := "failed" if _game_over else "cleared"
		print("LIVE_SMOKE_RESULT case=%s status=%s survived_m=%.2f kills=%d drafts=%d elites=%d" % [
			_live_smoke_case,
			status,
			_elapsed_minutes(),
			_run_kills,
			_run_drafts,
			_run_elite_kills
		])
		get_tree().quit()
		return

	if (now_s - _live_smoke_started_s) >= _live_smoke_timeout_s and not _live_smoke_reported:
		_live_smoke_reported = true
		print("LIVE_SMOKE_RESULT case=%s status=timeout survived_m=%.2f kills=%d drafts=%d elites=%d" % [
			_live_smoke_case,
			_elapsed_minutes(),
			_run_kills,
			_run_drafts,
			_run_elite_kills
		])
		get_tree().quit()

func _configure_boss_schedule() -> void:
	_multi_boss_schedule_enabled = false
	_boss_wave_times = PackedFloat32Array()
	_boss_wave_index = 0
	_boss_kills = 0
	var map_id := String(_map_mod.get("id", ""))
	if not enable_bosses:
		return
	# Church onboarding arc: two distinct boss checks in one run.
	if map_id == "church":
		_multi_boss_schedule_enabled = true
		_boss_wave_times = PackedFloat32Array([5.0, 10.0])
		boss_spawn_time_minutes = float(_boss_wave_times[0])
		run_timer_max_minutes = maxf(run_timer_max_minutes, 12.0)

func _apply_map_size_override() -> void:
	if _map_mod.is_empty():
		return
	var v: Variant = _map_mod.get("map_size", null)
	if v == null:
		return
	var override: Vector2 = map_size
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = v as Array
		if arr.size() >= 2:
			override = Vector2(float(arr[0]), float(arr[1]))
	elif typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v as Dictionary
		override = Vector2(float(d.get("x", map_size.x)), float(d.get("y", map_size.y)))
	if override.x >= 512.0 and override.y >= 512.0:
		map_size = override

func _make_background() -> void:
	# Determine biome from map_mod or theme_id
	var biome := "graveyard"
	var vis: Dictionary = {}
	if not _map_mod.is_empty():
		var vv: Variant = _map_mod.get("visuals", {})
		if typeof(vv) == TYPE_DICTIONARY:
			vis = vv as Dictionary
		if vis.has("theme_id"):
			biome = String(vis.get("theme_id"))
		elif _map_mod.has("id"):
			biome = String(_map_mod.get("id"))
	if biome.is_empty():
		biome = map_theme_id

	# Prefer authored TMX maps when provided by map data.
	var metadata_path := String(_map_mod.get("metadata_path", ""))
	if use_rich_map and not metadata_path.is_empty() and METADATA_MAP_WORLD_SCRIPT != null:
		var md_world := Node2D.new()
		md_world.set_script(METADATA_MAP_WORLD_SCRIPT)
		md_world.name = "MetadataMapWorld"
		md_world.set("metadata_path", metadata_path)
		md_world.set("map_size", map_size)
		var md_img := String(_map_mod.get("metadata_image_path", ""))
		if md_img != "":
			md_world.set("metadata_image_override", md_img)
		md_world.set("metadata_points_scale_mult", maxf(0.01, float(_map_mod.get("metadata_points_scale_mult", 1.0))))
		md_world.call("build_if_needed")
		if md_world.has_method("get_world_size"):
			var ws_md: Vector2 = md_world.get_world_size()
			if ws_md.x > 64.0 and ws_md.y > 64.0:
				map_size = ws_md
		add_child(md_world)
		_authored_map_world = md_world
		_add_tmx_atmo_overlay(vis)
		return

	# Prefer authored TMX maps when provided by map data.
	var tmx_path := String(_map_mod.get("tmx_path", ""))
	if use_rich_map and not tmx_path.is_empty() and TMX_MAP_WORLD_SCRIPT != null:
		var authored := Node2D.new()
		authored.set_script(TMX_MAP_WORLD_SCRIPT)
		authored.name = "TmxMapWorld"
		authored.set("tmx_path", tmx_path)
		authored.set("map_size", map_size)
		authored.call("build_if_needed")
		if authored.has_method("get_world_size"):
			var ws: Vector2 = authored.get_world_size()
			if ws.x > 64.0 and ws.y > 64.0:
				map_size = ws
		add_child(authored)
		_authored_map_world = authored
		_add_tmx_atmo_overlay(vis)
		return

	# If visuals explicitly provide a background image and there's no authored map,
	# render it directly as a static world sprite so tests see the exact PNG.
	var visual_bg_path := String(vis.get("bg_image_path", ""))
	if use_rich_map and not visual_bg_path.is_empty():
		var tex := _load_map_bg_texture(visual_bg_path)
		if tex != null:
			# Use the image's native pixel dimensions for a truthful visual test.
			map_size = tex.get_size()
			var bg := Sprite2D.new()
			bg.texture = tex
			bg.centered = false
			bg.position = Vector2(-map_size.x * 0.5, -map_size.y * 0.5)
			bg.z_index = -100
			bg.modulate = Color(1, 1, 1, clampf(float(vis.get("bg_image_alpha", 1.0)), 0.0, 1.0))
			add_child(bg)
			return
	
	# Try TileMapWorld (tile-based real maps) first
	if use_rich_map and TILE_MAP_WORLD_SCRIPT != null:
		var tmw := Node2D.new()
		tmw.set_script(TILE_MAP_WORLD_SCRIPT)
		tmw.name = "TileMapWorld"
		tmw.set("map_size", map_size)
		tmw.set("biome", biome)
		tmw.set("seed_value", random_seed)
		tmw.set("prop_count", map_prop_count)
		add_child(tmw)
		return
	
	# Fallback: MapRenderer (shader-based procedural ground + fog + props).
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
				&"map_visuals":
					mr.set(nm, vis)
				&"theme_id":
					mr.set(nm, biome)
				&"prop_count":
					if not vis.is_empty() and vis.has("prop_count"):
						mr.set(nm, int(vis.get("prop_count")))
					else:
						mr.set(nm, map_prop_count)
				&"fog_enabled":
					mr.set(nm, map_fog_enabled)
				&"fog_strength":
					if not vis.is_empty() and vis.has("fog_strength"):
						mr.set(nm, float(vis.get("fog_strength")))
					else:
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

func _load_map_bg_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _map_bg_texture_cache.has(path):
		var cached: Variant = _map_bg_texture_cache.get(path, null)
		if cached is Texture2D:
			return cached as Texture2D
	# Fast path: use Godot imported resource for res:// assets.
	# This avoids expensive raw PNG decode during boot.
	if path.begins_with("res://") and ResourceLoader.exists(path):
		# The menu kicks off a threaded load at Deploy click; collect it here
		# so the decode ran in parallel with scene instantiation.
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS or st == ResourceLoader.THREAD_LOAD_LOADED:
			var th_tex: Resource = ResourceLoader.load_threaded_get(path)
			if th_tex is Texture2D:
				var tt := th_tex as Texture2D
				_map_bg_texture_cache[path] = tt
				return tt
		var res_tex: Resource = ResourceLoader.load(path)
		if res_tex is Texture2D:
			var t2 := res_tex as Texture2D
			_map_bg_texture_cache[path] = t2
			return t2
	var candidates: Array[String] = [path]
	if path.begins_with("res://"):
		candidates.append(ProjectSettings.globalize_path(path))
	for p in candidates:
		if not FileAccess.file_exists(p):
			continue
		var img := Image.load_from_file(p)
		if img == null or img.is_empty():
			continue
		var tex := ImageTexture.create_from_image(img)
		if tex != null:
			_map_bg_texture_cache[path] = tex
			return tex
	var tex_any := load(path)
	if tex_any is Texture2D:
		var t3 := tex_any as Texture2D
		_map_bg_texture_cache[path] = t3
		return t3
	return null

func _add_tmx_atmo_overlay(vis: Dictionary) -> void:
	if _map_atmo_overlay != null and is_instance_valid(_map_atmo_overlay):
		_map_atmo_overlay.queue_free()
		_map_atmo_overlay = null
	var fog_col := Color(0.72, 0.76, 0.86, 1.0)
	if vis.has("fog_color"):
		fog_col = Color.html(String(vis.get("fog_color")))
	var fog_strength := clampf(float(vis.get("fog_strength", map_fog_strength)), 0.0, 0.45)
	var vignette_strength := clampf(float(vis.get("vignette", 0.28)), 0.0, 0.7)
	var light_strength := clampf(float(vis.get("light_strength", 0.15)), 0.0, 0.5)
	var root := Node2D.new()
	root.name = "MapAtmoOverlay"
	root.z_index = 1400
	add_child(root)
	_map_atmo_overlay = root

	# Optional authored background image (used for quick visual map tests while
	# still keeping TMX collisions/spawn and all gameplay data intact).
	var bg_image_path := String(vis.get("bg_image_path", ""))
	if not bg_image_path.is_empty():
		var bg_tex := _load_map_bg_texture(bg_image_path)
		if bg_tex != null:
			var bg := Sprite2D.new()
			bg.texture = bg_tex
			bg.centered = false
			bg.position = Vector2(-map_size.x * 0.5, -map_size.y * 0.5)
			bg.scale = Vector2(
				map_size.x / maxf(1.0, float(bg_tex.get_width())),
				map_size.y / maxf(1.0, float(bg_tex.get_height()))
			)
			bg.modulate = Color(1, 1, 1, clampf(float(vis.get("bg_image_alpha", 1.0)), 0.0, 1.0))
			bg.z_index = 1
			root.add_child(bg)

	# Fine noise tint to unify noisy authored tiles into one lighting mood.
	var fog_tex := _build_map_tint_texture(
		Color(fog_col.r, fog_col.g, fog_col.b, 1.0),
		0.04 + fog_strength * 0.22,
		0.02 + fog_strength * 0.10
	)
	var fog := Sprite2D.new()
	fog.texture = fog_tex
	fog.centered = false
	fog.position = Vector2(-map_size.x * 0.5, -map_size.y * 0.5)
	fog.scale = Vector2(map_size.x / maxf(1.0, float(fog_tex.get_width())), map_size.y / maxf(1.0, float(fog_tex.get_height())))
	fog.modulate = Color(1, 1, 1, 0.85)
	fog.z_index = 2
	root.add_child(fog)

	# Edge vignette keeps combat focus near the center camera area.
	var vig_tex := _build_map_vignette_texture(
		Color(0.05, 0.06, 0.08, 1.0),
		0.14 + vignette_strength * 0.46
	)
	var vignette := Sprite2D.new()
	vignette.texture = vig_tex
	vignette.centered = false
	vignette.position = Vector2(-map_size.x * 0.5, -map_size.y * 0.5)
	vignette.scale = Vector2(map_size.x / maxf(1.0, float(vig_tex.get_width())), map_size.y / maxf(1.0, float(vig_tex.get_height())))
	vignette.modulate = Color(1, 1, 1, 0.82)
	vignette.z_index = 3
	root.add_child(vignette)

	# Subtle top-down sacred light gradient to sell church atmosphere.
	var light_tex := _build_vertical_light_texture(Color(1.0, 0.96, 0.88, 1.0), 0.06 + light_strength * 0.24)
	var top_light := Sprite2D.new()
	top_light.texture = light_tex
	top_light.centered = false
	top_light.position = Vector2(-map_size.x * 0.5, -map_size.y * 0.5)
	top_light.scale = Vector2(map_size.x / maxf(1.0, float(light_tex.get_width())), map_size.y / maxf(1.0, float(light_tex.get_height())))
	top_light.modulate = Color(1, 1, 1, 0.85)
	top_light.z_index = 4
	root.add_child(top_light)

func _build_map_tint_texture(color: Color, base_alpha: float, noise_alpha: float) -> Texture2D:
	var w := 384
	var h := maxi(240, int(round(384.0 * (map_size.y / maxf(1.0, map_size.x)))))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var nrng := RandomNumberGenerator.new()
	nrng.seed = int(random_seed if random_seed != 0 else 1337)
	for y in range(h):
		for x in range(w):
			var n := nrng.randf_range(-1.0, 1.0)
			var a := clampf(base_alpha + n * noise_alpha, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	return ImageTexture.create_from_image(img)

func _build_map_vignette_texture(color: Color, edge_alpha: float) -> Texture2D:
	var w := 384
	var h := maxi(240, int(round(384.0 * (map_size.y / maxf(1.0, map_size.x)))))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := float(w - 1) * 0.5
	var cy := float(h - 1) * 0.5
	var inv_rx := 1.0 / maxf(1.0, cx)
	var inv_ry := 1.0 / maxf(1.0, cy)
	for y in range(h):
		for x in range(w):
			var nx := (float(x) - cx) * inv_rx
			var ny := (float(y) - cy) * inv_ry
			var d := sqrt(nx * nx + ny * ny)
			var e := clampf((d - 0.44) / 0.56, 0.0, 1.0)
			var a := edge_alpha * e * e
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	return ImageTexture.create_from_image(img)

func _build_vertical_light_texture(color: Color, max_alpha: float) -> Texture2D:
	var w := 256
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var t := float(y) / float(h - 1)
		var head := clampf(1.0 - t * 1.7, 0.0, 1.0)
		var a := max_alpha * head * head
		for x in range(w):
			var nx := absf((float(x) / float(w - 1)) * 2.0 - 1.0)
			var side_falloff := 1.0 - pow(nx, 1.5)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a * maxf(0.0, side_falloff)))
	return ImageTexture.create_from_image(img)

func _spawn_player() -> void:
	if PLAYER_SCENE == null:
		return
	var p := PLAYER_SCENE.instantiate()
	var spawn_pos := Vector2.ZERO
	if _authored_map_world != null and is_instance_valid(_authored_map_world) and _authored_map_world.has_method("get_default_spawn"):
		spawn_pos = _authored_map_world.get_default_spawn()
	p.position = spawn_pos
	add_child(p)
	_player_node_ref = p as Node2D
	if p.has_node("Camera2D"):
		var cam := p.get_node("Camera2D") as Camera2D
		if cam:
			_player_cam_ref = cam
			_configure_player_camera(cam)

func _announce_active_synergies() -> void:
	# Run-start callout so the player feels their squad build immediately.
	await get_tree().create_timer(1.4).timeout
	if _game_over or _victory or toast_layer == null:
		return
	var active := SynergySystem.get_active_synergies()
	if active.is_empty():
		return
	var parts: Array[String] = []
	for a in active:
		parts.append("%s ★%d" % [String(a.get("name", "")), int(a.get("tier", 0))])
	toast_layer.show_toast("Active Sets: %s" % "  •  ".join(parts), UiSkin.ACCENT_PURPLE)

func _spawn_initial_enemies() -> void:
	var mult := float(_map_mod.get("initial_enemies_mult", 1.0))
	var count: int = maxi(1, int(round(float(initial_enemy_count) * mult)))
	for i in range(count):
		_spawn_enemy(false, false, false)

func _spawn_initial_enemies_deferred() -> void:
	await get_tree().process_frame
	var tries := 0
	while _enemy_visual_ready.is_empty() and tries < 120:
		tries += 1
		await get_tree().process_frame
	_refill_enemy_templates()
	_spawn_initial_enemies()

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

func _spawn_map_shrines() -> void:
	if SHRINE_SCENE == null:
		return
	var count := maxi(0, int(_map_mod.get("shrine_count", 3)))
	if count <= 0:
		return
	var type_source: Array = _map_mod.get("shrine_types", ["war", "frost", "greed"]) as Array
	var shrine_types: Array[String] = []
	for t in type_source:
		var id := String(t).strip_edges().to_lower()
		if id == "":
			continue
		shrine_types.append(id)
	if shrine_types.is_empty():
		shrine_types = ["war", "frost", "greed"]
	var player := get_player_node()
	var player_pos := Vector2.ZERO
	if player != null and is_instance_valid(player):
		player_pos = player.global_position
	var placed: Array[Vector2] = []
	var ultra_type_flags: Dictionary = {}
	for i in range(count):
		var sid := shrine_types[i % shrine_types.size()]
		var pos := _find_random_shrine_position(player_pos, placed)
		var rarity := _roll_shrine_rarity()
		var sn := SHRINE_SCENE.instantiate() as Node2D
		if sn == null:
			continue
		sn.global_position = pos
		if sn.has_method("set"):
			sn.set("shrine_id", sid)
			sn.set("rarity", rarity)
		add_child(sn)
		_spawned_shrines.append(sn)
		placed.append(pos)
		if rarity == "ultra":
			ultra_type_flags[sid] = true
	_announce_ultra_shrines(ultra_type_flags)

func _announce_ultra_shrines(ultra_type_flags: Dictionary) -> void:
	if ultra_type_flags.is_empty():
		return
	var ultra_types: Array[String] = []
	for k in ultra_type_flags.keys():
		ultra_types.append(String(k))
	ultra_types.sort()
	var labels: Array[String] = []
	for t in ultra_types:
		labels.append(t.capitalize())
	var details := ", ".join(labels)
	if toast_layer != null:
		toast_layer.show_toast("Golden Shrine detected: %s." % details, Color(1.0, 0.92, 0.56, 1.0))
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui("ui.levelup")

func _roll_shrine_rarity() -> String:
	var base_ultra := clampf(float(_map_mod.get("shrine_ultra_chance", 0.0045)), 0.0, 0.20)
	var tier_bonus := float(maxi(0, _map_tier() - 1)) * 0.0012
	var chance := minf(0.015, base_ultra + tier_bonus)
	return "ultra" if rng.randf() < chance else "normal"

func _find_random_shrine_position(player_pos: Vector2, existing: Array[Vector2]) -> Vector2:
	var world_rect := _current_world_rect()
	var min_player_dist := clampf(minf(world_rect.size.x, world_rect.size.y) * 0.22, 420.0, 1200.0)
	var min_shrine_spacing := clampf(minf(world_rect.size.x, world_rect.size.y) * 0.14, 260.0, 700.0)
	for _i in range(160):
		var p := _sample_random_world_point(world_rect)
		if p.distance_to(player_pos) < min_player_dist:
			continue
		var too_close := false
		for ep in existing:
			if ep.distance_to(p) < min_shrine_spacing:
				too_close = true
				break
		if too_close:
			continue
		return p
	return _sample_random_world_point(world_rect)

func _sample_random_world_point(world_rect: Rect2) -> Vector2:
	if _authored_map_world != null and is_instance_valid(_authored_map_world) and _authored_map_world.has_method("get_random_walkable_point"):
		return _authored_map_world.get_random_walkable_point(rng)
	return Vector2(
		rng.randf_range(world_rect.position.x, world_rect.position.x + world_rect.size.x),
		rng.randf_range(world_rect.position.y, world_rect.position.y + world_rect.size.y)
	)

func _current_world_rect() -> Rect2:
	if _authored_map_world != null and is_instance_valid(_authored_map_world) and _authored_map_world.has_method("get_camera_rect"):
		return _authored_map_world.get_camera_rect()
	if _authored_map_world != null and is_instance_valid(_authored_map_world) and _authored_map_world.has_method("get_world_rect"):
		return _authored_map_world.get_world_rect()
	return Rect2(Vector2(-map_size.x * 0.5, -map_size.y * 0.5), map_size)

func activate_map_shrine(_shrine_node: Node, shrine_id: String, shrine_name: String = "", rarity: String = "normal") -> bool:
	if _game_over or _victory:
		return false
	var id := shrine_id.strip_edges().to_lower()
	var rr := rarity.strip_edges().to_lower()
	var ultra := rr == "ultra"
	if id == "":
		return false
	var nm := shrine_name if shrine_name != "" else ("%s Shrine" % id.capitalize())
	match id:
		"war":
			if ultra:
				_shrine_war_ultra_t = maxf(_shrine_war_ultra_t, 72.0)
				for _i in range(14):
					_spawn_enemy(rng.randf() < 0.90, true, false)
			else:
				_shrine_war_t = maxf(_shrine_war_t, 45.0)
				for _j in range(8):
					_spawn_enemy(rng.randf() < 0.65, true, false)
			if toast_layer != null:
				toast_layer.show_toast(
					("%s [ULTRA]: absurd damage tempo. Brutal elite ambush!" if ultra else "%s: +attack speed +damage. Elite ambush!") % nm,
					Color(1.0, 0.56, 0.38, 1.0)
				)
		"greed":
			if ultra:
				_shrine_greed_ultra_t = maxf(_shrine_greed_ultra_t, 86.0)
				essence += 110
				for _k in range(10):
					_spawn_enemy(rng.randf() < 0.70, true, false)
			else:
				_shrine_greed_t = maxf(_shrine_greed_t, 60.0)
				essence += 30
				for _l in range(5):
					_spawn_enemy(rng.randf() < 0.45, true, false)
			if toast_layer != null:
				toast_layer.show_toast(
					("%s [ULTRA]: jackpot mode active. Massive danger, massive rewards." if ultra else "%s: huge loot boost, enemy pressure rises.") % nm,
					Color(0.98, 0.90, 0.42, 1.0)
				)
		"frost":
			if ultra:
				_shrine_frost_ultra_t = maxf(_shrine_frost_ultra_t, 70.0)
			else:
				_shrine_frost_t = maxf(_shrine_frost_t, 42.0)
			_shrine_frost_tick_t = 0.2
			if toast_layer != null:
				toast_layer.show_toast(
					("%s [ULTRA]: relentless freezing shockwaves." if ultra else "%s: periodic frost shockwaves.") % nm,
					Color(0.62, 0.88, 1.0, 1.0)
				)
		_:
			return false
	return true

func _tick_shrine_effects(delta: float) -> void:
	_shrine_war_t = maxf(0.0, _shrine_war_t - delta)
	_shrine_greed_t = maxf(0.0, _shrine_greed_t - delta)
	_shrine_frost_t = maxf(0.0, _shrine_frost_t - delta)
	_shrine_war_ultra_t = maxf(0.0, _shrine_war_ultra_t - delta)
	_shrine_greed_ultra_t = maxf(0.0, _shrine_greed_ultra_t - delta)
	_shrine_frost_ultra_t = maxf(0.0, _shrine_frost_ultra_t - delta)
	if _shrine_frost_t <= 0.0 and _shrine_frost_ultra_t <= 0.0:
		return
	_shrine_frost_tick_t -= delta
	if _shrine_frost_tick_t > 0.0:
		return
	_shrine_frost_tick_t = 0.78 if _shrine_frost_ultra_t > 0.0 else 1.15
	_emit_frost_shrine_pulse()

func _emit_frost_shrine_pulse() -> void:
	var p := get_player_node()
	if p == null or not is_instance_valid(p):
		return
	var center := p.global_position
	var ultra := _shrine_frost_ultra_t > 0.0
	var radius := 520.0 if ultra else 360.0
	var r2 := radius * radius
	for e in live_enemies:
		if e == null or not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(center) > r2:
			continue
		if n2.has_method("apply_slow"):
			n2.apply_slow(0.42 if ultra else 0.70, 3.2 if ultra else 1.9)
		if n2.has_method("apply_execute_vulnerability"):
			n2.apply_execute_vulnerability(0.12 if ultra else 0.05, 3.0 if ultra else 2.3)
		if ultra and n2.has_method("take_damage"):
			n2.take_damage(18, false, "frost_shrine_ultra")
	var sw := VfxShockwave.new()
	sw.setup(center, Color(0.97, 0.95, 0.62, 0.98) if ultra else Color(0.60, 0.86, 1.0, 0.95), 10.0, radius * 0.44, 4.0, 0.18)
	add_child(sw)

func _physics_process(delta: float) -> void:
	if _live_smoke_enabled:
		_tick_live_smoke(delta)
	if _game_over or _victory:
		return
	var frame_start_us := int(Time.get_ticks_usec()) if hitch_probe_enabled else 0
	var seg_a_us := frame_start_us
	var seg_b_us := frame_start_us
	var seg_c_us := frame_start_us
	_prune_invalid_lists()
	_prune_selected_units()
	_update_camera_follow(delta)

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
	if _meta_kill_chain_t > 0.0:
		_meta_kill_chain_t = maxf(0.0, _meta_kill_chain_t - delta)
		if _meta_kill_chain_t <= 0.0:
			_meta_kill_chain_stacks = 0
	if _callout_until_s > 0.0:
		_callout_until_s = maxf(0.0, _callout_until_s - delta)
	if _callout_cd_s > 0.0:
		_callout_cd_s = maxf(0.0, _callout_cd_s - delta)
	if _arc_surge_until_s > 0.0:
		_arc_surge_until_s = maxf(0.0, _arc_surge_until_s - delta)
	_tick_shrine_effects(delta)
	if hitch_probe_enabled:
		seg_a_us = int(Time.get_ticks_usec())
	_probe_last_spawn_ms = 0.0
	_probe_last_spawn_count = 0

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
	var did_spawn_tick := false
	if _spawn_timer >= spawn_interval:
		did_spawn_tick = true
		_spawn_timer = 0.0
		_tick_spawns()
	_tick_objective_events()
	_tick_boss_mechanics(delta)

	var em := _elapsed_minutes()
	if enable_bosses:
		if _multi_boss_schedule_enabled:
			if (not _boss_fight_active) and _boss_wave_index < _boss_wave_times.size() and em >= float(_boss_wave_times[_boss_wave_index]):
				_spawn_boss()
		elif (not _boss_spawned) and em >= boss_spawn_time_minutes:
			_spawn_boss()
	_tick_end_of_run_timer()
	_hud_refresh_t -= delta
	if _hud_refresh_t <= 0.0:
		_hud_refresh_t = 0.10
		_update_hud_labels()
	_sync_passive_overlay_hotkey()
	if hitch_probe_enabled:
		seg_b_us = int(Time.get_ticks_usec())

	if debug_perf_overlay_enabled:
		var total_ms: float = float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
		_perf_text = "PERF frame_logic: %.2fms  enemies:%d  squad:%d" % [
			total_ms, live_enemies.size(), live_squad_units.size()
		]
	if hitch_probe_enabled:
		seg_c_us = int(Time.get_ticks_usec())
		_hitch_probe_cd = maxf(0.0, _hitch_probe_cd - delta)
		var total_ms2 := float(seg_c_us - frame_start_us) / 1000.0
		if total_ms2 >= hitch_probe_threshold_ms and _hitch_probe_cd <= 0.0:
			_hitch_probe_cd = 0.75
			var pre_ms := float(seg_a_us - frame_start_us) / 1000.0
			var core_ms := float(seg_b_us - seg_a_us) / 1000.0
			var post_ms := float(seg_c_us - seg_b_us) / 1000.0
			var map_id := String(_map_mod.get("id", "unknown"))
			print("HITCH total=%.1fms pre=%.1f core=%.1f post=%.1f enemies=%d squad=%d map=%s spawn_tick=%s spawn_ms=%.1f spawn_count=%d" % [
				total_ms2, pre_ms, core_ms, post_ms, live_enemies.size(), live_squad_units.size(), map_id,
				("1" if did_spawn_tick else "0"), _probe_last_spawn_ms, _probe_last_spawn_count
			])
			if _perf_spawn_detail != "":
				print("HITCH_SPAWN_DETAIL %s" % _perf_spawn_detail)

func _unhandled_input(event: InputEvent) -> void:
	# TAB: Show/hide passive overlay
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_TAB:
			if k.pressed and not k.echo:
				_show_passive_overlay()
			elif not k.pressed:
				_hide_passive_overlay()
			return
	
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

		# Ctrl+Shift+F8: toggle VFX debug toasts for heal/flame (shows exact source used).
		if k.keycode == KEY_F8 and k.ctrl_pressed and k.shift_pressed:
			var v := get_node_or_null("/root/VfxSystem")
			if v and is_instance_valid(v) and v.has_method("set_debug_toasts_enabled"):
				var enabled_now := not bool(v.get("debug_toasts_enabled"))
				v.set_debug_toasts_enabled(enabled_now)
				if toast_layer != null:
					toast_layer.show_toast("VFX debug toasts: %s" % ("ON" if enabled_now else "OFF"), Color(0.65, 0.85, 1.0, 1.0))

		# Ctrl+Shift+H: spawn syn.holy at player position (sanity test)
		if k.keycode == KEY_H and k.ctrl_pressed and k.shift_pressed:
			var v := get_node_or_null("/root/VfxSystem")
			var p := get_tree().get_first_node_in_group("player") as Node2D
			if v and is_instance_valid(v) and v.has_method("play_event") and p != null and is_instance_valid(p):
				v.play_event("syn.holy", p.global_position, self)

		# Ctrl+Shift+J: spawn syn.flame at player position (sanity test)
		if k.keycode == KEY_J and k.ctrl_pressed and k.shift_pressed:
			var v := get_node_or_null("/root/VfxSystem")
			var p := get_tree().get_first_node_in_group("player") as Node2D
			if v and is_instance_valid(v) and v.has_method("play_event") and p != null and is_instance_valid(p):
				v.play_event("syn.flame", p.global_position, self)

		# Ability: Overclock (Q)
		if k.keycode == KEY_Q:
			_try_overclock()
		# Ability: Class Callout (F)
		if k.keycode == KEY_F:
			_try_class_callout()
		# Camera mode toggle: default follows whole squad, unlocked follows selected split group.
		if k.keycode == KEY_C and (not k.ctrl_pressed) and (not k.alt_pressed) and (not k.shift_pressed):
			_camera_unlock_mode = not _camera_unlock_mode
			if not _camera_unlock_mode and _player_cam_ref != null and is_instance_valid(_player_cam_ref):
				_player_cam_ref.position = Vector2.ZERO
			if toast_layer != null:
				var msg := "Camera: UNLOCKED (manual WASD pan)" if _camera_unlock_mode else "Camera: LOCKED (auto follow)"
				toast_layer.show_toast(msg, Color(0.65, 0.85, 1.0, 1.0))

	# Player command input (ignore while paused/draft/pause menu)
	if get_tree().paused:
		return
	if has_node("RecruitDraftUI") or has_node("PauseMenu"):
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_select_started and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_drag_select_end = mm.position
			if (not _drag_select_active) and _drag_select_start.distance_to(_drag_select_end) >= DRAG_SELECT_THRESHOLD_PX:
				_drag_select_active = true
			if _drag_select_active:
				_update_selection_rect_visual()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_select_started = true
				_drag_select_active = false
				_drag_select_start = mb.position
				_drag_select_end = mb.position
				_update_selection_rect_visual()
			else:
				var was_drag := _drag_select_active
				_drag_select_started = false
				_drag_select_active = false
				_update_selection_rect_visual()
				if was_drag:
					_select_units_in_screen_rect(_drag_select_start, _drag_select_end, mb.shift_pressed)
				else:
					_select_single_unit_at(_screen_to_world(mb.position), mb.shift_pressed)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var mouse_world := _screen_to_world(mb.position)
			if not _selected_units.is_empty():
				var tgt := _pick_enemy_at(mouse_world, 72.0)
				if tgt != null and is_instance_valid(tgt):
					_issue_attack_command(tgt)
				else:
					_issue_move_command(mouse_world)
			elif not _rts_command_mode_enabled:
				_set_rally(mouse_world, 0.85)
			get_viewport().set_input_as_handled()
			return

func _setup_selection_ui() -> void:
	if _selection_layer != null and is_instance_valid(_selection_layer):
		return
	_selection_layer = CanvasLayer.new()
	_selection_layer.name = "CommandSelectionLayer"
	_selection_layer.layer = 40
	add_child(_selection_layer)
	_selection_rect = Panel.new()
	_selection_rect.name = "SelectionRect"
	_selection_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_rect.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.28, 0.72, 1.0, 0.12)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.40, 0.86, 1.0, 0.95)
	_selection_rect.add_theme_stylebox_override("panel", sb)
	_selection_layer.add_child(_selection_rect)

func _update_selection_rect_visual() -> void:
	if _selection_rect == null or not is_instance_valid(_selection_rect):
		return
	if not _drag_select_active:
		_selection_rect.visible = false
		return
	var min_x := minf(_drag_select_start.x, _drag_select_end.x)
	var min_y := minf(_drag_select_start.y, _drag_select_end.y)
	var max_x := maxf(_drag_select_start.x, _drag_select_end.x)
	var max_y := maxf(_drag_select_start.y, _drag_select_end.y)
	_selection_rect.position = Vector2(min_x, min_y)
	_selection_rect.size = Vector2(maxf(2.0, max_x - min_x), maxf(2.0, max_y - min_y))
	_selection_rect.visible = true

func _prune_selected_units() -> void:
	for i in range(_selected_units.size() - 1, -1, -1):
		if not is_instance_valid(_selected_units[i]):
			_selected_units.remove_at(i)

func _update_camera_follow(_delta: float) -> void:
	if _player_cam_ref == null or not is_instance_valid(_player_cam_ref):
		return
	_refresh_camera_limits()
	# Locked: camera is a zero-offset child of the player — Godot's limit_* keeps
	# the view in bounds at map edges. Do NOT manually offset/clamp each frame;
	# that fought the engine and made the camera lag behind fast movement.
	if not _camera_unlock_mode:
		if _player_cam_ref.position.length_squared() > 0.01:
			_player_cam_ref.position = Vector2.ZERO

func refresh_camera_limits() -> void:
	_refresh_camera_limits()

func _configure_player_camera(cam: Camera2D) -> void:
	cam.position_smoothing_enabled = false
	cam.rotation_smoothing_enabled = false
	cam.limit_smoothed = false
	cam.position = Vector2.ZERO
	var z := clampf(float(cam.zoom.x), 0.05, 4.0)
	cam.zoom = Vector2(z, z)
	_refresh_camera_limits()

func _refresh_camera_limits() -> void:
	if _player_cam_ref == null or not is_instance_valid(_player_cam_ref):
		return
	var world_rect := _current_world_rect()
	_player_cam_ref.limit_smoothed = false
	_player_cam_ref.limit_left = int(floor(world_rect.position.x))
	_player_cam_ref.limit_top = int(floor(world_rect.position.y))
	_player_cam_ref.limit_right = int(ceil(world_rect.position.x + world_rect.size.x))
	_player_cam_ref.limit_bottom = int(ceil(world_rect.position.y + world_rect.size.y))

func is_camera_manual_mode_enabled() -> bool:
	return _camera_unlock_mode

func _camera_locked_anchor_world() -> Vector2:
	# Used for spawn anchoring — not for per-frame camera offset anymore.
	if _player_node_ref == null or not is_instance_valid(_player_node_ref):
		return Vector2.ZERO
	var player_pos := _player_node_ref.global_position
	var sum := Vector2.ZERO
	var count := 0
	for u2 in live_squad_units:
		var n3 := u2 as Node2D
		if n3 == null or not is_instance_valid(n3):
			continue
		sum += n3.global_position
		count += 1
	if count <= 0:
		return player_pos
	return player_pos.lerp(sum / float(count), 0.22)

func _clear_selection() -> void:
	for u in _selected_units:
		if is_instance_valid(u) and (u as Node).has_method("set_selected"):
			(u as Node).set_selected(false)
	_selected_units.clear()

func _set_unit_selected(u: Node2D, selected: bool) -> void:
	if u == null or not is_instance_valid(u):
		return
	if (u as Node).has_method("set_selected"):
		(u as Node).set_selected(selected)

func _select_single_unit_at(world_pos: Vector2, additive: bool) -> void:
	_prune_invalid_lists()
	_prune_selected_units()
	var best: Node2D = null
	var best_d2 := INF
	var pick_r2 := 36.0 * 36.0
	for u in live_squad_units:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		var d2 := n2.global_position.distance_squared_to(world_pos)
		if d2 <= pick_r2 and d2 < best_d2:
			best_d2 = d2
			best = n2
	if not additive:
		_clear_selection()
	if best == null:
		return
	if _selected_units.has(best):
		if additive:
			_selected_units.erase(best)
			_set_unit_selected(best, false)
		return
	_selected_units.append(best)
	_set_unit_selected(best, true)

func _select_units_in_screen_rect(a: Vector2, b: Vector2, additive: bool) -> void:
	_prune_invalid_lists()
	_prune_selected_units()
	var canvas_xform: Transform2D = get_viewport().get_canvas_transform()
	var p0 := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var p1 := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var rect := Rect2(p0, p1 - p0)
	if rect.size.length() < DRAG_SELECT_THRESHOLD_PX:
		_select_single_unit_at(_screen_to_world((a + b) * 0.5), additive)
		return
	if not additive:
		_clear_selection()
	for u in live_squad_units:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		var sp: Vector2 = canvas_xform * n2.global_position
		if rect.has_point(sp) and (not _selected_units.has(n2)):
			_selected_units.append(n2)
			_set_unit_selected(n2, true)

func _mouse_world_pos() -> Vector2:
	var vp := get_viewport()
	if vp != null:
		return _screen_to_world(vp.get_mouse_position())
	return get_global_mouse_position()

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return get_global_mouse_position()
	var inv: Transform2D = vp.get_canvas_transform().affine_inverse()
	return inv * screen_pos

func _formation_offsets_for_count(count: int, spacing: float = 42.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if count <= 0:
		return out
	if count == 1:
		out.append(Vector2.ZERO)
		return out
	var cols := int(ceili(sqrt(float(count))))
	var rows := int(ceili(float(count) / float(cols)))
	for i in range(count):
		var col := i % cols
		var row := int(i / cols)
		var x := (float(col) - (float(cols - 1) * 0.5)) * spacing
		var y := (float(row) - (float(rows - 1) * 0.5)) * spacing
		out.append(Vector2(x, y))
	return out

func _issue_move_command(world_pos: Vector2) -> void:
	_prune_selected_units()
	if _selected_units.is_empty():
		return
	var offsets := _formation_offsets_for_count(_selected_units.size(), 42.0)
	for i in range(_selected_units.size()):
		var u := _selected_units[i]
		if not is_instance_valid(u):
			continue
		if (u as Node).has_method("set_manual_move_target"):
			(u as Node).set_manual_move_target(world_pos + offsets[i], 9999.0)
	_focus_target = null
	_focus_until_s = 0.0
	_rally_until_s = 0.0
	_spawn_command_marker(world_pos, Color(0.40, 0.85, 1.0, 0.95), false)

func _pick_enemy_at(world_pos: Vector2, radius: float = 72.0) -> Node2D:
	_prune_invalid_lists()
	var best: Node2D = null
	var best_d2 := INF
	var r2 := radius * radius
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
	return best

func _issue_attack_command(target: Node2D) -> void:
	_prune_selected_units()
	if target == null or not is_instance_valid(target) or _selected_units.is_empty():
		return
	for u in _selected_units:
		if not is_instance_valid(u):
			continue
		if (u as Node).has_method("set_manual_attack_target"):
			(u as Node).set_manual_attack_target(target, 9999.0)
	_focus_target = target
	_focus_until_s = 2.0
	_rally_until_s = 0.0
	_spawn_command_marker(target.global_position, Color(1.0, 0.46, 0.40, 0.98), true)

func _spawn_command_marker(world_pos: Vector2, color: Color, attack: bool) -> void:
	# Lightweight command marker (no noisy shockwave / rally-like SFX).
	var ring := Line2D.new()
	ring.width = 2.0 if attack else 1.6
	ring.default_color = color
	ring.z_index = 500
	ring.position = world_pos
	if attack:
		ring.add_point(Vector2(-12, 0))
		ring.add_point(Vector2(-4, 0))
		ring.add_point(Vector2(4, 0))
		ring.add_point(Vector2(12, 0))
		ring.add_point(Vector2(0, 0))
		ring.add_point(Vector2(0, -12))
		ring.add_point(Vector2(0, -4))
		ring.add_point(Vector2(0, 4))
		ring.add_point(Vector2(0, 12))
	else:
		ring.closed = true
		var r := 11.0
		for i in range(16):
			var a := TAU * float(i) / 16.0
			ring.add_point(Vector2(cos(a), sin(a)) * r)
	add_child(ring)
	var tw := create_tween()
	tw.tween_property(ring, "modulate:a", 0.0, 0.20 if attack else 0.16)
	tw.finished.connect(func():
		if is_instance_valid(ring):
			ring.queue_free()
	)

func is_rts_command_mode_enabled() -> bool:
	return _rts_command_mode_enabled

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

func is_arc_surge_active() -> bool:
	return _arc_surge_until_s > 0.0

func get_arc_surge_damage_mult() -> float:
	return _arc_surge_dmg_mult

func _dominant_squad_class() -> int:
	_prune_invalid_lists()
	if live_squad_units.is_empty():
		return int(CharacterData.Class.WARRIOR)
	var counts := {}
	for u in live_squad_units:
		if not is_instance_valid(u):
			continue
		var cd := (u as Node).get("character_data") as CharacterData
		if cd == null:
			continue
		var c := int(cd.class_type)
		counts[c] = int(counts.get(c, 0)) + 1
	var best_c := int(CharacterData.Class.WARRIOR)
	var best_n := -1
	for k in counts.keys():
		var n := int(counts[k])
		if n > best_n:
			best_n = n
			best_c = int(k)
	return best_c

func _try_class_callout() -> void:
	if get_tree().paused or _game_over or _victory:
		return
	if has_node("RecruitDraftUI") or has_node("PauseMenu"):
		return
	if _callout_cd_s > 0.0:
		return
	_prune_invalid_lists()
	if live_squad_units.is_empty():
		return

	# Baseline tuning: strong feel, modest power, clear cooldown.
	var duration := 4.0
	var cooldown := 18.0
	_callout_until_s = duration
	_callout_cd_s = cooldown
	_callout_class = _dominant_squad_class()

	var player := get_tree().get_first_node_in_group("player") as Node2D
	var origin := player.global_position if player and is_instance_valid(player) else global_position

	match _callout_class:
		CharacterData.Class.GUARDIAN:
			# Aegis: reduce incoming damage for a short window.
			for u in live_squad_units:
				if is_instance_valid(u) and (u as Node).has_method("apply_aegis"):
					(u as Node).apply_aegis(duration, 0.65)
			# Prefer EffectBlocks VFX if available.
			var v := get_node_or_null("/root/VfxSystem")
			var ok := false
			if v and is_instance_valid(v) and v.has_method("play_event"):
				ok = bool(v.play_event("callout.aegis", origin, self, Color(1, 1, 1, 1), 1.0))
			if not ok:
				var sw := VfxShockwave.new()
				sw.setup(origin, Color(0.40, 1.0, 0.65, 1.0), 14.0, 150.0, 4.0, 0.30)
				add_child(sw)
			var s_ev := get_node_or_null("/root/SfxSystem")
			if s_ev and is_instance_valid(s_ev) and s_ev.has_method("play_event"):
				s_ev.play_event("callout.aegis", origin, self)
		CharacterData.Class.ROGUE:
			# Smoke: enemies in radius have reduced hit chance and mild slow.
			var radius := 260.0
			var r2 := radius * radius
			for e in live_enemies:
				if not is_instance_valid(e):
					continue
				var n2 := e as Node2D
				if n2 == null:
					continue
				if n2.global_position.distance_squared_to(origin) <= r2:
					if (n2 as Node).has_method("apply_smoke_blind"):
						(n2 as Node).apply_smoke_blind(0.55, duration)
					if (n2 as Node).has_method("apply_slow"):
						(n2 as Node).apply_slow(0.82, duration)
			var sf := VfxSmokeField.new()
			sf.setup(origin, Color(0.70, 0.78, 0.90, 0.55), radius, duration)
			add_child(sf)
			var s_ev := get_node_or_null("/root/SfxSystem")
			if s_ev and is_instance_valid(s_ev) and s_ev.has_method("play_event"):
				s_ev.play_event("callout.smoke", origin, self)
		CharacterData.Class.MAGE:
			# Arc Surge: temporary extra chain lightning procs (implemented in PassiveSystem via main query).
			_arc_surge_until_s = maxf(_arc_surge_until_s, duration)
			_arc_surge_dmg_mult = 0.22
			# Prefer EffectBlocks VFX if available.
			var v := get_node_or_null("/root/VfxSystem")
			var ok := false
			if v and is_instance_valid(v) and v.has_method("play_event"):
				ok = bool(v.play_event("callout.arc_surge", origin, self, Color(1, 1, 1, 1), 1.0))
			if not ok:
				var hp := VfxHolyPulse.new()
				hp.setup(origin, Color(0.85, 0.45, 1.0, 1.0), 12.0, 120.0, 0.28)
				add_child(hp)
			var s_ev := get_node_or_null("/root/SfxSystem")
			if s_ev and is_instance_valid(s_ev) and s_ev.has_method("play_event"):
				s_ev.play_event("callout.arc_surge", origin, self)
		CharacterData.Class.HEALER:
			# Beacon: heal zone around the player.
			var hb := VfxHealBeacon.new()
			hb.setup(origin, 220.0, duration, 0.06, 1.0)
			add_child(hb)
			var s_ev := get_node_or_null("/root/SfxSystem")
			if s_ev and is_instance_valid(s_ev) and s_ev.has_method("play_event"):
				s_ev.play_event("callout.beacon", origin, self)
		_:
			# Fallback: small rally pulse (still feels like "something happened")
			var sw2 := VfxShockwave.new()
			sw2.setup(origin, Color(0.55, 0.85, 1.0, 1.0), 10.0, 110.0, 3.0, 0.22)
			add_child(sw2)

	# UI confirm
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui("ui.open")

static func _class_name(c: int) -> String:
	match c:
		CharacterData.Class.WARRIOR: return "Warrior"
		CharacterData.Class.MAGE: return "Mage"
		CharacterData.Class.ROGUE: return "Rogue"
		CharacterData.Class.GUARDIAN: return "Guardian"
		CharacterData.Class.HEALER: return "Healer"
		CharacterData.Class.SUMMONER: return "Summoner"
		_: return "Unknown"

func is_overclock_active() -> bool:
	return _overclock_until_s > 0.0 or _overclock_always_on_enabled()

func get_overclock_cd_left() -> float:
	if _overclock_always_on_enabled():
		return 0.0
	return _overclock_cd_s

func get_overclock_rate_mult() -> float:
	# Attack speed multiplier while active - MAKE IT FEEL POWERFUL
	var out := 1.0
	if is_overclock_active():
		var mp := get_node_or_null("/root/MetaProgression")
		var rate_mult := 1.65  # 65% faster attacks - noticeable power spike
		if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
			rate_mult *= float(mp.get_mod("overclock_attack_speed_mult", 1.0))
		out *= rate_mult
	out *= _shrine_attack_speed_mult()
	return out

func get_overclock_move_speed_mult() -> float:
	if not is_overclock_active():
		return 1.0
	var mp := get_node_or_null("/root/MetaProgression")
	var ms_mult := 1.35  # Faster movement during overclock
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		ms_mult *= float(mp.get_mod("overclock_move_speed_mult", 1.0))
	return ms_mult

func get_overclock_damage_mult() -> float:
	var out := 1.0
	if is_overclock_active():
		var mp := get_node_or_null("/root/MetaProgression")
		var dmg_mult := 1.30  # 30% damage boost during overclock
		if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
			dmg_mult *= float(mp.get_mod("overclock_damage_mult", 1.0))
		out *= dmg_mult
	out *= _shrine_damage_mult()
	return out

func get_overclock_focus_bias_mult() -> float:
	if not is_overclock_active():
		return 1.0
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		return clampf(float(mp.get_mod("overclock_focus_bias_mult", 1.0)), 0.15, 1.0)
	return 1.0

func get_overclock_chain_chance() -> float:
	if not is_overclock_active():
		return 0.0
	if _overclock_always_on_enabled():
		return 0.0
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_add"):
		return clampf(float(mp.get_add("overclock_chain_chance_add", 0.0)), 0.0, 0.95)
	return 0.0

func get_overclock_chain_jumps() -> int:
	if not is_overclock_active():
		return 0
	if _overclock_always_on_enabled():
		return 0
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_add"):
		return maxi(0, int(round(float(mp.get_add("overclock_chain_jumps_add", 0.0)))))
	return 0

func get_overclock_chain_damage_mult() -> float:
	if not is_overclock_active():
		return 0.0
	if _overclock_always_on_enabled():
		return 0.0
	var mp := get_node_or_null("/root/MetaProgression")
	var base := 0.24
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		base *= float(mp.get_mod("overclock_chain_damage_mult", 1.0))
	return clampf(base, 0.05, 1.0)

func get_overclock_chain_radius() -> float:
	if not is_overclock_active():
		return 0.0
	if _overclock_always_on_enabled():
		return 0.0
	var mp := get_node_or_null("/root/MetaProgression")
	var base := 170.0
	if mp and is_instance_valid(mp) and mp.has_method("get_add"):
		base += float(mp.get_add("overclock_chain_radius_add", 0.0))
	return clampf(base, 80.0, 520.0)

func _overclock_always_on_enabled() -> bool:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_add"):
		return float(mp.get_add("overclock_always_on_add", 0.0)) >= 1.0
	return false

func _try_overclock() -> void:
	if get_tree().paused or _game_over or _victory:
		return
	if has_node("RecruitDraftUI") or has_node("PauseMenu"):
		return
	if not _overclock_unlocked():
		return
	if _overclock_always_on_enabled():
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

	var duration := 5.5 * dur_mult  # Longer duration = more fun
	var cooldown := 12.0 * cd_mult  # Shorter cooldown = more frequent power spikes
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
	var t0_us := int(Time.get_ticks_usec()) if hitch_probe_enabled else 0
	_perf_spawn_detail = ""
	var spawned := 0
	# During boss phase, stop normal spawns (reads like a proper boss fight).
	if _boss_fight_active and _boss_node != null and is_instance_valid(_boss_node):
		if hitch_probe_enabled:
			_probe_last_spawn_ms = float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
			_probe_last_spawn_count = 0
		return
	var cap := _current_max_enemies()
	if live_enemies.size() >= cap:
		if hitch_probe_enabled:
			_probe_last_spawn_ms = float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
			_probe_last_spawn_count = 0
		return
	var burst := _current_spawn_burst()
	for i in range(burst):
		if live_enemies.size() >= cap:
			break
		# Keep elite pressure gentler early; ramp later.
		var r := _ramp01_curved()
		var elite_chance := lerpf(0.02, 0.14, r)
		elite_chance *= float(_map_mod.get("elite_spawn_mult", 1.0))
		var roll_elite := rng.randf() < elite_chance
		_spawn_enemy(roll_elite, false, false)
		spawned += 1
	if hitch_probe_enabled:
		_probe_last_spawn_ms = float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
		_probe_last_spawn_count = spawned
	if perf_trace_enabled:
		print("SPAWN_TICK_TRACE ms=%.2f spawned=%d enemies=%d cap=%d interval=%.3f templates=%d/%d visuals=%d" % [
			_probe_last_spawn_ms, spawned, live_enemies.size(), _current_max_enemies(), _current_spawn_interval(),
			_enemy_template_pool.size(), _enemy_template_target, _enemy_visual_pool.size()
		])

func _ramp01() -> float:
	var t := _elapsed_minutes()
	var mins_mult := float(_map_mod.get("difficulty_ramp_minutes_mult", 1.0))
	var denom := maxf(0.001, difficulty_ramp_minutes * maxf(0.10, mins_mult))
	return clampf(t / denom, 0.0, 1.0)

func _ramp01_curved() -> float:
	# Ease-in: keep early minutes calmer, then accelerate.
	var r := _ramp01()
	var curve_mult := float(_map_mod.get("ramp_curve_power_mult", 1.0))
	return pow(r, maxf(0.10, ramp_curve_power * maxf(0.10, curve_mult)))

func _current_spawn_interval() -> float:
	# Starts forgiving, ramps toward hectic.
	var a := spawn_interval_start * float(_map_mod.get("spawn_interval_start_mult", 1.0))
	var b := spawn_interval_end * float(_map_mod.get("spawn_interval_end_mult", 1.0))
	var r := _ramp01_curved()
	var base := lerpf(a, b, r)
	# Front-load action so first 2 minutes don't feel empty.
	var early_window := maxf(0.25, float(_map_mod.get("early_spawn_window_minutes", 2.0)))
	var early_mult := float(_map_mod.get("early_spawn_interval_mult", 0.84))
	var early_t := clampf(_elapsed_minutes() / early_window, 0.0, 1.0)
	base *= lerpf(early_mult, 1.0, early_t)
	base *= _shrine_spawn_interval_mult()
	return base * float(_map_mod.get("spawn_interval_mult", 1.0))

func _current_max_enemies() -> int:
	var a := float(max_enemies_start) * float(_map_mod.get("max_enemies_start_mult", 1.0))
	var b := float(max_enemies_end) * float(_map_mod.get("max_enemies_end_mult", 1.0))
	var r := _ramp01_curved()
	var base := int(round(lerpf(a, b, r)))
	var early_add := int(_map_mod.get("early_max_enemies_add", 0))
	if early_add != 0:
		var early_window := maxf(0.25, float(_map_mod.get("early_spawn_window_minutes", 2.0)))
		var early_t := clampf(_elapsed_minutes() / early_window, 0.0, 1.0)
		base += int(round(float(early_add) * (1.0 - early_t)))
	base = int(round(float(base) * _shrine_max_enemies_mult()))
	return maxi(1, int(round(float(base) * float(_map_mod.get("max_enemies_mult", 1.0)))))

func _current_spawn_burst() -> int:
	# Burst spawning only in true late-game.
	var r := _ramp01_curved()
	return 1 if r < 0.84 else 2

func _shrine_spawn_interval_mult() -> float:
	if _shrine_greed_ultra_t > 0.0:
		return 0.72
	if _shrine_greed_t > 0.0:
		return 0.84
	return 1.0

func _shrine_max_enemies_mult() -> float:
	if _shrine_greed_ultra_t > 0.0:
		return 1.45
	if _shrine_greed_t > 0.0:
		return 1.24
	return 1.0

func _shrine_essence_mult() -> float:
	if _shrine_greed_ultra_t > 0.0:
		return 3.2
	if _shrine_greed_t > 0.0:
		return 1.85
	return 1.0

func _shrine_draft_drop_bonus() -> float:
	if _shrine_greed_ultra_t > 0.0:
		return 0.16
	if _shrine_greed_t > 0.0:
		return 0.050
	return 0.0

func _shrine_attack_speed_mult() -> float:
	if _shrine_war_ultra_t > 0.0:
		return 1.55
	if _shrine_war_t > 0.0:
		return 1.22
	return 1.0

func _shrine_damage_mult() -> float:
	if _shrine_war_ultra_t > 0.0:
		return 1.50
	if _shrine_war_t > 0.0:
		return 1.18
	return 1.0

func _spawn_enemy(is_elite: bool, from_rift: bool, is_boss: bool) -> void:
	var t0_us := int(Time.get_ticks_usec()) if hitch_probe_enabled else 0
	if ENEMY_SCENE == null:
		return
	var e := ENEMY_SCENE.instantiate()

	var center := _camera_locked_anchor_world()
	if center == Vector2.ZERO:
		var player := get_player_node()
		if player and is_instance_valid(player):
			center = player.global_position

	var t_template0_us := int(Time.get_ticks_usec()) if hitch_probe_enabled else 0
	var cd: CharacterData = null
	if not _enemy_template_pool.is_empty():
		cd = _enemy_template_pool.pop_back().duplicate(true) as CharacterData
	if cd == null:
		var south_fallback := _pick_enemy_visual_path()
		if south_fallback == "":
			return
		cd = UnitFactory.build_character_data("enemy", rng, _elapsed_minutes(), south_fallback, _map_mod)
	if cd == null:
		return
	var south := String(cd.sprite_path)
	var template_ms := float(int(Time.get_ticks_usec()) - t_template0_us) / 1000.0 if hitch_probe_enabled else 0.0
	_refill_enemy_templates()
	if is_elite:
		cd.max_hp = int(round(float(cd.max_hp) * 1.55))
		cd.attack_damage = int(round(float(cd.attack_damage) * 1.25))

	# Boss tuning: heavy HP + meaningful damage, both map-driven.
	if is_boss:
		var bhp := float(_map_mod.get("boss_hp_mult", 10.0))
		var bdmg := float(_map_mod.get("boss_damage_mult", 1.5))
		cd.max_hp = int(round(float(cd.max_hp) * maxf(1.0, bhp)))
		cd.attack_damage = int(round(float(cd.attack_damage) * maxf(1.0, bdmg)))

	# Enemy archetype + affixes (behavior variety)
	var t_ai0_us := int(Time.get_ticks_usec()) if hitch_probe_enabled else 0
	var ai_id := EnemyFactory.roll_enemy_ai_id(rng, _elapsed_minutes())
	var affixes := PackedStringArray()
	if is_elite:
		affixes = EnemyFactory.roll_elite_affixes(rng, _elapsed_minutes(), 2)
	# Bosses lean toward spectacle.
	if is_boss:
		ai_id = "charger"
		var want := int(_map_mod.get("boss_affix_count", 2))
		affixes = EnemyFactory.roll_elite_affixes(rng, _elapsed_minutes(), maxi(0, want))
		if affixes.is_empty():
			affixes = PackedStringArray(["arcane", "volatile"])
	var ai_ms := float(int(Time.get_ticks_usec()) - t_ai0_us) / 1000.0 if hitch_probe_enabled else 0.0

	# IMPORTANT: set exported fields BEFORE add_child so Enemy._ready() sees them.
	var t_scene0_us := int(Time.get_ticks_usec()) if hitch_probe_enabled else 0
	e.set_meta("rift", from_rift)
	e.set_meta("boss", is_boss)
	e.character_data = cd
	e.is_elite = is_elite
	e.pixellab_south_path = south
	e.ai_id = ai_id
	e.affix_ids = affixes
	add_child(e)
	var scene_ms := float(int(Time.get_ticks_usec()) - t_scene0_us) / 1000.0 if hitch_probe_enabled else 0.0
	var t_pos0_us := int(Time.get_ticks_usec()) if hitch_probe_enabled else 0
	if _authored_map_world != null and is_instance_valid(_authored_map_world) and _authored_map_world.has_method("get_random_spawn_around"):
		e.global_position = _authored_map_world.get_random_spawn_around(center, spawn_radius_min, spawn_radius_max, rng)
	else:
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(spawn_radius_min, spawn_radius_max)
		e.global_position = center + Vector2(cos(ang), sin(ang)) * dist
	var pos_ms := float(int(Time.get_ticks_usec()) - t_pos0_us) / 1000.0 if hitch_probe_enabled else 0.0
	# SFX: elite spawns read as events (throttled).
	if is_elite and (not is_boss):
		var s := get_node_or_null("/root/SfxSystem")
		if s and is_instance_valid(s) and s.has_method("play_event"):
			s.play_event("enemy.elite_spawn", e.global_position, e)
		var v := get_node_or_null("/root/VfxSystem")
		if v and is_instance_valid(v) and v.has_method("play_event"):
			v.play_event("enemy.elite_spawn", e.global_position, self)
	if hitch_probe_enabled:
		var total_ms := float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
		_perf_spawn_detail = "spawn_total=%.2fms template=%.2f ai=%.2f scene=%.2f pos=%.2f pool=%d/%d visuals=%d elite=%s boss=%s" % [
			total_ms, template_ms, ai_ms, scene_ms, pos_ms, _enemy_template_pool.size(), _enemy_template_target, _enemy_visual_pool.size(),
			("1" if is_elite else "0"), ("1" if is_boss else "0")
		]
		if perf_trace_enabled and total_ms >= perf_trace_spawn_threshold_ms:
			print("SPAWN_TRACE %s" % _perf_spawn_detail)

func _build_enemy_visual_pool() -> void:
	var t0_us := int(Time.get_ticks_usec())
	_enemy_visual_pool = PackedStringArray()
	_enemy_visual_bag.clear()
	_enemy_visual_ready = PackedStringArray()
	_enemy_visual_warmed.clear()
	var all_paths := CharacterRegistryUtil.get_sprite_paths_for_context("enemy", _map_mod)
	# Default to full eligible map pool so race variety is preserved.
	# Optional cap is still supported for performance testing.
	var cap := int(_map_mod.get("enemy_visual_pool_cap", 0))
	if cap > 0 and all_paths.size() > cap:
		var tmp: Array[String] = []
		for p in all_paths:
			tmp.append(String(p))
		tmp.shuffle()
		for i in range(cap):
			_enemy_visual_pool.append(tmp[i])
	else:
		_enemy_visual_pool = all_paths
	if _enemy_visual_pool.is_empty():
		# Fallback for edge cases if registry/pool is empty.
		var want := mini(maxi(1, enemy_visual_pool_size), 8)
		var seen: Dictionary = {}
		var tries := 0
		while _enemy_visual_pool.size() < want and tries < want * 50:
			tries += 1
			var cd := CharacterRegistryUtil.build_random_character_data("enemy", rng, _elapsed_minutes(), _map_mod)
			if cd == null:
				continue
			var p2 := String(cd.sprite_path)
			if p2 == "":
				continue
			if seen.has(p2):
				continue
			seen[p2] = true
			_enemy_visual_pool.append(p2)
	if perf_trace_enabled:
		var ms := float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
		print("SPAWN_VISUAL_POOL_TRACE size=%d ms=%.2f map=%s" % [_enemy_visual_pool.size(), ms, String(_map_mod.get("id", "unknown"))])

func _refill_enemy_visual_bag() -> void:
	_enemy_visual_bag.clear()
	for p in _enemy_visual_pool:
		_enemy_visual_bag.append(String(p))
	_enemy_visual_bag.shuffle()

func _build_enemy_visual_pool_deferred() -> void:
	# Let gameplay become interactive before optional visual cache priming.
	await get_tree().process_frame
	await get_tree().process_frame
	_build_enemy_visual_pool()
	_warm_enemy_visuals_startup()

func _warm_enemy_visuals_startup() -> void:
	if _enemy_visual_pool.is_empty():
		return
	var target := mini(_enemy_visual_pool.size(), _enemy_startup_warm_count())
	if target <= 0:
		target = mini(_enemy_visual_pool.size(), 1)
	# Block only for a small starter set so the window never goes "not responding";
	# the rest streams in one visual per frame below.
	var sync_target := mini(target, 6)
	var warmed := 0
	for p in _enemy_visual_pool:
		if _enemy_visual_ready.size() >= sync_target:
			break
		var path := String(p)
		if bool(_enemy_visual_warmed.get(path, false)):
			continue
		PixellabUtil.walk_frames_from_south_path(path)
		_enemy_visual_warmed[path] = true
		_enemy_visual_ready.append(path)
		warmed += 1
	if perf_trace_enabled and warmed > 0:
		print("SPAWN_VISUAL_STARTUP_WARM warmed=%d ready=%d/%d target=%d map=%s" % [
			warmed, _enemy_visual_ready.size(), _enemy_visual_pool.size(), target, String(_map_mod.get("id", "unknown"))
		])
	if _enemy_visual_ready.size() < target:
		_warm_enemy_visuals_streamed(target)

func _warm_enemy_visuals_streamed(target: int) -> void:
	# One visual per frame keeps the main thread responsive while the pool fills.
	var warmed := 0
	while _enemy_visual_ready.size() < target:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		var next_path := ""
		for p in _enemy_visual_pool:
			var path := String(p)
			if not bool(_enemy_visual_warmed.get(path, false)):
				next_path = path
				break
		if next_path == "":
			break
		PixellabUtil.walk_frames_from_south_path(next_path)
		_enemy_visual_warmed[next_path] = true
		_enemy_visual_ready.append(next_path)
		warmed += 1
	if perf_trace_enabled and warmed > 0:
		print("SPAWN_VISUAL_STREAM_WARM warmed=%d ready=%d/%d map=%s" % [
			warmed, _enemy_visual_ready.size(), _enemy_visual_pool.size(), String(_map_mod.get("id", "unknown"))
		])

func _warm_enemy_visuals_incremental() -> void:
	if _enemy_visual_pool.is_empty():
		return
	if _enemy_visual_ready.size() >= mini(_enemy_visual_pool.size(), maxi(1, _enemy_visual_ready_target)):
		return
	var t0_us := int(Time.get_ticks_usec())
	var warmed := 0
	for p in _enemy_visual_pool:
		var path := String(p)
		if bool(_enemy_visual_warmed.get(path, false)):
			continue
		PixellabUtil.walk_frames_from_south_path(path)
		_enemy_visual_warmed[path] = true
		_enemy_visual_ready.append(path)
		warmed += 1
		var spent_ms := float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
		if spent_ms >= _enemy_template_refill_budget_ms:
			break
	if perf_trace_enabled and warmed > 0:
		var spent_ms2 := float(int(Time.get_ticks_usec()) - t0_us) / 1000.0
		if spent_ms2 >= perf_trace_spawn_threshold_ms:
			print("SPAWN_VISUAL_WARM_TRACE warmed=%d ready=%d/%d ms=%.2f" % [warmed, _enemy_visual_ready.size(), _enemy_visual_pool.size(), spent_ms2])

func _pick_enemy_visual_path() -> String:
	if not _enemy_visual_ready.is_empty():
		return String(_enemy_visual_ready[rng.randi_range(0, _enemy_visual_ready.size() - 1)])
	if _enemy_visual_pool.is_empty():
		# Emergency fallback still stays on curated CharacterRegistry (Ludo set), not PixelLab.
		var cd := CharacterRegistryUtil.build_random_character_data("enemy", rng, _elapsed_minutes(), _map_mod)
		if cd != null:
			var p := String(cd.sprite_path)
			if p != "":
				return p
		return ""
	# Avoid introducing new un-warmed visuals during active gameplay.
	return ""

func get_player_node() -> Node2D:
	if _player_node_ref != null and is_instance_valid(_player_node_ref):
		return _player_node_ref
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null and is_instance_valid(p):
		_player_node_ref = p
		return p
	return null

func get_player_presence_mult() -> float:
	return clampf(float(_map_mod.get("player_presence_mult", 1.16)), 0.70, 2.20)

func get_enemy_presence_mult() -> float:
	return clampf(float(_map_mod.get("enemy_presence_mult", 1.18)), 0.70, 2.20)

func _spawn_boss() -> void:
	_boss_spawned = true
	_boss_fight_active = true
	var profile := "default"
	var wave := _boss_wave_index
	if _multi_boss_schedule_enabled:
		profile = "siegebreaker" if wave == 0 else "storm_oracle"
	# Deadline for the boss fight (map-tunable). If 0 or missing, no deadline.
	var limit_m := float(_map_mod.get("boss_time_limit_minutes", 0.0))
	if limit_m > 0.05:
		var now_s := float(Time.get_ticks_msec()) / 1000.0
		_boss_deadline_s = now_s + limit_m * 60.0
	else:
		_boss_deadline_s = -1.0
	_spawn_boss_profile(profile)
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
	# VFX: boss spawn (if exported)
	var v := get_node_or_null("/root/VfxSystem")
	if v and is_instance_valid(v) and v.has_method("play_event"):
		var pos2 := Vector2.ZERO
		if _boss_node != null and is_instance_valid(_boss_node):
			pos2 = (_boss_node as Node2D).global_position
		v.play_event("boss.spawn", pos2, self)
	if toast_layer != null:
		var title := "Boss: Siegebreaker Vanguard" if profile == "siegebreaker" else ("Boss: Storm Oracle" if profile == "storm_oracle" else "Boss has spawned")
		toast_layer.show_toast(title, Color(1.0, 0.72, 0.42, 1.0))
	if _multi_boss_schedule_enabled:
		_boss_wave_index += 1

func _spawn_boss_profile(profile: String) -> void:
	# Use existing enemy/boss spawn path, then mutate profile-specific behavior.
	_spawn_enemy(true, false, true)
	if live_enemies.is_empty():
		return
	var b := live_enemies[live_enemies.size() - 1]
	if b == null or not is_instance_valid(b):
		return
	_boss_node = b
	b.set_meta("boss_profile", profile)
	b.set_meta("boss_spawn_elapsed", _elapsed_minutes())
	b.set_meta("boss_skill_cd", 2.0)
	b.set_meta("boss_summon_cd", 6.0)
	b.set_meta("boss_enraged", false)
	if profile == "siegebreaker":
		b.set_meta("boss_name", "Siegebreaker Vanguard")
		b.ai_id = "charger"
		b.affix_ids = PackedStringArray(["volatile", "vampiric"])
		if "contact_damage" in b:
			b.contact_damage = int(round(float(b.contact_damage) * 1.15))
	elif profile == "storm_oracle":
		b.set_meta("boss_name", "Storm Oracle")
		b.ai_id = "spitter"
		b.affix_ids = PackedStringArray(["arcane", "vampiric"])
		if "contact_damage" in b:
			b.contact_damage = int(round(float(b.contact_damage) * 1.25))
	else:
		b.set_meta("boss_name", "Archfiend")
		b.ai_id = "charger"
		b.affix_ids = PackedStringArray(["arcane", "volatile"])
	# Re-apply behavior modifiers when we override profile after spawn.
	if b.has_method("_apply_archetype_and_affixes"):
		b._apply_archetype_and_affixes()
	if b.has_method("_apply_visuals"):
		b._apply_visuals()

func _tick_boss_mechanics(delta: float) -> void:
	if not _boss_fight_active:
		return
	if _boss_node == null or not is_instance_valid(_boss_node):
		return
	var profile := String(_boss_node.get_meta("boss_profile", "default"))
	var hp_ratio := 1.0
	if _boss_node.has_method("get_hp_ratio"):
		hp_ratio = float(_boss_node.get_hp_ratio())
	if (not bool(_boss_node.get_meta("boss_enraged", false))) and hp_ratio <= 0.5:
		_boss_node.set_meta("boss_enraged", true)
		if "contact_damage" in _boss_node:
			_boss_node.contact_damage = int(round(float(_boss_node.contact_damage) * 1.2))
		if toast_layer != null:
			toast_layer.show_toast("Boss enrages!", Color(1.0, 0.45, 0.32, 1.0))

	var skill_cd := maxf(0.0, float(_boss_node.get_meta("boss_skill_cd", 0.0)) - delta)
	var summon_cd := maxf(0.0, float(_boss_node.get_meta("boss_summon_cd", 0.0)) - delta)
	_boss_node.set_meta("boss_skill_cd", skill_cd)
	_boss_node.set_meta("boss_summon_cd", summon_cd)

	if profile == "siegebreaker":
		if skill_cd <= 0.0:
			_do_siegebreaker_slam(_boss_node)
			_boss_node.set_meta("boss_skill_cd", 8.0 if hp_ratio > 0.5 else 5.8)
		if summon_cd <= 0.0:
			_spawn_boss_minions(_boss_node, "bomber", 2)
			_boss_node.set_meta("boss_summon_cd", 16.0 if hp_ratio > 0.5 else 11.0)
	elif profile == "storm_oracle":
		if skill_cd <= 0.0:
			_do_storm_oracle_barrage(_boss_node)
			_boss_node.set_meta("boss_skill_cd", 7.0 if hp_ratio > 0.5 else 4.6)
		if summon_cd <= 0.0:
			_spawn_boss_minions(_boss_node, "spitter", 2)
			_boss_node.set_meta("boss_summon_cd", 15.0 if hp_ratio > 0.5 else 10.0)
	if _boss_test_mode:
		var spawn_elapsed := float(_boss_node.get_meta("boss_spawn_elapsed", _elapsed_minutes()))
		if (_elapsed_minutes() - spawn_elapsed) >= 0.75 and _boss_node.has_method("take_damage"):
			_boss_node.take_damage(9999999, false, "test")

func _do_siegebreaker_slam(boss: Node2D) -> void:
	var pos := boss.global_position
	var sw := VfxShockwave.new()
	sw.setup(pos, Color(1.0, 0.55, 0.22, 1.0), 18.0, 220.0, 7.0, 0.30)
	add_child(sw)
	var ss := get_node_or_null("/root/ScreenShake")
	if ss and is_instance_valid(ss) and ss.has_method("shake"):
		ss.shake(9.0, 0.16)
	var s := get_node_or_null("/root/SfxSystem")
	if s and s.is_inside_tree() and s.has_method("play_event"):
		s.play_event("weapon.slam", pos, boss)
	var radius := 220.0
	var r2 := radius * radius
	var dmg := maxi(8, int(round(float(boss.contact_damage) * 1.45)))
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and is_instance_valid(player) and player.global_position.distance_squared_to(pos) <= r2 and player.has_method("take_damage"):
		player.take_damage(dmg, false, "blast")
	_prune_invalid_lists()
	for u in live_squad_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.global_position.distance_squared_to(pos) > r2:
			continue
		if u.has_method("take_damage"):
			u.take_damage(dmg, false, "blast")

func _do_storm_oracle_barrage(boss: Node2D) -> void:
	_prune_invalid_lists()
	var targets: Array[Node2D] = []
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and is_instance_valid(player):
		targets.append(player)
	for u in live_squad_units:
		if u != null and is_instance_valid(u):
			targets.append(u)
	if targets.is_empty():
		return
	targets.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_squared_to(boss.global_position) < b.global_position.distance_squared_to(boss.global_position)
	)
	var s := get_node_or_null("/root/SfxSystem")
	var v := get_node_or_null("/root/VfxSystem")
	var strikes := mini(3, targets.size())
	var dmg := maxi(7, int(round(float(boss.contact_damage) * 1.15)))
	for i in range(strikes):
		var t := targets[i]
		if t == null or not is_instance_valid(t):
			continue
		if t.has_method("take_damage"):
			t.take_damage(dmg, false, "arc")
		if VFX_ARC_SCENE != null:
			var arc := VFX_ARC_SCENE.instantiate()
			add_child(arc)
			if arc.has_method("setup"):
				arc.setup(boss.global_position, t.global_position, Color(0.55, 0.88, 1.0, 0.95))
		if v and is_instance_valid(v) and v.has_method("play_event"):
			v.play_event("syn.arc", t.global_position, self, Color(0.55, 0.88, 1.0, 1.0), 1.0)
		if s and is_instance_valid(s) and s.has_method("play_event"):
			s.play_event("enemy.arcane", t.global_position, boss)

func _spawn_boss_minions(boss: Node2D, ai_id: String, count: int) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	var center := boss.global_position
	if p != null and is_instance_valid(p):
		center = p.global_position
	for _i in range(maxi(1, count)):
		if live_enemies.size() >= _current_max_enemies():
			break
		_spawn_enemy(true, false, false)
		if live_enemies.is_empty():
			continue
		var n := live_enemies[live_enemies.size() - 1]
		if n == null or not is_instance_valid(n) or n == boss:
			continue
		n.ai_id = ai_id
		if n.has_method("_apply_archetype_and_affixes"):
			n._apply_archetype_and_affixes()
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(110.0, 180.0)
		n.global_position = center + Vector2(cos(ang), sin(ang)) * dist

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

func on_squad_unit_died(u: Node2D) -> void:
	# Called by SquadUnit right before it queue_free()s.
	# Remove explicitly so "last unit died" is detectable immediately.
	var idx := live_squad_units.find(u)
	if idx >= 0:
		live_squad_units.remove_at(idx)
	# Run fails if you lose your whole squad.
	if (not _boss_test_mode) and (not _game_over) and (not _victory) and live_squad_units.is_empty():
		_show_game_over()

func _prune_invalid_lists() -> void:
	for i in range(live_enemies.size() - 1, -1, -1):
		if not is_instance_valid(live_enemies[i]):
			live_enemies.remove_at(i)
	for j in range(live_squad_units.size() - 1, -1, -1):
		if not is_instance_valid(live_squad_units[j]):
			live_squad_units.remove_at(j)

func get_cached_enemies() -> Array[Node2D]:
	return live_enemies

func get_cached_squad_units() -> Array[Node2D]:
	return live_squad_units

func on_enemy_killed(is_elite: bool, cd: CharacterData, from_rift: bool, was_boss: bool) -> void:
	if _game_over or _victory:
		return

	# RNG draft drops (no capture bar)
	_roll_draft_drop(is_elite, was_boss)

	# Micro feedback: shake on kills (bigger on elites/bosses) - FEELS IMPACTFUL
	var ss := get_node_or_null("/root/ScreenShake")
	if ss and is_instance_valid(ss) and ss.has_method("shake"):
		var inten := 2.5  # Base shake on every kill
		if is_elite:
			inten = 7.0  # Elites feel like an accomplishment
		if was_boss:
			inten = 14.0  # Boss kills are HUGE
		ss.shake(inten, 0.12)

	# Global synergy triggers (on-kill effects like Undying heal)
	SynergySystem.on_enemy_killed(self, is_elite, was_boss)

	# Run stats
	_run_kills += 1
	if is_elite:
		_run_elite_kills += 1

	# Protocol keystone hooks: momentum chain and overclock kill-extension.
	var mp_chain := get_node_or_null("/root/MetaProgression")
	if mp_chain and is_instance_valid(mp_chain) and mp_chain.has_method("get_add"):
		var chain_window := maxf(0.0, float(mp_chain.get_add("kill_chain_window_add", 0.0)))
		if chain_window > 0.0:
			var max_stacks := 1 + maxi(0, int(round(float(mp_chain.get_add("kill_chain_max_stacks_add", 0.0)))))
			if _meta_kill_chain_t > 0.0:
				_meta_kill_chain_stacks = mini(max_stacks, _meta_kill_chain_stacks + 1)
			else:
				_meta_kill_chain_stacks = 1
			_meta_kill_chain_t = chain_window
		var oc_extend := maxf(0.0, float(mp_chain.get_add("overclock_extend_on_kill_add", 0.0)))
		if oc_extend > 0.0 and _overclock_until_s > 0.0 and (not _overclock_always_on_enabled()):
			_overclock_until_s = minf(18.0, _overclock_until_s + oc_extend)

	# Essence economy for rerolls - generous rewards feel good!
	var base := 2 if not is_elite else 5  # More essence per kill
	if was_boss:
		base = 15  # Boss kills are very rewarding
	var mult := float(_map_mod.get("essence_mult", 1.0))
	# Meta progression essence bonus
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		mult *= float(mp.get_mod("essence_mult", 1.0))
	mult *= _shrine_essence_mult()
	essence += maxi(1, int(round(float(base) * mult)))
	_apply_meta_on_kill_heal()

	# Trophy pool: store recent killed character variants for unlocks
	if cd != null:
		_recent_trophy_pool.append(cd)
		if _recent_trophy_pool.size() > 18:
			_recent_trophy_pool.pop_front()

	# Boss victory
	if enable_bosses and was_boss:
		_boss_fight_active = false
		_boss_node = null
		_boss_deadline_s = -1.0
		_boss_kills += 1
		if _multi_boss_schedule_enabled:
			if _boss_wave_index >= _boss_wave_times.size():
				_show_victory()
			else:
				if toast_layer != null:
					var next_m := float(_boss_wave_times[_boss_wave_index])
					toast_layer.show_toast("Boss defeated. Next threat at %d:%02d." % [int(next_m), int(round(fmod(next_m * 60.0, 60.0)))], Color(0.72, 0.92, 1.0, 1.0))
		else:
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

func _apply_meta_on_kill_heal() -> void:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp) or (not mp.has_method("get_add")):
		return
	var heal_amt := int(round(float(mp.get_add("on_kill_heal_add", 0.0))))
	if heal_amt <= 0:
		return
	for u in live_squad_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.has_method("heal"):
			u.heal(heal_amt)

func try_absorb_damage_with_essence(amount: int, origin: Vector2 = Vector2.ZERO) -> int:
	if amount <= 0:
		return 0
	var absorbed := mini(amount, essence)
	if absorbed <= 0:
		return 0
	essence -= absorbed
	_proc_essence_guard_reflect(origin, absorbed)
	return absorbed

func get_meta_kill_chain_attack_speed_mult() -> float:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp) or (not mp.has_method("get_add")):
		return 1.0
	var per_stack := maxf(0.0, float(mp.get_add("kill_chain_haste_per_stack_add", 0.0)))
	if per_stack <= 0.0 or _meta_kill_chain_stacks <= 0:
		return 1.0
	return clampf(1.0 + float(_meta_kill_chain_stacks) * per_stack, 1.0, 2.4)

func proc_execute_blast(origin: Vector2, source_damage: int) -> void:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp) or (not mp.has_method("get_add")):
		return
	var radius := maxf(0.0, float(mp.get_add("execute_blast_radius_add", 0.0)))
	if radius <= 0.0:
		return
	var mult := 0.0
	if mp.has_method("get_mod"):
		mult = maxf(0.0, float(mp.get_mod("execute_blast_damage_mult", 0.0)))
	if mult <= 0.0:
		return
	var blast_dmg := maxi(1, int(round(float(maxi(1, source_damage)) * mult)))
	# Safety cap: keep execute blast impactful but not wave-deleting.
	blast_dmg = mini(blast_dmg, 260)
	var mark_add := maxf(0.0, float(mp.get_add("execute_blast_mark_threshold_add", 0.0)))
	var max_targets := 10
	var hit_count := 0
	var r2 := radius * radius
	for e in live_enemies:
		if e == null or not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2 and n2.has_method("take_damage"):
			var dist := n2.global_position.distance_to(origin)
			var t := clampf(dist / maxf(1.0, radius), 0.0, 1.0)
			var falloff := lerpf(1.0, 0.35, t)
			var dealt := maxi(1, int(round(float(blast_dmg) * falloff)))
			n2.take_damage(dealt, false, "execute_blast")
			if mark_add > 0.0 and n2.has_method("apply_execute_vulnerability"):
				n2.apply_execute_vulnerability(mark_add, 3.0)
			hit_count += 1
			if hit_count >= max_targets:
				break
	var sw := VfxShockwave.new()
	sw.setup(origin, Color(1.0, 0.45, 0.35, 1.0), 12.0, radius * 0.46, 4.5, 0.20)
	add_child(sw)

func _proc_essence_guard_reflect(origin: Vector2, absorbed: int) -> void:
	if absorbed <= 0:
		return
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp) or (not mp.has_method("get_add")):
		return
	var ratio := clampf(float(mp.get_add("essence_guard_reflect_ratio_add", 0.0)), 0.0, 2.0)
	if ratio <= 0.0:
		return
	var radius := 170.0 + maxf(0.0, float(mp.get_add("essence_guard_reflect_radius_add", 0.0)))
	var pos := origin
	if pos == Vector2.ZERO:
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p and is_instance_valid(p):
			pos = p.global_position
	var dmg := maxi(1, int(round(float(absorbed) * ratio)))
	# Guardrail: this proc is defensive utility, not a full nuke.
	dmg = mini(dmg, 180)
	var max_targets := 8
	var hit_count := 0
	var r2 := radius * radius
	for e in live_enemies:
		if e == null or not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(pos) <= r2 and n2.has_method("take_damage"):
			var dist := n2.global_position.distance_to(pos)
			var t := clampf(dist / maxf(1.0, radius), 0.0, 1.0)
			var falloff := lerpf(1.0, 0.40, t)
			var dealt := maxi(1, int(round(float(dmg) * falloff)))
			n2.take_damage(dealt, false, "essence_guard")
			hit_count += 1
			if hit_count >= max_targets:
				break

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
	var chance := clampf(base + _draft_pity + map_bonus + _shrine_draft_drop_bonus(), 0.0, 0.85)

	if rng.randf() < chance:
		_last_draft_time_s = now_s
		_draft_pity = 0.0
		var s := get_node_or_null("/root/SfxSystem")
		if s and s.has_method("play_ui"):
			s.play_ui("ui.drop")
		_on_draft_ready()
	else:
		_draft_pity = minf(draft_drop_pity_cap, _draft_pity + draft_drop_pity_add_per_kill)

func _map_tier() -> int:
	return maxi(1, int(_map_mod.get("tier", 1)))

func _show_recruit_draft() -> void:
	_RecruitDraftUI.present(self)

func _show_swap_prompt(cd: CharacterData, ui: CanvasLayer = null) -> void:
	var draft: CanvasLayer = ui
	if draft == null:
		draft = get_node_or_null("RecruitDraftUI") as CanvasLayer
	if draft != null and draft.has_method("show_swap_prompt"):
		draft.show_swap_prompt(cd)

func _setup_hud() -> void:
	_RunHudUI.attach(self)

func _update_hud_labels() -> void:
	var hud := get_node_or_null("HUD")
	if hud != null and hud.has_method("refresh"):
		hud.refresh()

func _sync_passive_overlay_hotkey() -> void:
	var hud := get_node_or_null("HUD")
	if hud != null and hud.has_method("sync_passive_overlay_hotkey"):
		hud.sync_passive_overlay_hotkey()

func _show_passive_overlay() -> void:
	var hud := get_node_or_null("HUD")
	if hud != null and hud.has_method("show_passive_overlay"):
		hud.show_passive_overlay()

func _hide_passive_overlay() -> void:
	var hud := get_node_or_null("HUD")
	if hud != null and hud.has_method("hide_passive_overlay"):
		hud.hide_passive_overlay()

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

func _tick_end_of_run_timer() -> void:
	if _victory or _game_over:
		return
	var now_m := _elapsed_minutes()
	if _multi_boss_schedule_enabled:
		# Multi-boss mode: victory is granted on final boss kill, not by surviving the timer.
		if _boss_wave_index >= _boss_wave_times.size() and (not _boss_fight_active) and _boss_kills >= _boss_wave_times.size():
			_show_victory()
		# Fail-safe for very long stalled runs.
		if now_m >= maxf(run_timer_max_minutes, float(_boss_wave_times[_boss_wave_times.size() - 1]) + 5.0) and (not _victory):
			_show_game_over()
		return
	if enable_bosses:
		# Boss-at-end: reaching the timer triggers the boss; victory requires killing it.
		if (not _boss_spawned) and now_m >= run_timer_max_minutes:
			_spawn_boss()
		# Boss time limit: fail if you can't kill it in time.
		if _boss_fight_active and _boss_deadline_s > 0.0:
			var now_s := float(Time.get_ticks_msec()) / 1000.0
			if now_s >= _boss_deadline_s:
				_show_game_over()
	else:
		# Survival mode
		if now_m >= run_timer_max_minutes:
			_show_victory()

func _apply_map_pacing_overrides() -> void:
	var map_id := String(_map_mod.get("id", ""))
	# Church is the onboarding map: faster rewards, cleaner first minutes, less downtime.
	if map_id == "church":
		draft_drop_chance_normal = maxf(draft_drop_chance_normal, 0.012)
		draft_drop_chance_elite = maxf(draft_drop_chance_elite, 0.085)
		draft_drop_pity_add_per_kill = maxf(draft_drop_pity_add_per_kill, 0.0014)
		draft_drop_pity_cap = maxf(draft_drop_pity_cap, 0.05)
		draft_drop_min_seconds_between = minf(draft_drop_min_seconds_between, 52.0)
		reroll_cost_essence = mini(reroll_cost_essence, 2)
		spawn_interval_start = minf(spawn_interval_start, 1.40)
		spawn_interval_end = minf(spawn_interval_end, 0.62)
		max_enemies_start = maxi(max_enemies_start, 26)
		max_enemies_end = maxi(max_enemies_end, 138)
		# Keep pressure arcs visible on church without overwhelming beginners.
		_objective_events = PackedFloat32Array([1.8, 4.5, 7.0, 10.0, 13.0, 16.0])
	else:
		_objective_events = PackedFloat32Array([2.5, 6.0, 10.0, 14.0])
	_objective_event_index = 0

func _tick_objective_events() -> void:
	if _game_over or _victory:
		return
	if _boss_fight_active:
		return
	if _objective_event_index >= _objective_events.size():
		return
	var now_m := _elapsed_minutes()
	if now_m < float(_objective_events[_objective_event_index]):
		return
	var stage := _objective_event_index + 1
	_objective_event_index += 1
	var map_id := String(_map_mod.get("id", ""))
	# Milestone reward: a little certainty in a highly random loop.
	var reward_essence := 5 + stage * 2
	if map_id == "church":
		reward_essence = 7 + stage * 3
	essence += reward_essence
	_draft_pity = minf(draft_drop_pity_cap, _draft_pity + (0.016 if map_id == "church" else 0.012))
	if toast_layer != null:
		toast_layer.show_toast("Milestone %d: +%d Essence. Enemy surge incoming!" % [stage, reward_essence], Color(1.0, 0.90, 0.45, 1.0))
	# Controlled intensity spike to create memorable beats.
	var extra_elites := 1 + int(stage / 2)
	if map_id == "church":
		extra_elites += 1
	for _i in range(extra_elites):
		if live_enemies.size() >= _current_max_enemies():
			break
		_spawn_enemy(true, false, false)
	if map_id == "church":
		var extra_normals := mini(10, 2 + stage)
		for _j in range(extra_normals):
			if live_enemies.size() >= _current_max_enemies():
				break
			_spawn_enemy(false, false, false)
	# Every other milestone gives a deterministic choice moment.
	var now_s := float(Time.get_ticks_msec()) / 1000.0
	var should_offer_draft := (stage % 2 == 0)
	if map_id == "church" and stage >= 5:
		should_offer_draft = true
	if should_offer_draft and not has_node("RecruitDraftUI") and (now_s - _last_draft_time_s) >= 30.0:
		_last_draft_time_s = now_s
		_draft_pity = 0.0
		_on_draft_ready()

func _sync_objective_event_index_from_elapsed() -> void:
	var now_m := _elapsed_minutes()
	_objective_event_index = 0
	while _objective_event_index < _objective_events.size() and now_m >= float(_objective_events[_objective_event_index]):
		_objective_event_index += 1

func _sync_boss_wave_index_from_elapsed() -> void:
	if not _multi_boss_schedule_enabled:
		return
	var now_m := _elapsed_minutes()
	_boss_wave_index = 0
	while _boss_wave_index < _boss_wave_times.size() and now_m >= float(_boss_wave_times[_boss_wave_index]):
		_boss_wave_index += 1

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
	_sync_objective_event_index_from_elapsed()
	_sync_boss_wave_index_from_elapsed()

func _build_end_screen(ui: CanvasLayer, title_text: String, victory: bool) -> void:
	# CRITICAL: Allow UI to work while paused
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var accent := Color(0.4, 0.85, 1.0, 1.0) if victory else Color(1.0, 0.35, 0.35, 1.0)
	var accent_dim := Color(0.3, 0.65, 0.85, 0.7) if victory else Color(0.85, 0.3, 0.3, 0.6)
	
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.88)
	bg.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.add_child(bg)
	var bgmat := ShaderMaterial.new()
	bgmat.shader = preload("res://shaders/ui_arcane_scifi_backdrop.gdshader")
	bg.material = bgmat

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -400
	card.offset_right = 400
	card.offset_top = -300
	card.offset_bottom = 300
	card.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.add_child(card)

	card.add_theme_stylebox_override("panel", UiSkin.glowing_panel_style(accent))

	var neon := ShaderMaterial.new()
	neon.shader = preload("res://shaders/ui_neon_frame.gdshader")
	neon.set_shader_parameter("base_color", Color(0.05, 0.06, 0.09, 0.98))
	neon.set_shader_parameter("glow_color", accent * 0.65)
	neon.set_shader_parameter("glow_width", 0.025)
	neon.set_shader_parameter("pulse_speed", 0.8 if victory else 1.5)
	card.material = neon

	# Entrance: dim fades, card lands with weight (the run just ended — sell it).
	bg.modulate.a = 0.0
	var bg_tw := bg.create_tween()
	bg_tw.tween_property(bg, "modulate:a", 1.0, UiSkin.DUR_MED)
	card.pivot_offset = Vector2(400, 300)
	card.scale = Vector2(0.90, 0.90)
	card.modulate.a = 0.0
	var card_tw := card.create_tween()
	card_tw.set_parallel(true)
	card_tw.tween_property(card, "modulate:a", 1.0, UiSkin.DUR_MED)
	card_tw.tween_property(card, "scale", Vector2.ONE, UiSkin.DUR_SLOW) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 32)
	pad.add_theme_constant_override("margin_right", 32)
	pad.add_theme_constant_override("margin_top", 28)
	pad.add_theme_constant_override("margin_bottom", 28)
	card.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	pad.add_child(v)

	# Header icon
	var icon_lbl := Label.new()
	icon_lbl.text = "⚔" if victory else "☠"
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 52)
	icon_lbl.add_theme_color_override("font_color", accent)
	v.add_child(icon_lbl)

	# Title
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46 if victory else 42)
	title.add_theme_color_override("font_color", accent)
	v.add_child(title)

	# Divider
	var div1 := HSeparator.new()
	div1.add_theme_constant_override("separation", 12)
	div1.add_theme_stylebox_override("separator", _make_divider_style(accent_dim))
	v.add_child(div1)

	var mp := get_node_or_null("/root/MetaProgression")
	var lr: Dictionary = {}
	if mp and is_instance_valid(mp) and "last_run" in mp:
		lr = mp.last_run as Dictionary

	# Stats grid
	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 40)
	stats_grid.add_theme_constant_override("v_separation", 8)
	v.add_child(stats_grid)
	
	var map_name := String(lr.get("map_name", "Unknown"))
	var minutes := int(lr.get("minutes", 0))
	var kills := int(lr.get("kills", 0))
	var elite_kills := int(lr.get("elite_kills", 0))
	var drafts := int(lr.get("drafts", 0))
	var sigils_earned := int(lr.get("sigils_earned", 0))
	var total_sigils := int(mp.sigils) if mp != null and "sigils" in mp else 0
	
	_add_stat_row(stats_grid, "⚑ Map", map_name, Color(0.85, 0.90, 0.96))
	_add_stat_row(stats_grid, "⏱ Time", "%dm %ds" % [minutes, int(lr.get("seconds", 0)) % 60], Color(0.85, 0.90, 0.96))
	_add_stat_row(stats_grid, "💀 Kills", "%d" % kills, Color(0.95, 0.75, 0.6))
	_add_stat_row(stats_grid, "⭐ Elites", "%d" % elite_kills, Color(1.0, 0.85, 0.4))
	_add_stat_row(stats_grid, "📜 Drafts", "%d" % drafts, Color(0.7, 0.85, 1.0))
	_add_stat_row(stats_grid, "✧ Sigils", "+%d" % sigils_earned, Color(0.6, 1.0, 0.7))

	# Divider
	var div2 := HSeparator.new()
	div2.add_theme_constant_override("separation", 12)
	div2.add_theme_stylebox_override("separator", _make_divider_style(accent_dim))
	v.add_child(div2)

	# Total sigils display
	var sigil_row := HBoxContainer.new()
	sigil_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(sigil_row)
	var sigil_icon := Label.new()
	sigil_icon.text = "✧"
	sigil_icon.add_theme_font_size_override("font_size", 28)
	sigil_icon.add_theme_color_override("font_color", Color(0.6, 1.0, 0.75))
	sigil_row.add_child(sigil_icon)
	var sigil_total := Label.new()
	sigil_total.text = "  Total Sigils: %d" % total_sigils
	sigil_total.add_theme_font_size_override("font_size", 20)
	sigil_total.add_theme_color_override("font_color", Color(0.75, 0.92, 0.8))
	sigil_row.add_child(sigil_total)

	# Progress to next slot
	if mp and is_instance_valid(mp) and mp.has_method("get_next_slot_cost") and mp.has_method("get_squad_slots"):
		var cost := int(mp.get_next_slot_cost())
		if cost > 0:
			var prog_box := VBoxContainer.new()
			prog_box.add_theme_constant_override("separation", 6)
			v.add_child(prog_box)
			
			var prog_lbl := Label.new()
			prog_lbl.text = "Squad Slot Progress: %d → %d" % [int(mp.get_squad_slots()), int(mp.get_squad_slots()) + 1]
			prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			prog_lbl.add_theme_font_size_override("font_size", 14)
			prog_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
			prog_box.add_child(prog_lbl)
			
			var bar := ProgressBar.new()
			bar.min_value = 0
			bar.max_value = cost
			bar.value = clampi(total_sigils, 0, cost)
			bar.custom_minimum_size = Vector2(0, 22)
			bar.show_percentage = false
			UiSkin.style_progress_bar(bar)
			prog_box.add_child(bar)
			
			var bar_pct := Label.new()
			bar_pct.text = "%d / %d sigils" % [total_sigils, cost]
			bar_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bar_pct.add_theme_font_size_override("font_size", 13)
			bar_pct.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
			prog_box.add_child(bar_pct)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	v.add_child(spacer)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 20)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btn_row)
	
	var btn := Button.new()
	btn.text = "  Return to Menu  "
	btn.custom_minimum_size = Vector2(260, 52)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.add_theme_font_size_override("font_size", 18)
	UiSkin.style_primary_button(btn, accent)
	btn.pressed.connect(_return_to_menu_from_end_screen)
	btn_row.add_child(btn)

func _return_to_menu_from_end_screen() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func _add_stat_row(grid: GridContainer, label_text: String, value_text: String, value_color: Color) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	grid.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 16)
	val.add_theme_color_override("font_color", value_color)
	grid.add_child(val)

func _make_divider_style(color: Color) -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = color * 0.5
	line.thickness = 1
	line.grow_begin = 20
	line.grow_end = 20
	return line

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
	var tier := maxi(1, int(_map_mod.get("tier", 1)))
	var tier_scale := maxi(0, tier - 1)
	var bonus := 0
	if victory:
		bonus += 220 + tier_scale * 70
	var difficulty_flat := tier_scale * 45
	var elite_bonus := _run_elite_kills * tier_scale * 4
	# Map multiplier (harder maps => faster meta progress)
	var mult := float(_map_mod.get("meta_sigils_mult", 1.0))
	var total := int(round(float(base + bonus + difficulty_flat + elite_bonus) * mult))
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

	# Progression gate: unlock next map on victory.
	if victory and mp != null and is_instance_valid(mp) and mp.has_method("unlock_map"):
		var rc2 := get_node_or_null("/root/RunConfig")
		if rc2 != null and is_instance_valid(rc2) and rc2.has_method("get_map_ids_ordered"):
			var ordered: Array[String] = rc2.get_map_ids_ordered()
			var cur := String(rc2.get("selected_map_id"))
			var idx := ordered.find(cur)
			if idx >= 0 and idx + 1 < ordered.size():
				mp.unlock_map(ordered[idx + 1])
