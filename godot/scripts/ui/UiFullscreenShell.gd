class_name UiFullscreenShell
extends Control

const _PixelUi := preload("res://scripts/ui/PixelUi.gd")

var backdrop: ColorRect
var panel: PanelContainer
var body: VBoxContainer
var title_label: Label
var subtitle_label: Label
var close_btn: Button

static func build(title: String, subtitle: String = "", accent: Color = UiSkin.ACCENT) -> UiFullscreenShell:
	UiSkin.apply_global_font()
	var shell := UiFullscreenShell.new()
	shell.name = "FullscreenShell"
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	shell._build(title, subtitle, accent)
	return shell

func _build(title: String, subtitle: String, accent: Color) -> void:
	backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.01, 0.02, 0.04, 0.90)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 22
	panel.offset_top = 16
	panel.offset_right = -22
	panel.offset_bottom = -16
	panel.add_theme_stylebox_override("panel", UiSkin.pixel_panel(accent, 0.86))
	add_child(panel)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", UiSkin.SPACE_LG)
	outer.add_theme_constant_override("margin_right", UiSkin.SPACE_LG)
	outer.add_theme_constant_override("margin_top", UiSkin.SPACE_MD)
	outer.add_theme_constant_override("margin_bottom", UiSkin.SPACE_MD)
	panel.add_child(outer)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	outer.add_child(root_v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiSkin.SPACE_MD)
	root_v.add_child(header)

	var head_v := VBoxContainer.new()
	head_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_v.add_theme_constant_override("separation", 2)
	header.add_child(head_v)

	title_label = Label.new()
	title_label.text = title.to_upper()
	UiSkin.style_label(title_label, UiSkin.FONT_H2, UiSkin.TEXT)
	head_v.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = subtitle
	subtitle_label.visible = subtitle != ""
	UiSkin.style_label(subtitle_label, UiSkin.FONT_XS, UiSkin.TEXT_SOFT)
	head_v.add_child(subtitle_label)

	close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(44, 44)
	_PixelUi.style_button(close_btn, false, UiSkin.ACCENT_RED)
	header.add_child(close_btn)

	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	root_v.add_child(body)

func animate_in() -> void:
	modulate.a = 0.0
	panel.scale = Vector2(0.98, 0.98)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, UiSkin.DUR_MED)
	tw.tween_property(panel, "scale", Vector2.ONE, UiSkin.DUR_MED) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
