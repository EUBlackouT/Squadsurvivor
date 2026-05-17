extends SceneTree

class EnemyStub extends Node2D:
	var hp: int = 1000
	var hits: int = 0
	func _init(p: Vector2) -> void:
		global_position = p
	func take_damage(amount: int, _is_crit: bool = false, _source: String = "") -> void:
		hits += 1
		hp = maxi(0, hp - maxi(0, amount))
	func get_hp_ratio() -> float:
		return float(hp) / 1000.0

class MainStub extends Node2D:
	var enemies: Array[Node2D] = []
	func get_cached_enemies() -> Array[Node2D]:
		return enemies

func _init() -> void:
	var mp: Node = root.get_node_or_null("MetaProgression")
	if mp == null:
		var meta_script := load("res://scripts/MetaProgression.gd")
		mp = meta_script.new() as Node
		root.add_child(mp)
		mp.name = "MetaProgression"
	if mp == null or not is_instance_valid(mp):
		push_error("PROTOCOL_COMPARE missing MetaProgression")
		quit(1)
		return

	var tree: Dictionary = mp.tree_data() if mp.has_method("tree_data") else {}
	var nodes: Array = tree.get("nodes", []) as Array
	var node_by_id: Dictionary = {}
	for n in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var d := n as Dictionary
		var id := String(d.get("id", ""))
		if id != "":
			node_by_id[id] = d

	var baseline := _run_profile(mp, node_by_id, [])
	var god_targets: Array[String] = [
		"storm_closed_circuit",
		"fire_ash_economy",
		"frost_stillness_tax",
		"poison_terminal_dose",
		"proj_converging_fire",
		"scatter_shotgun_saint",
		"rico_violence_geometry",
		"pierce_execution_line",
		"bomb_delayed_catastrophe",
		"beam_surgical_continuity",
		"orbital_judgment_delay",
		"hybrid_needle_storm",
		"hybrid_cinder_banking",
		"hybrid_cryo_lance",
		"execution_net",
		"feedback_loop"
	]
	var god := _run_profile(mp, node_by_id, god_targets)

	print("PROTOCOL_COMPARE baseline owned=%d proj_add=%.1f chain_add=%.1f cluster_add=%.1f chain_rehit_hits=%d projectile_spawned=%d bomb_spawned=%d" % [
		int(baseline.get("owned", 0)),
		float(baseline.get("proj_count_add", 0.0)),
		float(baseline.get("chain_jumps_add", 0.0)),
		float(baseline.get("bomb_cluster_add", 0.0)),
		int(baseline.get("chain_hits_total", 0)),
		int(baseline.get("projectiles_spawned", 0)),
		int(baseline.get("bombs_spawned", 0))
	])
	print("PROTOCOL_COMPARE god owned=%d proj_add=%.1f chain_add=%.1f cluster_add=%.1f chain_rehit_hits=%d projectile_spawned=%d bomb_spawned=%d" % [
		int(god.get("owned", 0)),
		float(god.get("proj_count_add", 0.0)),
		float(god.get("chain_jumps_add", 0.0)),
		float(god.get("bomb_cluster_add", 0.0)),
		int(god.get("chain_hits_total", 0)),
		int(god.get("projectiles_spawned", 0)),
		int(god.get("bombs_spawned", 0))
	])
	print("PROTOCOL_COMPARE_DELTA chain_hits=%d projectile_spawned=%d bomb_spawned=%d" % [
		int(god.get("chain_hits_total", 0)) - int(baseline.get("chain_hits_total", 0)),
		int(god.get("projectiles_spawned", 0)) - int(baseline.get("projectiles_spawned", 0)),
		int(god.get("bombs_spawned", 0)) - int(baseline.get("bombs_spawned", 0))
	])
	quit()

func _run_profile(mp: Node, node_by_id: Dictionary, targets: Array[String]) -> Dictionary:
	var owned := _resolve_nodes(targets, node_by_id)
	mp.set("meta_nodes_owned", owned)
	mp.set("sigils", 999999999)
	mp.set("_mods_dirty", true)

	var main_stub := MainStub.new()
	root.add_child(main_stub)
	var attacker := Node2D.new()
	attacker.global_position = Vector2.ZERO
	main_stub.add_child(attacker)
	var e1 := EnemyStub.new(Vector2(140, 0))
	var e2 := EnemyStub.new(Vector2(185, 30))
	var target := EnemyStub.new(Vector2(240, 0))
	main_stub.add_child(e1)
	main_stub.add_child(e2)
	main_stub.add_child(target)
	main_stub.enemies = [e1, e2, target]

	WeaponSystem._fire_chain_lightning(attacker, e1, 90, false, main_stub, null, {"chain_count": 2, "chain_damage_decay": 0.80, "chain_range": 220.0})
	var before_proj := main_stub.get_child_count()
	WeaponSystem._fire_standard_projectile(attacker, target, 70, false, main_stub, null)
	var after_proj := main_stub.get_child_count()
	var before_bomb := main_stub.get_child_count()
	WeaponSystem._fire_bomb(attacker, target, 120, false, main_stub, null, {"explosion_radius": 80.0, "projectile_speed": 380.0, "burn_duration": 0.0, "burn_dps_mult": 0.0})
	var after_bomb := main_stub.get_child_count()

	var out := {
		"owned": owned.size(),
		"proj_count_add": WeaponSystem._get_mp_add(main_stub, "projectile_count_add", 0.0),
		"chain_jumps_add": WeaponSystem._get_mp_add(main_stub, "chain_jumps_add", 0.0),
		"bomb_cluster_add": WeaponSystem._get_mp_add(main_stub, "bomb_cluster_count_add", 0.0),
		"chain_hits_total": e1.hits + e2.hits,
		"projectiles_spawned": maxi(0, after_proj - before_proj),
		"bombs_spawned": maxi(0, after_bomb - before_bomb)
	}
	main_stub.queue_free()
	return out

func _resolve_nodes(targets: Array[String], node_by_id: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(["core_0"])
	if targets.is_empty():
		return out
	var stack: Array[String] = targets.duplicate()
	while not stack.is_empty():
		var id := String(stack.pop_back())
		if id == "" or out.has(id):
			continue
		out.append(id)
		var n := node_by_id.get(id, {}) as Dictionary
		var prereq := n.get("prereq", []) as Array
		for p in prereq:
			var pid := String(p)
			if pid != "" and not out.has(pid):
				stack.append(pid)
	return out
