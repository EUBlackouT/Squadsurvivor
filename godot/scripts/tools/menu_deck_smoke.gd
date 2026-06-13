extends SceneTree
# Boots the command-deck main menu headlessly and verifies the new layout.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var err := change_scene_to_file("res://scenes/MainMenu.tscn")
	if err != OK:
		print("MENU_DECK_SMOKE_FAIL scene_change err=%d" % err)
		quit(1)
		return
	for _i in range(80):
		await process_frame

	var menu := current_scene
	if menu == null:
		print("MENU_DECK_SMOKE_FAIL no_scene")
		quit(1)
		return

	var fails := 0

	# Zone tiles exist and one is selected.
	var tiles: Array = []
	var deploy: Button = null
	var stack: Array = [menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.name.begins_with("ZoneTile_"):
			tiles.append(n)
		elif n is Button and ((n as Button).text.contains("DEPLOY") or (n as Button).text.contains("LOCKED")):
			deploy = n as Button

	var selected := 0
	for t in tiles:
		if bool((t as Node).get_meta("selected", false)):
			selected += 1
	print("MENU_DECK_SMOKE tiles=%d selected=%d deploy=%s" % [
		tiles.size(), selected, "yes" if deploy != null else "no"])
	if tiles.size() < 2 or selected != 1 or deploy == null:
		fails += 1

	# Hero art is set.
	var hero_ok := false
	var stack2: Array = [menu]
	while not stack2.is_empty():
		var n2: Node = stack2.pop_back()
		for c2 in n2.get_children():
			stack2.append(c2)
		if n2 is MenuMapPreview and (n2 as MenuMapPreview).texture != null:
			hero_ok = true
		elif n2 is TextureRect and (n2 as TextureRect).stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED \
				and (n2 as TextureRect).texture != null:
			hero_ok = true
	print("MENU_DECK_SMOKE hero_art=%s" % ("yes" if hero_ok else "no"))
	if not hero_ok:
		fails += 1

	# Filmstrip exists and drag-to-pan works (synthetic mouse events).
	var strip := menu.find_child("ZoneStrip", true, false) as Control
	if strip == null:
		print("MENU_DECK_SMOKE_FAIL no_zone_strip")
		fails += 1
	else:
		var rc0 := root.get_node_or_null("/root/RunConfig")
		var sel_before := String(rc0.get("selected_map_id")) if rc0 else ""
		var scroll_before := float(menu.get("_zone_scroll"))
		# Drag toward whichever side has scroll room left.
		var drag_dx := 180.0 if scroll_before > 200.0 else -180.0
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = strip.size * 0.5
		menu.call("_on_zone_strip_input", press)
		var motion := InputEventMouseMotion.new()
		motion.position = strip.size * 0.5 + Vector2(drag_dx, 0)
		motion.relative = Vector2(drag_dx, 0)
		menu.call("_on_zone_strip_input", motion)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = motion.position
		menu.call("_on_zone_strip_input", release)
		await process_frame
		var scroll_after := float(menu.get("_zone_scroll"))
		var sel_after := String(rc0.get("selected_map_id")) if rc0 else ""
		var drag_ok := absf(scroll_after - scroll_before) > 50.0 and sel_before == sel_after
		print("MENU_DECK_SMOKE drag scroll %.1f -> %.1f selection_stable=%s -> %s" % [
			scroll_before, scroll_after, str(sel_before == sel_after), "OK" if drag_ok else "FAIL"])
		if not drag_ok:
			fails += 1

	# Zone cycling works (simulate right key).
	if menu.has_method("_cycle_zone"):
		var rc := root.get_node_or_null("/root/RunConfig")
		var before := String(rc.get("selected_map_id")) if rc else ""
		menu.call("_cycle_zone", 1)
		await process_frame
		var after := String(rc.get("selected_map_id")) if rc else ""
		print("MENU_DECK_SMOKE cycle %s -> %s" % [before, after])
		if before == after:
			fails += 1
	else:
		print("MENU_DECK_SMOKE_FAIL no_cycle_zone")
		fails += 1

	print("MENU_DECK_SMOKE fails=%d -> %s" % [fails, "OK" if fails == 0 else "FAIL"])
	quit(0 if fails == 0 else 1)
