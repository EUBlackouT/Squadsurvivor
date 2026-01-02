class_name UiSkin
extends Node

# Neon Protocol UI skin: centralized colors + reusable style helpers.
# Goal: keep all menus consistent without duplicating StyleBox setup per screen.

const ACCENT: Color = Color(0.40, 0.85, 1.0, 1.0)
const BG_PANEL: Color = Color(0.07, 0.08, 0.10, 0.96)
const BG_PANEL_SOFT: Color = Color(0.08, 0.09, 0.11, 0.92)
const TEXT: Color = Color(0.92, 0.95, 1.0, 1.0)
const TEXT_SOFT: Color = Color(0.82, 0.86, 0.92, 0.95)
const BORDER_SOFT: Color = Color(1, 1, 1, 0.10)

static func panel_style(accent: Color = ACCENT, strong: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_PANEL if strong else BG_PANEL_SOFT
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.18)
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 16
	return sb

static func chip_style(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.80)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	return sb

static func style_primary_button(btn: Button, accent: Color = ACCENT) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal := StyleBoxFlat.new()
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.corner_radius_bottom_right = 12
	normal.bg_color = Color(accent.r, accent.g, accent.b, 0.18)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.65)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent.r, accent.g, accent.b, 0.24)
	hover.border_color = Color(accent.r, accent.g, accent.b, 0.90)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent.r, accent.g, accent.b, 0.30)
	pressed.border_color = Color(accent.r, accent.g, accent.b, 0.98)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))

static func style_secondary_button(btn: Button, accent: Color = ACCENT) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal := StyleBoxFlat.new()
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.corner_radius_bottom_right = 12
	normal.bg_color = Color(0.08, 0.09, 0.11, 0.70)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = BORDER_SOFT

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.10, 0.11, 0.13, 0.78)
	hover.border_color = Color(accent.r, accent.g, accent.b, 0.70)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.12, 0.13, 0.16, 0.85)
	pressed.border_color = Color(accent.r, accent.g, accent.b, 0.85)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
