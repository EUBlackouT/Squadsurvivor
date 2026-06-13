extends SceneTree
# Verifies the camera keeps the player on screen at map corners across zoom
# levels (regression test for the clamp that snapped the camera to map center
# when zoomed in).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var rc := root.get_node_or_null("/root/RunConfig")
	if rc != null:
		rc.call("set_selected_map_id", "church")
	change_scene_to_file("res://scenes/Main.tscn")
	for _i in range(40):
		await process_frame

	var main := root.get_node_or_null("/root/Main")
	var player := get_first_node_in_group("player") as CharacterBody2D
	if main == null or player == null:
		print("CAMERA_SMOKE FAIL missing main/player")
		quit(1)
		return
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		print("CAMERA_SMOKE FAIL missing camera")
		quit(1)
		return

	var world_rect: Rect2 = main.call("_current_world_rect")
	var corner := world_rect.position + world_rect.size - Vector2(40, 40)
	var fails := 0
	for zoom in [0.5, 0.78, 1.4, 2.2]:
		cam.zoom = Vector2(zoom, zoom)
		if main.has_method("refresh_camera_limits"):
			main.call("refresh_camera_limits")
		player.global_position = corner
		for _j in range(12):
			await process_frame
		# Player must be inside the visible camera window.
		var cam_center := cam.get_screen_center_position()
		var half := root.get_viewport().get_visible_rect().size * 0.5 / float(zoom)
		var dx := absf(player.global_position.x - cam_center.x)
		var dy := absf(player.global_position.y - cam_center.y)
		var on_screen := dx <= half.x + 1.0 and dy <= half.y + 1.0
		print("CAMERA_SMOKE zoom=%.2f cam_center=%s player=%s on_screen=%s" % [
			zoom, str(cam_center.round()), str(player.global_position.round()), str(on_screen)])
		if not on_screen:
			fails += 1

	# Walk the player to the corner over several physics frames — camera must track.
	player.global_position = world_rect.position + world_rect.size * 0.5
	main.call("refresh_camera_limits")
	cam.zoom = Vector2(0.78, 0.78)
	var dest := world_rect.position + world_rect.size - Vector2(80, 80)
	for _k in range(48):
		var dir := (dest - player.global_position)
		if dir.length() < 8.0:
			break
		player.velocity = dir.normalized() * 900.0
		player.move_and_slide()
		await process_frame
	var move_center := cam.get_screen_center_position()
	var move_ok := player.global_position.distance_to(move_center) < 24.0
	print("CAMERA_SMOKE move_track player=%s cam_center=%s dist=%.1f -> %s" % [
		str(player.global_position.round()), str(move_center.round()),
		player.global_position.distance_to(move_center), "OK" if move_ok else "FAIL"])
	if not move_ok:
		fails += 1

	print("CAMERA_SMOKE fails=%d -> %s" % [fails, "OK" if fails == 0 else "FAIL"])
	quit(0 if fails == 0 else 1)
