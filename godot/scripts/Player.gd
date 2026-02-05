extends CharacterBody2D

@export var move_speed: float = 265.0  # Snappier base movement
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
			var cd := CharacterRegistryUtil.build_random_character_data("recruit", rng, 0.0)
			if cd == null:
				var south := PixellabUtil.pick_random_south_path(rng)
				cd = UnitFactory.build_character_data("recruit", rng, 0.0, south)
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

	var dir := Vector2.ZERO
	dir.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	dir.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	if dir.length() > 1.0:
		dir = dir.normalized()
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

# Dash ability removed - was causing issues

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
