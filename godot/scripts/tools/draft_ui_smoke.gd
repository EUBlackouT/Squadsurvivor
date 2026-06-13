extends SceneTree

const _RecruitDraftUI := preload("res://scripts/run/RecruitDraftUI.gd")

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

	_RecruitDraftUI.present(main)
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
			if bt == "RECRUIT":
				unlock_buttons += 1
			elif bt == "DETAILS":
				detail_buttons += 1
		elif n is PanelContainer and (n as PanelContainer).get_parent() is HFlowContainer:
			chips += 1

	var ok := unlock_buttons == 3 and detail_buttons == 3 and chips >= 9
	print("DRAFT_SMOKE unlock=%d details=%d chips=%d -> %s" % [
		unlock_buttons, detail_buttons, chips, "OK" if ok else "FAIL"])

	# Banish buttons: one per card.
	var banish_buttons := 0
	var stack2: Array = [draft]
	while not stack2.is_empty():
		var n2: Node = stack2.pop_back()
		for c2 in n2.get_children():
			stack2.append(c2)
		if n2 is Button and (n2 as Button).text.begins_with("↻ BANISH"):
			banish_buttons += 1
	var banish_ok := banish_buttons == 3
	print("DRAFT_SMOKE banish_buttons=%d -> %s" % [banish_buttons, "OK" if banish_ok else "FAIL"])
	ok = ok and banish_ok

	# Swap prompt: fabricate a recruit and verify deploy/swap flow end-to-end.
	var swap_ok := await _check_swap_prompt(main, draft)
	print("DRAFT_SMOKE swap_prompt -> %s" % ("OK" if swap_ok else "FAIL"))

	# Squad strip: HUD shows one chip per live member (updates while unpaused).
	paused = false
	for _i in range(25):
		await process_frame
	var strip := main.get_node_or_null("HUD/SquadStrip")
	var squad_n := get_nodes_in_group("squad_units").size()
	var strip_n := strip.get_child_count() if strip != null else -1
	var strip_ok := strip != null and strip_n == squad_n and squad_n > 0
	print("DRAFT_SMOKE squad_strip chips=%d squad=%d -> %s" % [strip_n, squad_n, "OK" if strip_ok else "FAIL"])

	quit(0 if (ok and swap_ok and strip_ok) else 1)

func _check_swap_prompt(main: Node, draft: Node) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var cd := CharacterRegistryUtil.build_random_character_data("recruit", rng, 2.0, {})
	if cd == null:
		print("DRAFT_SMOKE_FAIL no_character_data")
		return false
	if draft == null or not draft.has_method("show_swap_prompt"):
		print("DRAFT_SMOKE_FAIL no_swap_method")
		return false
	draft.show_swap_prompt(cd)
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
