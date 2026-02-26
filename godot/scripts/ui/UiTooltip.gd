class_name UiTooltip
extends RefCounted

# Small helper to build stylized tooltips (used by TooltipButton).

static func build(bbcode_text: String, accent: Color = UiSkin.ACCENT) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(360, 0)

	panel.add_theme_stylebox_override("panel", UiSkin.tooltip_style(accent))

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(pad)

	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.scroll_active = false
	rich.fit_content = true
	rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rich.add_theme_font_size_override("normal_font_size", 12)
	rich.add_theme_color_override("default_color", UiSkin.TEXT_SOFT)
	rich.text = bbcode_text
	pad.add_child(rich)

	return panel



