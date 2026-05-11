extends SceneTree

class MainStub:
	extends Node2D
	var player_node: Node2D = null
	var squad_nodes: Array = []

	func get_player_node() -> Node2D:
		return player_node

	func get_cached_squad_units() -> Array:
		return squad_nodes

func _init() -> void:
	var ok_click := _run_click_mapping_smoke()
	var ok_target := _run_enemy_targeting_smoke()
	print("TARGET_LOGIC_SMOKE click_ok=%s target_ok=%s" % [str(ok_click), str(ok_target)])
	if ok_click and ok_target:
		print("TARGET_LOGIC_SMOKE status=pass")
		quit(0)
	else:
		print("TARGET_LOGIC_SMOKE status=fail")
		quit(1)

func _run_click_mapping_smoke() -> bool:
	var path := "res://scripts/Main.gd"
	if not ResourceLoader.exists(path):
		print("TARGET_LOGIC_SMOKE click reason=main_script_missing")
		return false
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		print("TARGET_LOGIC_SMOKE click reason=main_script_empty")
		return false
	var has_converter := txt.find("func _screen_to_world(") >= 0
	var uses_canvas_inverse := txt.find("get_canvas_transform().affine_inverse()") >= 0
	var left_click_uses_screen := txt.find("_select_single_unit_at(_screen_to_world(mb.position)") >= 0
	var right_click_uses_screen := txt.find("var mouse_world := _screen_to_world(mb.position)") >= 0
	var ok := has_converter and uses_canvas_inverse and left_click_uses_screen and right_click_uses_screen
	print("TARGET_LOGIC_SMOKE click has_converter=%s uses_canvas_inverse=%s left_click_uses_screen=%s right_click_uses_screen=%s" % [
		str(has_converter),
		str(uses_canvas_inverse),
		str(left_click_uses_screen),
		str(right_click_uses_screen)
	])
	return ok

func _run_enemy_targeting_smoke() -> bool:
	var main := MainStub.new()
	main.add_to_group("main")
	get_root().add_child(main)

	var player := Node2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(3000.0, 1400.0)
	get_root().add_child(player)
	main.player_node = player

	var enemy_script: GDScript = load("res://scripts/Enemy.gd") as GDScript
	if enemy_script == null:
		print("TARGET_LOGIC_SMOKE target reason=enemy_script_missing")
		return false
	var enemy := enemy_script.new() as Node2D
	if enemy == null:
		print("TARGET_LOGIC_SMOKE target reason=enemy_instance_missing")
		return false
	get_root().add_child(enemy)
	enemy.global_position = Vector2.ZERO
	enemy.set("_main", main)

	# Case A: no squad nearby, should still target far-away player.
	main.squad_nodes = []
	var t_player: Node2D = enemy._find_target() as Node2D
	var case_player_ok: bool = (t_player == player)

	# Case B: nearby squad should be preferred over farther player.
	var squad := Node2D.new()
	squad.add_to_group("squad_units")
	squad.global_position = Vector2(350.0, 0.0)
	get_root().add_child(squad)
	main.squad_nodes = [squad]
	var t_squad: Node2D = enemy._find_target() as Node2D
	var case_squad_ok: bool = (t_squad == squad)

	print("TARGET_LOGIC_SMOKE target case_player_ok=%s case_squad_ok=%s" % [str(case_player_ok), str(case_squad_ok)])
	return case_player_ok and case_squad_ok
