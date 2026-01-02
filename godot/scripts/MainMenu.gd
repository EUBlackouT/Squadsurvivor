extends Control

@onready var resume_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Resume") as Button
@onready var play_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Play") as Button
@onready var armory_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Armory") as Button
@onready var settings_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Settings") as Button
@onready var quit_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Quit") as Button

@onready var card: Control = get_node_or_null("Root/Card") as Control
@onready var title_lbl: Label = get_node_or_null("Root/Card/Pad/VBox/Title") as Label
@onready var subtitle_lbl: Label = get_node_or_null("Root/Card/Pad/VBox/Subtitle") as Label

@onready var map_overlay: Control = get_node_or_null("MapOverlay") as Control
@onready var map_list: ItemList = get_node_or_null("MapOverlay/Panel/Pad/VBox/MapList") as ItemList
@onready var map_tagline: Label = get_node_or_null("MapOverlay/Panel/Pad/VBox/MapTagline") as Label
@onready var map_back_btn: Button = get_node_or_null("MapOverlay/Panel/Pad/VBox/Buttons/Back") as Button
@onready var map_start_btn: Button = get_node_or_null("MapOverlay/Panel/Pad/VBox/Buttons/Start") as Button

var _map_ids: Array[String] = []
var _crowd: Node2D = null

@export var game_title: String = "Squad Protocol"
@export var game_tagline: String = "Draft a squad. Survive the swarm."
@export var show_footer: bool = true
@export var footer_text: String = "v4.2 • Draft a squad • Survive the swarm"

func _ready() -> void:
	# Menu music
	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm) and mm.has_method("play"):
		mm.play("menu", 1.0)

	_spawn_menu_crowd()
	_polish_menu_ui()

	if play_btn:
		play_btn.pressed.connect(func():
			_play_ui("ui.confirm")
			_open_map_overlay()
		)

	_setup_map_select_overlay()

	# Resume run (if available)
	var sv := get_node_or_null("/root/SaveManager")
	var has := false
	if sv and is_instance_valid(sv) and sv.has_method("has_saved_run"):
		has = bool(sv.has_saved_run())
	if resume_btn:
		resume_btn.visible = has
		if has:
			resume_btn.pressed.connect(func():
				_play_ui("ui.resume_load")
				if sv and is_instance_valid(sv) and sv.has_method("request_resume"):
					if bool(sv.request_resume()):
						get_tree().change_scene_to_file("res://scenes/Main.tscn")
			)

	if armory_btn:
		armory_btn.pressed.connect(func():
			_play_ui("ui.click")
			get_tree().change_scene_to_file("res://scenes/Menu.tscn")
		)

	if settings_btn:
		settings_btn.pressed.connect(func():
			_play_ui("ui.click")
			_open_settings()
		)

	if quit_btn:
		quit_btn.pressed.connect(func():
			_play_ui("ui.cancel")
			get_tree().quit()
		)

func _setup_map_select_overlay() -> void:
	if map_list == null:
		return
	var rc := get_node_or_null("/root/RunConfig")
	if rc == null or not is_instance_valid(rc):
		return
	if rc.has_method("ensure_loaded"):
		rc.ensure_loaded()

	map_list.clear()
	_map_ids.clear()
	if rc.has_method("get_map_ids"):
		_map_ids = rc.get_map_ids()
	for i in range(_map_ids.size()):
		var m: Dictionary = rc.get_map(_map_ids[i]) if rc.has_method("get_map") else {}
		var name := String(m.get("name", _map_ids[i]))
		var tagline := String(m.get("tagline", ""))
		var mult := float(m.get("meta_sigils_mult", 1.0))
		var desc := tagline
		if desc != "":
			desc += "  "
		desc += "(x%.2f Sigils)" % mult
		map_list.add_item("%s\n%s" % [name, desc])

	# Select current
	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	for i in range(_map_ids.size()):
		if _map_ids[i] == cur:
			map_list.select(i)
			break

	_update_map_tagline(rc)

	map_list.item_selected.connect(func(idx: int):
		if idx < 0 or idx >= _map_ids.size():
			return
		var id := _map_ids[idx]
		_play_ui("ui.click")
		if rc.has_method("set_selected_map_id"):
			rc.set_selected_map_id(id)
		_update_map_tagline(rc)
	)

	if map_back_btn:
		map_back_btn.pressed.connect(func():
			_play_ui("ui.cancel")
			_close_map_overlay()
		)
	if map_start_btn:
		map_start_btn.pressed.connect(func():
			_play_ui("ui.confirm")
			_start_run_with_selected_map()
		)

func _update_map_tagline(rc: Node) -> void:
	if map_tagline == null:
		return
	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	var m: Dictionary = rc.get_map(cur) if rc.has_method("get_map") else {}
	var t := String(m.get("tagline", ""))
	var mult := float(m.get("meta_sigils_mult", 1.0))
	if t == "":
		map_tagline.text = ""
	else:
		map_tagline.text = "%s\nSigils multiplier: x%.2f" % [t, mult]

func _open_map_overlay() -> void:
	if map_overlay == null:
		# Fallback: if overlay is missing, still start the run.
		_start_run_with_selected_map()
		return
	map_overlay.visible = true
	if map_list:
		map_list.grab_focus()
	elif map_start_btn:
		map_start_btn.grab_focus()

func _close_map_overlay() -> void:
	if map_overlay == null:
		return
	map_overlay.visible = false
	if play_btn:
		play_btn.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE and map_overlay and map_overlay.visible:
			_close_map_overlay()
			get_viewport().set_input_as_handled()

func _start_run_with_selected_map() -> void:
	# RunConfig already holds selected_map_id; Main.gd reads it on _ready.
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _play_ui(id: String) -> void:
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui(id)

func _open_settings() -> void:
	if has_node("SettingsMenu"):
		return
	var sm := preload("res://scripts/SettingsMenu.gd").new()
	sm.name = "SettingsMenu"
	add_child(sm)

func _spawn_menu_crowd() -> void:
	# Fill empty space with a fun wandering crowd behind the UI.
	if _crowd != null and is_instance_valid(_crowd):
		return

	# Push backdrops behind everything so the crowd is visible but UI stays on top.
	var bd := get_node_or_null("Backdrop") as CanvasItem
	if bd:
		bd.z_index = -100
	var bds := get_node_or_null("BackdropShader") as CanvasItem
	if bds:
		bds.z_index = -90

	var c := preload("res://scripts/MainMenuCrowd.gd").new()
	c.name = "MenuCrowd"
	add_child(c)
	# Ensure it's drawn above backdrop but below Root/Card (which stays at z_index 0 by default).
	if c is CanvasItem:
		(c as CanvasItem).z_index = -50
	_crowd = c
	# Keep it behind Root in draw order.
	if has_node("Root"):
		move_child(_crowd, get_node("Root").get_index())

func _polish_menu_ui() -> void:
	# Title/subtitle (lets us rename without touching the scene file).
	if title_lbl:
		title_lbl.text = game_title
		title_lbl.add_theme_font_size_override("font_size", 52)
		title_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	if subtitle_lbl:
		subtitle_lbl.text = game_tagline
		subtitle_lbl.add_theme_font_size_override("font_size", 15)
		subtitle_lbl.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0, 0.92))

	# Card entrance: subtle slide + fade for “premium” feel.
	if card:
		card.modulate = Color(1, 1, 1, 0)
		var base := card.position
		card.position = base + Vector2(0, 18)
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "position", base, 0.22)
		tw.parallel().tween_property(card, "modulate", Color(1, 1, 1, 1), 0.22)

	# Buttons: consistent “neon” pill style, with a stronger primary (Start/Resume).
	var primary := Color(0.40, 0.85, 1.0, 1.0)
	var secondary := Color(1, 1, 1, 0.10)
	_style_button(play_btn, true, primary, secondary)
	_style_button(resume_btn, true, primary, secondary)
	_style_button(armory_btn, false, primary, secondary)
	_style_button(settings_btn, false, primary, secondary)
	_style_button(quit_btn, false, primary, secondary)

	# Footer line (small, helps communicate the loop).
	if show_footer and card and card.has_node("Pad/VBox"):
		var vb := card.get_node("Pad/VBox") as VBoxContainer
		if vb and vb.get_node_or_null("Footer") == null:
			vb.add_spacer(true)
			var ft := Label.new()
			ft.name = "Footer"
			ft.text = footer_text
			ft.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ft.add_theme_font_size_override("font_size", 12)
			ft.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 0.65))
			vb.add_child(ft)

func _style_button(btn: Button, is_primary: bool, primary: Color, secondary: Color) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal := StyleBoxFlat.new()
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.corner_radius_bottom_right = 12
	normal.bg_color = Color(primary.r, primary.g, primary.b, 0.16) if is_primary else Color(0.08, 0.09, 0.11, 0.70)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(primary.r, primary.g, primary.b, 0.55) if is_primary else secondary

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(primary.r, primary.g, primary.b, 0.22) if is_primary else Color(0.10, 0.11, 0.13, 0.78)
	hover.border_color = Color(primary.r, primary.g, primary.b, 0.85)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(primary.r, primary.g, primary.b, 0.28) if is_primary else Color(0.12, 0.13, 0.16, 0.85)
	pressed.border_color = Color(primary.r, primary.g, primary.b, 0.95)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))


