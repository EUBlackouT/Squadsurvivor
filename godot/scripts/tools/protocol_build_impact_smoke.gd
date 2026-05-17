extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var mp: Node = null
	if root != null and is_instance_valid(root):
		mp = root.get_node_or_null("MetaProgression")
		if mp == null:
			var meta_script := load("res://scripts/MetaProgression.gd")
			if meta_script != null:
				mp = meta_script.new() as Node
				if mp != null:
					mp.name = "MetaProgression"
					root.add_child(mp)
	if mp == null or not is_instance_valid(mp):
		push_error("PROTOCOL_IMPACT missing /root/MetaProgression autoload")
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

	var profiles: Array = [
		{"name": "baseline_core", "targets": []},
		{"name": "mixed_mastery_build", "targets": ["storm_closed_circuit", "rico_violence_geometry", "beam_surgical_continuity", "orbital_judgment_delay"]},
		{"name": "control_execute_build", "targets": ["frost_stillness_tax", "fire_ash_economy", "execution_net", "pierce_execution_line"]},
		{"name": "all_nodes", "targets": ["__ALL__"]}
	]

	for p in profiles:
		var profile := p as Dictionary
		var profile_name := String(profile.get("name", "unknown"))
		var targets := profile.get("targets", []) as Array
		var owned: PackedStringArray = _resolve_profile_nodes(targets, node_by_id)
		_apply_meta_profile(mp, owned)
		var mods: Dictionary = mp.mods() if mp.has_method("mods") else {}
		var result := await _run_live_smoke_once("starter", 12.0, 90.0)
		print("PROTOCOL_IMPACT profile=%s owned=%d survived_m=%.2f kills=%d elites=%d status=%s dps_mult=%.3f as_mult=%.3f range_mult=%.3f exec_add=%.3f chain_jumps=%.1f proj_count=%.1f" % [
			profile_name,
			owned.size(),
			float(result.get("survived_m", 0.0)),
			int(result.get("kills", 0)),
			int(result.get("elites", 0)),
			String(result.get("status", "unknown")),
			float(mods.get("squad_damage_mult", 1.0)),
			float(mods.get("squad_attack_speed_mult", 1.0)),
			float(mods.get("squad_range_mult", 1.0)),
			float(mods.get("execute_threshold_add", 0.0)),
			float(mods.get("chain_jumps_add", 0.0)),
			float(mods.get("projectile_count_add", 0.0))
		])

	quit()

func _resolve_profile_nodes(targets: Array, node_by_id: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(["core_0"])
	if targets.is_empty():
		return out
	if targets.size() == 1 and String(targets[0]) == "__ALL__":
		for id in node_by_id.keys():
			var sid := String(id)
			if not out.has(sid):
				out.append(sid)
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
		var d := node_by_id.get(id, {}) as Dictionary
		var prereq := d.get("prereq", []) as Array
		for p in prereq:
			var pid := String(p)
			if pid != "" and not out.has(pid):
				stack.append(pid)
	return out

func _apply_meta_profile(mp: Node, owned: PackedStringArray) -> void:
	if mp == null or not is_instance_valid(mp):
		return
	mp.set("meta_nodes_owned", owned)
	mp.set("sigils", 999999999)
	mp.set("_mods_dirty", true)
	if mp.has_method("save"):
		mp.save()

func _run_live_smoke_once(case_id: String, clock_scale: float, timeout_s: float) -> Dictionary:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame

	main.set("_live_smoke_enabled", true)
	main.set("_live_smoke_case", case_id)
	main.set("_live_smoke_clock_scale", clock_scale)
	main.set("_live_smoke_timeout_s", timeout_s)
	main.set("_live_smoke_reported", false)
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
