extends Control

@onready var resume_btn: Button = get_node_or_null("Root/Card/VBox/Resume") as Button
@onready var map_select: OptionButton = get_node_or_null("Root/Card/VBox/MapSelect") as OptionButton
@onready var map_tagline: Label = get_node_or_null("Root/Card/VBox/MapTagline") as Label
@onready var play_btn: Button = get_node_or_null("Root/Card/VBox/Play") as Button
@onready var armory_btn: Button = get_node_or_null("Root/Card/VBox/Armory") as Button
@onready var settings_btn: Button = get_node_or_null("Root/Card/VBox/Settings") as Button
@onready var quit_btn: Button = get_node_or_null("Root/Card/VBox/Quit") as Button

func _ready() -> void:
	# Menu music
	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm) and mm.has_method("play"):
		mm.play("menu", 0.35)

	if play_btn:
		play_btn.pressed.connect(func():
			_play_ui("ui.confirm")
			get_tree().change_scene_to_file("res://scenes/Main.tscn")
		)

	_setup_map_select()

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

func _setup_map_select() -> void:
	if map_select == null:
		return
	var rc := get_node_or_null("/root/RunConfig")
	if rc == null or not is_instance_valid(rc):
		return
	if rc.has_method("ensure_loaded"):
		rc.ensure_loaded()

	map_select.clear()
	var ids: Array[String] = []
	if rc.has_method("get_map_ids"):
		ids = rc.get_map_ids()
	for i in range(ids.size()):
		var m: Dictionary = rc.get_map(ids[i]) if rc.has_method("get_map") else {}
		var name := String(m.get("name", ids[i]))
		map_select.add_item(name, i)
		map_select.set_item_metadata(i, ids[i])

	# Select current
	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	for i in range(map_select.item_count):
		if String(map_select.get_item_metadata(i)) == cur:
			map_select.select(i)
			break

	_update_map_tagline(rc)

	map_select.item_selected.connect(func(idx: int):
		var id := String(map_select.get_item_metadata(idx))
		_play_ui("ui.click")
		if rc.has_method("set_selected_map_id"):
			rc.set_selected_map_id(id)
		_update_map_tagline(rc)
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


