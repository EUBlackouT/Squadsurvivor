class_name UiTooltip
extends RefCounted

# Small helper to build stylized tooltips (used by TooltipButton).

static func build(bbcode_text: String, accent: Color = UiSkin.ACCENT) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(360, 0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.96)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.shadow_size = 14
	sb.shadow_color = Color(0, 0, 0, 0.65)
	panel.add_theme_stylebox_override("panel", sb)

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


