extends CanvasLayer

# Simple in-game settings menu. Build UI in code to avoid scene churn.

var _backdrop: ColorRect = null
var _panel: PanelContainer = null

var _master_slider: HSlider = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null

var _fullscreen_toggle: CheckButton = null
var _vsync_toggle: CheckButton = null
var _shake_toggle: CheckButton = null
var _shake_slider: HSlider = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 240
	_build_ui()
	_sync_from_settings()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			close()

func close() -> void:
	queue_free()

func _settings() -> Node:
	return get_node_or_null("/root/SettingsManager")

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0, 0, 0, 0.72)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_backdrop)
	_backdrop.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close()
	)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -320
	_panel.offset_right = 320
	_panel.offset_top = -260
	_panel.offset_bottom = 260
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
	v.add_theme_constant_override("separation", 12)
	pad.add_child(v)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
	v.add_child(title)

	_master_slider = _make_slider_row(v, "Master Volume", func(val: float):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("master_volume", val / 100.0)
	)
	_music_slider = _make_slider_row(v, "Music Volume", func(val: float):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("music_volume", val / 100.0)
	)
	_sfx_slider = _make_slider_row(v, "SFX Volume", func(val: float):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("sfx_volume", val / 100.0)
	)

	var sep := HSeparator.new()
	v.add_child(sep)

	_fullscreen_toggle = _make_toggle_row(v, "Fullscreen", func(on: bool):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("fullscreen", on)
	)
	_vsync_toggle = _make_toggle_row(v, "VSync", func(on: bool):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("vsync_enabled", on)
	)
	_shake_toggle = _make_toggle_row(v, "Screen Shake", func(on: bool):
		var s := _settings()
		if s and is_instance_valid(s):
			s.set("screen_shake_enabled", on)
		if _shake_slider:
			_shake_slider.editable = on
	)
	_shake_slider = _make_slider_row(v, "Shake Intensity", func(val: float):
		var s := _settings()
		if s and is_instance_valid(s):
			# 0..3 range (more expressive than 0..1)
			s.set("screen_shake_intensity", (val / 100.0) * 3.0)
	)

	var hint := Label.new()
	hint.text = "Press Esc to close"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.75, 0.80, 0.86, 0.85))
	v.add_child(hint)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(func(): close())
	v.add_child(close)

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

func _make_slider_row(parent: VBoxContainer, label_text: String, on_change: Callable) -> HSlider:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	row.add_child(top)

	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96, 0.95))
	top.add_child(l)

	var val_label := Label.new()
	val_label.text = "0%"
	val_label.add_theme_font_size_override("font_size", 13)
	val_label.add_theme_color_override("font_color", Color(0.75, 0.80, 0.86, 0.95))
	top.add_child(val_label)

	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)

	s.value_changed.connect(func(v: float):
		val_label.text = "%d%%" % int(round(v))
		on_change.call(v)
	)
	return s

func _make_toggle_row(parent: VBoxContainer, label_text: String, on_toggle: Callable) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96, 0.95))
	row.add_child(l)

	var b := CheckButton.new()
	row.add_child(b)
	b.toggled.connect(func(on: bool):
		on_toggle.call(on)
	)
	return b


