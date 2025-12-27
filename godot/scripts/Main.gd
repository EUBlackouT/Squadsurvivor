extends Node2D

@export var map_size: Vector2 = Vector2(4800, 3600)
@export var random_seed: int = 0

@export var initial_enemy_count: int = 16
@export var max_enemies_alive: int = 90
@export var enemy_spawn_interval: float = 1.15
@export var enemy_spawn_burst: int = 1
@export var spawn_radius_min: float = 820.0
@export var spawn_radius_max: float = 1300.0

@export var run_timer_max_minutes: float = 18.0
@export var boss_spawn_time_minutes: float = 14.0
@export var enable_rifts: bool = false

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const RIFT_SCENE: PackedScene = preload("res://scenes/RiftNode.tscn")

var damage_numbers: DamageNumbersLayer

var rng: RandomNumberGenerator
var run_start_time: float = 0.0

# Performance: live lists (no get_nodes_in_group() in hot paths)
var live_enemies: Array[Node2D] = []
var live_squad_units: Array[Node2D] = []

# Recruit/trophy flow
var essence: int = 0
var reroll_cost_essence: int = 3
var _recent_trophy_pool: Array[CharacterData] = []
var _force_rift_next_draft: bool = false

# Run structure
var _boss_spawned: bool = false
var _boss_node: Node2D = null
var _game_over: bool = false
var _victory: bool = false

var capture_meter: CaptureMeter

var _spawn_timer: float = 0.0
var _dbg_cd: float = 0.0
var _dbg_text: String = ""
var _hide_projectiles: bool = false
var _strip_cd: float = 0.0
var _dbg_reported: Dictionary = {}
var _hide_debug_shapes_cd: float = 0.0

func _ready() -> void:
	add_to_group("main")
	_init_rng()
	run_start_time = Time.get_ticks_msec() / 1000.0

	# Hard-disable editor debug overlays that can make gameplay unreadable.
	# (Some run configurations can keep these on even when the menu checkbox looks off.)
	get_tree().debug_collisions_hint = false
	get_tree().debug_navigation_hint = false
	# NOTE: Some PhysicsServer2D debug APIs are not available in all builds; keep this portable.

	# Ensure data systems are loaded early.
	PixellabUtil.ensure_loaded()
	UnitFactory.ensure_loaded()
	PassiveSystem.ensure_loaded()

	_make_background()

	damage_numbers = DamageNumbersLayer.new()
	add_child(damage_numbers)

	# Safety: remove any unexpected CircleShape2D CollisionShape2D nodes (these match the "orb" visuals).
	# Keep the RiftNode trigger intact.
	_strip_circle_collision_shapes()

	capture_meter = CaptureMeter.new()
	add_child(capture_meter)
	capture_meter.draft_ready.connect(_on_draft_ready)

	_spawn_player()
	_spawn_initial_enemies()
	if enable_rifts:
		_spawn_rifts()
	_setup_hud()

func _init_rng() -> void:
	rng = RandomNumberGenerator.new()
	if random_seed == 0:
		rng.seed = int(Time.get_unix_time_from_system())
	else:
		rng.seed = random_seed

func _elapsed_minutes() -> float:
	return ((Time.get_ticks_msec() / 1000.0) - run_start_time) / 60.0

func _make_background() -> void:
	var w := int(map_size.x)
	var h := int(map_size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var tile := 32
	for y in range(0, h, tile):
		for x in range(0, w, tile):
			var base := Color(0.10, 0.12, 0.16, 1.0)
			var alt := Color(0.11, 0.14, 0.18, 1.0)
			var c := base if ((x / tile + y / tile) % 2 == 0) else alt
			img.fill_rect(Rect2i(x, y, tile, tile), c)
	var tex := ImageTexture.create_from_image(img)
	var bg := Sprite2D.new()
	bg.texture = tex
	bg.centered = false
	bg.position = Vector2(-map_size.x * 0.5, -map_size.y * 0.5)
	bg.z_index = -100
	add_child(bg)

func _spawn_player() -> void:
	if PLAYER_SCENE == null:
		return
	var p := PLAYER_SCENE.instantiate()
	p.position = Vector2.ZERO
	add_child(p)
	if p.has_node("Camera2D"):
		var cam := p.get_node("Camera2D") as Camera2D
		if cam:
			cam.limit_left = int(-map_size.x * 0.5)
			cam.limit_top = int(-map_size.y * 0.5)
			cam.limit_right = int(map_size.x * 0.5)
			cam.limit_bottom = int(map_size.y * 0.5)

func _spawn_initial_enemies() -> void:
	for i in range(initial_enemy_count):
		_spawn_enemy(false, false, false)

func _spawn_rifts() -> void:
	if RIFT_SCENE == null:
		return
	# 2 rifts placed far from center for mid-run agency
	for i in range(2):
		var r := RIFT_SCENE.instantiate()
		add_child(r)
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(900.0, 1400.0)
		r.global_position = Vector2(cos(ang), sin(ang)) * dist

func _physics_process(delta: float) -> void:
	if _game_over or _victory:
		return
	_strip_cd -= delta
	if _strip_cd <= 0.0:
		_strip_cd = 0.6
		_strip_circle_collision_shapes()
	_hide_debug_shapes_cd -= delta
	if _hide_debug_shapes_cd <= 0.0:
		_hide_debug_shapes_cd = 0.4
		_hide_collision_debug_visuals()
	_spawn_timer += delta
	if _spawn_timer >= enemy_spawn_interval:
		_spawn_timer = 0.0
		_tick_spawns()

	var em := _elapsed_minutes()
	if (not _boss_spawned) and em >= boss_spawn_time_minutes:
		_spawn_boss()
	_update_hud_labels()

func _unhandled_input(event: InputEvent) -> void:
	# Debug helper: toggle damage number layer to verify what's drawing the "orbs".
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		# NOTE: F8 is an editor hotkey (can stop the running game). Use Ctrl+Shift+F9.
		if k.keycode == KEY_F9 and k.ctrl_pressed and k.shift_pressed and damage_numbers != null:
			damage_numbers.visible = not damage_numbers.visible
		# Debug helper: hide projectiles to confirm whether the "orbs" are projectile visuals.
		# Ctrl+Shift+F10
		if k.keycode == KEY_F10 and k.ctrl_pressed and k.shift_pressed:
			_hide_projectiles = not _hide_projectiles
			for p in get_tree().get_nodes_in_group("projectiles"):
				if not is_instance_valid(p):
					continue
				var n2 := p as Node2D
				if n2:
					n2.visible = not _hide_projectiles

func _tick_spawns() -> void:
	_prune_invalid_lists()
	if live_enemies.size() >= max_enemies_alive:
		return
	for i in range(enemy_spawn_burst):
		if live_enemies.size() >= max_enemies_alive:
			break
		_spawn_enemy(false, false, false)

func _spawn_enemy(is_elite: bool, from_rift: bool, is_boss: bool) -> void:
	if ENEMY_SCENE == null:
		return
	var e := ENEMY_SCENE.instantiate()

	var player := get_tree().get_first_node_in_group("player") as Node2D
	var center := Vector2.ZERO
	if player and is_instance_valid(player):
		center = player.global_position
	var ang := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(spawn_radius_min, spawn_radius_max)

	# Random character pool -> random enemy skin
	var south := PixellabUtil.pick_random_south_path(rng)
	var cd := UnitFactory.build_character_data("enemy", rng, _elapsed_minutes(), south)
	if is_elite:
		cd.max_hp = int(round(float(cd.max_hp) * 1.55))
		cd.attack_damage = int(round(float(cd.attack_damage) * 1.25))

	# IMPORTANT: set exported fields BEFORE add_child so Enemy._ready() sees them.
	e.set_meta("rift", from_rift)
	e.set_meta("boss", is_boss)
	e.character_data = cd
	e.is_elite = is_elite
	e.pixellab_south_path = south
	add_child(e)
	e.global_position = center + Vector2(cos(ang), sin(ang)) * dist

func _spawn_boss() -> void:
	_boss_spawned = true
	_spawn_enemy(true, false, true)
	# Best-effort: last enemy spawned is boss
	if live_enemies.size() > 0:
		_boss_node = live_enemies[live_enemies.size() - 1]

func register_enemy(e: Node2D) -> void:
	live_enemies.append(e)

func unregister_enemy(e: Node2D) -> void:
	var idx := live_enemies.find(e)
	if idx >= 0:
		live_enemies.remove_at(idx)

func register_squad_unit(u: Node2D) -> void:
	live_squad_units.append(u)

func unregister_squad_unit(u: Node2D) -> void:
	var idx := live_squad_units.find(u)
	if idx >= 0:
		live_squad_units.remove_at(idx)

func _prune_invalid_lists() -> void:
	for i in range(live_enemies.size() - 1, -1, -1):
		if not is_instance_valid(live_enemies[i]):
			live_enemies.remove_at(i)
	for j in range(live_squad_units.size() - 1, -1, -1):
		if not is_instance_valid(live_squad_units[j]):
			live_squad_units.remove_at(j)

func get_cached_enemies() -> Array[Node2D]:
	_prune_invalid_lists()
	return live_enemies

func get_cached_squad_units() -> Array[Node2D]:
	_prune_invalid_lists()
	return live_squad_units

func on_enemy_killed(is_elite: bool, cd: CharacterData, from_rift: bool, was_boss: bool) -> void:
	if _game_over or _victory:
		return

	# Capture meter -> draft pacing
	if capture_meter:
		if is_elite:
			capture_meter.add_capture_elite()
		else:
			capture_meter.add_capture_normal()

	# Essence economy for rerolls
	essence += 1 if not is_elite else 3

	# Trophy pool: store recent killed character variants for unlocks
	if cd != null:
		_recent_trophy_pool.append(cd)
		if _recent_trophy_pool.size() > 18:
			_recent_trophy_pool.pop_front()

	# Boss victory
	if was_boss:
		_show_victory()

func start_rift_encounter(_rift: Node) -> void:
	# Next draft offers a "Mystery Rift" option with better odds
	_force_rift_next_draft = true
	# Spawn a short elite burst
	for i in range(10):
		_spawn_enemy(rng.randf() < 0.35, true, false)

func show_damage_number(source_id: int, channel: String, amount: int, world_pos: Vector2, style: int, is_crit: bool) -> void:
	if damage_numbers == null:
		return
	damage_numbers.spawn_aggregated(source_id, channel, amount, world_pos, style, is_crit)

func _on_draft_ready() -> void:
	# Pause game and show recruit draft UI
	get_tree().paused = true
	_show_recruit_draft()

func _show_recruit_draft() -> void:
	if has_node("RecruitDraftUI"):
		return
	var draft_ui := CanvasLayer.new()
	draft_ui.name = "RecruitDraftUI"
	draft_ui.layer = 100
	draft_ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(draft_ui)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	draft_ui.add_child(backdrop)

	var backdrop_shader_mat := ShaderMaterial.new()
	backdrop_shader_mat.shader = preload("res://shaders/ui_arcane_scifi_backdrop.gdshader")
	backdrop.material = backdrop_shader_mat

	var modal := PanelContainer.new()
	modal.set_anchors_preset(Control.PRESET_CENTER)
	modal.offset_left = -460
	modal.offset_top = -280
	modal.offset_right = 460
	modal.offset_bottom = 280
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	draft_ui.add_child(modal)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.13, 0.98)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(1, 1, 1, 0.10)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	modal.add_theme_stylebox_override("panel", sb)

	var neon_shader_mat := ShaderMaterial.new()
	neon_shader_mat.shader = preload("res://shaders/ui_neon_frame.gdshader")
	neon_shader_mat.set_shader_parameter("base_color", Color(0.10, 0.11, 0.13, 0.98))
	neon_shader_mat.set_shader_parameter("glow_color", Color(0.4, 0.8, 1.0, 0.6))
	neon_shader_mat.set_shader_parameter("glow_width", 0.02)
	neon_shader_mat.set_shader_parameter("pulse_speed", 1.2)
	modal.material = neon_shader_mat

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 22)
	modal.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	pad.add_child(vbox)

	var title := Label.new()
	title.text = "Recruit Draft"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Choose 1. Trophies unlock into your collection (not auto-added)."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 0.95))
	vbox.add_child(subtitle)

	var info := Label.new()
	info.name = "InfoLabel"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "Essence: %d   (Reroll costs %d)" % [essence, reroll_cost_essence]
	info.add_theme_font_size_override("font_size", 16)
	info.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1))
	vbox.add_child(info)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	vbox.add_child(btns)

	var reroll_btn := Button.new()
	reroll_btn.text = "Reroll (%d)" % reroll_cost_essence
	reroll_btn.add_theme_font_size_override("font_size", 18)
	reroll_btn.custom_minimum_size = Vector2(180, 46)
	btns.add_child(reroll_btn)

	reroll_btn.pressed.connect(func():
		if essence < reroll_cost_essence:
			return
		essence -= reroll_cost_essence
		for c in hbox.get_children():
			c.queue_free()
		_populate_recruit_cards(hbox, draft_ui, false)
		info.text = "Essence: %d   (Reroll costs %d)" % [essence, reroll_cost_essence]
	)

	_populate_recruit_cards(hbox, draft_ui, _force_rift_next_draft)
	_force_rift_next_draft = false

	btns.add_spacer(true)

	var close_btn := Button.new()
	close_btn.text = "Close (Select Later)"
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.custom_minimum_size = Vector2(220, 46)
	close_btn.pressed.connect(func(): _close_draft(draft_ui))
	btns.add_child(close_btn)

func _populate_recruit_cards(hbox: HBoxContainer, ui: CanvasLayer, is_rift: bool) -> void:
	var options: Array[CharacterData] = []

	# Option 1-2: trophies from recent kills
	_recent_trophy_pool.shuffle()
	for i in range(min(2, _recent_trophy_pool.size())):
		options.append(_recent_trophy_pool[i])

	# Option 3: random recruit roll (rift improves odds via elapsed minutes bias already)
	var south := PixellabUtil.pick_random_south_path(rng)
	var cd := UnitFactory.build_character_data("recruit", rng, _elapsed_minutes() + (3.0 if is_rift else 0.0), south)
	options.append(cd)

	# Ensure 3 cards
	while options.size() < 3:
		var s2 := PixellabUtil.pick_random_south_path(rng)
		options.append(UnitFactory.build_character_data("recruit", rng, _elapsed_minutes(), s2))

	for c in options:
		hbox.add_child(_create_character_card(c, ui))

func _create_character_card(cd: CharacterData, ui: CanvasLayer) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(260, 220)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.92)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = UnitFactory.rarity_color(cd.rarity_id)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	card.add_theme_stylebox_override("panel", sb)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	card.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pad.add_child(v)

	var name := Label.new()
	name.text = "%s • %s" % [UnitFactory.rarity_name(cd.rarity_id), cd.archetype_id]
	name.add_theme_font_size_override("font_size", 18)
	name.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1))
	v.add_child(name)

	var style_label := Label.new()
	style_label.text = "Style: %s" % ("MELEE" if cd.attack_style == CharacterData.AttackStyle.MELEE else "RANGED")
	style_label.add_theme_color_override("font_color", Color(0.78, 0.88, 1.0, 0.95))
	v.add_child(style_label)

	var stats := Label.new()
	stats.text = "HP %d  DMG %d  CD %.2f  RNG %d" % [cd.max_hp, cd.attack_damage, cd.attack_cooldown, int(cd.attack_range)]
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 0.95))
	v.add_child(stats)

	var pass_label := Label.new()
	var lines: Array[String] = []
	for pid in cd.passive_ids:
		lines.append("- %s: %s" % [PassiveSystem.passive_name(pid), PassiveSystem.passive_description(pid)])
	pass_label.text = "Passives:\n%s" % "\n".join(lines)
	pass_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pass_label.add_theme_font_size_override("font_size", 12)
	pass_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 0.95))
	v.add_child(pass_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	v.add_child(btn_row)

	var details := Button.new()
	details.text = "Details"
	btn_row.add_child(details)
	details.pressed.connect(func(): _show_character_details(cd, ui))

	var unlock := Button.new()
	unlock.text = "Unlock"
	btn_row.add_child(unlock)
	unlock.pressed.connect(func(): _select_character(cd, ui))

	return card

func _show_character_details(cd: CharacterData, ui: CanvasLayer) -> void:
	if ui.has_node("CharacterDetails"):
		ui.get_node("CharacterDetails").queue_free()
	var layer := CanvasLayer.new()
	layer.name = "CharacterDetails"
	layer.layer = 110
	layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	ui.add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -360
	panel.offset_top = -240
	panel.offset_right = 360
	panel.offset_bottom = 240
	layer.add_child(panel)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.95)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = UnitFactory.rarity_color(cd.rarity_id)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	panel.add_theme_stylebox_override("panel", sb)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)

	var t := Label.new()
	t.text = "Character Sheet"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 26)
	v.add_child(t)

	var b := Label.new()
	b.text = "%s • %s • %s\nHP %d  DMG %d  CD %.2f  RNG %d\nCrit %.0f%%  x%.2f" % [
		UnitFactory.rarity_name(cd.rarity_id),
		cd.archetype_id,
		"MELEE" if cd.attack_style == CharacterData.AttackStyle.MELEE else "RANGED",
		cd.max_hp, cd.attack_damage, cd.attack_cooldown, int(cd.attack_range),
		cd.crit_chance * 100.0, cd.crit_mult
	]
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(b)

	var p := Label.new()
	var lines: Array[String] = []
	for pid in cd.passive_ids:
		lines.append("• %s\n  %s" % [PassiveSystem.passive_name(pid), PassiveSystem.passive_description(pid)])
	p.text = "Passives:\n%s" % "\n".join(lines)
	p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(p)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): layer.queue_free())
	v.add_child(close)

func _select_character(cd: CharacterData, ui: CanvasLayer) -> void:
	# Unlock into persistent collection (NOT directly into squad).
	var cm := get_node_or_null("/root/CollectionManager")
	if cm and is_instance_valid(cm) and cm.has_method("unlock_character"):
		cm.unlock_character(cd)
	_close_draft(ui)

func _close_draft(ui: Node) -> void:
	if ui:
		ui.queue_free()
	get_tree().paused = false

func _setup_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	add_child(hud)

	var container := VBoxContainer.new()
	container.name = "HUDVBox"
	container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	container.offset_left = 18
	container.offset_top = 18
	container.add_theme_constant_override("separation", 6)
	hud.add_child(container)

	var timer := Label.new()
	timer.name = "RunTimerLabel"
	timer.text = "Time: 0:00"
	container.add_child(timer)

	var formation := Label.new()
	formation.name = "FormationLabel"
	formation.text = "Formation: TIGHT   Tactics: NEAREST"
	container.add_child(formation)

	var boss := Label.new()
	boss.name = "BossLabel"
	boss.text = ""
	container.add_child(boss)

	# Debug label to identify what is drawing the "orbs"
	var dbg := Label.new()
	dbg.name = "DebugLabel"
	dbg.text = ""
	container.add_child(dbg)

func _update_hud_labels() -> void:
	var hud := get_node_or_null("HUD/HUDVBox") as VBoxContainer
	if hud == null:
		return
	var t := get_node_or_null("HUD/HUDVBox/RunTimerLabel") as Label
	if t:
		var secs := int(round(((Time.get_ticks_msec() / 1000.0) - run_start_time)))
		var mm := int(secs / 60)
		var ss := int(secs % 60)
		t.text = "Time: %d:%02d   Essence: %d" % [mm, ss, essence]

	var b := get_node_or_null("HUD/HUDVBox/BossLabel") as Label
	if b:
		if _boss_node and is_instance_valid(_boss_node) and _boss_node.has_method("get_hp_ratio"):
			var r := float(_boss_node.get_hp_ratio())
			b.text = "Boss: %d%%" % int(round(r * 100.0))
		else:
			b.text = ""

	# Debug: count collision shapes / particles to confirm source of circles.
	var dbg := get_node_or_null("HUD/HUDVBox/DebugLabel") as Label
	if dbg:
		_dbg_cd -= get_process_delta_time()
		if _dbg_cd <= 0.0:
			_dbg_cd = 0.6
			var info := _collect_debug_counts(self)
			_dbg_text = "DBG CollisionShape2D:%d  CircleShape2D:%d  Particles:%d" % [
				int(info.get("cshape2d", 0)),
				int(info.get("circle2d", 0)),
				int(info.get("particles2d", 0))
			]
			var proj_count: int = get_tree().get_nodes_in_group("projectiles").size()
			_dbg_text += "  Projectiles:%d%s" % [proj_count, " (HIDDEN)" if _hide_projectiles else ""]
			var samples_v: Variant = info.get("circle_paths", PackedStringArray())
			var samples: PackedStringArray = samples_v if samples_v is PackedStringArray else PackedStringArray()
			if samples.size() > 0:
				_dbg_text += "\nCircles: " + ", ".join(samples)
			var details_v: Variant = info.get("circle_details", PackedStringArray())
			var details: PackedStringArray = details_v if details_v is PackedStringArray else PackedStringArray()
			if details.size() > 0:
				_dbg_text += "\nCircleSrc: " + " || ".join(details)
		dbg.text = _dbg_text

func _collect_debug_counts(root: Node) -> Dictionary:
	var cshape2d: int = 0
	var circle2d: int = 0
	var particles2d: int = 0
	var circle_paths := PackedStringArray()
	var circle_details := PackedStringArray()

	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back() as Node
		if n is CollisionShape2D:
			cshape2d += 1
			var cs := n as CollisionShape2D
			var sh := cs.shape
			if sh is CircleShape2D:
				circle2d += 1
				if circle_paths.size() < 6:
					circle_paths.append(String(cs.get_path()))
					var parent := cs.get_parent()
					var ppath: String = "<no-parent>"
					var ptype: String = "<no-parent>"
					var scr_path: String = "<no-script>"
					if parent != null:
						ppath = String(parent.get_path())
						ptype = parent.get_class()
						var scr: Script = parent.get_script() as Script
						if scr != null:
							scr_path = String(scr.resource_path)
					circle_details.append("%s | %s | %s" % [ppath, ptype, scr_path])
		elif n is GPUParticles2D or n is CPUParticles2D:
			particles2d += 1
		for ch in n.get_children():
			if ch is Node:
				stack.append(ch)

	return {
		"cshape2d": cshape2d,
		"circle2d": circle2d,
		"particles2d": particles2d,
		"circle_paths": circle_paths,
		"circle_details": circle_details
	}

func _strip_circle_collision_shapes() -> void:
	# Remove all CollisionShape2D nodes that have CircleShape2D shapes, except the RiftNode trigger.
	var stack: Array[Node] = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back() as Node
		if n is CollisionShape2D:
			var cs := n as CollisionShape2D
			var sh := cs.shape
			if sh is CircleShape2D:
				var parent := cs.get_parent()
				var keep: bool = false
				if parent != null and (parent.name == "RiftNode" or parent.get_script() == preload("res://scripts/RiftNode.gd")):
					keep = true
				if not keep:
					# One-time report so we can identify the source of @Area2D@20.
					var ppath: String = "<no-parent>"
					if parent != null:
						ppath = String(parent.get_path())
					if not _dbg_reported.has(ppath):
						_dbg_reported[ppath] = true
						var scr: Script = null
						if parent != null:
							scr = parent.get_script() as Script
						var scr_path: String = "<no-script>"
						if scr != null:
							scr_path = String(scr.resource_path)
						var ptype: String = parent.get_class() if parent != null else "<no-parent>"
						print("Stripping CircleShape2D at ", cs.get_path(), " parent=", ppath, " parent_type=", ptype, " script=", scr_path)
					cs.queue_free()
					continue
		for ch in n.get_children():
			if ch is Node:
				stack.append(ch)

func _hide_collision_debug_visuals() -> void:
	# If collision debug rendering is being forced on by the editor/run instance,
	# make all CollisionShape2D debug colors transparent so they can't show as "orbs".
	var stack: Array[Node] = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back() as Node
		if n is CollisionShape2D:
			var cs := n as CollisionShape2D
			cs.debug_color = Color(0, 0, 0, 0)
		for ch in n.get_children():
			if ch is Node:
				stack.append(ch)

	# End-of-run timer
	if _elapsed_minutes() >= run_timer_max_minutes and not _victory:
		_show_game_over()

func _show_game_over() -> void:
	_game_over = true
	get_tree().paused = true
	var ui := CanvasLayer.new()
	ui.layer = 200
	add_child(ui)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.85)
	ui.add_child(bg)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.offset_left = -220
	label.offset_right = 220
	label.offset_top = -40
	label.offset_bottom = 40
	label.text = "Run Failed"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 38)
	ui.add_child(label)

func _show_victory() -> void:
	_victory = true
	get_tree().paused = true
	var ui := CanvasLayer.new()
	ui.layer = 200
	add_child(ui)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.85)
	ui.add_child(bg)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.offset_left = -260
	label.offset_right = 260
	label.offset_top = -40
	label.offset_bottom = 40
	label.text = "Victory"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	ui.add_child(label)
