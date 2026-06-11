extends CanvasLayer

# Pause menu that works while the tree is paused.
# Built on the shared UiModal shell + UiComponents widgets (design system Phase 1).

var _modal: UiModal = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 229
	_build_ui()

func _build_ui() -> void:
	_modal = UiModal.build({
		"size": Vector2(560, 420),
		"accent": UiSkin.ACCENT,
		"layer": 230,
		"process_mode": Node.PROCESS_MODE_WHEN_PAUSED,
		"esc_closes": true,
		"click_outside_closes": true,
	})
	add_child(_modal)
	_modal.closed.connect(_on_resume)

	var c := _modal.content
	c.add_child(UiComponents.title("Paused", 26))

	var resume := UiComponents.menu_button("Resume", UiSkin.ACCENT, true)
	resume.pressed.connect(func(): _modal.close())
	c.add_child(resume)

	var settings := UiComponents.menu_button("Settings", UiSkin.ACCENT_PURPLE)
	settings.pressed.connect(func(): _on_settings())
	c.add_child(settings)

	var save_quit := UiComponents.menu_button("Save & Quit", UiSkin.ACCENT_GOLD)
	save_quit.pressed.connect(func(): _on_save_and_quit())
	c.add_child(save_quit)

	var quit := UiComponents.menu_button("Quit (No Save)", UiSkin.ACCENT_RED)
	quit.pressed.connect(func(): _on_quit_no_save())
	c.add_child(quit)

	c.add_child(UiComponents.hint("Esc to resume"))

func _play_ui(id: String) -> void:
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui(id)

func _on_resume() -> void:
	_play_ui("ui.pause_close")
	get_tree().paused = false
	# Let the modal finish its close animation before freeing the host layer.
	if _modal != null and is_instance_valid(_modal) and _modal.is_inside_tree():
		_modal.tree_exited.connect(queue_free)
	else:
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
