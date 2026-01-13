class_name UiSkin
extends Node

# Neon Protocol UI skin: centralized colors + reusable style helpers.
# Goal: keep all menus consistent without duplicating StyleBox setup per screen.

const ACCENT: Color = Color(0.40, 0.85, 1.0, 1.0)
const ACCENT_PURPLE: Color = Color(0.70, 0.45, 1.0, 1.0)
const ACCENT_GOLD: Color = Color(1.0, 0.80, 0.30, 1.0)
const ACCENT_GREEN: Color = Color(0.40, 1.0, 0.65, 1.0)
const ACCENT_RED: Color = Color(1.0, 0.45, 0.40, 1.0)
const BG_PANEL: Color = Color(0.05, 0.06, 0.08, 0.98)
const BG_PANEL_SOFT: Color = Color(0.06, 0.07, 0.09, 0.95)
const BG_CARD: Color = Color(0.08, 0.09, 0.12, 0.92)
const TEXT: Color = Color(0.92, 0.95, 1.0, 1.0)
const TEXT_SOFT: Color = Color(0.75, 0.80, 0.88, 0.95)
const TEXT_DIM: Color = Color(0.55, 0.60, 0.70, 0.85)
const BORDER_SOFT: Color = Color(1, 1, 1, 0.08)
const BORDER_GLOW: Color = Color(0.40, 0.85, 1.0, 0.25)

static var _global_font_applied: bool = false
static var _cached_font: Font = null

const FONT_PATH: String = "res://assets/ui/fonts/Orbitron-VariableFont_wght.ttf"

static func apply_global_font(font_path: String = FONT_PATH, base_size: int = 14) -> void:
	# Apply a global fallback font for all UI text (labels/buttons/tooltips/etc).
	# This avoids having to set fonts per scene/control.
	if _global_font_applied:
		return
	if not ResourceLoader.exists(font_path):
		push_warning("UiSkin: Font not found at %s" % font_path)
		return
	var f: Resource = load(font_path)
	if f == null:
		push_warning("UiSkin: Failed to load font at %s" % font_path)
		return
	# Imported .ttf is typically a FontFile (inherits Font).
	if f is Font:
		_cached_font = (f as Font)
		ThemeDB.fallback_font = _cached_font
		ThemeDB.fallback_font_size = base_size
		_global_font_applied = true

static func get_font() -> Font:
	# Get the cached font for explicit use
	if _cached_font == null:
		apply_global_font()
	return _cached_font

static func style_label(lbl: Label, size: int = 14, color: Color = TEXT) -> void:
	# Convenience to style a label with our font and colors
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if _cached_font != null:
		lbl.add_theme_font_override("font", _cached_font)

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

# === ENHANCED CARD STYLES ===

static func card_style(accent: Color, glow: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_CARD
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.35)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	if glow:
		sb.shadow_size = 20
		sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.15)
	else:
		sb.shadow_size = 12
		sb.shadow_color = Color(0, 0, 0, 0.4)
	return sb

static func card_style_hover(accent: Color) -> StyleBoxFlat:
	var sb := card_style(accent, true)
	sb.bg_color = Color(BG_CARD.r + 0.02, BG_CARD.g + 0.02, BG_CARD.b + 0.03, 0.96)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.65)
	sb.shadow_size = 28
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.22)
	return sb

static func glowing_panel_style(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.98)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_left = 18
	sb.corner_radius_bottom_right = 18
	sb.shadow_size = 32
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.18)
	return sb

static func node_button_style(accent: Color, owned: bool, available: bool, is_keystone: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var radius := 22 if is_keystone else 18
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = 2 if not is_keystone else 3
	sb.border_width_right = 2 if not is_keystone else 3
	sb.border_width_top = 2 if not is_keystone else 3
	sb.border_width_bottom = 2 if not is_keystone else 3
	
	if owned:
		sb.bg_color = Color(accent.r, accent.g, accent.b, 0.25)
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.95)
		sb.shadow_size = 24
		sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.30)
	elif available:
		sb.bg_color = Color(accent.r, accent.g, accent.b, 0.12)
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
		sb.shadow_size = 16
		sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.15)
	else:
		sb.bg_color = Color(0.05, 0.06, 0.08, 0.85)
		sb.border_color = Color(0.3, 0.35, 0.4, 0.25)
		sb.shadow_size = 8
		sb.shadow_color = Color(0, 0, 0, 0.4)
	return sb

# === HOVER ANIMATION HELPERS ===

static func add_hover_scale(control: Control, scale_up: float = 1.03, duration: float = 0.12) -> void:
	if control == null:
		return
	control.pivot_offset = control.size * 0.5
	control.mouse_entered.connect(func():
		var tw: Tween = control.get_meta("_hover_tw", null) as Tween
		if tw != null and tw.is_valid():
			tw.kill()
		var t := control.create_tween()
		control.set_meta("_hover_tw", t)
		t.set_trans(Tween.TRANS_BACK)
		t.set_ease(Tween.EASE_OUT)
		t.tween_property(control, "scale", Vector2(scale_up, scale_up), duration)
	)
	control.mouse_exited.connect(func():
		var tw: Tween = control.get_meta("_hover_tw", null) as Tween
		if tw != null and tw.is_valid():
			tw.kill()
		var t := control.create_tween()
		control.set_meta("_hover_tw", t)
		t.set_trans(Tween.TRANS_SINE)
		t.set_ease(Tween.EASE_OUT)
		t.tween_property(control, "scale", Vector2.ONE, duration * 0.8)
	)

static func add_hover_glow(panel: PanelContainer, accent: Color) -> void:
	if panel == null:
		return
	var normal := card_style(accent, false)
	var hover := card_style_hover(accent)
	panel.add_theme_stylebox_override("panel", normal)
	panel.mouse_entered.connect(func():
		panel.add_theme_stylebox_override("panel", hover)
	)
	panel.mouse_exited.connect(func():
		panel.add_theme_stylebox_override("panel", normal)
	)

# === TITLE STYLING ===

static func style_section_title(label: Label, accent: Color = ACCENT) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_color_override("font_outline_color", Color(accent.r, accent.g, accent.b, 0.35))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_shadow_color", Color(accent.r, accent.g, accent.b, 0.15))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 2)

static func style_page_title(label: Label, accent: Color = ACCENT) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_shadow_color", Color(accent.r, accent.g, accent.b, 0.25))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 3)
