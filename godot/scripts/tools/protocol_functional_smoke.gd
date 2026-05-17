extends SceneTree

class EnemyStub extends Node2D:
	var hp: int = 1000
	var hits: int = 0
	var total_damage: int = 0
	func _init(p: Vector2) -> void:
		global_position = p
	func take_damage(amount: int, _is_crit: bool = false, _source: String = "") -> void:
		hits += 1
		total_damage += maxi(0, amount)
		hp = maxi(0, hp - maxi(0, amount))
	func get_hp_ratio() -> float:
		return float(hp) / 1000.0

class MainStub extends Node2D:
	var enemies: Array[Node2D] = []
	func get_cached_enemies() -> Array[Node2D]:
		return enemies

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var mode := _arg_value(OS.get_cmdline_user_args(), "protocol_profile", "god")
	var mp: Node = root.get_node_or_null("MetaProgression")
	if mp == null:
		var meta_script := load("res://scripts/MetaProgression.gd")
		mp = meta_script.new() as Node
		root.add_child(mp)
		mp.name = "MetaProgression"
	await process_frame
	print("PROTOCOL_FUNC_SMOKE mp_path=%s has_root_meta=%s" % [str(mp.get_path()), str(root.get_node_or_null("MetaProgression") != null)])

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

	# "Infinite essence/sigils" internal profile setup.
	mp.set("sigils", 999999999)
	var build_targets: Array[String] = []
	if mode == "mid":
		build_targets = [
			"execution_net",
			"fire_kindling_marks",
			"frost_brittle_window",
			"proj_split_barrel",
			"proj_needle_formation",
			"rico_hard_angles",
			"bomb_heavy_payload",
			"bomb_cluster_charge",
			"beam_thermal_lock"
		]
	elif mode != "baseline":
		build_targets = [
			"storm_closed_circuit",
			"scatter_shotgun_saint",
			"proj_converging_fire",
			"beam_surgical_continuity",
			"orbital_judgment_delay",
			"rico_violence_geometry",
			"pierce_execution_line",
			"bomb_delayed_catastrophe"
		]
	var owned := _resolve_nodes(build_targets, node_by_id)
	mp.set("meta_nodes_owned", owned)
	mp.set("_mods_dirty", true)

	var mods: Dictionary = mp.mods() if mp.has_method("mods") else {}
	print("PROTOCOL_FUNC_SMOKE profile=%s build_nodes=%d squad_dmg_mult=%.3f chain_jumps=%.1f proj_count=%.1f exec_add=%.3f" % [
		mode,
		owned.size(),
		float(mods.get("squad_damage_mult", 1.0)),
		float(mods.get("chain_jumps_add", 0.0)),
		float(mods.get("projectile_count_add", 0.0)),
		float(mods.get("execute_threshold_add", 0.0))
	])

	var pass_count := 0
	var fail := 0

	# Test 1: Closed Circuit behavior should allow chain re-hits when unique targets run out.
	var main_stub := MainStub.new()
	root.add_child(main_stub)
	await process_frame
	print("PROTOCOL_FUNC_SMOKE main_in_tree=%s root_meta_from_main=%s" % [str(main_stub.is_inside_tree()), str(main_stub.get_node_or_null("/root/MetaProgression") != null)])
	print("PROTOCOL_FUNC_SMOKE lookup proj_count=%.2f chain_jumps=%.2f cluster_count=%.2f" % [
		float(WeaponSystem._get_mp_add(main_stub, "projectile_count_add", 0.0)),
		float(WeaponSystem._get_mp_add(main_stub, "chain_jumps_add", 0.0)),
		float(WeaponSystem._get_mp_add(main_stub, "bomb_cluster_count_add", 0.0))
	])
	var attacker := Node2D.new()
	attacker.global_position = Vector2.ZERO
	main_stub.add_child(attacker)
	var e1 := EnemyStub.new(Vector2(140, 0))
	var e2 := EnemyStub.new(Vector2(185, 30))
	main_stub.add_child(e1)
	main_stub.add_child(e2)
	main_stub.enemies = [e1, e2]
	WeaponSystem._fire_chain_lightning(attacker, e1, 90, false, main_stub, null, {"chain_count": 2, "chain_damage_decay": 0.80, "chain_range": 220.0})
	var rehit_ok := (e1.hits > 1 or e2.hits > 1)
	if rehit_ok:
		pass_count += 1
	else:
		fail += 1
	print("PROTOCOL_FUNC_SMOKE chain_rehit hits_e1=%d hits_e2=%d status=%s" % [e1.hits, e2.hits, "pass" if rehit_ok else "fail"])

	# Test 2: Projectile mastery should spawn multiple projectiles.
	var target := EnemyStub.new(Vector2(240, 0))
	main_stub.add_child(target)
	main_stub.enemies.append(target)
	var before := main_stub.get_child_count()
	WeaponSystem._fire_standard_projectile(attacker, target, 70, false, main_stub, null)
	var after := main_stub.get_child_count()
	var spawned := maxi(0, after - before)
	var proj_ok := spawned >= 2
	if proj_ok:
		pass_count += 1
	else:
		fail += 1
	print("PROTOCOL_FUNC_SMOKE projectile_spawned=%d status=%s" % [spawned, "pass" if proj_ok else "fail"])

	# Test 3: Bomb cluster mastery should spawn extra bombs.
	var before_bomb := main_stub.get_child_count()
	WeaponSystem._fire_bomb(attacker, target, 120, false, main_stub, null, {"explosion_radius": 80.0, "projectile_speed": 380.0, "burn_duration": 0.0, "burn_dps_mult": 0.0})
	var after_bomb := main_stub.get_child_count()
	var bomb_spawned := maxi(0, after_bomb - before_bomb)
	var bomb_ok := bomb_spawned >= 2
	if bomb_ok:
		pass_count += 1
	else:
		fail += 1
	print("PROTOCOL_FUNC_SMOKE bomb_spawned=%d status=%s" % [bomb_spawned, "pass" if bomb_ok else "fail"])

	print("PROTOCOL_FUNC_SMOKE result pass=%d fail=%d" % [pass_count, fail])
	quit(0 if fail == 0 else 1)

func _arg_value(uargs: PackedStringArray, key: String, default_v: String = "") -> String:
	var prefix := key + "="
	for a in uargs:
		var s := String(a)
		if s.begins_with(prefix):
			return s.substr(prefix.length())
	return default_v

func _resolve_nodes(targets: Array[String], node_by_id: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(["core_0"])
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
