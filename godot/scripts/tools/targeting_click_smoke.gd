extends SceneTree

const TEST_ENEMY_COUNT: int = 18
const TEST_FRAMES: int = 240

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	if scene == null:
		print("TARGET_SMOKE status=fail reason=main_scene_missing")
		quit(2)
		return

	var root := scene.instantiate()
	get_root().add_child(root)

	for _i in range(8):
		await process_frame

	var main := get_first_node_in_group("main") as Node2D
	if main == null:
		print("TARGET_SMOKE status=fail reason=main_node_missing")
		quit(2)
		return
	if not main.has_method("get_player_node"):
		print("TARGET_SMOKE status=fail reason=get_player_node_missing")
		quit(2)
		return

	var player := main.get_player_node() as Node2D
	if player == null or not is_instance_valid(player):
		print("TARGET_SMOKE status=fail reason=player_missing")
		quit(2)
		return

	# Move player far from origin to expose any center-lock behavior.
	player.global_position = Vector2(1700.0, 940.0)
	for _j in range(4):
		await process_frame

	var click_ok := _check_click_world_mapping(main, player)
	var chase_ok: bool = await _check_enemy_chase(main, player)

	if click_ok and chase_ok:
		print("TARGET_SMOKE status=pass")
		quit(0)
		return

	print("TARGET_SMOKE status=fail click_ok=%s chase_ok=%s" % [str(click_ok), str(chase_ok)])
	quit(1)

func _check_click_world_mapping(main: Node2D, player: Node2D) -> bool:
	if not main.has_method("_screen_to_world"):
		print("TARGET_SMOKE click status=fail reason=screen_to_world_missing")
		return false

	var vp := get_root()
	var size: Vector2 = vp.get_visible_rect().size
	var c: Vector2 = size * 0.5
	var p1 := Vector2(size.x * 0.18, size.y * 0.22)
	var p2 := Vector2(size.x * 0.82, size.y * 0.76)
	var w_center: Vector2 = main._screen_to_world(c)
	var w1: Vector2 = main._screen_to_world(p1)
	var w2: Vector2 = main._screen_to_world(p2)

	var center_tracks_player: bool = w_center.distance_to(player.global_position) <= 40.0
	var points_separate: bool = w1.distance_to(w2) >= 120.0
	var not_center_locked: bool = w1.length() > 1.0 or w2.length() > 1.0
	var ok := center_tracks_player and points_separate and not_center_locked

	print("TARGET_SMOKE click center_dist=%.2f p1p2_dist=%.2f ok=%s" % [
		w_center.distance_to(player.global_position),
		w1.distance_to(w2),
		str(ok)
	])
	return ok

func _check_enemy_chase(main: Node2D, player: Node2D) -> bool:
	if not main.has_method("_spawn_enemy"):
		print("TARGET_SMOKE chase status=fail reason=spawn_enemy_missing")
		return false

	for _i in range(TEST_ENEMY_COUNT):
		main._spawn_enemy(false, false, false)
	for _j in range(6):
		await process_frame

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var enemies := get_nodes_in_group("enemies")
	var seeded: int = 0
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		n2.global_position = Vector2(rng.randf_range(-240.0, 240.0), rng.randf_range(-220.0, 220.0))
		seeded += 1

	for _k in range(5):
		await process_frame

	var start_avg: float = _avg_enemy_dist_to_player(player)
	for _f in range(TEST_FRAMES):
		# Keep moving the player so enemies must retarget off-center continuously.
		player.global_position += Vector2(1.8, 0.7)
		await process_frame
	var end_avg: float = _avg_enemy_dist_to_player(player)
	var chased: bool = end_avg < start_avg * 0.78

	var null_targets: int = 0
	var alive: int = 0
	var final_enemies := get_nodes_in_group("enemies")
	for e2 in final_enemies:
		if not is_instance_valid(e2):
			continue
		alive += 1
		var t: Variant = e2.get("_target")
		if t == null:
			null_targets += 1

	print("TARGET_SMOKE chase seeded=%d alive=%d start_avg=%.2f end_avg=%.2f null_targets=%d ok=%s" % [
		seeded,
		alive,
		start_avg,
		end_avg,
		null_targets,
		str(chased)
	])
	return chased

func _avg_enemy_dist_to_player(player: Node2D) -> float:
	var enemies := get_nodes_in_group("enemies")
	var total: float = 0.0
	var count: int = 0
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		total += n2.global_position.distance_to(player.global_position)
		count += 1
	if count <= 0:
		return INF
	return total / float(count)
