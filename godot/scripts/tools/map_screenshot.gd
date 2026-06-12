extends SceneTree
# Boots Main on MAP_SHOT_ID with rendering and saves a screenshot of live
# gameplay to MAP_SHOT_PATH. Run windowed (not --headless).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var map_id := OS.get_environment("MAP_SHOT_ID")
	var out := OS.get_environment("MAP_SHOT_PATH")
	if out.is_empty():
		out = "user://map_shot.png"
	var rc := root.get_node_or_null("/root/RunConfig")
	if rc != null and not map_id.is_empty():
		rc.call("set_selected_map_id", map_id)
	change_scene_to_file("res://scenes/Main.tscn")
	for _i in range(90):
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("MAP_SHOT saved %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	quit(0)
