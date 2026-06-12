extends SceneTree

# Boots the real Main scene on each authored metadata map and verifies the
# world builds, the player spawns on walkable ground, and enemies appear.

const MAP_IDS: Array[String] = [
	"church", "library", "foundry", "cathedral",
	"cathedral_nave", "infernal_reliquary", "grand_basilica",
]

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

	# Physics probe: the player body must overlap when placed inside a blocker
	# (proving walls physically collide) and must be free at its spawn point.
	var collides_in_wall := false
	var free_at_spawn := false
	if player_ok and player is PhysicsBody2D:
		var body := player as PhysicsBody2D
		var blockers_arr: Array = world.get("_hard_blockers")
		if blockers_arr is Array and not (blockers_arr as Array).is_empty():
			var poly: PackedVector2Array = (blockers_arr as Array)[0]
			var centroid := Vector2.ZERO
			for p in poly:
				centroid += p
			centroid /= float(poly.size())
			free_at_spawn = not body.test_move(body.global_transform, Vector2.ZERO)
			var xf := body.global_transform
			xf.origin = centroid
			collides_in_wall = body.test_move(xf, Vector2.ZERO)

	var ok := blocker_count > 0 and player_ok and spawn_walkable and enemies > 0 \
		and collides_in_wall and free_at_spawn
	print("AUTHORED_BOOT_SMOKE %s blockers=%d player=%s spawn_walkable=%s enemies=%d wall_collides=%s spawn_free=%s -> %s" % [
		map_id, blocker_count, str(player_ok), str(spawn_walkable), enemies,
		str(collides_in_wall), str(free_at_spawn), "OK" if ok else "FAIL"])
	return ok
