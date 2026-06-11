class_name UiComponents
extends RefCounted

# Shared widget factory: the layer above UiSkin styleboxes.
# Every menu/modal/draft screen should build common widgets through here
# instead of hand-rolling Label/Button/chip styling per file.

static func title(text: String, size: int = UiSkin.FONT_H2, color: Color = UiSkin.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSkin.style_label(l, size, color)
	return l

static func body_label(text: String, color: Color = UiSkin.TEXT_SOFT) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSkin.style_label(l, UiSkin.FONT_BODY, color)
	return l

static func hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSkin.style_label(l, UiSkin.FONT_XS, UiSkin.TEXT_DIM)
	return l

static func menu_button(text: String, accent: Color = UiSkin.ACCENT, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, UiSkin.BUTTON_HEIGHT)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	if primary:
		UiSkin.style_primary_button(b, accent)
	else:
		UiSkin.style_secondary_button(b, accent)
	return b

static func chip(text: String, accent: Color = UiSkin.ACCENT, font_size: int = UiSkin.FONT_SM) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiSkin.chip_style(accent))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", UiSkin.SPACE_SM)
	pad.add_theme_constant_override("margin_right", UiSkin.SPACE_SM)
	pad.add_theme_constant_override("margin_top", UiSkin.SPACE_XS)
	pad.add_theme_constant_override("margin_bottom", UiSkin.SPACE_XS)
	p.add_child(pad)
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSkin.style_label(l, font_size, UiSkin.TEXT_SOFT)
	pad.add_child(l)
	return p

static func separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep

# Labeled slider row (0..100 with live % readout). Returns the slider.
static func slider_row(parent: Container, label_text: String, on_change: Callable) -> HSlider:
	var row := VBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", UiSkin.SPACE_XS)
	parent.add_child(row)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_theme_constant_override("separation", UiSkin.SPACE_MD)
	row.add_child(top)

	var l := body_label(label_text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)

	var val_label := Label.new()
	val_label.text = "0%"
	val_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSkin.style_label(val_label, UiSkin.FONT_SM, UiSkin.TEXT_DIM)
	top.add_child(val_label)

	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.editable = true
	s.mouse_filter = Control.MOUSE_FILTER_STOP
	s.focus_mode = Control.FOCUS_ALL
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiSkin.style_slider(s)
	row.add_child(s)

	s.value_changed.connect(func(v: float):
		val_label.text = "%d%%" % int(round(v))
		on_change.call(v)
	)
	return s

# Labeled toggle row. Returns the CheckButton.
static func toggle_row(parent: Container, label_text: String, on_toggle: Callable) -> CheckButton:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", UiSkin.SPACE_MD)
	parent.add_child(row)

	var l := body_label(label_text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)

	var b := CheckButton.new()
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiSkin.style_toggle(b)
	row.add_child(b)
	b.toggled.connect(func(on: bool):
		on_toggle.call(on)
	)
	return b
