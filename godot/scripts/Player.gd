extends CharacterBody2D

@export var move_speed: float = 520.0  # Fast, responsive direct-control speed
@export var squad_size: int = 3
@export var gameplay_camera_zoom: Vector2 = Vector2(0.78, 0.78)
@export var zoom_min: float = 0.42
@export var zoom_max: float = 2.20
@export var zoom_step: float = 0.10
@export var manual_camera_pan_speed: float = 760.0

@onready var cam: Camera2D = get_node_or_null("Camera2D")

const SQUAD_UNIT_SCENE: PackedScene = preload("res://scenes/SquadUnit.tscn")

var squad_units: Array[Node2D] = []

enum FormationMode { TIGHT, SPREAD, WEDGE, RING }
enum TargetMode { NEAREST, LOWEST_HP, ELITES_FIRST }
const TARGET_MODE_COUNT: int = 3

var _formation_mode: int = FormationMode.TIGHT
var _target_mode: int = TargetMode.NEAREST

# Active ability: dash (Shift)
var _dash_cd: float = 0.0
var _dash_t: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _dash_speed_mult: float = 1.0
var _dash_key_prev_down: bool = false
var _main: Node2D = null

func get_dash_cd_left() -> float:
	return _dash_cd

func is_dashing() -> bool:
	return _dash_t > 0.0

func get_dash_dir() -> Vector2:
	return _dash_dir

var formation_offsets: Array[Vector2] = [
	Vector2(-40, -30),
	Vector2(40, -30),
	Vector2(-40, 30),
	Vector2(40, 30),
	Vector2(0, -60),
	Vector2(0, 60),
	Vector2(-72, 0),
	Vector2(72, 0)
]

func _ready() -> void:
	if cam:
		cam.make_current()
		var z := clampf(gameplay_camera_zoom.x, zoom_min, zoom_max)
		cam.zoom = Vector2(z, z)
	add_to_group("player")
	_main = get_tree().get_first_node_in_group("main") as Node2D

	# Meta progression overrides squad size.
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_squad_slots"):
		squad_size = int(mp.get_squad_slots())

	# Player physics layer: 4, collide with enemies layer 2
	collision_layer = 1 << 3
	collision_mask = (1 << 1) | (1 << 0)
	_apply_player_visual_identity()

	_spawn_initial_squad()

func _unhandled_input(event: InputEvent) -> void:
	if cam == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_camera_zoom(cam.zoom.x - zoom_step)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_camera_zoom(cam.zoom.x + zoom_step)

func _set_camera_zoom(v: float) -> void:
	if cam == null:
		return
	var z := clampf(v, zoom_min, zoom_max)
	cam.zoom = Vector2(z, z)

func _apply_player_visual_identity() -> void:
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		spr.scale = Vector2(0.22, 0.22)
		spr.modulate = Color(0.25, 1.0, 0.45, 1.0)
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/pixel_outline.gdshader")
		mat.set_shader_parameter("outline_color", Color(0.20, 1.0, 0.40, 0.98))
		mat.set_shader_parameter("outline_px", 1.5)
		spr.material = mat

func _spawn_initial_squad() -> void:
	await get_tree().process_frame

	var roster: Array[CharacterData] = []
	var cm := get_node_or_null("/root/CollectionManager")
	if cm and is_instance_valid(cm) and cm.has_method("get_active_roster_character_data"):
		roster = cm.get_active_roster_character_data()

	# If roster empty, generate a starter team and auto-add to roster for convenience.
	if roster.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(Time.get_ticks_usec())
		var map_mod: Dictionary = {}
		var rc := get_node_or_null("/root/RunConfig")
		if rc and is_instance_valid(rc) and rc.has_method("get_selected_map"):
			map_mod = rc.get_selected_map()
		for i in range(3):
			var cd := CharacterRegistryUtil.build_random_character_data("recruit", rng, 0.0, map_mod)
			if cd == null:
				continue
			roster.append(cd)
			# Also unlock and add to roster
			var cm2 := get_node_or_null("/root/CollectionManager")
			if cm2 and is_instance_valid(cm2):
				if cm2.has_method("unlock_character"):
					cm2.unlock_character(cd)
				if cm2.has_method("add_to_roster"):
					cm2.add_to_roster(cd)

	# Update synergy snapshot from roster.
	SynergySystem.set_roster(roster)

	for i in range(min(squad_size, formation_offsets.size(), roster.size())):
		var cd2 := roster[i]
		_spawn_squad_unit(cd2, formation_offsets[i])

func add_squad_unit(character_data: CharacterData) -> void:
	var cap := 6
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_squad_slots"):
		cap = int(mp.get_squad_slots())
	if squad_units.size() >= cap:
		return
	var idx := squad_units.size()
	var offset := formation_offsets[idx] if idx < formation_offsets.size() else Vector2.ZERO
	_spawn_squad_unit(character_data, offset)
	_refresh_synergies()

func _refresh_synergies() -> void:
	var cds: Array = []
	for u in squad_units:
		if not is_instance_valid(u):
			continue
		var cd := (u as Node).get("character_data") as CharacterData
		if cd != null:
			cds.append(cd)
	SynergySystem.set_roster(cds)

func _spawn_squad_unit(cd: CharacterData, offset: Vector2) -> void:
	if SQUAD_UNIT_SCENE == null:
		return
	
	# Failsafe: if weapon is still standard_bolt, assign a random one
	if cd.weapon_id == "standard_bolt" or cd.weapon_id == "":
		WeaponSystem.ensure_loaded()
		var all_weapons: Array = WeaponSystem.all_weapon_ids()
		if not all_weapons.is_empty():
			# Filter out standard_bolt so we get interesting weapons
			var interesting: Array = []
			for w in all_weapons:
				if w != "standard_bolt":
					interesting.append(w)
			if interesting.is_empty():
				interesting = all_weapons
			cd.weapon_id = interesting[randi() % interesting.size()]
			# Update attack style based on weapon
			var tags := WeaponSystem.weapon_tags(cd.weapon_id)
			if tags.has("melee"):
				cd.attack_style = CharacterData.AttackStyle.MELEE
				cd.attack_range = 80.0
			else:
				cd.attack_style = CharacterData.AttackStyle.RANGED
				cd.attack_range = 350.0
	
	var unit := SQUAD_UNIT_SCENE.instantiate()
	unit.character_data = cd
	var parent := get_parent()
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(unit)
	unit.global_position = global_position + offset
	if unit.has_method("set_squad_leader"):
		unit.set_squad_leader(self, offset)
	if unit.has_method("set_formation_mode"):
		unit.set_formation_mode(_formation_mode)
	if unit.has_method("set_target_mode"):
		unit.set_target_mode(_target_mode)
	squad_units.append(unit)

func _physics_process(_delta: float) -> void:
	var delta := _delta
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_dash_t = maxf(0.0, _dash_t - delta)

	# Keep squad list clean (units can die)
	for i in range(squad_units.size() - 1, -1, -1):
		if not is_instance_valid(squad_units[i]):
			squad_units.remove_at(i)

	var manual_cam_mode := false
	if _main and is_instance_valid(_main) and _main.has_method("is_camera_manual_mode_enabled"):
		manual_cam_mode = bool(_main.is_camera_manual_mode_enabled())
	if manual_cam_mode:
		_pan_camera_manual(delta)
		velocity = Vector2.ZERO
		return

	var dir := Vector2.ZERO
	dir.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	dir.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	if dir.length() > 1.0:
		dir = dir.normalized()
	var dash_key_down := Input.is_key_pressed(KEY_SHIFT)
	if dash_key_down and (not _dash_key_prev_down):
		_try_dash(dir)
	_dash_key_prev_down = dash_key_down
	# Dash movement - feels punchy and fast
	if _dash_t > 0.0:
		velocity = _dash_dir * (move_speed * 5.5 * _dash_speed_mult)
		move_and_slide()
	else:
		var spd := move_speed
		if _main and is_instance_valid(_main) and _main.has_method("get_overclock_move_speed_mult"):
			spd *= float(_main.get_overclock_move_speed_mult())
		velocity = dir * spd
		move_and_slide()

	# Formation hotkeys
	if Input.is_action_just_pressed("ui_1"):
		_set_formation_mode(FormationMode.TIGHT)
	elif Input.is_action_just_pressed("ui_2"):
		_set_formation_mode(FormationMode.SPREAD)
	elif Input.is_action_just_pressed("ui_3"):
		_set_formation_mode(FormationMode.WEDGE)
	elif Input.is_action_just_pressed("ui_4"):
		_set_formation_mode(FormationMode.RING)

	# Targeting hotkey
	if Input.is_action_just_pressed("ui_t"):
		_set_target_mode((_target_mode + 1) % TARGET_MODE_COUNT)

func _pan_camera_manual(delta: float) -> void:
	if cam == null:
		return
	var pan := Vector2.ZERO
	pan.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	pan.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	if pan.length() > 1.0:
		pan = pan.normalized()
	cam.position += pan * manual_camera_pan_speed * delta

# Dash ability removed - was causing issues
func _try_dash(input_dir: Vector2) -> void:
	if _dash_t > 0.0 or _dash_cd > 0.0:
		return
	var dir := input_dir
	if dir.length() <= 0.01:
		dir = velocity.normalized()
	if dir.length() <= 0.01:
		return
	var cd_mult := 1.0
	var dist_mult := 1.0
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_mod"):
		cd_mult = float(mp.get_mod("dash_cooldown_mult", 1.0))
		dist_mult = float(mp.get_mod("dash_distance_mult", 1.0))
	cd_mult = clampf(cd_mult, 0.35, 2.5)
	dist_mult = clampf(dist_mult, 0.70, 1.80)
	_dash_dir = dir.normalized()
	_dash_speed_mult = dist_mult
	_dash_t = 0.17 * dist_mult
	_dash_cd = 2.4 * cd_mult

func _set_formation_mode(mode: int) -> void:
	_formation_mode = mode
	for u in squad_units:
		if is_instance_valid(u) and u.has_method("set_formation_mode"):
			u.set_formation_mode(mode)
	var main := get_tree().get_first_node_in_group("main")
	if main and is_instance_valid(main) and main.has_method("_update_hud_labels"):
		main._update_hud_labels()

func _set_target_mode(mode: int) -> void:
	_target_mode = mode
	for u in squad_units:
		if is_instance_valid(u) and u.has_method("set_target_mode"):
			u.set_target_mode(mode)
	var main := get_tree().get_first_node_in_group("main")
	if main and is_instance_valid(main) and main.has_method("_update_hud_labels"):
		main._update_hud_labels()

func on_squad_unit_died(unit: Node2D) -> void:
	# Called by SquadUnit right before it queue_free()s
	var idx := squad_units.find(unit)
	if idx >= 0:
		squad_units.remove_at(idx)
	_refresh_synergies()
