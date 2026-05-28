extends SceneTree

func _init() -> void:
	var rc := preload("res://scripts/RunConfig.gd").new()
	rc.name = "RunConfig"
	root.add_child(rc)
	rc.ensure_loaded()
	rc.selected_map_id = "church"

	var scene := load("res://scenes/Main.tscn") as PackedScene
	if scene == null:
		print("PERF_TRACE_SMOKE status=error reason=missing_main_scene")
		quit(1)
		return
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await create_timer(3.0).timeout
	print("PERF_TRACE_SMOKE status=done")
	quit()
