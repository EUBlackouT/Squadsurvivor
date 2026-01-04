extends CharacterBody2D

@export var move_speed: float = 240.0
@export var squad_size: int = 3

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
	add_to_group("player")
	_main = get_tree().get_first_node_in_group("main") as Node2D

	# Meta progression overrides squad size.
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_squad_slots"):
		squad_size = int(mp.get_squad_slots())

	# Player physics layer: 4, collide with enemies layer 2
	collision_layer = 1 << 3
	collision_mask = 1 << 1

	_spawn_initial_squad()

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
		for i in range(3):
			var south := PixellabUtil.pick_random_south_path(rng)
			var cd := UnitFactory.build_character_data("recruit", rng, 0.0, south)
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

	var dir := Vector2.ZERO
	dir.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	dir.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	if dir.length() > 1.0:
		dir = dir.normalized()
	# Dash movement
	if _dash_t > 0.0:
		velocity = _dash_dir * (move_speed * 4.2 * _dash_speed_mult)
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

func _unhandled_input(event: InputEvent) -> void:
	# Active ability: Dash (Shift). Keep it snappy; uses input direction, or mouse direction if standing still.
	if get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_SHIFT and _dash_cd <= 0.0 and _dash_t <= 0.0:
			var dir := Vector2.ZERO
			dir.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
			dir.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
			if dir.length() <= 0.05:
				dir = (get_global_mouse_position() - global_position)
			if dir.length() <= 0.05:
				return
			_dash_dir = dir.normalized()
			_dash_t = 0.14
			var mp := get_node_or_null("/root/MetaProgression")
			var cd_mult := 1.0
			var dist_mult := 1.0
			if mp and is_instance_valid(mp):
				if mp.has_method("get_mod"):
					cd_mult = float(mp.get_mod("dash_cooldown_mult", 1.0))
					dist_mult = float(mp.get_mod("dash_distance_mult", 1.0))
			_dash_speed_mult = dist_mult
			_dash_cd = 1.25 * cd_mult
			# Pull squad with you: issue a short rally toward the dash endpoint.
			var main2 := get_tree().get_first_node_in_group("main") as Node2D
			if main2 and is_instance_valid(main2) and main2.has_method("_set_rally"):
				var dash_dist := move_speed * 4.2 * _dash_t * dist_mult
				main2._set_rally(global_position + _dash_dir * dash_dist, 0.35)
			# Feedback
			var main := get_tree().get_first_node_in_group("main") as Node2D
			if main:
				var sw := VfxShockwave.new()
				sw.setup(global_position, Color(0.45, 0.90, 1.0, 1.0), 10.0, 70.0, 3.0, 0.18)
				main.add_child(sw)
			var s := get_node_or_null("/root/SfxSystem")
			if s and is_instance_valid(s) and s.has_method("play_ui"):
				s.play_ui("ui.click")

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
