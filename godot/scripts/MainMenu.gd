extends Control

@onready var resume_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Resume") as Button
@onready var play_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Play") as Button
@onready var armory_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Armory") as Button
@onready var settings_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Settings") as Button
@onready var quit_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Quit") as Button

@onready var map_overlay: Control = get_node_or_null("MapOverlay") as Control
@onready var map_list: ItemList = get_node_or_null("MapOverlay/Panel/Pad/VBox/MapList") as ItemList
@onready var map_tagline: Label = get_node_or_null("MapOverlay/Panel/Pad/VBox/MapTagline") as Label
@onready var map_back_btn: Button = get_node_or_null("MapOverlay/Panel/Pad/VBox/Buttons/Back") as Button
@onready var map_start_btn: Button = get_node_or_null("MapOverlay/Panel/Pad/VBox/Buttons/Start") as Button

var _map_ids: Array[String] = []

func _ready() -> void:
	# Menu music
	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm) and mm.has_method("play"):
		mm.play("menu", 1.0)

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


