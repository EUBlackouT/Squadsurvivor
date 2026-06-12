extends SceneTree
# Boots the main menu with rendering, waits for it to settle, then saves a
# screenshot for visual review. Run windowed (not --headless).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	change_scene_to_file("res://scenes/MainMenu.tscn")
	for _i in range(110):
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var out := OS.get_environment("MENU_SHOT_PATH")
	if out.is_empty():
		out = "user://menu_shot.png"
	img.save_png(out)
	print("MENU_SHOT saved %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	quit(0)
