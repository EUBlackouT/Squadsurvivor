extends CanvasLayer

# In-game settings menu, used from MainMenu, Menu, and PauseMenu.
# Built on the shared UiModal shell + UiComponents widgets (design system Phase 1).

var _modal: UiModal = null

var _master_slider: HSlider = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null

var _fullscreen_toggle: CheckButton = null
var _vsync_toggle: CheckButton = null
var _shake_toggle: CheckButton = null
var _shake_slider: HSlider = null

func _ready() -> void:
	# Always active; this menu is used both in MainMenu and while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 239
	_build_ui()
	_sync_from_settings()

func close() -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.close()
	else:
		queue_free()

func _settings() -> Node:
	return get_node_or_null("/root/SettingsManager")

func _build_ui() -> void:
	_modal = UiModal.build({
		"size": Vector2(640, 520),
		"accent": UiSkin.ACCENT,
		"layer": 240,
		"process_mode": Node.PROCESS_MODE_ALWAYS,
		"esc_closes": true,
		"click_outside_closes": true,
	})
	add_child(_modal)
	_modal.closed.connect(func():
		# Free the host layer once the modal has animated out.
		if _modal.is_inside_tree():
			_modal.tree_exited.connect(queue_free)
		else:
			queue_free()
	)

	var c := _modal.content

	var title := UiComponents.title("Settings", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	c.add_child(title)

	_master_slider = UiComponents.slider_row(c, "Master Volume", func(val: float):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("master_volume", val / 100.0)
	)
	_music_slider = UiComponents.slider_row(c, "Music Volume", func(val: float):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("music_volume", val / 100.0)
	)
	_sfx_slider = UiComponents.slider_row(c, "SFX Volume", func(val: float):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("sfx_volume", val / 100.0)
	)

	c.add_child(UiComponents.separator())

	_fullscreen_toggle = UiComponents.toggle_row(c, "Fullscreen", func(on: bool):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("fullscreen", on)
	)
	_vsync_toggle = UiComponents.toggle_row(c, "VSync", func(on: bool):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("vsync_enabled", on)
	)
	_shake_toggle = UiComponents.toggle_row(c, "Screen Shake", func(on: bool):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("screen_shake_enabled", on)
		if _shake_slider:
			_shake_slider.editable = on
	)
	_shake_slider = UiComponents.slider_row(c, "Shake Intensity", func(val: float):
		var s := _settings()
		if s and is_instance_valid(s):
			# 0..3 range (more expressive than 0..1)
			s.set("screen_shake_intensity", (val / 100.0) * 3.0)
	)

	c.add_child(UiComponents.hint("Press Esc to close"))

	var close_btn := UiComponents.menu_button("Close", UiSkin.ACCENT, true)
	close_btn.pressed.connect(func(): close())
	c.add_child(close_btn)

func _sync_from_settings() -> void:
	var s := _settings()
	if s == null or not is_instance_valid(s):
		return
	if _master_slider: _master_slider.value = float(s.get("master_volume")) * 100.0
	if _music_slider: _music_slider.value = float(s.get("music_volume")) * 100.0
	if _sfx_slider: _sfx_slider.value = float(s.get("sfx_volume")) * 100.0
	if _fullscreen_toggle: _fullscreen_toggle.button_pressed = bool(s.get("fullscreen"))
	if _vsync_toggle: _vsync_toggle.button_pressed = bool(s.get("vsync_enabled"))
	if _shake_toggle: _shake_toggle.button_pressed = bool(s.get("screen_shake_enabled"))
	if _shake_slider:
		var v := float(s.get("screen_shake_intensity"))
		_shake_slider.value = clampf(v / 3.0, 0.0, 1.0) * 100.0
		_shake_slider.editable = bool(s.get("screen_shake_enabled"))
