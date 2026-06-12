extends SceneTree
# Verifies authored metadata maps: metadata parses, world builds with collision,
# spawn point lands on walkable ground, and the baked source image exists.

const METADATA_MAP_WORLD := preload("res://scripts/MetadataMapWorld.gd")

func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("AUTHORED_MAPS_SMOKE FAIL invalid maps.json")
		quit(1)
		return
	var maps: Array = (parsed as Dictionary).get("maps", []) as Array
	var fails := 0
	var checked := 0
	for m in maps:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md := m as Dictionary
		var meta_path := String(md.get("metadata_path", ""))
		if meta_path.is_empty():
			continue
		checked += 1
		var id := String(md.get("id", "?"))
		if not FileAccess.file_exists(meta_path):
			print("AUTHORED_MAPS_SMOKE %s missing metadata: %s" % [id, meta_path])
			fails += 1
			continue
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if typeof(meta) != TYPE_DICTIONARY:
			print("AUTHORED_MAPS_SMOKE %s invalid metadata json" % id)
			fails += 1
			continue
		var src := String((meta as Dictionary).get("source_image", ""))
		var img_path := meta_path.get_base_dir().path_join(src)
		if src.is_empty() or not (ResourceLoader.exists(img_path) or FileAccess.file_exists(img_path)):
			print("AUTHORED_MAPS_SMOKE %s missing source image: %s" % [id, img_path])
			fails += 1

		var world := Node2D.new()
		world.set_script(METADATA_MAP_WORLD)
		var ms: Array = md.get("map_size", [0, 0]) as Array
		world.set("metadata_path", meta_path)
		world.set("map_size", Vector2(float(ms[0]), float(ms[1])))
		world.set("perf_trace_enabled", false)
		root.add_child(world)
		world.call("build_if_needed")

		var ws: Vector2 = world.call("get_world_size")
		var spawn: Vector2 = world.call("get_default_spawn")
		var blockers := world.get_node_or_null("CollisionStatic")
		var blocker_count := blockers.get_child_count() if blockers != null else 0
		var spawn_ok: bool = is_finite(spawn.x) and is_finite(spawn.y) and world.call("_is_point_walkable", spawn)
		var ok := ws.x > 64.0 and ws.y > 64.0 and blocker_count > 0 and spawn_ok
		print("AUTHORED_MAPS_SMOKE %s world=%s spawn=%s blockers=%d spawn_walkable=%s -> %s" % [
			id, str(ws), str(spawn), blocker_count, str(spawn_ok), "OK" if ok else "FAIL"])
		if not ok:
			fails += 1
		world.queue_free()
	print("AUTHORED_MAPS_SMOKE checked=%d fails=%d -> %s" % [checked, fails, "OK" if fails == 0 else "FAIL"])
	quit(0 if fails == 0 else 1)
