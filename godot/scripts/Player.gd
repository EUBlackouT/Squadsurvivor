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

var formation_offsets: Array[Vector2] = [
	Vector2(-40, -30),
	Vector2(40, -30),
	Vector2(-40, 30),
	Vector2(40, 30),
	Vector2(0, -60),
	Vector2(0, 60)
]

func _ready() -> void:
	if cam:
		cam.make_current()
	add_to_group("player")

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
		var util := PixellabUtil._singleton(get_tree())
		for i in range(3):
			var south := util.pick_random_south_path(rng)
			var cd := UnitFactory.build_character_data("recruit", rng, 0.0, south)
			roster.append(cd)
			# Also unlock and add to roster
			var cm2 := get_node_or_null("/root/CollectionManager")
			if cm2 and is_instance_valid(cm2):
				if cm2.has_method("unlock_character"):
					cm2.unlock_character(cd)
				if cm2.has_method("add_to_roster"):
					cm2.add_to_roster(cd)

	for i in range(min(squad_size, formation_offsets.size(), roster.size())):
		var cd2 := roster[i]
		_spawn_squad_unit(cd2, formation_offsets[i])

func add_squad_unit(character_data: CharacterData) -> void:
	if squad_units.size() >= 6:
		return
	var idx := squad_units.size()
	var offset := formation_offsets[idx] if idx < formation_offsets.size() else Vector2.ZERO
	_spawn_squad_unit(character_data, offset)

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
	var dir := Vector2.ZERO
	dir.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	dir.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	if dir.length() > 1.0:
		dir = dir.normalized()
	velocity = dir * move_speed
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


