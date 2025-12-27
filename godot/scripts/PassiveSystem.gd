class_name PassiveSystem
extends Node

# Data-driven passive system with lightweight VFX hooks.

static var _loaded: bool = false
static var _passives: Dictionary = {} # id -> Dictionary

const VFX_ARC_SCENE: PackedScene = preload("res://scenes/VfxArcLightning.tscn")
const VFX_SLASH_SCENE: PackedScene = preload("res://scenes/VfxSlash.tscn")

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path := "res://data/passives.json"
	if not ResourceLoader.exists(path):
		push_warning("PassiveSystem: missing %s" % path)
		return
	var json_text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	var arr: Array = d.get("passives", [])
	for p in arr:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = p
		var id := String(pd.get("id", ""))
		if id != "":
			_passives[id] = pd

static func passive_name(id: String) -> String:
	ensure_loaded()
	return String((_passives.get(id, {}) as Dictionary).get("name", id))

static func passive_description(id: String) -> String:
	ensure_loaded()
	return String((_passives.get(id, {}) as Dictionary).get("description", ""))

static func passive_tags(id: String) -> PackedStringArray:
	ensure_loaded()
	var arr: Array = (_passives.get(id, {}) as Dictionary).get("tags", [])
	var out := PackedStringArray()
	for t in arr:
		out.append(String(t))
	return out

static func extra_pierce_count(passive_ids: PackedStringArray) -> int:
	# Only one passive currently affects pierce.
	var extra: int = 0
	for id in passive_ids:
		if id == "piercing_rounds":
			extra += 1
	return extra

static func on_unit_attack(cd: CharacterData, unit: Node2D, target: Node2D, damage: int, is_crit: bool, is_melee: bool) -> void:
	if cd == null:
		return
	ensure_loaded()
	var ids := cd.passive_ids
	for pid in ids:
		match String(pid):
			"arc_chain":
				_arc_chain(unit, target, damage)
			"frost_tag":
				_frost_tag(target)
			"bleed_edge":
				if is_melee:
					_bleed_edge(target, damage)
			"echo_strike":
				_echo_strike(unit, target, damage, is_crit)
			_:
				pass

static func on_projectile_hit(passive_ids: PackedStringArray, _proj: Node2D, enemy: Node2D, damage: int, _is_crit: bool) -> void:
	if passive_ids.is_empty():
		return
	ensure_loaded()
	for pid in passive_ids:
		match String(pid):
			"arc_chain":
				_arc_chain(_proj, enemy, damage)
			"frost_tag":
				_frost_tag(enemy)
			_:
				pass

static func _main_world(from: Node) -> Node2D:
	if from == null:
		return null
	var main := from.get_tree().get_first_node_in_group("main") as Node2D
	return main

static func _arc_chain(unit: Node2D, target: Node2D, damage: int) -> void:
	var world := _main_world(unit)
	if world == null or target == null or not is_instance_valid(target):
		return
	var enemies: Array = []
	if world.has_method("get_cached_enemies"):
		enemies = world.get_cached_enemies()
	else:
		enemies = world.get_tree().get_nodes_in_group("enemies")

	var origin := (target as Node2D).global_position
	var radius := 220.0
	var r2 := radius * radius
	var candidates: Array[Node2D] = []
	for e_node in enemies:
		if not is_instance_valid(e_node):
			continue
		var n2 := e_node as Node2D
		if n2 == null or n2 == target:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			candidates.append(n2)
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin)
	)
	var hits: int = int(min(2, candidates.size()))
	if hits <= 0:
		return
	var arc_dmg := int(round(float(damage) * 0.35))
	for i in range(hits):
		var n := candidates[i]
		if n != null and is_instance_valid(n):
			if n.has_method("take_damage"):
				n.take_damage(arc_dmg, false, "arc")
			_spawn_arc(world, origin, n.global_position, Color(0.55, 0.95, 1.0, 0.95))

static func _frost_tag(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("apply_slow"):
		target.apply_slow(0.75, 1.5)
	_spawn_status_vfx(target, Color(0.55, 0.85, 1.0, 0.55))

static func _bleed_edge(target: Node2D, damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("apply_bleed"):
		var dps := float(damage) * 0.15
		target.apply_bleed(dps, 3.0, 0.5)
	_spawn_status_vfx(target, Color(1.0, 0.25, 0.35, 0.55))

static func _echo_strike(unit: Node2D, target: Node2D, damage: int, _is_crit: bool) -> void:
	if unit == null or target == null:
		return
	# Use node metadata to avoid adding fields to SquadUnit.
	var c: int = int(unit.get_meta("_echo_ctr", 0))
	c += 1
	unit.set_meta("_echo_ctr", c)
	if c % 3 != 0:
		return
	if target.has_method("take_damage"):
		target.take_damage(int(round(float(damage) * 0.5)), false, "echo")
	var world := _main_world(unit)
	if world != null:
		_spawn_echo_slash(world, (target as Node2D).global_position, Color(1.0, 0.85, 0.30, 0.9))

static func _spawn_arc(world: Node2D, a: Vector2, b: Vector2, color: Color) -> void:
	if VFX_ARC_SCENE == null:
		return
	var v := VFX_ARC_SCENE.instantiate()
	world.add_child(v)
	if v.has_method("setup"):
		v.setup(a, b, color)

static func _spawn_echo_slash(world: Node2D, pos: Vector2, color: Color) -> void:
	if VFX_SLASH_SCENE == null:
		return
	var v := VFX_SLASH_SCENE.instantiate()
	world.add_child(v)
	if v.has_method("setup"):
		v.setup(pos, Vector2(1, 0), color)

static func _spawn_status_vfx(target: Node2D, color: Color) -> void:
	# Minimal: tiny pulse ring as a slash reused, but with low alpha.
	var world := _main_world(target)
	if world == null:
		return
	if VFX_SLASH_SCENE == null:
		return
	var v := VFX_SLASH_SCENE.instantiate()
	world.add_child(v)
	if v.has_method("setup"):
		v.setup(target.global_position, Vector2(0, -1), color)


