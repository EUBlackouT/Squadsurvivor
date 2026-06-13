extends SceneTree
# Boots Collection screen, selects first operative, saves screenshot for visual QA.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	change_scene_to_file("res://scenes/Menu.tscn")
	for _i in range(120):
		await process_frame
	var menu := current_scene
	if menu != null:
		var cm = menu.call("_get_collection_manager")
		if cm != null and cm.unlocked.size() > 0:
			var e: Variant = cm.unlocked[0]
			if typeof(e) == TYPE_DICTIONARY:
				var data: Dictionary = (e as Dictionary).get("data", {})
				if not data.is_empty() and menu.has_method("_select_unlock"):
					menu.call("_select_unlock", data)
					for _j in range(8):
						await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var out := OS.get_environment("COLLECTION_SHOT_PATH")
	if out.is_empty():
		out = "E:/SplitCode/godot/screenshots/collection_qa.png"
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("COLLECTION_SHOT saved %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	quit(0)
