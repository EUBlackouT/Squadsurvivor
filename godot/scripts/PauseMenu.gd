extends CanvasLayer

# Pause menu that works while the tree is paused.

var _panel: PanelContainer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 230
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			_on_resume()

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.72)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_on_resume()
	)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -280
	_panel.offset_right = 280
	_panel.offset_top = -210
	_panel.offset_bottom = 210
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.10, 0.96)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.4, 0.8, 1.0, 0.18)
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 16
	_panel.add_theme_stylebox_override("panel", sb)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
	v.add_child(title)

	var resume := Button.new()
	resume.text = "Resume"
	resume.custom_minimum_size = Vector2(0, 44)
	resume.pressed.connect(func(): _on_resume())
	v.add_child(resume)

	var settings := Button.new()
	settings.text = "Settings"
	settings.custom_minimum_size = Vector2(0, 44)
	settings.pressed.connect(func(): _on_settings())
	v.add_child(settings)

	var save_quit := Button.new()
	save_quit.text = "Save & Quit"
	save_quit.custom_minimum_size = Vector2(0, 44)
	save_quit.pressed.connect(func(): _on_save_and_quit())
	v.add_child(save_quit)

	var quit := Button.new()
	quit.text = "Quit (No Save)"
	quit.custom_minimum_size = Vector2(0, 44)
	quit.pressed.connect(func(): _on_quit_no_save())
	v.add_child(quit)

	var hint := Label.new()
	hint.text = "Esc to resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.75, 0.80, 0.86, 0.85))
	v.add_child(hint)

func _play_ui(id: String) -> void:
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui(id)

func _on_resume() -> void:
	_play_ui("ui.pause_close")
	get_tree().paused = false
	queue_free()

func _on_settings() -> void:
	_play_ui("ui.click")
	if get_parent() != null and get_parent().has_node("SettingsMenu"):
		return
	var sm := preload("res://scripts/SettingsMenu.gd").new()
	sm.name = "SettingsMenu"
	get_parent().add_child(sm)

func _on_save_and_quit() -> void:
	_play_ui("ui.save")
	var sv := get_node_or_null("/root/SaveManager")
	var main := get_tree().get_first_node_in_group("main")
	if sv and is_instance_valid(sv) and sv.has_method("save_run"):
		sv.save_run(main)
	if sv and is_instance_valid(sv) and sv.has_method("save_meta"):
		sv.save_meta()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func _on_quit_no_save() -> void:
	_play_ui("ui.cancel")
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")


