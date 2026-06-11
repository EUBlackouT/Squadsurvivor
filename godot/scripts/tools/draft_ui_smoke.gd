extends SceneTree

# Boots the real Main scene headless, opens the recruit draft,
# and verifies the new card UI builds (3 cards, badges, chips, buttons).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var err := change_scene_to_file("res://scenes/Main.tscn")
	if err != OK:
		print("DRAFT_SMOKE_FAIL scene_change err=%d" % err)
		quit(1)
		return
	# Let the game finish booting.
	for _i in range(90):
		await process_frame
	var main := get_first_node_in_group("main")
	if main == null:
		main = current_scene
	if main == null or not main.has_method("_show_recruit_draft"):
		print("DRAFT_SMOKE_FAIL main_not_found")
		quit(1)
		return

	main.call("_show_recruit_draft")
	for _i in range(20):
		await process_frame

	var draft := main.get_node_or_null("RecruitDraftUI")
	if draft == null:
		print("DRAFT_SMOKE_FAIL no_draft_ui")
		quit(1)
		return

	var unlock_buttons := 0
	var detail_buttons := 0
	var chips := 0
	var stack: Array = [draft]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Button:
			var bt := (n as Button).text
			if bt == "Unlock":
				unlock_buttons += 1
			elif bt == "Details":
				detail_buttons += 1
		elif n is PanelContainer and (n as PanelContainer).get_parent() is HFlowContainer:
			chips += 1

	var ok := unlock_buttons == 3 and detail_buttons == 3 and chips >= 9
	print("DRAFT_SMOKE unlock=%d details=%d chips=%d -> %s" % [
		unlock_buttons, detail_buttons, chips, "OK" if ok else "FAIL"])
	get_tree_paused_off()
	quit(0 if ok else 1)

func get_tree_paused_off() -> void:
	paused = false
