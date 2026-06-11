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

	# Swap prompt: fabricate a recruit and verify deploy/swap flow end-to-end.
	var swap_ok := await _check_swap_prompt(main, draft)
	print("DRAFT_SMOKE swap_prompt -> %s" % ("OK" if swap_ok else "FAIL"))

	paused = false
	quit(0 if (ok and swap_ok) else 1)

func _check_swap_prompt(main: Node, draft: Node) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var cd := CharacterRegistryUtil.build_random_character_data("recruit", rng, 2.0, {})
	if cd == null:
		print("DRAFT_SMOKE_FAIL no_character_data")
		return false
	main.call("_show_swap_prompt", cd, draft)
	for _i in range(5):
		await process_frame
	var prompt := draft.get_node_or_null("SwapPrompt")
	if prompt == null:
		print("DRAFT_SMOKE_FAIL no_swap_prompt")
		return false
	var swap_buttons: Array = []
	var stack: Array = [prompt]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Button and (n as Button).text == "Swap":
			swap_buttons.append(n)
	if swap_buttons.is_empty():
		print("DRAFT_SMOKE_FAIL no_swap_rows")
		return false
	var player := get_first_node_in_group("player")
	var size_before: int = (player.get("squad_units") as Array).size()
	(swap_buttons[0] as Button).pressed.emit()
	for _i in range(10):
		await process_frame
	var squad_after: Array = player.get("squad_units") as Array
	var has_new := false
	for u in squad_after:
		if is_instance_valid(u):
			var ucd := (u as Node).get("character_data") as CharacterData
			if ucd != null and ucd.archetype_id == cd.archetype_id and ucd.race_id == cd.race_id:
				has_new = true
	if squad_after.size() != size_before:
		print("DRAFT_SMOKE_FAIL squad_size_changed %d -> %d" % [size_before, squad_after.size()])
		return false
	if not has_new:
		print("DRAFT_SMOKE_FAIL recruit_not_in_squad")
		return false
	return true
