extends Control

# Main Menu - fantasy meadow theme with animated layered backdrop.
# Behavior (scene changes, signals, logic) stays the same.

var _menu_root: Control
var _card: PanelContainer
var _play_btn: Button
var _resume_btn: Button
var _armory_btn: Button
var _protocol_btn: Button
var _info_btn: Button
var _settings_btn: Button
var _quit_btn: Button

var _map_overlay: Control
var _map_list: ItemList
var _map_preview_vp: SubViewport
var _map_tagline: Label
var _map_details: RichTextLabel
var _map_back_btn: Button
var _map_start_btn: Button
var _map_panel: PanelContainer

# Map overlay extra refs
var _map_preview_lock_lbl: Label = null
var _map_list_frame: PanelContainer = null
var _map_details_frame: PanelContainer = null

var _map_ids: Array[String] = []
var _crowd: Node2D = null
var _preview_root: Node = null
var _selected_map_locked: bool = false
var _bg_far: TextureRect = null
var _bg_near: TextureRect = null
var _bg_light: ColorRect = null
var _menu_anim_t: float = 0.0

var _crowd_prev_visible: bool = true
var _crowd_prev_process_mode: int = Node.PROCESS_MODE_INHERIT

var _info_overlay: Control = null
var _info_search: LineEdit = null
var _info_section: OptionButton = null
var _info_list: ItemList = null
var _info_details: RichTextLabel = null
var _info_hint: Label = null
var _info_entries: Array[Dictionary] = []

@export var game_title: String = "Character Collection"
@export var game_tagline: String = "Collect • Upgrade • Build your dream team"
@export var footer_text: String = "v0.1 • Cozy collection run"

# ─────────────────────────────────────────────────────────────────────────────
# ASSETS (put the generated PNGs here)
# ─────────────────────────────────────────────────────────────────────────────
const BG_PATH: String = "res://assets/ui/meadow_menu/bg_meadow_base.webp"
const BG_NEAR_PATH: String = "res://assets/ui/meadow_menu/bg_meadow_foreground.webp"
const ASSET_PANEL: String = "res://assets/ui/meadow_menu/panel_ornate.webp"

const BTN_NORMAL: String = "res://assets/ui/meadow_menu/button_normal.webp"
const BTN_HOVER: String = "res://assets/ui/meadow_menu/button_hover.webp"
const BTN_PRESSED: String = "res://assets/ui/meadow_menu/button_pressed.webp"
const BTN_DISABLED: String = "res://assets/ui/meadow_menu/button_disabled.webp"

const TAB_NORMAL: String = "res://assets/ui/wood_menu/tab_wood_normal_384x128.png"
const TAB_HOVER: String = "res://assets/ui/wood_menu/tab_wood_hover_384x128.png"
const TAB_PRESSED: String = "res://assets/ui/wood_menu/tab_wood_pressed_384x128.png"

# Keep your existing font pipeline; swap FONT_PATH if you have a pixel font.
const FONT_PATH: String = "res://assets/ui/fonts/Orbitron-VariableFont_wght.ttf"

# Optional intro splash if you still use it (safe to ignore if not present)
const INTRO_BG_PATH: String = ""
const USE_UI_MOCKUPS: bool = false

# ─────────────────────────────────────────────────────────────────────────────
# COLORS (fallback / text)
# ─────────────────────────────────────────────────────────────────────────────
const TITLE_COLOR: Color = Color(1.0, 0.96, 0.86, 1.0)
const SUBTITLE_COLOR: Color = Color(0.96, 0.92, 0.82, 0.92)
const TEXT_DARK: Color = Color(0.12, 0.08, 0.06, 1.0)

const ACCENT_LEAF: Color = Color(0.42, 0.86, 0.52, 1.0)
const ACCENT_SUN: Color = Color(1.0, 0.83, 0.44, 1.0)
const ACCENT_BERRY: Color = Color(0.86, 0.55, 0.88, 1.0)

# Readability surfaces for map overlay
const SURFACE_BG := Color(0.07, 0.06, 0.05, 0.90)
const SURFACE_BG_SOFT := Color(0.06, 0.05, 0.04, 0.82)
const SURFACE_BORDER := Color(1, 1, 1, 0.12)
const LOCKED_FG := Color(0.90, 0.86, 0.76, 0.45)
const NORMAL_FG := Color(0.98, 0.96, 0.90, 1.0)

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# If UiSkin exists in your project, keep using it.
	# If you want pure pixel readability, swap FONT_PATH to your pixel font.
	UiSkin.apply_global_font(FONT_PATH, 14)

	_menu_root = get_node_or_null("MenuRoot")
	if _menu_root == null:
		_menu_root = self

	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)

	_apply_menu_art()
	_play_intro_splash()

	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm) and mm.has_method("play"):
		mm.play("menu", 1.0)

	_build_menu()
	_build_map_overlay()
	_connect_signals()

func _process(delta: float) -> void:
	_menu_anim_t += delta
	if _bg_far != null and is_instance_valid(_bg_far):
		_bg_far.position = Vector2(
			sin(_menu_anim_t * 0.10) * 18.0,
			cos(_menu_anim_t * 0.07) * 6.0
		)
	if _bg_near != null and is_instance_valid(_bg_near):
		_bg_near.position = Vector2(
			sin(_menu_anim_t * 0.22 + 1.3) * 34.0,
			cos(_menu_anim_t * 0.16 + 0.4) * 10.0
		)
	if _bg_light != null and is_instance_valid(_bg_light):
		_bg_light.modulate.a = 0.26 + sin(_menu_anim_t * 0.32) * 0.07
	if _card != null and is_instance_valid(_card):
		_card.rotation = sin(_menu_anim_t * 0.42) * 0.004

func _apply_menu_art() -> void:
	var bg := get_node_or_null("MenuBackground") as TextureRect
	if bg == null:
		bg = TextureRect.new()
		bg.name = "MenuBackground"
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.z_index = -220
		add_child(bg)
		move_child(bg, 0)
	_bg_far = bg

	var t := _load_tex(BG_PATH)
	if t == null:
		push_error("MainMenu: BG texture missing: " + BG_PATH)
	_bg_far.texture = t

	var near := get_node_or_null("MenuBackgroundNear") as TextureRect
	if near == null:
		near = TextureRect.new()
		near.name = "MenuBackgroundNear"
		near.set_anchors_preset(Control.PRESET_FULL_RECT)
		near.mouse_filter = Control.MOUSE_FILTER_IGNORE
		near.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		near.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		near.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		near.z_index = -210
		near.modulate = Color(1, 1, 1, 0.68)
		add_child(near)
		move_child(near, 1)
	_bg_near = near
	_bg_near.texture = _load_tex(BG_NEAR_PATH)

	var light := get_node_or_null("MenuSunwash") as ColorRect
	if light == null:
		light = ColorRect.new()
		light.name = "MenuSunwash"
		light.set_anchors_preset(Control.PRESET_FULL_RECT)
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		light.color = Color(1.0, 0.92, 0.78, 0.26)
		light.z_index = -205
		add_child(light)
		move_child(light, 2)
	_bg_light = light

	# Hide purple overlays when we have a BG (otherwise they draw on top)
	var bds := get_node_or_null("BackdropShader") as CanvasItem
	if bds:
		bds.visible = (t == null)
	var bd := get_node_or_null("Backdrop") as CanvasItem
	if bd:
		bd.visible = (t == null)
	var fs := get_node_or_null("FrameShader") as CanvasItem
	if fs:
		fs.visible = (t == null)

func _play_intro_splash() -> void:
	if (not USE_UI_MOCKUPS) or INTRO_BG_PATH.is_empty() or (not ResourceLoader.exists(INTRO_BG_PATH)):
		return
	var splash := TextureRect.new()
	splash.name = "IntroSplash"
	splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	splash.texture = load(INTRO_BG_PATH) as Texture2D
	splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(splash)
	move_child(splash, get_child_count() - 1)
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(splash, "modulate:a", 0.0, 0.4)
	tw.tween_callback(splash.queue_free)

func _spawn_menu_crowd() -> void:
	# Your existing background FX/spawn
	if _crowd != null and is_instance_valid(_crowd):
		return
	var bd := get_node_or_null("Backdrop") as CanvasItem
	if bd:
		bd.z_index = -100
	var bds := get_node_or_null("BackdropShader") as CanvasItem
	if bds:
		bds.z_index = -90
	var c := preload("res://scripts/MainMenuCrowd.gd").new()
	c.name = "MenuCrowd"
	add_child(c)
	if c is CanvasItem:
		(c as CanvasItem).z_index = -50
	_crowd = c
	if has_node("MenuRoot"):
		move_child(_crowd, get_node("MenuRoot").get_index())

# ─────────────────────────────────────────────────────────────────────────────
# BUILD MENU (wooden sign style)
# ─────────────────────────────────────────────────────────────────────────────

func _load_tex(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _build_menu() -> void:
	# Main wooden panel card (left-ish like your preferred concept)
	_card = PanelContainer.new()
	_card.name = "MenuCard"
	_card.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_card.offset_left = 64
	_card.offset_top = -360
	_card.offset_right = 560
	_card.offset_bottom = 360
	_card.add_theme_stylebox_override("panel", _make_panel_style())
	_menu_root.add_child(_card)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 36)
	pad.add_theme_constant_override("margin_right", 36)
	pad.add_theme_constant_override("margin_top", 34)
	pad.add_theme_constant_override("margin_bottom", 28)
	_card.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	pad.add_child(vbox)

	# Title (big, cozy)
	var title := Label.new()
	title.name = "Title"
	title.text = game_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.06, 1))
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.pivot_offset = Vector2(200, 30)
	title.rotation = deg_to_rad(-1.0)
	_apply_font(title)
	vbox.add_child(title)

	# Subtitle
	var sub := Label.new()
	sub.text = game_tagline
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", SUBTITLE_COLOR)
	_apply_font(sub)
	vbox.add_child(sub)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	# Buttons (wood)
	_resume_btn = _make_menu_button("Resume", false)
	_resume_btn.visible = false
	vbox.add_child(_resume_btn)

	_play_btn = _make_menu_button("▶ Start", true)
	vbox.add_child(_play_btn)

	_armory_btn = _make_menu_button("Collection / Setup", false)
	vbox.add_child(_armory_btn)

	_protocol_btn = _make_menu_button("★ Progression", false, ACCENT_BERRY)
	vbox.add_child(_protocol_btn)

	_info_btn = _make_menu_button("Info / Codex", false)
	vbox.add_child(_info_btn)

	_settings_btn = _make_menu_button("Settings", false)
	vbox.add_child(_settings_btn)

	_quit_btn = _make_menu_button("Quit", false)
	vbox.add_child(_quit_btn)

	# Footer
	vbox.add_spacer(true)
	var footer := Label.new()
	footer.name = "Footer"
	footer.text = footer_text
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(0.98, 0.94, 0.86, 0.70))
	_apply_font(footer)
	vbox.add_child(footer)

	# Entrance animation (gentle pop)
	_card.modulate.a = 0
	_card.scale = Vector2(0.94, 0.94)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "scale", Vector2(1, 1), 0.45)
	tw.parallel().tween_property(_card, "modulate:a", 1.0, 0.32)

func _make_panel_style() -> StyleBox:
	var tex := _load_tex(ASSET_PANEL)
	if tex != null:
		var sbt := StyleBoxTexture.new()
		sbt.texture = tex
		sbt.texture_margin_left = 56
		sbt.texture_margin_right = 56
		sbt.texture_margin_top = 56
		sbt.texture_margin_bottom = 56
		sbt.content_margin_left = 28
		sbt.content_margin_right = 28
		sbt.content_margin_top = 24
		sbt.content_margin_bottom = 24
		return sbt

	# Fallback
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.15, 0.10, 0.95)
	sb.border_width_left = 4
	sb.border_width_right = 4
	sb.border_width_top = 4
	sb.border_width_bottom = 4
	sb.border_color = Color(0.10, 0.06, 0.03, 0.8)
	sb.corner_radius_top_left = 22
	sb.corner_radius_top_right = 22
	sb.corner_radius_bottom_left = 22
	sb.corner_radius_bottom_right = 22
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 20
	return sb

func _stylebox_from(tex_path: String, tm: int, cm_v: int, cm_h: int) -> StyleBoxTexture:
	var tex := _load_tex(tex_path)
	if tex == null:
		return null
	var sbt := StyleBoxTexture.new()
	sbt.texture = tex
	sbt.texture_margin_left = tm
	sbt.texture_margin_right = tm
	sbt.texture_margin_top = tm
	sbt.texture_margin_bottom = tm
	sbt.content_margin_left = cm_h
	sbt.content_margin_right = cm_h
	sbt.content_margin_top = cm_v
	sbt.content_margin_bottom = cm_v
	return sbt

func _make_menu_button(text: String, is_primary: bool, accent: Color = ACCENT_SUN) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 62)
	btn.add_theme_font_size_override("font_size", 21)
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_font(btn)

	# Wooden button textures (separate states)
	var normal := _stylebox_from(BTN_NORMAL, 64, 22, 36)
	var hover := _stylebox_from(BTN_HOVER, 64, 22, 36)
	var pressed := _stylebox_from(BTN_PRESSED, 64, 24, 36)
	var disabled := _stylebox_from(BTN_DISABLED, 64, 22, 36)

	if normal != null:
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover if hover != null else normal)
		btn.add_theme_stylebox_override("pressed", pressed if pressed != null else normal)
		btn.add_theme_stylebox_override("focus", hover if hover != null else normal)
		btn.add_theme_stylebox_override("disabled", disabled if disabled != null else normal)

		# Text styling
		btn.add_theme_color_override("font_color", TITLE_COLOR)
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_pressed_color", TITLE_COLOR)
		btn.add_theme_color_override("font_disabled_color", Color(0.9, 0.9, 0.9, 0.55))
		btn.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04, 1))
		btn.add_theme_constant_override("outline_size", 4)
	else:
		# Fallback flat
		var sb := StyleBoxFlat.new()
		sb.corner_radius_top_left = 14
		sb.corner_radius_top_right = 14
		sb.corner_radius_bottom_left = 14
		sb.corner_radius_bottom_right = 14
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_width_top = 2
		sb.border_width_bottom = 2
		sb.bg_color = Color(0.42, 0.28, 0.16, 1.0)
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.75)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb.duplicate())
		btn.add_theme_stylebox_override("pressed", sb.duplicate())
		btn.add_theme_stylebox_override("focus", sb.duplicate())
		btn.add_theme_color_override("font_color", TITLE_COLOR)

	# Subtle bouncy hover (keeps your existing behavior vibe)
	btn.mouse_entered.connect(func():
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.08).set_trans(Tween.TRANS_BACK)
	)
	btn.mouse_exited.connect(func():
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(1, 1), 0.10)
	)

	return btn

func _apply_font(c: Control) -> void:
	var f := UiSkin.get_font()
	if f != null:
		if c is Label:
			(c as Label).add_theme_font_override("font", f)
		elif c is Button:
			(c as Button).add_theme_font_override("font", f)
		elif c is RichTextLabel:
			(c as RichTextLabel).add_theme_font_override("normal_font", f)

# ─────────────────────────────────────────────────────────────────────────────
# MAP OVERLAY (readable surfaces, vignette, crowd tempering)
# ─────────────────────────────────────────────────────────────────────────────

func _sb_inset(radius: int = 12, alpha: float = 0.86) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(SURFACE_BG.r, SURFACE_BG.g, SURFACE_BG.b, alpha)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = SURFACE_BORDER
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _sb_list_selected() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.34, 0.20, 0.92)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	return sb

func _make_vignette_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.70;
uniform float inner : hint_range(0.0, 1.0) = 0.45;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment(){
	vec2 uv = SCREEN_UV;
	vec2 p = uv * 2.0 - 1.0;
	float r = length(p);
	float v = smoothstep(inner, 1.25, r);
	COLOR = vec4(tint.rgb, tint.a * v * strength);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("strength", 0.75)
	m.set_shader_parameter("inner", 0.40)
	m.set_shader_parameter("tint", Color(0, 0, 0, 1))
	return m

func _build_map_overlay() -> void:
	_map_overlay = Control.new()
	_map_overlay.name = "MapOverlay"
	_map_overlay.visible = false
	_map_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_map_overlay)

	# Strong scrim + vignette so UI wins vs crowd/background
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.03, 0.025, 0.02, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_overlay.add_child(dim)

	var vign := ColorRect.new()
	vign.name = "Vignette"
	vign.color = Color(1, 1, 1, 1)
	vign.set_anchors_preset(Control.PRESET_FULL_RECT)
	vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vign.material = _make_vignette_material()
	_map_overlay.add_child(vign)

	_map_panel = PanelContainer.new()
	_map_panel.set_anchors_preset(Control.PRESET_CENTER)
	_map_panel.offset_left = -520
	_map_panel.offset_top = -350
	_map_panel.offset_right = 520
	_map_panel.offset_bottom = 350
	_map_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_map_overlay.add_child(_map_panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 22)
	pad.add_theme_constant_override("margin_bottom", 22)
	_map_panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	pad.add_child(vbox)

	var title := Label.new()
	title.text = "Choose your zone"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04, 1))
	title.add_theme_constant_override("outline_size", 6)
	_apply_font(title)
	vbox.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)

	# LEFT: Zones list wrapped in readable inset panel
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	left.add_theme_constant_override("separation", 8)
	hbox.add_child(left)

	var list_lbl := Label.new()
	list_lbl.text = "Zones"
	list_lbl.add_theme_font_size_override("font_size", 14)
	list_lbl.add_theme_color_override("font_color", SUBTITLE_COLOR)
	list_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(list_lbl)
	left.add_child(list_lbl)

	_map_list_frame = PanelContainer.new()
	_map_list_frame.add_theme_stylebox_override("panel", _sb_inset(14, 0.86))
	_map_list_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_map_list_frame)

	var lf_pad := MarginContainer.new()
	lf_pad.add_theme_constant_override("margin_left", 6)
	lf_pad.add_theme_constant_override("margin_right", 6)
	lf_pad.add_theme_constant_override("margin_top", 6)
	lf_pad.add_theme_constant_override("margin_bottom", 6)
	_map_list_frame.add_child(lf_pad)

	_map_list = ItemList.new()
	_map_list.custom_minimum_size.y = 320
	_map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_list.allow_reselect = true
	_map_list.add_theme_font_size_override("font_size", 16)
	_map_list.add_theme_color_override("font_color", NORMAL_FG)
	_map_list.add_theme_color_override("font_selected_color", Color(1, 1, 1, 1))
	_map_list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_apply_font(_map_list)

	var sel_sb := _sb_list_selected()
	_map_list.add_theme_stylebox_override("selected", sel_sb)
	_map_list.add_theme_stylebox_override("selected_focus", sel_sb)
	lf_pad.add_child(_map_list)

	# RIGHT: Preview + info cards (all on dark surfaces)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	hbox.add_child(right)

	var preview_frame := PanelContainer.new()
	preview_frame.custom_minimum_size.y = 280
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_frame.add_theme_stylebox_override("panel", _sb_inset(14, 0.90))
	right.add_child(preview_frame)

	var prev_pad := MarginContainer.new()
	prev_pad.add_theme_constant_override("margin_left", 6)
	prev_pad.add_theme_constant_override("margin_right", 6)
	prev_pad.add_theme_constant_override("margin_top", 6)
	prev_pad.add_theme_constant_override("margin_bottom", 6)
	preview_frame.add_child(prev_pad)

	var prev_container := SubViewportContainer.new()
	prev_container.stretch = true
	prev_pad.add_child(prev_container)

	_map_preview_vp = SubViewport.new()
	_map_preview_vp.size = Vector2i(720, 360)
	_map_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_map_preview_vp.transparent_bg = false
	prev_container.add_child(_map_preview_vp)

	# LOCK overlay on preview
	_map_preview_lock_lbl = Label.new()
	_map_preview_lock_lbl.name = "PreviewLocked"
	_map_preview_lock_lbl.text = "LOCKED"
	_map_preview_lock_lbl.visible = false
	_map_preview_lock_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_map_preview_lock_lbl.add_theme_font_size_override("font_size", 34)
	_map_preview_lock_lbl.add_theme_color_override("font_color", Color(1, 0.6, 0.5, 1))
	_map_preview_lock_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_map_preview_lock_lbl.add_theme_constant_override("outline_size", 6)
	_apply_font(_map_preview_lock_lbl)
	preview_frame.add_child(_map_preview_lock_lbl)

	_map_details_frame = PanelContainer.new()
	_map_details_frame.add_theme_stylebox_override("panel", _sb_inset(14, 0.84))
	right.add_child(_map_details_frame)

	var df_pad := MarginContainer.new()
	df_pad.add_theme_constant_override("margin_left", 10)
	df_pad.add_theme_constant_override("margin_right", 10)
	df_pad.add_theme_constant_override("margin_top", 8)
	df_pad.add_theme_constant_override("margin_bottom", 8)
	_map_details_frame.add_child(df_pad)

	var info_v := VBoxContainer.new()
	info_v.add_theme_constant_override("separation", 6)
	df_pad.add_child(info_v)

	_map_tagline = Label.new()
	_map_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_tagline.add_theme_font_size_override("font_size", 14)
	_map_tagline.add_theme_color_override("font_color", SUBTITLE_COLOR)
	_map_tagline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	_map_tagline.add_theme_constant_override("outline_size", 3)
	_apply_font(_map_tagline)
	info_v.add_child(_map_tagline)

	_map_details = RichTextLabel.new()
	_map_details.custom_minimum_size.y = 84
	_map_details.bbcode_enabled = true
	_map_details.fit_content = true
	_map_details.scroll_active = false
	_map_details.add_theme_font_size_override("normal_font_size", 13)
	_map_details.add_theme_color_override("default_color", Color(0.92, 0.90, 0.86, 0.95))
	_apply_font(_map_details)
	info_v.add_child(_map_details)

	# Buttons row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_map_back_btn = _make_menu_button("← Back", false)
	_map_back_btn.custom_minimum_size = Vector2(170, 50)
	btn_row.add_child(_map_back_btn)

	_map_start_btn = _make_menu_button("Start", true)
	_map_start_btn.custom_minimum_size = Vector2(200, 50)
	btn_row.add_child(_map_start_btn)

	_setup_map_select_overlay()

# ─────────────────────────────────────────────────────────────────────────────
# SIGNALS & LOGIC (unchanged behavior)
# ─────────────────────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	if _play_btn:
		_play_btn.pressed.connect(func():
			_play_ui("ui.confirm")
			_open_map_overlay()
		)

	var sv := get_node_or_null("/root/SaveManager")
	var has_resume := sv and is_instance_valid(sv) and sv.has_method("has_saved_run") and bool(sv.has_saved_run())
	if _resume_btn:
		_resume_btn.visible = has_resume
		if has_resume:
			_resume_btn.pressed.connect(func():
				_play_ui("ui.resume_load")
				if sv and sv.has_method("request_resume") and bool(sv.request_resume()):
					get_tree().change_scene_to_file("res://scenes/Main.tscn")
			)

	if _armory_btn:
		_armory_btn.pressed.connect(func():
			_play_ui("ui.click")
			get_tree().change_scene_to_file("res://scenes/Menu.tscn")
		)

	if _protocol_btn:
		_protocol_btn.pressed.connect(func():
			_play_ui("ui.click")
			_open_protocol_grid()
		)

	if _info_btn:
		_info_btn.pressed.connect(func():
			_play_ui("ui.click")
			_open_info_overlay()
		)

	if _settings_btn:
		_settings_btn.pressed.connect(func():
			_play_ui("ui.click")
			_open_settings()
		)

	if _quit_btn:
		_quit_btn.pressed.connect(func():
			_play_ui("ui.cancel")
			get_tree().quit()
		)

	if _map_back_btn:
		_map_back_btn.pressed.connect(func():
			_play_ui("ui.cancel")
			_close_map_overlay()
		)
	if _map_start_btn:
		_map_start_btn.pressed.connect(func():
			_play_ui("ui.confirm")
			_start_run_with_selected_map()
		)

func _setup_map_select_overlay() -> void:
	if _map_list == null:
		return
	var rc := get_node_or_null("/root/RunConfig")
	if rc == null or not is_instance_valid(rc):
		return
	if rc.has_method("ensure_loaded"):
		rc.ensure_loaded()

	_map_list.clear()
	_map_ids.clear()
	if rc.has_method("get_map_ids_ordered"):
		_map_ids = rc.get_map_ids_ordered()
	elif rc.has_method("get_map_ids"):
		_map_ids = rc.get_map_ids()
	for i in range(_map_ids.size()):
		var m: Dictionary = rc.get_map(_map_ids[i]) if rc.has_method("get_map") else {}
		var name := String(m.get("name", _map_ids[i]))
		var mult := float(m.get("meta_sigils_mult", 1.0))
		var tier := "★" if mult < 1.2 else ("★★" if mult < 1.5 else "★★★")
		var locked := not _is_map_unlocked(_map_ids[i])
		var label := name
		if locked:
			label = "🔒 " + name

		var text := "%s    %s" % [label, tier]
		_map_list.add_item(text)

		_map_list.set_item_disabled(i, locked)
		_map_list.set_item_custom_fg_color(i, LOCKED_FG if locked else NORMAL_FG)
		if locked:
			_map_list.set_item_custom_bg_color(i, Color(0, 0, 0, 0.10))
			_map_list.set_item_tooltip(i, "Locked. Win the previous map to unlock.")
		else:
			_map_list.set_item_custom_bg_color(i, Color(0, 0, 0, 0.0))

	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	for i in range(_map_ids.size()):
		if _map_ids[i] == cur:
			_map_list.select(i)
			break

	_update_map_tagline(rc)
	_update_map_preview(rc)
	_update_map_lock_state(rc)

	_map_list.item_selected.connect(func(idx: int):
		if idx < 0 or idx >= _map_ids.size():
			return
		if _map_list.is_item_disabled(idx):
			_play_ui("ui.error")
			return
		var id := _map_ids[idx]
		_play_ui("ui.click")
		if rc.has_method("set_selected_map_id"):
			rc.set_selected_map_id(id)
		_update_map_tagline(rc)
		_update_map_preview(rc)
		_update_map_lock_state(rc)
	)

func _update_map_tagline(rc: Node) -> void:
	if _map_tagline == null:
		return
	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	var m: Dictionary = rc.get_map(cur) if rc.has_method("get_map") else {}
	var t := String(m.get("tagline", ""))
	var mult := float(m.get("meta_sigils_mult", 1.0))
	_map_tagline.text = "%s\nSigils: x%.2f" % [t, mult] if t != "" else ""
	_update_map_details(m)
	_update_map_lock_state(rc)

func _update_map_lock_state(rc: Node) -> void:
	if rc == null:
		return
	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	_selected_map_locked = not _is_map_unlocked(cur)

	if _map_start_btn:
		_map_start_btn.disabled = _selected_map_locked
		_map_start_btn.text = "Locked" if _selected_map_locked else "Start"

	if _map_preview_lock_lbl:
		_map_preview_lock_lbl.visible = _selected_map_locked

	if _map_details_frame:
		_map_details_frame.modulate = Color(1, 1, 1, 0.85) if _selected_map_locked else Color(1, 1, 1, 1)

func _danger_score(m: Dictionary) -> float:
	var hp: float = float(m.get("enemy_hp_mult", 1.0))
	var dmg: float = float(m.get("enemy_damage_mult", 1.0))
	var spd: float = float(m.get("enemy_speed_mult", 1.0))
	var maxe: float = float(m.get("max_enemies_mult", 1.0))
	var si: float = float(m.get("spawn_interval_mult", 1.0))
	var hp_dev := (hp - 1.0) * 2.5
	var dmg_dev := (dmg - 1.0) * 3.0
	var spd_dev := (spd - 1.0) * 1.5
	var maxe_dev := (maxe - 1.0) * 2.0
	var si_dev := (1.0 - si) * 2.0
	return clampf(5.0 + hp_dev + dmg_dev + spd_dev + maxe_dev + si_dev, 1.0, 10.0)

func _tier_color(score: float) -> String:
	if score < 3.5: return "#79ffd2"
	if score < 6.5: return "#ffd86b"
	return "#ff6a55"

func _bar(score: float) -> String:
	var n := int(round(score))
	n = clampi(n, 0, 10)
	var s := ""
	for i in range(10):
		s += "■" if i < n else "·"
	return s

func _update_map_details(m: Dictionary) -> void:
	if _map_details == null:
		return
	var score := _danger_score(m)
	var col := _tier_color(score)
	var sig := float(m.get("meta_sigils_mult", 1.0))
	var ess := float(m.get("essence_mult", 1.0))
	var boss := bool(m.get("boss_enabled", true))
	var boss_m := float(m.get("boss_spawn_minutes", 18.0))
	var diff_bar := "[color=%s]%s[/color]" % [col, _bar(score)]
	var diff_line := "[color=#a8a0a0]Danger:[/color] %s [color=%s]%.1f[/color]" % [diff_bar, col, score]
	var reward_line := "[color=#a8a0a0]Rewards:[/color] [color=#ffd070]★ x%.2f[/color]  [color=#70d0ff]◆ x%.2f[/color]" % [sig, ess]
	var boss_text := "[color=#ff7070]Yes @ %.0fm[/color]" % boss_m if boss else "[color=#70ff70]No[/color]"
	_map_details.text = "%s\n%s\n[color=#a8a0a0]Boss:[/color] %s" % [diff_line, reward_line, boss_text]

func _hash32(s: String) -> int:
	var h: int = 2166136261
	for i in range(s.length()):
		h = int((h ^ s.unicode_at(i)) * 16777619) & 0x7fffffff
	return h

func _update_map_preview(rc: Node) -> void:
	if _map_preview_vp == null:
		return
	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	var m: Dictionary = rc.get_map(cur) if rc.has_method("get_map") else {}
	var vis: Dictionary = {}
	var vv: Variant = m.get("visuals", {})
	if typeof(vv) == TYPE_DICTIONARY:
		vis = vv as Dictionary

	if _preview_root != null and is_instance_valid(_preview_root):
		_preview_root.queue_free()
		_preview_root = null
	for c in _map_preview_vp.get_children():
		(c as Node).queue_free()

	_map_preview_vp.size = Vector2i(720, 360)
	_map_preview_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST

	var root := Node2D.new()
	root.name = "PreviewRoot"
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	_map_preview_vp.add_child(root)
	_preview_root = root

	var cam := Camera2D.new()
	cam.position = Vector2.ZERO
	cam.zoom = Vector2(0.34, 0.34)
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	cam.enabled = true
	root.add_child(cam)
	cam.make_current()

	var biome := cur
	if vis.has("theme_id"):
		biome = String(vis.get("theme_id"))

	var tmw := Node2D.new()
	tmw.name = "TileMapWorld"
	tmw.process_mode = Node.PROCESS_MODE_ALWAYS
	var tmx_path := String(m.get("tmx_path", ""))
	if not tmx_path.is_empty():
		tmw.set_script(preload("res://scripts/TmxMapWorld.gd"))
		tmw.set("tmx_path", tmx_path)
		tmw.set("map_size", Vector2(2400, 1800))
	else:
		tmw.set_script(preload("res://scripts/TileMapWorld.gd"))
		tmw.set("map_size", Vector2(2400, 1800))
		tmw.set("biome", biome)
		tmw.set("seed_value", _hash32(cur))
		tmw.set("prop_count", 18)
		tmw.set("prop_min_dist_from_center", 60.0)
	root.add_child(tmw)

func _open_map_overlay() -> void:
	if _map_overlay == null:
		_start_run_with_selected_map()
		return

	if _crowd != null and is_instance_valid(_crowd):
		_crowd_prev_visible = _crowd.visible
		_crowd_prev_process_mode = _crowd.process_mode
		_crowd.visible = false
		_crowd.process_mode = Node.PROCESS_MODE_DISABLED

	_map_overlay.visible = true
	_map_overlay.grab_focus()
	if _map_list:
		_map_list.grab_focus()
	elif _map_start_btn:
		_map_start_btn.grab_focus()

func _close_map_overlay() -> void:
	if _map_overlay == null:
		return
	_map_overlay.visible = false

	if _crowd != null and is_instance_valid(_crowd):
		_crowd.visible = _crowd_prev_visible
		_crowd.process_mode = _crowd_prev_process_mode

	if _play_btn:
		_play_btn.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			if _map_overlay and _map_overlay.visible:
				_close_map_overlay()
				get_viewport().set_input_as_handled()
				return
			if _info_overlay and _info_overlay.visible:
				_close_info_overlay()
				get_viewport().set_input_as_handled()
				return
			if _protocol_overlay and _protocol_overlay.visible:
				_protocol_overlay.visible = false
				if _play_btn:
					_play_btn.grab_focus()
				get_viewport().set_input_as_handled()
				return

func _start_run_with_selected_map() -> void:
	if _selected_map_locked:
		_play_ui("ui.error")
		return
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _is_map_unlocked(map_id: String) -> bool:
	if map_id == "" or map_id == "graveyard" or map_id == "cathedral" or map_id == "church":
		return true
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp):
		return map_id == "graveyard" or map_id == "cathedral" or map_id == "church"
	return bool(mp.is_map_unlocked(map_id)) if mp.has_method("is_map_unlocked") else (map_id == "graveyard" or map_id == "cathedral" or map_id == "church")

func _play_ui(id: String) -> void:
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui(id)

func _open_info_overlay() -> void:
	if _info_overlay != null and is_instance_valid(_info_overlay):
		if _crowd != null and is_instance_valid(_crowd):
			_crowd_prev_visible = _crowd.visible
			_crowd_prev_process_mode = _crowd.process_mode
			_crowd.visible = false
			_crowd.process_mode = Node.PROCESS_MODE_DISABLED
		_info_overlay.visible = true
		_reload_info_entries()
		if _info_search:
			_info_search.grab_focus()
		return
	_create_info_overlay()
	_reload_info_entries()
	if _info_search:
		_info_search.grab_focus()
	if _crowd != null and is_instance_valid(_crowd):
		_crowd_prev_visible = _crowd.visible
		_crowd_prev_process_mode = _crowd.process_mode
		_crowd.visible = false
		_crowd.process_mode = Node.PROCESS_MODE_DISABLED

func _close_info_overlay() -> void:
	if _info_overlay == null:
		return
	_info_overlay.visible = false
	if _crowd != null and is_instance_valid(_crowd):
		_crowd.visible = _crowd_prev_visible
		_crowd.process_mode = _crowd_prev_process_mode
	if _play_btn:
		_play_btn.grab_focus()

func _create_info_overlay() -> void:
	_info_overlay = Control.new()
	_info_overlay.name = "InfoOverlay"
	_info_overlay.visible = false
	_info_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_info_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_info_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.05, 0.04, 0.92)
	_info_overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -620
	panel.offset_top = -350
	panel.offset_right = 620
	panel.offset_bottom = 350
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	_info_overlay.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pad.add_child(v)

	var title := Label.new()
	title.text = "Info Codex"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04, 1))
	title.add_theme_constant_override("outline_size", 6)
	_apply_font(title)
	v.add_child(title)

	var sub := Label.new()
	sub.text = "Search passives, synergies, weapons, stats and tuning."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", SUBTITLE_COLOR)
	_apply_font(sub)
	v.add_child(sub)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 10)
	v.add_child(filter_row)

	_info_section = OptionButton.new()
	_info_section.custom_minimum_size = Vector2(190, 34)
	_info_section.add_item("All", 0)
	_info_section.add_item("Overview", 1)
	_info_section.add_item("Stats", 2)
	_info_section.add_item("Passives", 3)
	_info_section.add_item("Synergies", 4)
	_info_section.add_item("Weapons", 5)
	_info_section.selected = 0
	filter_row.add_child(_info_section)

	_info_search = LineEdit.new()
	_info_search.placeholder_text = "Search (name, id, tags, description...)"
	_info_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(_info_search)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	var left_frame := PanelContainer.new()
	left_frame.custom_minimum_size = Vector2(380, 420)
	left_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_frame.add_theme_stylebox_override("panel", _sb_inset(12, 0.88))
	body.add_child(left_frame)

	var left_pad := MarginContainer.new()
	left_pad.add_theme_constant_override("margin_left", 8)
	left_pad.add_theme_constant_override("margin_right", 8)
	left_pad.add_theme_constant_override("margin_top", 8)
	left_pad.add_theme_constant_override("margin_bottom", 8)
	left_frame.add_child(left_pad)

	_info_list = ItemList.new()
	_info_list.select_mode = ItemList.SELECT_SINGLE
	_info_list.allow_reselect = true
	_info_list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_info_list.add_theme_font_size_override("font_size", 14)
	_info_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_pad.add_child(_info_list)

	var right_frame := PanelContainer.new()
	right_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_frame.add_theme_stylebox_override("panel", _sb_inset(12, 0.86))
	body.add_child(right_frame)

	var right_pad := MarginContainer.new()
	right_pad.add_theme_constant_override("margin_left", 10)
	right_pad.add_theme_constant_override("margin_right", 10)
	right_pad.add_theme_constant_override("margin_top", 10)
	right_pad.add_theme_constant_override("margin_bottom", 10)
	right_frame.add_child(right_pad)

	var right_v := VBoxContainer.new()
	right_v.add_theme_constant_override("separation", 8)
	right_pad.add_child(right_v)

	_info_hint = Label.new()
	_info_hint.text = "Select an entry on the left."
	_info_hint.add_theme_font_size_override("font_size", 13)
	_info_hint.add_theme_color_override("font_color", Color(0.95, 0.92, 0.80, 0.85))
	_apply_font(_info_hint)
	right_v.add_child(_info_hint)

	_info_details = RichTextLabel.new()
	_info_details.bbcode_enabled = true
	_info_details.fit_content = false
	_info_details.scroll_active = true
	_info_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_details.add_theme_font_size_override("normal_font_size", 13)
	_info_details.add_theme_color_override("default_color", Color(0.94, 0.91, 0.86, 0.96))
	_apply_font(_info_details)
	right_v.add_child(_info_details)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	v.add_child(btn_row)

	var close_btn := _make_menu_button("Close", false)
	close_btn.custom_minimum_size = Vector2(180, 46)
	close_btn.pressed.connect(func():
		_play_ui("ui.cancel")
		_close_info_overlay()
	)
	btn_row.add_child(close_btn)

	_info_section.item_selected.connect(func(_idx: int):
		_update_info_list()
	)
	_info_search.text_changed.connect(func(_t: String):
		_update_info_list()
	)
	_info_list.item_selected.connect(func(idx: int):
		_render_info_entry(idx)
	)

	_info_overlay.visible = true

func _load_json_dict(path: String) -> Dictionary:
	if path.is_empty() or not ResourceLoader.exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary

func _join_string_array(values: Array) -> String:
	var out: PackedStringArray = PackedStringArray()
	for v in values:
		var s := String(v).strip_edges()
		if s != "":
			out.append(s)
	return ", ".join(out)

func _reload_info_entries() -> void:
	_info_entries.clear()
	_info_entries.append({
		"section": "Overview",
		"title": "Game Loop",
		"id": "overview_game_loop",
		"text": "Draft units, combine synergies, and survive scaling enemy waves. Characters are now tuned as identity units (race + class + role + chase passives)."
	})
	_info_entries.append({
		"section": "Overview",
		"title": "Optimization Basics",
		"id": "overview_builds",
		"text": "Build around one carry and one support core. Chase units have curated signatures; higher rarity opens more passive slots and build variants."
	})
	_info_entries.append({
		"section": "Stats",
		"title": "Stat Meanings",
		"id": "stats_meanings",
		"text": "HP: survivability.\nDamage: hit strength.\nCooldown: attack interval (lower is faster).\nRange: attack distance.\nMove Speed: repositioning and kite potential."
	})
	var ub := _load_json_dict("res://data/unit_balance.json")
	if not ub.is_empty():
		var ctx := ub.get("context_stat_mult", {}) as Dictionary
		var enemy := ctx.get("enemy", {}) as Dictionary
		var recruit := ctx.get("recruit", {}) as Dictionary
		var scal := ub.get("enemy_scaling", {}) as Dictionary
		var txt := "Recruit multipliers: hp x%.2f, dmg x%.2f, move x%.2f\nEnemy multipliers: hp x%.2f, dmg x%.2f, move x%.2f\nEnemy scaling per minute: hp +%.1f%%, dmg +%.1f%%" % [
			float(recruit.get("max_hp", 1.0)), float(recruit.get("attack_damage", 1.0)), float(recruit.get("move_speed", 1.0)),
			float(enemy.get("max_hp", 1.0)), float(enemy.get("attack_damage", 1.0)), float(enemy.get("move_speed", 1.0)),
			float(scal.get("hp_per_minute_mult", 0.0)) * 100.0, float(scal.get("damage_per_minute_mult", 0.0)) * 100.0
		]
		_info_entries.append({
			"section": "Stats",
			"title": "Current Tuning Snapshot",
			"id": "stats_tuning_snapshot",
			"text": txt
		})

	var pd := _load_json_dict("res://data/passives.json")
	for p in pd.get("passives", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var d := p as Dictionary
		var tags := _join_string_array(d.get("tags", []) as Array)
		var body := String(d.get("description", ""))
		if tags != "":
			body += "\nTags: " + tags
		_info_entries.append({
			"section": "Passives",
			"title": String(d.get("name", d.get("id", ""))),
			"id": String(d.get("id", "")),
			"search": String(d.get("id", "")) + " " + tags,
			"text": body
		})

	var sd := _load_json_dict("res://data/synergies.json")
	for s in sd.get("synergies", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sy := s as Dictionary
		var tiers: Array = sy.get("tiers", []) as Array
		var lines: Array[String] = []
		for t in tiers:
			if typeof(t) != TYPE_DICTIONARY:
				continue
			var td := t as Dictionary
			var c := int(td.get("count", 0))
			var mods := td.get("mods", {}) as Dictionary
			lines.append("%d units: %s" % [c, JSON.stringify(mods)])
		_info_entries.append({
			"section": "Synergies",
			"title": String(sy.get("name", sy.get("id", ""))),
			"id": String(sy.get("id", "")),
			"search": String(sy.get("count_tag", "")),
			"text": String(sy.get("description", "")) + ("\n" + "\n".join(lines) if not lines.is_empty() else "")
		})

	var wd := _load_json_dict("res://data/weapons.json")
	for wid in wd.keys():
		var wv: Variant = wd.get(wid, {})
		if typeof(wv) != TYPE_DICTIONARY:
			continue
		var w := wv as Dictionary
		var tags2 := _join_string_array(w.get("tags", []) as Array)
		var txt2 := "%s\nType: %s" % [String(w.get("description", "")), String(w.get("type", ""))]
		if tags2 != "":
			txt2 += "\nTags: " + tags2
		_info_entries.append({
			"section": "Weapons",
			"title": String(w.get("name", String(wid))),
			"id": String(wid),
			"search": tags2,
			"text": txt2
		})

	_update_info_list()

func _info_section_name() -> String:
	if _info_section == null:
		return "All"
	return _info_section.get_item_text(_info_section.selected)

func _update_info_list() -> void:
	if _info_list == null:
		return
	_info_list.clear()
	var section := _info_section_name()
	var needle := ""
	if _info_search != null:
		needle = _info_search.text.strip_edges().to_lower()
	var count := 0
	for i in range(_info_entries.size()):
		var e := _info_entries[i]
		var sec := String(e.get("section", ""))
		if section != "All" and sec != section:
			continue
		var hay := "%s %s %s %s %s" % [
			String(e.get("title", "")),
			String(e.get("id", "")),
			String(e.get("text", "")),
			String(e.get("search", "")),
			sec
		]
		if needle != "" and hay.to_lower().find(needle) < 0:
			continue
		var label := "[%s] %s" % [sec, String(e.get("title", e.get("id", "")))]
		_info_list.add_item(label)
		_info_list.set_item_metadata(count, i)
		count += 1
	if _info_hint:
		_info_hint.text = "Results: %d" % count
	if count > 0:
		_info_list.select(0)
		_render_info_entry(0)
	else:
		if _info_details:
			_info_details.text = "No results for current filter."

func _render_info_entry(list_idx: int) -> void:
	if _info_list == null or _info_details == null:
		return
	if list_idx < 0 or list_idx >= _info_list.item_count:
		return
	var meta: Variant = _info_list.get_item_metadata(list_idx)
	if typeof(meta) != TYPE_INT:
		return
	var src_idx := int(meta)
	if src_idx < 0 or src_idx >= _info_entries.size():
		return
	var e := _info_entries[src_idx]
	var title := String(e.get("title", "Entry"))
	var sec := String(e.get("section", ""))
	var id := String(e.get("id", ""))
	var body := String(e.get("text", ""))
	_info_details.text = "[b][color=#ffe0a2]%s[/color][/b]\n[color=#b9b2aa]%s • %s[/color]\n\n%s" % [title, sec, id, body]

func _open_settings() -> void:
	if has_node("SettingsMenu"):
		return
	var sm := preload("res://scripts/SettingsMenu.gd").new()
	sm.name = "SettingsMenu"
	add_child(sm)

# ─────────────────────────────────────────────────────────────────────────────
# PROTOCOL GRID (logic unchanged; small fix: node VBox named so lookups work)
# ─────────────────────────────────────────────────────────────────────────────

var _protocol_overlay: Control = null
var _protocol_nodes: Array[Dictionary] = []

const PROTOCOL_UPGRADES := [
	{"id": "hp_boost_1", "name": "Vitality I", "desc": "+10% Squad HP", "cost": 50, "icon": "♥", "row": 0, "col": 1, "color": "#ff6060", "prereq": []},
	{"id": "dmg_boost_1", "name": "Power I", "desc": "+8% Squad Damage", "cost": 60, "icon": "⚔", "row": 0, "col": 3, "color": "#ffa040", "prereq": []},
	{"id": "speed_1", "name": "Agility I", "desc": "+5% Move Speed", "cost": 40, "icon": "»", "row": 0, "col": 2, "color": "#60ff90", "prereq": []},
	{"id": "hp_boost_2", "name": "Vitality II", "desc": "+15% Squad HP", "cost": 180, "icon": "♥♥", "row": 1, "col": 0, "color": "#ff4040", "prereq": ["hp_boost_1"]},
	{"id": "dmg_boost_2", "name": "Power II", "desc": "+12% Squad Damage", "cost": 200, "icon": "⚔⚔", "row": 1, "col": 4, "color": "#ff8020", "prereq": ["dmg_boost_1"]},
	{"id": "speed_2", "name": "Agility II", "desc": "+8% Move Speed", "cost": 150, "icon": "»»", "row": 1, "col": 2, "color": "#40ff70", "prereq": ["speed_1"]},
	{"id": "crit_1", "name": "Precision I", "desc": "+3% Crit Chance", "cost": 120, "icon": "✧", "row": 1, "col": 1, "color": "#ffff60", "prereq": ["hp_boost_1"]},
	{"id": "essence_1", "name": "Harvest I", "desc": "+10% Essence Gain", "cost": 100, "icon": "◆", "row": 1, "col": 3, "color": "#60d0ff", "prereq": ["dmg_boost_1"]},
	{"id": "hp_boost_3", "name": "Vitality III", "desc": "+20% Squad HP", "cost": 450, "icon": "♥♥♥", "row": 2, "col": 0, "color": "#ff2020", "prereq": ["hp_boost_2"]},
	{"id": "dmg_boost_3", "name": "Power III", "desc": "+18% Squad Damage", "cost": 500, "icon": "⚔⚔⚔", "row": 2, "col": 4, "color": "#ff6000", "prereq": ["dmg_boost_2"]},
	{"id": "crit_2", "name": "Precision II", "desc": "+5% Crit Chance", "cost": 350, "icon": "✧✧", "row": 2, "col": 1, "color": "#ffff40", "prereq": ["crit_1"]},
	{"id": "essence_2", "name": "Harvest II", "desc": "+15% Essence Gain", "cost": 300, "icon": "◆◆", "row": 2, "col": 3, "color": "#40b0ff", "prereq": ["essence_1"]},
	{"id": "draft_luck", "name": "Fortune", "desc": "+Higher Rarity Drafts", "cost": 400, "icon": "★", "row": 2, "col": 2, "color": "#c080ff", "prereq": ["speed_2"]},
	{"id": "starting_unit", "name": "Reinforcement", "desc": "+1 Starting Squad", "cost": 800, "icon": "☗", "row": 3, "col": 2, "color": "#ff80c0", "prereq": ["draft_luck", "crit_2", "essence_2"]},
]

func _open_protocol_grid() -> void:
	if _protocol_overlay != null and is_instance_valid(_protocol_overlay):
		_protocol_overlay.visible = true
		_update_protocol_grid()
		return
	_create_protocol_overlay()
	_update_protocol_grid()

func _create_protocol_overlay() -> void:
	_protocol_overlay = Control.new()
	_protocol_overlay.name = "ProtocolOverlay"
	_protocol_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_protocol_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_protocol_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.06, 0.05, 0.92)
	_protocol_overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.name = "PanelContainer"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(900, 650)
	panel.position = Vector2(-450, -325)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	_protocol_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "★ Progression ★"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", ACCENT_BERRY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_font(title)
	header.add_child(title)

	var sigils_lbl := Label.new()
	sigils_lbl.name = "SigilsLabel"
	sigils_lbl.text = "★ 0"
	sigils_lbl.add_theme_font_size_override("font_size", 24)
	sigils_lbl.add_theme_color_override("font_color", ACCENT_SUN)
	_apply_font(sigils_lbl)
	header.add_child(sigils_lbl)

	var sub := Label.new()
	sub.text = "Permanent upgrades that persist across all runs"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", SUBTITLE_COLOR)
	_apply_font(sub)
	vbox.add_child(sub)

	var grid_wrap := Control.new()
	grid_wrap.name = "GridWrap"
	grid_wrap.custom_minimum_size = Vector2(850, 420)
	grid_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid_wrap)

	_protocol_nodes.clear()
	for upgrade in PROTOCOL_UPGRADES:
		var node := _create_protocol_node(upgrade)
		grid_wrap.add_child(node["panel"])
		_protocol_nodes.append(node)

	_draw_protocol_lines(grid_wrap)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var back_btn := _make_menu_button("← Back", false)
	back_btn.custom_minimum_size = Vector2(160, 44)
	back_btn.pressed.connect(func():
		_play_ui("ui.cancel")
		_protocol_overlay.visible = false
	)
	btn_row.add_child(back_btn)

func _create_protocol_node(upgrade: Dictionary) -> Dictionary:
	var col := int(upgrade.get("col", 0))
	var row := int(upgrade.get("row", 0))
	var node_color := Color.from_string(String(upgrade.get("color", "#ffffff")), Color.WHITE)

	var panel := PanelContainer.new()
	panel.name = String(upgrade.get("id", "node"))
	panel.custom_minimum_size = Vector2(140, 92)
	panel.position = Vector2(80.0 + float(col) * 160.0, 20.0 + float(row) * 100.0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.12, 0.08, 0.95)
	sb.border_color = Color(node_color.r, node_color.g, node_color.b, 0.65)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)

	var content := VBoxContainer.new()
	content.name = "VBoxContainer" # fixes later lookups
	content.add_theme_constant_override("separation", 2)
	panel.add_child(content)

	var icon_lbl := Label.new()
	icon_lbl.text = String(upgrade.get("icon", "?"))
	icon_lbl.add_theme_font_size_override("font_size", 22)
	icon_lbl.add_theme_color_override("font_color", node_color)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(icon_lbl)
	content.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = String(upgrade.get("name", "?"))
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", TITLE_COLOR)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(name_lbl)
	content.add_child(name_lbl)

	var cost_lbl := Label.new()
	cost_lbl.name = "Cost"
	cost_lbl.text = "★ %d" % int(upgrade.get("cost", 0))
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", ACCENT_SUN)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(cost_lbl)
	content.add_child(cost_lbl)

	var btn_overlay := Button.new()
	btn_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_overlay.flat = true
	btn_overlay.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_child(btn_overlay)

	var upgrade_id := String(upgrade.get("id", ""))
	btn_overlay.pressed.connect(func(): _on_protocol_node_clicked(upgrade_id))
	btn_overlay.mouse_entered.connect(func(): _on_protocol_node_hovered(upgrade_id, true))
	btn_overlay.mouse_exited.connect(func(): _on_protocol_node_hovered(upgrade_id, false))

	return {"id": upgrade_id, "panel": panel, "color": node_color, "upgrade": upgrade}

func _draw_protocol_lines(container: Control) -> void:
	for node in _protocol_nodes:
		var upgrade: Dictionary = node.get("upgrade", {})
		var prereqs: Array = upgrade.get("prereq", [])
		var panel: Control = node.get("panel")
		if panel == null:
			continue
		var to_pos := panel.position + Vector2(70, 0)
		for prereq_id in prereqs:
			for pnode in _protocol_nodes:
				if String(pnode.get("id", "")) == String(prereq_id):
					var from_panel: Control = pnode.get("panel")
					if from_panel == null:
						continue
					var from_pos := from_panel.position + Vector2(70, 92)
					var line := Line2D.new()
					line.width = 2.0
					line.default_color = Color(0.75, 0.55, 0.35, 0.45)
					line.points = [from_pos, to_pos]
					line.z_index = -1
					container.add_child(line)
					break

func _update_protocol_grid() -> void:
	var mp := get_node_or_null("/root/MetaProgression")
	var sigils := 0
	var unlocked: Array = []
	if mp and is_instance_valid(mp):
		if mp.has_method("get_sigils"):
			sigils = int(mp.get_sigils())
		if mp.has_method("get_unlocked_upgrades"):
			unlocked = mp.get_unlocked_upgrades()

	if _protocol_overlay:
		var sigils_lbl := _protocol_overlay.get_node_or_null("PanelContainer/VBoxContainer/HBoxContainer/SigilsLabel") as Label
		if sigils_lbl == null:
			for child in _protocol_overlay.get_children():
				if child is PanelContainer:
					for c2 in child.get_children():
						if c2 is VBoxContainer:
							for c3 in c2.get_children():
								if c3 is HBoxContainer:
									for c4 in c3.get_children():
										if c4 is Label and c4.name == "SigilsLabel":
											sigils_lbl = c4
											break
		if sigils_lbl:
			sigils_lbl.text = "★ %d" % sigils

	for node in _protocol_nodes:
		var id := String(node.get("id", ""))
		var panel: PanelContainer = node.get("panel")
		var upgrade: Dictionary = node.get("upgrade", {})
		if panel == null:
			continue

		var is_unlocked := id in unlocked
		var prereqs: Array = upgrade.get("prereq", [])
		var prereqs_met := true
		for prereq_id in prereqs:
			if not String(prereq_id) in unlocked:
				prereqs_met = false
				break

		var cost := int(upgrade.get("cost", 0))
		var can_afford := sigils >= cost

		if is_unlocked:
			panel.modulate = Color(1, 1, 1, 1)
			var cost_lbl := panel.get_node_or_null("VBoxContainer/Cost") as Label
			if cost_lbl:
				cost_lbl.text = "✓ OWNED"
				cost_lbl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65, 1.0))
		elif prereqs_met and can_afford:
			panel.modulate = Color(1, 1, 1, 1)
		elif prereqs_met:
			panel.modulate = Color(0.75, 0.75, 0.75, 1)
		else:
			panel.modulate = Color(0.45, 0.45, 0.45, 0.75)

func _on_protocol_node_clicked(upgrade_id: String) -> void:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp):
		return
	var upgrade: Dictionary = {}
	for u in PROTOCOL_UPGRADES:
		if String(u.get("id", "")) == upgrade_id:
			upgrade = u
			break
	if upgrade.is_empty():
		return
	var unlocked: Array = mp.get_unlocked_upgrades() if mp.has_method("get_unlocked_upgrades") else []
	if upgrade_id in unlocked:
		_play_ui("ui.error")
		return
	for prereq_id in upgrade.get("prereq", []):
		if not String(prereq_id) in unlocked:
			_play_ui("ui.error")
			return
	var cost := int(upgrade.get("cost", 0))
	var sigils := int(mp.get_sigils()) if mp.has_method("get_sigils") else 0
	if sigils < cost:
		_play_ui("ui.error")
		return
	if mp.has_method("spend_sigils"):
		mp.spend_sigils(cost)
	if mp.has_method("unlock_upgrade"):
		mp.unlock_upgrade(upgrade_id)
	_play_ui("ui.levelup")
	_update_protocol_grid()

func _on_protocol_node_hovered(upgrade_id: String, hovered: bool) -> void:
	for node in _protocol_nodes:
		if String(node.get("id", "")) == upgrade_id:
			var panel: Control = node.get("panel")
			if panel:
				var t := panel.create_tween()
				t.tween_property(panel, "scale", Vector2(1.08, 1.08) if hovered else Vector2(1, 1), 0.10)
			break
