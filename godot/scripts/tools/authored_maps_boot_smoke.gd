extends SceneTree

# Boots the real Main scene on each authored metadata map and verifies the
# world builds, the player spawns on walkable ground, and enemies appear.

const MAP_IDS: Array[String] = ["cathedral_nave", "infernal_reliquary"]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fails := 0
	for map_id in MAP_IDS:
		var ok := await _boot_map(map_id)
		if not ok:
			fails += 1
	print("AUTHORED_BOOT_SMOKE checked=%d fails=%d -> %s" % [MAP_IDS.size(), fails, "OK" if fails == 0 else "FAIL"])
	quit(0 if fails == 0 else 1)

func _boot_map(map_id: String) -> bool:
	var rc := root.get_node_or_null("/root/RunConfig")
	if rc == null:
		print("AUTHORED_BOOT_SMOKE %s FAIL no RunConfig autoload" % map_id)
		return false
	rc.call("set_selected_map_id", map_id)
	var err := change_scene_to_file("res://scenes/Main.tscn")
	if err != OK:
		print("AUTHORED_BOOT_SMOKE %s FAIL scene_change err=%d" % [map_id, err])
		return false
	for _i in range(120):
		await process_frame

	var main := get_first_node_in_group("main")
	if main == null:
		main = current_scene
	var world := main.get_node_or_null("MetadataMapWorld") if main != null else null
	if world == null:
		print("AUTHORED_BOOT_SMOKE %s FAIL no MetadataMapWorld in scene" % map_id)
		return false
	var blockers := world.get_node_or_null("CollisionStatic")
	var blocker_count := blockers.get_child_count() if blockers != null else 0

	var player := root.find_child("Player", true, false)
	var player_ok := player != null
	var spawn_walkable := false
	if player_ok:
		spawn_walkable = bool(world.call("_is_point_walkable", (player as Node2D).global_position))

	var enemies := get_nodes_in_group("enemies").size()
	var ok := blocker_count > 0 and player_ok and spawn_walkable and enemies > 0
	print("AUTHORED_BOOT_SMOKE %s blockers=%d player=%s spawn_walkable=%s enemies=%d -> %s" % [
		map_id, blocker_count, str(player_ok), str(spawn_walkable), enemies, "OK" if ok else "FAIL"])
	return ok
