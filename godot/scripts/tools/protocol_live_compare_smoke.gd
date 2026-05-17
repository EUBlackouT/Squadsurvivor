extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")

func _init() -> void:
	await _run()

func _run() -> void:
	var mp: Node = root.get_node_or_null("MetaProgression")
	if mp == null:
		var meta_script := load("res://scripts/MetaProgression.gd")
		mp = meta_script.new() as Node
		root.add_child(mp)
		mp.name = "MetaProgression"
		await process_frame
	if mp == null or not is_instance_valid(mp):
		push_error("PROTOCOL_LIVE_COMPARE missing /root/MetaProgression")
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

	var snapshot_sigils: int = int(mp.get("sigils"))
	var snapshot_owned: PackedStringArray = mp.get("meta_nodes_owned") as PackedStringArray

	var profiles: Array[Dictionary] = [
		{"name": "baseline_core", "targets": []},
		{
			"name": "god_build",
			"targets": [
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
		}
	]

	var results: Dictionary = {}
	for p in profiles:
		var profile := p as Dictionary
		var name := String(profile.get("name", "unknown"))
		var targets := profile.get("targets", []) as Array
		var owned := _resolve_nodes(targets, node_by_id)
		_apply_meta_profile(mp, owned)

		var res := await _run_live_smoke_once("starter", 14.0, 95.0)
		results[name] = res
		print("PROTOCOL_LIVE_COMPARE profile=%s owned=%d status=%s survived_m=%.2f kills=%d elites=%d" % [
			name,
			owned.size(),
			String(res.get("status", "unknown")),
			float(res.get("survived_m", 0.0)),
			int(res.get("kills", 0)),
			int(res.get("elites", 0))
		])

	var base := results.get("baseline_core", {}) as Dictionary
	var god := results.get("god_build", {}) as Dictionary
	if not base.is_empty() and not god.is_empty():
		var dm := float(god.get("survived_m", 0.0)) - float(base.get("survived_m", 0.0))
		var dk := int(god.get("kills", 0)) - int(base.get("kills", 0))
		var de := int(god.get("elites", 0)) - int(base.get("elites", 0))
		print("PROTOCOL_LIVE_COMPARE_DELTA survived_m=%.2f kills=%d elites=%d" % [dm, dk, de])

	# Restore user state
	mp.set("sigils", snapshot_sigils)
	mp.set("meta_nodes_owned", snapshot_owned)
	mp.set("_mods_dirty", true)
	if mp.has_method("save"):
		mp.save()

	quit()

func _resolve_nodes(targets: Array, node_by_id: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(["core_0"])
	if targets.is_empty():
		return out
	var stack: Array[String] = []
	for t in targets:
		var tid := String(t)
		if tid != "":
			stack.append(tid)
	while not stack.is_empty():
		var id := String(stack.pop_back())
		if id == "" or out.has(id):
			continue
		out.append(id)
		var node := node_by_id.get(id, {}) as Dictionary
		var prereq := node.get("prereq", []) as Array
		for p in prereq:
			var pid := String(p)
			if pid != "" and not out.has(pid):
				stack.append(pid)
	return out

func _apply_meta_profile(mp: Node, owned: PackedStringArray) -> void:
	mp.set("sigils", 999999999)
	mp.set("meta_nodes_owned", owned)
	mp.set("_mods_dirty", true)
	if mp.has_method("save"):
		mp.save()

func _run_live_smoke_once(case_id: String, clock_scale: float, timeout_s: float) -> Dictionary:
	var main := MAIN_SCENE.instantiate()
	main.set("_live_smoke_enabled", true)
	main.set("_live_smoke_case", case_id)
	main.set("_live_smoke_clock_scale", clock_scale)
	main.set("_live_smoke_timeout_s", timeout_s)
	main.set("_live_smoke_reported", false)
	root.add_child(main)
	await process_frame
	# Ensure smoke overrides are applied even if _ready path changed.
	if main.has_method("_apply_live_smoke_overrides"):
		main.call("_apply_live_smoke_overrides")

	var started_s := Time.get_ticks_msec() / 1000.0
	var status := "timeout"
	while true:
		await process_frame
		if not is_instance_valid(main):
			status = "freed"
			break
		if bool(main.get("_game_over")):
			status = "game_over"
			break
		if bool(main.get("_victory")):
			status = "victory"
			break
		if (Time.get_ticks_msec() / 1000.0) - started_s >= timeout_s:
			status = "timeout"
			break

	var result := {
		"status": status,
		"survived_m": float(main.call("_elapsed_minutes")) if is_instance_valid(main) and main.has_method("_elapsed_minutes") else 0.0,
		"kills": int(main.get("_run_kills")) if is_instance_valid(main) else 0,
		"elites": int(main.get("_run_elite_kills")) if is_instance_valid(main) else 0
	}

	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	return result
