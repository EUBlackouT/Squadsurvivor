class_name UiSkin
extends Node

# Fun Arcade UI skin: centralized colors + reusable style helpers.
# Goal: keep all menus consistent without duplicating StyleBox setup per screen.

# Warm stone / gem palette — matches map tile art, not sci-fi HUD teal.
const ACCENT: Color = Color(0.58, 0.76, 0.62, 1.0) # jade moss
const ACCENT_PURPLE: Color = Color(0.70, 0.56, 0.82, 1.0) # reliquary violet
const ACCENT_GOLD: Color = Color(0.90, 0.72, 0.38, 1.0) # cathedral gold
const ACCENT_GREEN: Color = Color(0.50, 0.80, 0.52, 1.0)
const ACCENT_RED: Color = Color(0.88, 0.46, 0.40, 1.0)
const BG_PANEL: Color = Color(0.10, 0.08, 0.11, 0.96)
const BG_PANEL_SOFT: Color = Color(0.12, 0.10, 0.13, 0.94)
const BG_CARD: Color = Color(0.14, 0.11, 0.15, 0.92)
const TEXT: Color = Color(0.94, 0.90, 0.82, 1.0)
const TEXT_SOFT: Color = Color(0.80, 0.76, 0.68, 0.96)
const TEXT_DIM: Color = Color(0.56, 0.52, 0.48, 0.90)
const BORDER_SOFT: Color = Color(0.94, 0.88, 0.78, 0.14)
const BORDER_GLOW: Color = Color(0.58, 0.76, 0.62, 0.28)

# === DESIGN TOKENS (Phase 1 foundation) ===
# Spacing scale: use these instead of magic numbers in margins/separations.
const SPACE_XS: int = 4
const SPACE_SM: int = 8
const SPACE_MD: int = 12
const SPACE_LG: int = 18
const SPACE_XL: int = 28

# Typography scale tuned for Press Start 2P (pixel font reads small — bump sizes).
const FONT_XS: int = 10
const FONT_SM: int = 11
const FONT_BODY: int = 12
const FONT_LEAD: int = 13
const FONT_H3: int = 14
const FONT_H2: int = 16
const FONT_H1: int = 20

# Corner radius scale.
const RADIUS_SM: int = 8
const RADIUS_MD: int = 12
const RADIUS_LG: int = 18

# Motion durations: keep all UI animation timing consistent.
const DUR_FAST: float = 0.12
const DUR_MED: float = 0.22
const DUR_SLOW: float = 0.35

# Standard modal backdrop dim (single convention across all modals).
const BACKDROP_DIM: Color = Color(0, 0, 0, 0.72)
# Standard control heights.
const BUTTON_HEIGHT: int = 44

# Shared race identity palette (map cards, draft chips, codex).
const RACE_COLORS: Dictionary = {
	"HUMANOID": Color("d9c08c"), "MACHINE": Color("8cd9f2"), "ALIEN": Color("99f28c"),
	"MUTANT": Color("ccf266"), "FAE": Color("f299e6"), "ELEMENTAL": Color("73b3ff"),
	"SHADOWBORN": Color("9e80e6"), "DRACONIC": Color("ff8c66"), "CELESTIAL": Color("ffd973"),
	"CRYSTALLINE": Color("99f2e6"), "AQUATIC": Color("66ccff"), "PLANTOID": Color("80e680"),
	"SLIMEKIN": Color("99f2b3"), "INSECTOID": Color("ccb34d"), "UNDEAD": Color("b3ccb3"),
}

static func race_color(race_id: String) -> Color:
	return RACE_COLORS.get(race_id.to_upper(), Color("a8b8c8"))

static func race_hex(race_id: String) -> String:
	return "#" + race_color(race_id).to_html(false)

const PANEL_FRAME_PATH: String = "res://assets/ui/kit/panel_frame.webp"
const BUTTON_PRIMARY_PATH: String = "res://assets/ui/kit/button_primary.webp"
const BUTTON_SECONDARY_PATH: String = "res://assets/ui/kit/button_secondary.webp"
const CHIP_PATH: String = "res://assets/ui/kit/chip.webp"
const BAR_FRAME_PATH: String = "res://assets/ui/kit/bar_frame.webp"
const BAR_FILL_PATH: String = "res://assets/ui/kit/bar_fill.webp"
const TOOLTIP_PATH: String = "res://assets/ui/kit/tooltip.webp"
const CARD_FRAME_PATH: String = "res://assets/ui/kit/card_frame.webp"
const TOGGLE_ON_PATH: String = "res://assets/ui/kit/toggle_on.webp"
const TOGGLE_OFF_PATH: String = "res://assets/ui/kit/toggle_off.webp"
const SLIDER_TRACK_PATH: String = "res://assets/ui/kit/slider_track.webp"
const SLIDER_FILL_PATH: String = "res://assets/ui/kit/slider_fill.webp"
const SLIDER_KNOB_PATH: String = "res://assets/ui/kit/slider_knob.webp"

const USE_TEXTURE_KIT: bool = false

static var _global_font_applied: bool = false
static var _applied_font_path: String = ""
static var _cached_font: Font = null

const FONT_PATH: String = "res://assets/ui/fonts/PressStart2P-Regular.ttf"
const FONT_PATH_DISPLAY: String = "res://assets/ui/fonts/Orbitron-VariableFont_wght.ttf"

static func apply_global_font(font_path: String = FONT_PATH, base_size: int = 12) -> void:
	if _global_font_applied and _applied_font_path == font_path:
		return
	if not ResourceLoader.exists(font_path):
		push_warning("UiSkin: Font not found at %s — trying fallback" % font_path)
		font_path = FONT_PATH_DISPLAY if ResourceLoader.exists(FONT_PATH_DISPLAY) else font_path
	if not ResourceLoader.exists(font_path):
		return
	var f: Resource = load(font_path)
	if f == null and font_path != FONT_PATH_DISPLAY and ResourceLoader.exists(FONT_PATH_DISPLAY):
		font_path = FONT_PATH_DISPLAY
		f = load(font_path)
	if f == null:
		push_warning("UiSkin: Failed to load font at %s" % font_path)
		return
	if f is Font:
		_cached_font = (f as Font)
		ThemeDB.fallback_font = _cached_font
		ThemeDB.fallback_font_size = base_size
		_applied_font_path = font_path
		_global_font_applied = true

static func get_font() -> Font:
	# Get the cached font for explicit use
	if _cached_font == null:
		apply_global_font()
	return _cached_font

static func style_label(lbl: Label, size: int = 14, color: Color = TEXT) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if size >= 12:
		lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.05, 0.95))
		lbl.add_theme_constant_override("outline_size", 2 if size >= 16 else 1)
	if _cached_font != null:
		lbl.add_theme_font_override("font", _cached_font)
	lbl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

static func panel_style(accent: Color = ACCENT, strong: bool = false) -> StyleBox:
	var tex := _maybe_stylebox_texture(PANEL_FRAME_PATH, 30, 20)
	if tex != null:
		return tex
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_PANEL if strong else BG_PANEL_SOFT
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.30)
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_left = 18
	sb.corner_radius_bottom_right = 18
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 18
	return sb

static func chip_style(accent: Color) -> StyleBox:
	var tex := _maybe_stylebox_texture(CHIP_PATH, 12, 6)
	if tex != null:
		return tex
	var sb := pixel_inset(0.94)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(accent.r * 0.55 + 0.22, accent.g * 0.55 + 0.22, accent.b * 0.55 + 0.22, 0.82)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

static func style_primary_button(btn: Button, accent: Color = ACCENT) -> void:
	if btn == null:
		return
	if not USE_TEXTURE_KIT:
		style_pixel_primary_button(btn, accent)
		return
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var tex := _maybe_stylebox_texture(BUTTON_PRIMARY_PATH, 22, 14)
	if tex != null:
		btn.add_theme_stylebox_override("normal", tex)
		btn.add_theme_stylebox_override("hover", tex)
		btn.add_theme_stylebox_override("pressed", tex)
		btn.add_theme_stylebox_override("focus", tex)
		btn.add_theme_color_override("font_color", Color(0.05, 0.08, 0.12, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.05, 0.08, 0.12, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.05, 0.08, 0.12, 1.0))
		return

	var normal := StyleBoxFlat.new()
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.corner_radius_bottom_right = 12
	normal.bg_color = Color(accent.r, accent.g, accent.b, 0.45)
	normal.border_width_left = 3
	normal.border_width_right = 3
	normal.border_width_top = 3
	normal.border_width_bottom = 3
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.85)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent.r, accent.g, accent.b, 0.55)
	hover.border_color = Color(accent.r, accent.g, accent.b, 0.98)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent.r, accent.g, accent.b, 0.68)
	pressed.border_color = Color(accent.r, accent.g, accent.b, 1.0)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(0.08, 0.10, 0.12, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.10, 0.12, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.08, 0.10, 0.12, 1))

static func style_secondary_button(btn: Button, accent: Color = ACCENT) -> void:
	if btn == null:
		return
	if not USE_TEXTURE_KIT:
		style_pixel_secondary_button(btn, accent)
		return
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var tex := _maybe_stylebox_texture(BUTTON_SECONDARY_PATH, 22, 14)
	if tex != null:
		btn.add_theme_stylebox_override("normal", tex)
		btn.add_theme_stylebox_override("hover", tex)
		btn.add_theme_stylebox_override("pressed", tex)
		btn.add_theme_stylebox_override("focus", tex)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1.0))
		return

	var normal := StyleBoxFlat.new()
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.corner_radius_bottom_right = 12
	normal.bg_color = Color(0.12, 0.16, 0.20, 0.85)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.35)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.20, 0.24, 0.90)
	hover.border_color = Color(accent.r, accent.g, accent.b, 0.65)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.20, 0.24, 0.28, 0.95)
	pressed.border_color = Color(accent.r, accent.g, accent.b, 0.85)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.add_theme_color_override("font_pressed_color", TEXT)

# === ENHANCED CARD STYLES ===

static func card_style(accent: Color, glow: bool = false) -> StyleBox:
	var tex := _maybe_stylebox_texture(CARD_FRAME_PATH, 22, 12)
	if tex != null:
		return tex
	if not USE_TEXTURE_KIT:
		return pixel_card(accent, false)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_CARD
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	if glow:
		sb.shadow_size = 26
		sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.22)
	else:
		sb.shadow_size = 16
		sb.shadow_color = Color(0, 0, 0, 0.45)
	return sb

static func card_style_hover(accent: Color) -> StyleBox:
	if not USE_TEXTURE_KIT:
		return pixel_card(accent, true)
	var sb := card_style(accent, true)
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		flat.bg_color = Color(BG_CARD.r + 0.02, BG_CARD.g + 0.02, BG_CARD.b + 0.03, 0.96)
		flat.border_color = Color(accent.r, accent.g, accent.b, 0.65)
		flat.shadow_size = 28
		flat.shadow_color = Color(accent.r, accent.g, accent.b, 0.22)
		return flat
	return sb

static func glowing_panel_style(accent: Color) -> StyleBox:
	return pixel_panel(accent, 0.84)

## Sharp-edged HUD panels that sit next to pixel sprites (no sci-fi glow/radius).
static func pixel_panel(accent: Color, bg_alpha: float = 0.84) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.09, bg_alpha)
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	var edge := Color(
		accent.r * 0.35 + 0.18,
		accent.g * 0.35 + 0.18,
		accent.b * 0.35 + 0.20,
		0.88)
	sb.border_color = edge
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_size = 0
	sb.anti_aliasing = false
	return sb

static func pixel_inset(alpha: float = 0.90) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.07, alpha)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.30, 0.28, 0.34, 0.72)
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	return sb

static func pixel_card(accent: Color, selected: bool = false) -> StyleBoxFlat:
	var sb := pixel_inset(0.90 if selected else 0.82)
	sb.border_width_left = 3 if selected else 2
	sb.border_width_right = 3 if selected else 2
	sb.border_width_top = 3 if selected else 2
	sb.border_width_bottom = 3 if selected else 2
	sb.border_color = Color(
		accent.r * 0.55 + 0.20,
		accent.g * 0.55 + 0.20,
		accent.b * 0.55 + 0.22,
		0.95 if selected else 0.55)
	return sb

static func style_pixel_primary_button(btn: Button, accent: Color = ACCENT_GOLD) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var n := pixel_inset(1.0)
	n.bg_color = Color(accent.r, accent.g, accent.b, 0.88)
	n.border_color = Color(accent.r * 0.6, accent.g * 0.6, accent.b * 0.6, 1.0)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(accent.r, accent.g, accent.b, 1.0)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = Color(accent.r * 0.85, accent.g * 0.85, accent.b * 0.85, 1.0)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("focus", h)
	btn.add_theme_color_override("font_color", Color(0.08, 0.06, 0.05, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.05, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.08, 0.06, 0.05, 1.0))
	if _cached_font != null:
		btn.add_theme_font_override("font", _cached_font)

static func style_pixel_secondary_button(btn: Button, accent: Color = ACCENT) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var n := pixel_inset(0.94)
	n.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.06, 0.06, 0.09, 0.98)
	h.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.add_theme_stylebox_override("focus", h)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.add_theme_color_override("font_pressed_color", TEXT)
	if _cached_font != null:
		btn.add_theme_font_override("font", _cached_font)

static func glowing_panel_style_legacy(accent: Color) -> StyleBox:
	var tex := _maybe_stylebox_texture(PANEL_FRAME_PATH, 30, 20)
	if tex != null:
		return tex
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.14, 0.18, 0.98)
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.corner_radius_top_left = 20
	sb.corner_radius_top_right = 20
	sb.corner_radius_bottom_left = 20
	sb.corner_radius_bottom_right = 20
	sb.shadow_size = 34
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.22)
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
		if control.has_meta("_hover_tw"):
			var tw: Tween = control.get_meta("_hover_tw") as Tween
			if tw != null and tw.is_valid():
				tw.kill()
		var t := control.create_tween()
		control.set_meta("_hover_tw", t)
		t.set_trans(Tween.TRANS_BACK)
		t.set_ease(Tween.EASE_OUT)
		t.tween_property(control, "scale", Vector2(scale_up, scale_up), duration)
	)
	control.mouse_exited.connect(func():
		if control.has_meta("_hover_tw"):
			var tw: Tween = control.get_meta("_hover_tw") as Tween
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

static func style_progress_bar(bar: ProgressBar) -> void:
	if bar == null:
		return
	var frame := _maybe_stylebox_texture(BAR_FRAME_PATH, 18, 8)
	var fill := _maybe_stylebox_texture(BAR_FILL_PATH, 18, 8)
	if frame != null:
		bar.add_theme_stylebox_override("background", frame)
	if fill != null:
		bar.add_theme_stylebox_override("fill", fill)
	if frame == null:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.08, 0.12, 0.15, 0.95)
		bg.border_width_left = 2
		bg.border_width_right = 2
		bg.border_width_top = 2
		bg.border_width_bottom = 2
		bg.border_color = BORDER_SOFT
		bg.corner_radius_top_left = 8
		bg.corner_radius_top_right = 8
		bg.corner_radius_bottom_left = 8
		bg.corner_radius_bottom_right = 8
		bar.add_theme_stylebox_override("background", bg)
	if fill == null:
		var fg := StyleBoxFlat.new()
		fg.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85)
		fg.corner_radius_top_left = 8
		fg.corner_radius_top_right = 8
		fg.corner_radius_bottom_left = 8
		fg.corner_radius_bottom_right = 8
		bar.add_theme_stylebox_override("fill", fg)

static func style_toggle(btn: CheckButton) -> void:
	if btn == null:
		return
	var on_tex := _maybe_texture(TOGGLE_ON_PATH)
	var off_tex := _maybe_texture(TOGGLE_OFF_PATH)
	if on_tex != null:
		btn.add_theme_icon_override("checked", on_tex)
	if off_tex != null:
		btn.add_theme_icon_override("unchecked", off_tex)
	btn.add_theme_constant_override("h_separation", 8)
	if on_tex == null or off_tex == null:
		var normal := chip_style(ACCENT)
		var hover := chip_style(ACCENT_GOLD)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		btn.add_theme_color_override("font_color", TEXT)

static func style_slider(slider: HSlider) -> void:
	if slider == null:
		return
	var track := _maybe_stylebox_texture(SLIDER_TRACK_PATH, 12, 4)
	var fill := _maybe_stylebox_texture(SLIDER_FILL_PATH, 12, 4)
	var knob := _maybe_texture(SLIDER_KNOB_PATH)
	if track != null:
		slider.add_theme_stylebox_override("slider", track)
	if fill != null:
		slider.add_theme_stylebox_override("grabber_area", fill)
	if knob != null:
		slider.add_theme_icon_override("grabber", knob)
		slider.add_theme_icon_override("grabber_highlight", knob)
	slider.add_theme_constant_override("grabber_offset", 0)
	if track == null:
		var t := StyleBoxFlat.new()
		t.bg_color = Color(0.10, 0.14, 0.18, 0.95)
		t.corner_radius_top_left = 6
		t.corner_radius_top_right = 6
		t.corner_radius_bottom_left = 6
		t.corner_radius_bottom_right = 6
		slider.add_theme_stylebox_override("slider", t)
	if fill == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85)
		f.corner_radius_top_left = 6
		f.corner_radius_top_right = 6
		f.corner_radius_bottom_left = 6
		f.corner_radius_bottom_right = 6
		slider.add_theme_stylebox_override("grabber_area", f)

static func inset_style(radius: int = RADIUS_MD, alpha: float = 0.86, surface: Color = Color(0.04, 0.06, 0.10, 1.0), border: Color = Color(0.50, 0.74, 1.0, 0.28)) -> StyleBoxFlat:
	if not USE_TEXTURE_KIT:
		var sb := pixel_inset(alpha)
		sb.border_color = Color(border.r, border.g, border.b, border.a * 0.85)
		return sb
	# Dark readable inset surface for lists/previews inside larger panels.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(surface.r, surface.g, surface.b, alpha)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = border
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

static func list_selected_style(accent: Color = ACCENT) -> StyleBoxFlat:
	var sb := pixel_inset(0.92)
	sb.bg_color = Color(accent.r * 0.25, accent.g * 0.25, accent.b * 0.25, 0.55)
	sb.border_width_left = 3
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	return sb

static func tooltip_style(accent: Color = ACCENT) -> StyleBox:
	var tex := _maybe_stylebox_texture(TOOLTIP_PATH, 18, 12)
	if tex != null:
		return tex
	return pixel_panel(accent, 0.94)

static func _maybe_texture(path: String) -> Texture2D:
	if not USE_TEXTURE_KIT:
		return null
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	return tex

static func _maybe_stylebox_texture(path: String, tex_margin: int, content_margin: int) -> StyleBoxTexture:
	if not USE_TEXTURE_KIT:
		return null
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = tex_margin
	sb.texture_margin_right = tex_margin
	sb.texture_margin_top = tex_margin
	sb.texture_margin_bottom = tex_margin
	sb.content_margin_left = content_margin
	sb.content_margin_right = content_margin
	sb.content_margin_top = content_margin
	sb.content_margin_bottom = content_margin
	return sb
