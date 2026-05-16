extends Control

# Main Menu - dark tactical sci-fi theme.
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
var _bg_reactor_ring: Node2D = null
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

@export var game_title: String = "SQUADSURVIVOR"
@export var game_tagline: String = "Recruit • Draft • Survive"
@export var footer_text: String = "Build 4.4 • Tactical Operations"

# ─────────────────────────────────────────────────────────────────────────────
# ASSETS (put the generated PNGs here)
# ─────────────────────────────────────────────────────────────────────────────
const BG_PATH: String = "res://assets/ui/revamp/menu_factory_bg.png"
const BG_NEAR_PATH: String = ""
const ASSET_PANEL: String = "res://assets/ui/revamp/codex_panel.png"
const CODEX_PANEL_PATH: String = "res://assets/ui/revamp/codex_panel.png"

const BTN_NORMAL: String = ""
const BTN_HOVER: String = ""
const BTN_PRESSED: String = ""
const BTN_DISABLED: String = ""

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
const TITLE_COLOR: Color = Color(0.92, 0.97, 1.0, 1.0)
const SUBTITLE_COLOR: Color = Color(0.70, 0.86, 1.0, 0.92)
const TEXT_DARK: Color = Color(0.06, 0.09, 0.14, 1.0)

const ACCENT_LEAF: Color = Color(0.35, 0.95, 0.85, 1.0)
const ACCENT_SUN: Color = Color(1.0, 0.72, 0.38, 1.0)
const ACCENT_BERRY: Color = Color(0.58, 0.72, 1.0, 1.0)

# Readability surfaces for map overlay
const SURFACE_BG := Color(0.04, 0.06, 0.10, 0.92)
const SURFACE_BG_SOFT := Color(0.03, 0.05, 0.08, 0.86)
const SURFACE_BORDER := Color(0.50, 0.74, 1.0, 0.28)
const LOCKED_FG := Color(0.72, 0.80, 0.90, 0.45)
const NORMAL_FG := Color(0.93, 0.97, 1.0, 1.0)

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
	_spawn_menu_crowd()
	_build_map_overlay()
	_connect_signals()

func _process(delta: float) -> void:
	_menu_anim_t += delta
	if _bg_far != null and is_instance_valid(_bg_far):
		_bg_far.position = Vector2(
			sin(_menu_anim_t * 0.16) * 20.0,
			cos(_menu_anim_t * 0.11) * 9.0
		)
	if _bg_near != null and is_instance_valid(_bg_near):
		_bg_near.position = Vector2(
			sin(_menu_anim_t * 0.22 + 1.3) * 34.0,
			cos(_menu_anim_t * 0.16 + 0.4) * 10.0
		)
	if _bg_light != null and is_instance_valid(_bg_light):
		_bg_light.modulate.a = 0.26 + sin(_menu_anim_t * 0.32) * 0.07
	if _bg_reactor_ring != null and is_instance_valid(_bg_reactor_ring):
		var vp_size := get_viewport_rect().size
		_bg_reactor_ring.position = Vector2(vp_size.x * 0.70, vp_size.y * 0.52) + Vector2(
			sin(_menu_anim_t * 0.28) * 8.0,
			cos(_menu_anim_t * 0.24) * 5.0
		)
	if _card != null and is_instance_valid(_card):
		_card.rotation = sin(_menu_anim_t * 0.55) * 0.002

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

	if _bg_reactor_ring == null or not is_instance_valid(_bg_reactor_ring):
		var ring := preload("res://scripts/MainMenuReactorRing.gd").new()
		ring.name = "MenuReactorRing"
		add_child(ring)
		move_child(ring, 3)
		_bg_reactor_ring = ring

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
	var c := preload("res://scripts/MainMenuAmbientLife.gd").new()
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
	# Main tactical panel card.
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

	_play_btn = _make_menu_button("▶ Deploy", true)
	vbox.add_child(_play_btn)

	_armory_btn = _make_menu_button("Collection / Squad", false)
	vbox.add_child(_armory_btn)

	_protocol_btn = _make_menu_button("Protocol Grid", false, ACCENT_BERRY)
	vbox.add_child(_protocol_btn)

	_info_btn = _make_menu_button("Codex", false)
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
	sb.bg_color = Color(0.08, 0.11, 0.18, 0.96)
	sb.border_width_left = 4
	sb.border_width_right = 4
	sb.border_width_top = 4
	sb.border_width_bottom = 4
	sb.border_color = Color(0.25, 0.55, 0.9, 0.45)
	sb.corner_radius_top_left = 22
	sb.corner_radius_top_right = 22
	sb.corner_radius_bottom_left = 22
	sb.corner_radius_bottom_right = 22
	sb.shadow_color = Color(0.05, 0.12, 0.22, 0.35)
	sb.shadow_size = 24
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

	if is_primary:
		UiSkin.style_primary_button(btn, accent)
	else:
		UiSkin.style_secondary_button(btn, accent)

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

func _make_codex_panel_style() -> StyleBox:
	var tex := _load_tex(CODEX_PANEL_PATH)
	if tex != null:
		var sbt := StyleBoxTexture.new()
		sbt.texture = tex
		sbt.texture_margin_left = 42
		sbt.texture_margin_right = 42
		sbt.texture_margin_top = 42
		sbt.texture_margin_bottom = 42
		sbt.content_margin_left = 20
		sbt.content_margin_right = 20
		sbt.content_margin_top = 16
		sbt.content_margin_bottom = 16
		return sbt
	return _make_panel_style()

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
				_close_protocol_overlay()
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
	panel.add_theme_stylebox_override("panel", _make_codex_panel_style())
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
	title.text = "TACTICAL CODEX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04, 1))
	title.add_theme_constant_override("outline_size", 6)
	_apply_font(title)
	v.add_child(title)

	var sub := Label.new()
	sub.text = "Search races, passives, synergies, weapons, and live tuning."
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
	_info_section.add_item("Races", 6)
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

	var cr := _load_json_dict("res://data/character_registry.json")
	var races := cr.get("races", {}) as Dictionary
	for rk in races.keys():
		var rv: Variant = races.get(rk, {})
		if typeof(rv) != TYPE_DICTIONARY:
			continue
		var rd := rv as Dictionary
		_info_entries.append({
			"section": "Races",
			"title": String(rk),
			"id": String(rk).to_lower(),
			"search": _join_string_array(rd.get("passive_slots", []) as Array),
			"text": String(rd.get("description", ""))
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
# PROTOCOL GRID (large draggable planner, PoE-inspired hierarchy)
# ─────────────────────────────────────────────────────────────────────────────

const PROTOCOL_GRID_BG_PATH: String = "res://assets/ui/revamp/protocol_grid_bg_v2.webp"
const PROTOCOL_GRID_FRAME_PATH: String = "res://assets/ui/revamp/protocol_grid_frame_v2.webp"
const PROTOCOL_NODE_RING_PATH: String = "res://assets/ui/revamp/protocol_node_ring_v2.webp"
const PROTOCOL_USE_FRAME_OVERLAY: bool = false
const PROTOCOL_ICON_DIR: String = "res://assets/ui/revamp/protocol_icons/"
const PROTOCOL_ICON_BY_FAMILY := {
	"core": "fam_core_v2.webp",
	"vitality": "fam_vitality_v2.webp",
	"offense": "fam_offense_v2.webp",
	"focus": "fam_focus_v2.webp",
	"rally": "fam_command_v2.webp",
	"squad": "fam_command_v2.webp",
	"dash": "fam_mobility_v2.webp",
	"mobility": "fam_mobility_v2.webp",
	"overclock": "fam_overclock_v2.webp",
	"misc": "fam_offense_v2.webp"
}
const PROTOCOL_KEYSTONE_ICON_BY_ID := {
	"starting_unit": "key_starting_unit_v3.webp",
	"focus_keystone": "key_focus_keystone_v3.webp",
	"rally_keystone": "key_rally_keystone_v3.webp",
	"dash_keystone": "key_dash_keystone_v3.webp",
	"squad_keystone": "key_squad_keystone_v3.webp",
	"oc_keystone": "key_oc_keystone_v3.webp",
	"oc_discharge": "key_oc_discharge_v3.webp",
	"starting_unit_2": "key_starting_unit_2_v3.webp",
	"dash_strider": "key_dash_strider_v3.webp",
	"bulwark_keystone": "key_bulwark_keystone_v3.webp",
	"tempo_keystone": "key_tempo_keystone_v3.webp",
	"sniper_grid": "key_marksman_v2.webp",
	"glass_core": "key_glass_v2.webp",
	"blood_circuit": "key_sustain_v2.webp",
	"oc_storm_keystone": "key_oc_storm_keystone_v3.webp",
	"execution_net": "key_execution_net_v3.webp",
	"point_blank_oath": "key_point_blank_oath_v3.webp",
	"conductor_oath": "key_conductor_oath_v3.webp",
	"phalanx_protocol": "key_phalanx_protocol_v3.webp",
	"headhunter_grid": "key_headhunter_grid_v3.webp",
	"fusion_overload": "key_fusion_v2.webp",
	"war_doctrine": "key_war_doctrine_v3.webp",
	"mindforge_oath": "key_mindforge_v2.webp",
	"reaper_clause": "key_reaper_clause_v3.webp",
	"eldritch_drive": "key_eldritch_v2.webp",
	"reaper_momentum": "key_momentum_v2.webp",
	"butcher_protocol": "key_butcher_v2.webp",
	"mirror_aegis": "key_mirror_v2.webp",
	"last_stand_kernel": "key_laststand_v2.webp",
	"feedback_loop": "key_feedback_v2.webp",
	"singularity_drive": "key_singularity_v2.webp",
	"bloodforge_oath": "key_bloodforge_v2.webp",
	"capacitor_lord": "key_capacitor_v2.webp"
}

var _protocol_overlay: Control = null
var _protocol_nodes: Array[Dictionary] = []
var _protocol_node_by_id: Dictionary = {}
var _protocol_edges: Array[Dictionary] = []
var _protocol_upgrades_runtime: Array[Dictionary] = []
var _protocol_selected_id: String = ""
var _protocol_sel_title: Label = null
var _protocol_sel_desc: Label = null
var _protocol_sel_cost: Label = null
var _protocol_buy_btn: Button = null
var _protocol_sigils_lbl: Label = null
var _protocol_sel_effects: RichTextLabel = null
var _protocol_graph_view: Control = null
var _protocol_graph_root: Control = null
var _protocol_dragging: bool = false
var _protocol_drag_candidate: bool = false
var _protocol_drag_start: Vector2 = Vector2.ZERO
var _protocol_drag_last: Vector2 = Vector2.ZERO
var _protocol_pan: Vector2 = Vector2.ZERO
var _protocol_zoom: float = 1.0
var _protocol_hover_id: String = ""
var _protocol_icon_cache: Dictionary = {}
var _protocol_node_ring_tex: Texture2D = null
var _protocol_search: LineEdit = null
var _protocol_search_query: String = ""

func _open_protocol_grid() -> void:
	if _crowd != null and is_instance_valid(_crowd):
		_crowd_prev_visible = _crowd.visible
		_crowd_prev_process_mode = _crowd.process_mode
		_crowd.visible = false
		_crowd.process_mode = Node.PROCESS_MODE_DISABLED
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
	bg.color = Color(0.02, 0.03, 0.06, 0.95)
	_protocol_overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.name = "PanelContainer"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var vp_h := get_viewport_rect().size.y
	var outer_margin := 26.0
	if vp_h <= 800.0:
		outer_margin = 12.0
	if vp_h <= 740.0:
		outer_margin = 8.0
	panel.offset_left = outer_margin
	panel.offset_top = outer_margin
	panel.offset_right = -outer_margin
	panel.offset_bottom = -outer_margin
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	_protocol_overlay.add_child(panel)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 8 if vp_h <= 760.0 else 12)
	pad.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "★ Protocol Grid"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.86, 0.91, 1.0, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_font(title)
	header.add_child(title)

	_protocol_sigils_lbl = Label.new()
	_protocol_sigils_lbl.name = "SigilsLabel"
	_protocol_sigils_lbl.text = "★ 0"
	_protocol_sigils_lbl.add_theme_font_size_override("font_size", 24)
	_protocol_sigils_lbl.add_theme_color_override("font_color", ACCENT_SUN)
	_apply_font(_protocol_sigils_lbl)
	header.add_child(_protocol_sigils_lbl)

	var sub := Label.new()
	sub.text = "Drag: Left Mouse  •  Zoom: Mouse Wheel  •  Keystone nodes reshape your run."
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.67, 0.78, 0.94, 0.98))
	_apply_font(sub)
	vbox.add_child(sub)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	vbox.add_child(search_row)

	var search_lbl := Label.new()
	search_lbl.text = "Search"
	search_lbl.add_theme_font_size_override("font_size", 13)
	search_lbl.add_theme_color_override("font_color", Color(0.76, 0.86, 0.99, 0.94))
	_apply_font(search_lbl)
	search_row.add_child(search_lbl)

	_protocol_search = LineEdit.new()
	_protocol_search.placeholder_text = "node, effect, element, weapon..."
	_protocol_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_protocol_search.text_changed.connect(func(t: String):
		_protocol_search_query = t.strip_edges().to_lower()
		_update_protocol_grid()
	)
	_protocol_search.text_submitted.connect(func(_t: String):
		_focus_first_protocol_search_match()
	)
	search_row.add_child(_protocol_search)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	var graph_frame := PanelContainer.new()
	# Important: never force a fixed graph height; this caused bottom clipping on 720p windows.
	graph_frame.custom_minimum_size = Vector2.ZERO
	graph_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_frame.add_theme_stylebox_override("panel", _sb_inset(14, 0.88))
	body.add_child(graph_frame)

	var graph_bg := TextureRect.new()
	graph_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	graph_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	graph_bg.stretch_mode = TextureRect.STRETCH_SCALE
	graph_bg.texture = _load_tex(PROTOCOL_GRID_BG_PATH)
	graph_bg.modulate = Color(0.96, 0.98, 1.0, 0.90)
	graph_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph_frame.add_child(graph_bg)

	var graph_vignette := ColorRect.new()
	graph_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	graph_vignette.color = Color(0.03, 0.04, 0.08, 0.22)
	graph_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph_frame.add_child(graph_vignette)

	if PROTOCOL_USE_FRAME_OVERLAY and ResourceLoader.exists(PROTOCOL_GRID_FRAME_PATH):
		var frame_tex := load(PROTOCOL_GRID_FRAME_PATH) as Texture2D
		if frame_tex != null:
			var frame_ov := TextureRect.new()
			frame_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
			frame_ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			frame_ov.stretch_mode = TextureRect.STRETCH_SCALE
			frame_ov.texture = frame_tex
			frame_ov.modulate = Color(1.0, 1.0, 1.0, 0.82)
			frame_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame_ov.z_index = 6
			graph_frame.add_child(frame_ov)

	_protocol_graph_view = Control.new()
	_protocol_graph_view.name = "GraphView"
	_protocol_graph_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_protocol_graph_view.clip_contents = true
	_protocol_graph_view.mouse_filter = Control.MOUSE_FILTER_STOP
	graph_frame.add_child(_protocol_graph_view)

	_protocol_graph_root = Control.new()
	_protocol_graph_root.name = "GraphRoot"
	_protocol_graph_root.custom_minimum_size = Vector2(6200, 4600)
	_protocol_graph_view.add_child(_protocol_graph_root)
	_protocol_zoom = 1.0
	_protocol_pan = Vector2.ZERO

	if PROTOCOL_USE_FRAME_OVERLAY and ResourceLoader.exists(PROTOCOL_GRID_FRAME_PATH):
		var frame_top_tex := load(PROTOCOL_GRID_FRAME_PATH) as Texture2D
		if frame_top_tex != null:
			var frame_top := TextureRect.new()
			frame_top.set_anchors_preset(Control.PRESET_FULL_RECT)
			frame_top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			frame_top.stretch_mode = TextureRect.STRETCH_SCALE
			frame_top.texture = frame_top_tex
			frame_top.modulate = Color(1.0, 1.0, 1.0, 0.68)
			frame_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
			graph_frame.add_child(frame_top)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(220, 0)
	side.size_flags_horizontal = Control.SIZE_SHRINK_END
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_stylebox_override("panel", _sb_inset(12, 0.96))
	body.add_child(side)

	var side_pad := MarginContainer.new()
	side_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	side_pad.add_theme_constant_override("margin_left", 10)
	side_pad.add_theme_constant_override("margin_right", 10)
	side_pad.add_theme_constant_override("margin_top", 10)
	side_pad.add_theme_constant_override("margin_bottom", 10)
	side.add_child(side_pad)

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	side_pad.add_child(sv)

	_protocol_sel_title = Label.new()
	_protocol_sel_title.text = "Select a node"
	_protocol_sel_title.add_theme_font_size_override("font_size", 20)
	_protocol_sel_title.add_theme_color_override("font_color", TITLE_COLOR)
	_apply_font(_protocol_sel_title)
	sv.add_child(_protocol_sel_title)

	_protocol_sel_desc = Label.new()
	_protocol_sel_desc.text = "Travel nodes are small. Keystone nodes are large build changers."
	_protocol_sel_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_protocol_sel_desc.add_theme_font_size_override("font_size", 13)
	_protocol_sel_desc.add_theme_color_override("font_color", SUBTITLE_COLOR)
	_apply_font(_protocol_sel_desc)
	sv.add_child(_protocol_sel_desc)

	_protocol_sel_cost = Label.new()
	_protocol_sel_cost.add_theme_font_size_override("font_size", 16)
	_protocol_sel_cost.add_theme_color_override("font_color", ACCENT_SUN)
	_apply_font(_protocol_sel_cost)
	sv.add_child(_protocol_sel_cost)

	_protocol_sel_effects = RichTextLabel.new()
	_protocol_sel_effects.bbcode_enabled = true
	_protocol_sel_effects.scroll_active = false
	_protocol_sel_effects.fit_content = true
	_protocol_sel_effects.add_theme_font_size_override("normal_font_size", 12)
	_protocol_sel_effects.add_theme_color_override("default_color", Color(0.80, 0.90, 1.0, 0.95))
	sv.add_child(_protocol_sel_effects)

	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.scroll_active = false
	legend.fit_content = true
	legend.text = "[color=#66ff99]● Owned[/color]  [color=#aee1ff]● Available[/color]  [color=#55657a]● Locked[/color]  [color=#ffd36b]⬢ Keystone[/color]"
	legend.add_theme_font_size_override("normal_font_size", 12)
	legend.add_theme_color_override("default_color", Color(0.74, 0.84, 0.95, 0.9))
	sv.add_child(legend)

	sv.add_spacer(true)

	_protocol_buy_btn = _make_menu_button("Unlock Node", true)
	_protocol_buy_btn.custom_minimum_size = Vector2(0, 48)
	_protocol_buy_btn.pressed.connect(func():
		if _protocol_selected_id == "":
			_play_ui("ui.error")
			return
		_unlock_protocol_node(_protocol_selected_id)
	)
	sv.add_child(_protocol_buy_btn)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var back_btn := _make_menu_button("← Back", false)
	back_btn.custom_minimum_size = Vector2(180, 44)
	back_btn.pressed.connect(func():
		_play_ui("ui.cancel")
		_close_protocol_overlay()
	)
	btn_row.add_child(back_btn)

	_build_protocol_graph()
	_update_protocol_grid()
	call_deferred("_focus_protocol_graph")

func _build_protocol_graph() -> void:
	if _protocol_graph_root == null or not is_instance_valid(_protocol_graph_root):
		return
	for c in _protocol_graph_root.get_children():
		c.queue_free()
	_protocol_nodes.clear()
	_protocol_edges.clear()
	_protocol_node_by_id.clear()
	_protocol_upgrades_runtime = _protocol_data()
	for upgrade in _protocol_upgrades_runtime:
		var node := _create_protocol_node(upgrade)
		_protocol_graph_root.add_child(node["panel"])
		_protocol_nodes.append(node)
		_protocol_node_by_id[node["id"]] = node
	_draw_protocol_lines(_protocol_graph_root)
	_layout_protocol_tree(_protocol_graph_root)

func _create_protocol_node(upgrade: Dictionary) -> Dictionary:
	var graph_pos: Vector2 = upgrade.get("graph_pos", Vector2.ZERO) as Vector2
	var node_color := _protocol_node_accent_color(upgrade, String(upgrade.get("id", "")))
	var is_keystone := bool(upgrade.get("is_keystone", false))
	var is_major := bool(upgrade.get("is_major", false))

	var node_size := Vector2(52, 52)
	if is_major:
		node_size = Vector2(78, 78)
	if is_keystone:
		node_size = Vector2(116, 116)

	var panel := PanelContainer.new()
	panel.name = String(upgrade.get("id", "node"))
	panel.custom_minimum_size = node_size
	panel.position = graph_pos - node_size * 0.5
	panel.z_index = 4

	if _protocol_node_ring_tex == null and ResourceLoader.exists(PROTOCOL_NODE_RING_PATH):
		_protocol_node_ring_tex = load(PROTOCOL_NODE_RING_PATH) as Texture2D
	if _protocol_node_ring_tex != null:
		var ring := TextureRect.new()
		ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ring.texture = _protocol_node_ring_tex
		ring.modulate = Color(node_color.r, node_color.g, node_color.b, 0.60 if not is_keystone else 0.78)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(ring)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.94)
	sb.border_color = Color(node_color.r, node_color.g, node_color.b, 0.92)
	var radius := int(node_size.y * 0.5)
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = 3 if is_keystone else 2
	sb.border_width_right = 3 if is_keystone else 2
	sb.border_width_top = 3 if is_keystone else 2
	sb.border_width_bottom = 3 if is_keystone else 2
	sb.shadow_color = Color(node_color.r, node_color.g, node_color.b, 0.22)
	sb.shadow_size = 8 if is_keystone else 6
	panel.add_theme_stylebox_override("panel", sb)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var vcenter := VBoxContainer.new()
	vcenter.alignment = BoxContainer.ALIGNMENT_CENTER
	vcenter.add_theme_constant_override("separation", 2)
	center.add_child(vcenter)

	var icon_tex := _protocol_icon_texture_for_id(String(upgrade.get("id", "")), is_keystone)
	if icon_tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_tex
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_size := 22.0 if not is_major else 30.0
		if is_keystone:
			icon_size = 44.0
		icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
		icon_rect.modulate = Color(1.0, 1.0, 1.0, 0.98)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vcenter.add_child(icon_rect)
	else:
		var icon_lbl := Label.new()
		icon_lbl.text = String(upgrade.get("icon", "N"))
		icon_lbl.add_theme_font_size_override("font_size", 14 if not is_major else 18)
		if is_keystone:
			icon_lbl.add_theme_font_size_override("font_size", 22)
		icon_lbl.add_theme_color_override("font_color", node_color)
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_apply_font(icon_lbl)
		vcenter.add_child(icon_lbl)

	var mini := Label.new()
	mini.text = _protocol_short_name(String(upgrade.get("name", "")))
	mini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mini.add_theme_font_size_override("font_size", 8 if not is_keystone else 9)
	mini.add_theme_color_override("font_color", Color(0.84, 0.92, 1.0, 0.90))
	_apply_font(mini)
	if is_keystone or is_major:
		vcenter.add_child(mini)

	var btn_overlay := Button.new()
	btn_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_overlay.flat = true
	btn_overlay.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_child(btn_overlay)

	var upgrade_id := String(upgrade.get("id", ""))
	panel.tooltip_text = "%s\n%s\nCost: ★ %d" % [
		String(upgrade.get("name", upgrade_id)),
		String(upgrade.get("desc", "")),
		int(upgrade.get("cost", 0))
	]
	btn_overlay.pressed.connect(func():
		_protocol_selected_id = upgrade_id
		_update_protocol_grid()
		var tw := panel.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "scale", Vector2(1.16, 1.16), 0.06)
		tw.tween_property(panel, "scale", Vector2(1.10, 1.10), 0.08)
	)
	btn_overlay.mouse_entered.connect(func():
		_protocol_hover_id = upgrade_id
		_on_protocol_node_hovered(upgrade_id, true)
		_update_protocol_grid()
	)
	btn_overlay.mouse_exited.connect(func():
		if _protocol_hover_id == upgrade_id:
			_protocol_hover_id = ""
		_on_protocol_node_hovered(upgrade_id, false)
		_update_protocol_grid()
	)

	return {
		"id": upgrade_id,
		"panel": panel,
		"color": node_color,
		"upgrade": upgrade,
		"is_keystone": is_keystone,
		"is_major": is_major
	}

func _draw_protocol_lines(container: Control) -> void:
	for ch in container.get_children():
		if ch is Line2D:
			ch.queue_free()
		elif ch is Control and String(ch.name).begins_with("EdgeDot_"):
			ch.queue_free()
	_protocol_edges.clear()
	for node in _protocol_nodes:
		var upgrade: Dictionary = node.get("upgrade", {})
		var prereqs: Array = upgrade.get("prereq", [])
		var panel: Control = node.get("panel")
		if panel == null:
			continue
		var to_pos := panel.position + panel.size * 0.5
		for prereq_id in prereqs:
			var from: Dictionary = _protocol_node_by_id.get(String(prereq_id), {}) as Dictionary
			var from_panel: Control = from.get("panel", null) as Control
			if from_panel == null:
				continue
			var from_pos := from_panel.position + from_panel.size * 0.5
			var fam_col := _protocol_node_accent_color(upgrade, String(node.get("id", "")))
			var line := Line2D.new()
			line.width = 3.2
			line.default_color = Color(fam_col.r, fam_col.g, fam_col.b, 0.68)
			line.antialiased = true
			line.points = [from_pos, to_pos]
			line.z_index = 3
			var under := Line2D.new()
			under.width = 8.2
			under.default_color = Color(fam_col.r * 0.45, fam_col.g * 0.45, fam_col.b * 0.45, 0.22)
			under.antialiased = true
			under.points = [from_pos, to_pos]
			under.z_index = 2
			container.add_child(under)
			container.add_child(line)
			# Add small "travel beads" so paths read as continuous build routes.
			var segment_len := from_pos.distance_to(to_pos)
			var bead_count := maxi(1, int(segment_len / 120.0))
			for bi in range(1, bead_count):
				var t := float(bi) / float(bead_count)
				var bp := from_pos.lerp(to_pos, t)
				var dot := ColorRect.new()
				dot.name = "EdgeDot_%s_%s_%d" % [String(prereq_id), String(node.get("id", "")), bi]
				dot.color = Color(fam_col.r, fam_col.g, fam_col.b, 0.72)
				dot.custom_minimum_size = Vector2(6, 6)
				dot.position = bp - Vector2(3, 3)
				dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
				dot.z_index = 3
				container.add_child(dot)
			_protocol_edges.append({"from": String(prereq_id), "to": String(node.get("id", "")), "line": line, "under": under, "family_color": fam_col})

func _update_protocol_grid() -> void:
	var mp := get_node_or_null("/root/MetaProgression")
	var sigils := 0
	var unlocked: Array = []
	if mp and is_instance_valid(mp):
		if mp.has_method("get_sigils"):
			sigils = int(mp.get_sigils())
		if mp.has_method("get_unlocked_upgrades"):
			unlocked = mp.get_unlocked_upgrades()

	if _protocol_sigils_lbl != null and is_instance_valid(_protocol_sigils_lbl):
		_protocol_sigils_lbl.text = "★ %d" % sigils

	var detail_id := _protocol_selected_id if _protocol_hover_id == "" else _protocol_hover_id
	var trace_ids := _protocol_trace_ids(detail_id)

	for node in _protocol_nodes:
		var id := String(node.get("id", ""))
		var panel: PanelContainer = node.get("panel", null) as PanelContainer
		var upgrade: Dictionary = node.get("upgrade", {})
		if panel == null:
			continue
		var matches_search := _protocol_node_matches_search(upgrade)

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
			panel.self_modulate = Color(0.90, 1.0, 0.94, 1.0)
		elif prereqs_met and can_afford:
			panel.self_modulate = Color(0.98, 1.0, 1.0, 1.0)
		elif prereqs_met:
			panel.self_modulate = Color(0.84, 0.90, 0.98, 0.95)
		else:
			panel.self_modulate = Color(0.58, 0.64, 0.74, 0.82)
		if _protocol_search_query != "" and not matches_search:
			panel.self_modulate = Color(panel.self_modulate.r * 0.56, panel.self_modulate.g * 0.56, panel.self_modulate.b * 0.58, 0.26)
		panel.modulate = Color(1, 1, 1, 1)
		panel.scale = Vector2(1.10, 1.10) if id == _protocol_selected_id else (Vector2(1.06, 1.06) if trace_ids.has(id) else Vector2.ONE)
		if trace_ids.has(id) and not is_unlocked:
			panel.self_modulate = Color(
				minf(1.0, panel.self_modulate.r + 0.10),
				minf(1.0, panel.self_modulate.g + 0.10),
				minf(1.0, panel.self_modulate.b + 0.10),
				panel.self_modulate.a
			)

	for e in _protocol_edges:
		var line := e.get("line", null) as Line2D
		var under := e.get("under", null) as Line2D
		if line == null:
			continue
		var from_id := String(e.get("from", ""))
		var to_id := String(e.get("to", ""))
		var edge_visible := true
		if _protocol_search_query != "":
			var from_u := _protocol_find_upgrade(from_id)
			var to_u := _protocol_find_upgrade(to_id)
			edge_visible = _protocol_node_matches_search(from_u) or _protocol_node_matches_search(to_u)
		var from_owned := from_id in unlocked
		var to_owned := to_id in unlocked
		var to_available := from_owned and (not to_owned)
		var fam_col := e.get("family_color", Color(0.57, 0.85, 1.0, 1.0)) as Color
		if trace_ids.has(from_id) and trace_ids.has(to_id):
			line.default_color = Color(1.0, 0.92, 0.58, 0.95)
			line.width = 4.8
			if under != null:
				under.default_color = Color(1.0, 0.82, 0.38, 0.30)
				under.width = 10.2
		elif from_owned and to_owned:
			line.default_color = Color(0.55, 1.0, 0.70, 0.84)
			line.width = 4.0
			if under != null:
				under.default_color = Color(0.35, 0.95, 0.55, 0.22)
				under.width = 8.8
		elif to_available:
			line.default_color = Color(fam_col.r, fam_col.g, fam_col.b, 0.78)
			line.width = 3.6
			if under != null:
				under.default_color = Color(fam_col.r * 0.45, fam_col.g * 0.45, fam_col.b * 0.45, 0.18)
				under.width = 8.0
		else:
			line.default_color = Color(fam_col.r * 0.75, fam_col.g * 0.75, fam_col.b * 0.75, 0.42)
			line.width = 3.0
			if under != null:
				under.default_color = Color(fam_col.r * 0.35, fam_col.g * 0.35, fam_col.b * 0.35, 0.12)
				under.width = 7.2
		if not edge_visible:
			line.default_color = Color(line.default_color.r, line.default_color.g, line.default_color.b, line.default_color.a * 0.18)
			line.width = maxf(1.2, line.width * 0.62)
			if under != null:
				under.default_color = Color(under.default_color.r, under.default_color.g, under.default_color.b, under.default_color.a * 0.12)
				under.width = maxf(2.0, under.width * 0.62)

	if _protocol_sel_title != null and _protocol_sel_desc != null and _protocol_sel_cost != null:
		var nd := _protocol_find_upgrade(detail_id)
		if nd.is_empty():
			_protocol_sel_title.text = "Select a node"
			_protocol_sel_desc.text = "Choose a path node to plan your build."
			_protocol_sel_cost.text = ""
			if _protocol_sel_effects:
				_protocol_sel_effects.text = ""
			if _protocol_buy_btn:
				_protocol_buy_btn.disabled = true
		else:
			_protocol_sel_title.text = String(nd.get("name", detail_id))
			_protocol_sel_desc.text = String(nd.get("desc", ""))
			var cst := int(nd.get("cost", 0))
			var owned := detail_id in unlocked
			_protocol_sel_cost.text = "Owned" if owned else ("Cost: ★ %d" % cst)
			if _protocol_sel_effects:
				_protocol_sel_effects.text = _protocol_effects_bbcode(nd)
			if _protocol_buy_btn:
				var pre_ok := true
				for pr in nd.get("prereq", []):
					if not String(pr) in unlocked:
						pre_ok = false
						break
				_protocol_buy_btn.disabled = owned or (not pre_ok) or (sigils < cst)
func _unlock_protocol_node(upgrade_id: String) -> void:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp):
		return
	var upgrade := _protocol_find_upgrade(upgrade_id)
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

func _protocol_find_upgrade(id: String) -> Dictionary:
	for u in _protocol_upgrades_runtime:
		if String(u.get("id", "")) == id:
			return u
	return {}

func _on_protocol_node_hovered(upgrade_id: String, hovered: bool) -> void:
	for node in _protocol_nodes:
		if String(node.get("id", "")) != upgrade_id:
			continue
		var panel: Control = node.get("panel", null) as Control
		if panel == null:
			break
		var target_scale := Vector2(1.08, 1.08) if String(node.get("id", "")) == _protocol_selected_id else Vector2.ONE
		if hovered:
			target_scale = Vector2(1.12, 1.12)
		var t := panel.create_tween()
		t.tween_property(panel, "scale", target_scale, 0.10)
		break

func _close_protocol_overlay() -> void:
	if _protocol_overlay == null:
		return
	_protocol_overlay.visible = false
	_protocol_drag_candidate = false
	_protocol_dragging = false
	_protocol_hover_id = ""
	_protocol_search_query = ""
	if _protocol_search != null and is_instance_valid(_protocol_search):
		_protocol_search.clear()
	if _crowd != null and is_instance_valid(_crowd):
		_crowd.visible = _crowd_prev_visible
		_crowd.process_mode = _crowd_prev_process_mode
	if _play_btn:
		_play_btn.grab_focus()

func _layout_protocol_tree(root: Control) -> void:
	if root == null or not is_instance_valid(root):
		return
	if _protocol_nodes.is_empty():
		return
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for n in _protocol_nodes:
		var panel := n.get("panel", null) as Control
		if panel == null:
			continue
		var center := panel.position + panel.size * 0.5
		minp.x = minf(minp.x, center.x)
		minp.y = minf(minp.y, center.y)
		maxp.x = maxf(maxp.x, center.x)
		maxp.y = maxf(maxp.y, center.y)
	var padding := Vector2(260, 240)
	root.custom_minimum_size = Vector2(
		maxf(2200.0, (maxp.x - minp.x) + padding.x * 2.0),
		maxf(1600.0, (maxp.y - minp.y) + padding.y * 2.0)
	)
	var shift := Vector2(padding.x - minp.x, padding.y - minp.y)
	for n2 in _protocol_nodes:
		var panel2 := n2.get("panel", null) as Control
		if panel2 == null:
			continue
		panel2.position += shift
	_draw_protocol_lines(root)
	_clamp_protocol_pan()
	_apply_protocol_pan()

func _focus_protocol_graph() -> void:
	if _protocol_graph_view == null or not is_instance_valid(_protocol_graph_view):
		return
	if _protocol_graph_root == null or not is_instance_valid(_protocol_graph_root):
		return
	var target := Vector2(_protocol_graph_root.custom_minimum_size.x * 0.5, _protocol_graph_root.custom_minimum_size.y * 0.5)
	var mp := get_node_or_null("/root/MetaProgression")
	var unlocked: Array = []
	if mp and is_instance_valid(mp) and mp.has_method("get_unlocked_upgrades"):
		unlocked = mp.get_unlocked_upgrades()
	for n in _protocol_nodes:
		var id := String(n.get("id", ""))
		if id in unlocked:
			var panel := n.get("panel", null) as Control
			if panel != null:
				target = panel.position + panel.size * 0.5
				if _protocol_selected_id == "":
					_protocol_selected_id = id
				break
	var viewport_size := _protocol_graph_view.size
	_protocol_pan = viewport_size * 0.5 - target * _protocol_zoom
	_clamp_protocol_pan()
	_apply_protocol_pan()
	_update_protocol_grid()

func _focus_protocol_node(id: String) -> void:
	if _protocol_graph_view == null or not is_instance_valid(_protocol_graph_view):
		return
	var nd := _protocol_node_by_id.get(id, {}) as Dictionary
	var panel := nd.get("panel", null) as Control
	if panel == null:
		return
	var target := panel.position + panel.size * 0.5
	var viewport_size := _protocol_graph_view.size
	_protocol_pan = viewport_size * 0.5 - target * _protocol_zoom
	_clamp_protocol_pan()
	_apply_protocol_pan()

func _protocol_data() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp) or (not mp.has_method("tree_data")):
		return out
	var tree: Dictionary = mp.tree_data()
	var nodes: Array = tree.get("nodes", []) as Array
	var filtered: Array[Dictionary] = []
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for n in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var d := n as Dictionary
		var id := String(d.get("id", ""))
		if id == "":
			continue
		var pos_arr := d.get("pos", [0, 0]) as Array
		var px := float(pos_arr[0]) if pos_arr.size() > 0 else 0.0
		var py := float(pos_arr[1]) if pos_arr.size() > 1 else 0.0
		d["__pos_v2"] = Vector2(px, py)
		filtered.append(d)
		minp.x = minf(minp.x, px)
		minp.y = minf(minp.y, py)
		maxp.x = maxf(maxp.x, px)
		maxp.y = maxf(maxp.y, py)
	if filtered.is_empty():
		return out

	var graph_size := Vector2(6200, 4600)
	var margin := Vector2(430, 340)
	var span := maxp - minp
	var inv_span := Vector2(1.0 / maxf(1.0, span.x), 1.0 / maxf(1.0, span.y))
	for d2 in filtered:
		var id2 := String(d2.get("id", ""))
		var name2 := String(d2.get("name", id2))
		var desc2 := String(d2.get("desc", ""))
		var cost2 := int(d2.get("cost", 0))
		var prereq_raw := d2.get("prereq", []) as Array
		var prereq: Array[String] = []
		for p in prereq_raw:
			var ps := String(p)
			if ps != "":
				prereq.append(ps)
		var pos_v: Vector2 = d2.get("__pos_v2", Vector2.ZERO) as Vector2
		var nx := (pos_v.x - minp.x) * inv_span.x
		var ny := (pos_v.y - minp.y) * inv_span.y
		var gp := Vector2(
			margin.x + nx * (graph_size.x - margin.x * 2.0),
			margin.y + ny * (graph_size.y - margin.y * 2.0)
		)
		# Slight constellation jitter so travel chains don't feel like straight rails.
		gp += Vector2(sin(gp.y * 0.006 + gp.x * 0.001) * 24.0, cos(gp.x * 0.005 + gp.y * 0.001) * 20.0)
		out.append({
			"id": id2,
			"name": name2,
			"desc": desc2,
			"cost": cost2,
			"icon": _protocol_icon_for_node(d2),
			"color": _protocol_color_for_node(d2),
			"is_keystone": _protocol_is_keystone(d2),
			"is_major": _protocol_is_major(d2),
			"prereq": prereq,
			"graph_pos": gp,
			"cluster": String(d2.get("cluster", "")),
			"search": _protocol_node_search_blob(d2)
		})
	return out

func _protocol_node_search_blob(node: Dictionary) -> String:
	var bits: Array[String] = []
	bits.append(String(node.get("id", "")))
	bits.append(String(node.get("name", "")))
	bits.append(String(node.get("desc", "")))
	bits.append(String(node.get("cluster", "")))
	for t in node.get("tags", []) as Array:
		bits.append(String(t))
	var mods := node.get("mods", {}) as Dictionary
	for k in mods.keys():
		bits.append(String(k))
	return " ".join(bits).to_lower()

func _protocol_node_matches_search(upgrade: Dictionary) -> bool:
	if _protocol_search_query == "":
		return true
	if upgrade.is_empty():
		return false
	return String(upgrade.get("search", "")).find(_protocol_search_query) >= 0

func _focus_first_protocol_search_match() -> void:
	if _protocol_search_query == "":
		return
	for u in _protocol_upgrades_runtime:
		if not _protocol_node_matches_search(u):
			continue
		var id := String(u.get("id", ""))
		if id == "":
			continue
		_protocol_selected_id = id
		_focus_protocol_node(id)
		_update_protocol_grid()
		return

func _apply_protocol_pan() -> void:
	if _protocol_graph_root == null or not is_instance_valid(_protocol_graph_root):
		return
	_protocol_graph_root.scale = Vector2.ONE * _protocol_zoom
	_protocol_graph_root.position = _protocol_pan

func _clamp_protocol_pan() -> void:
	if _protocol_graph_view == null or not is_instance_valid(_protocol_graph_view):
		return
	if _protocol_graph_root == null or not is_instance_valid(_protocol_graph_root):
		return
	var view_size := _protocol_graph_view.size
	var root_size := _protocol_graph_root.custom_minimum_size * _protocol_zoom
	if root_size.x <= view_size.x:
		_protocol_pan.x = (view_size.x - root_size.x) * 0.5
	else:
		var over_x := 220.0
		var min_x := view_size.x - root_size.x - over_x
		var max_x := over_x
		_protocol_pan.x = clampf(_protocol_pan.x, min_x, max_x)
	if root_size.y <= view_size.y:
		_protocol_pan.y = (view_size.y - root_size.y) * 0.5
	else:
		var over_y := 180.0
		var min_y := view_size.y - root_size.y - over_y
		var max_y := over_y
		_protocol_pan.y = clampf(_protocol_pan.y, min_y, max_y)

func _set_protocol_zoom(new_zoom: float, screen_pos: Vector2) -> void:
	if _protocol_graph_view == null or not is_instance_valid(_protocol_graph_view):
		return
	var graph_rect := _protocol_graph_view.get_global_rect()
	var local := screen_pos - graph_rect.position
	var before := (local - _protocol_pan) / maxf(0.001, _protocol_zoom)
	_protocol_zoom = clampf(new_zoom, 0.55, 1.85)
	_protocol_pan = local - before * _protocol_zoom
	_clamp_protocol_pan()
	_apply_protocol_pan()

func _input(event: InputEvent) -> void:
	if _protocol_overlay == null or not is_instance_valid(_protocol_overlay) or (not _protocol_overlay.visible):
		return
	if _protocol_graph_view == null or not is_instance_valid(_protocol_graph_view):
		return
	var graph_rect := _protocol_graph_view.get_global_rect()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and graph_rect.has_point(mb.position):
				_protocol_drag_candidate = true
				_protocol_dragging = false
				_protocol_drag_start = mb.position
				_protocol_drag_last = mb.position
			elif not mb.pressed:
				if _protocol_dragging:
					get_viewport().set_input_as_handled()
				_protocol_drag_candidate = false
				_protocol_dragging = false
		elif (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and graph_rect.has_point(mb.position):
			var step := 1.11 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / 1.11)
			_set_protocol_zoom(_protocol_zoom * step, mb.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _protocol_drag_candidate:
			var moved := mm.position.distance_to(_protocol_drag_start)
			if moved > 8.0:
				_protocol_dragging = true
			if _protocol_dragging:
				_protocol_pan += mm.relative
				_clamp_protocol_pan()
				_apply_protocol_pan()
				_protocol_drag_last = mm.position
				get_viewport().set_input_as_handled()

func _protocol_icon_for_node(node: Dictionary) -> String:
	var tags := node.get("tags", []) as Array
	for t in tags:
		if String(t) == "keystone":
			return "KEY"
	var id := String(node.get("id", ""))
	if id.find("hp_") >= 0:
		return "HP"
	if id.find("dmg_") >= 0:
		return "DMG"
	if id.find("armor_") >= 0 or id.find("bulwark") >= 0:
		return "ARM"
	if id.find("speed") >= 0 or id.find("dash") >= 0:
		return "SPD"
	if id.find("tempo") >= 0:
		return "AS"
	if id.find("crit") >= 0:
		return "CRT"
	if id.find("ballistics") >= 0 or id.find("sniper") >= 0:
		return "RNG"
	if id.find("essence") >= 0:
		return "ESS"
	if id.find("recycle") >= 0 or id.find("blood_circuit") >= 0:
		return "HEAL"
	if id.find("focus") >= 0:
		return "FOC"
	if id.find("predator") >= 0 or id.find("execution") >= 0:
		return "HNT"
	if id.find("aether") >= 0 or id.find("mindforge") >= 0:
		return "MND"
	if id.find("surge") >= 0 or id.find("conductor") >= 0:
		return "SRG"
	if id.find("rally") >= 0:
		return "RLY"
	if id.find("bridge") >= 0:
		return "LNK"
	if id.find("squad") >= 0:
		return "SQD"
	if id.find("anchor") >= 0 or id.find("phalanx") >= 0:
		return "ANK"
	if id.find("brawler") >= 0 or id.find("point_blank") >= 0:
		return "CLS"
	if id.find("crit_weave") >= 0 or id.find("headhunter") >= 0:
		return "CRX"
	if id.find("oc_") >= 0 or id.find("overclock") >= 0:
		return "ARC"
	return "MOD"

func _protocol_color_for_node(node: Dictionary) -> String:
	var tags := node.get("tags", []) as Array
	for t in tags:
		if String(t) == "keystone":
			return "#ffd36b"
	var id := String(node.get("id", ""))
	if id.find("hp_") >= 0:
		return "#ff6464"
	if id.find("dmg_") >= 0:
		return "#ff9850"
	if id.find("speed") >= 0 or id.find("dash") >= 0:
		return "#66ff9a"
	if id.find("crit") >= 0:
		return "#ffe066"
	if id.find("essence") >= 0:
		return "#66d2ff"
	if id.find("focus") >= 0:
		return "#9a8cff"
	if id.find("predator") >= 0 or id.find("execution") >= 0:
		return "#b69bff"
	if id.find("aether") >= 0 or id.find("mindforge") >= 0:
		return "#6ed1ff"
	if id.find("static_drive") >= 0 or id.find("eldritch_drive") >= 0:
		return "#9f86ff"
	if id.find("surge") >= 0 or id.find("conductor") >= 0:
		return "#7bb7ff"
	if id.find("rally") >= 0:
		return "#5ec6ff"
	if id.find("bridge") >= 0:
		return "#7ec7d8"
	if id.find("squad") >= 0:
		return "#7dffcb"
	if id.find("anchor") >= 0 or id.find("phalanx") >= 0:
		return "#69d8a0"
	if id.find("brawler") >= 0 or id.find("point_blank") >= 0:
		return "#ff8f6c"
	if id.find("crit_weave") >= 0 or id.find("headhunter") >= 0:
		return "#ffa76d"
	if id.find("oc_") >= 0 or id.find("overclock") >= 0:
		return "#c288ff"
	return "#9eb8ff"

func _protocol_is_keystone(node: Dictionary) -> bool:
	var tags := node.get("tags", []) as Array
	for t in tags:
		if String(t) == "keystone":
			return true
	return false

func _protocol_family_key(id: String) -> String:
	if id == "core_0":
		return "core"
	if id.begins_with("storm_") or id.find("closed_circuit") >= 0:
		return "overclock"
	if id.begins_with("fire_") or id.find("ash_economy") >= 0:
		return "offense"
	if id.begins_with("frost_") or id.find("stillness_tax") >= 0:
		return "focus"
	if id.begins_with("poison_") or id.find("terminal_dose") >= 0:
		return "rally"
	if id.begins_with("proj_"):
		return "offense"
	if id.begins_with("scatter_"):
		return "offense"
	if id.begins_with("rico_") or id.begins_with("pierce_"):
		return "focus"
	if id.begins_with("bomb_"):
		return "offense"
	if id.begins_with("beam_"):
		return "focus"
	if id.begins_with("orbital_"):
		return "focus"
	if id.begins_with("hybrid_"):
		return "squad"
	if id.begins_with("hp_") or id.begins_with("crit_"):
		return "vitality"
	if id.begins_with("armor_") or id.find("bulwark") >= 0:
		return "vitality"
	if id.begins_with("dmg_") or id.begins_with("essence_") or id.begins_with("draft_") or id.begins_with("starting_"):
		return "offense"
	if id.begins_with("tempo_") or id.find("glass_core") >= 0:
		return "offense"
	if id.begins_with("ballistics_") or id.find("sniper_grid") >= 0:
		return "focus"
	if id.begins_with("recycle_") or id.find("blood_circuit") >= 0:
		return "rally"
	if id.begins_with("tactician_") or id.find("war_doctrine") >= 0:
		return "rally"
	if id.begins_with("focus_"):
		return "focus"
	if id.begins_with("rally_"):
		return "rally"
	if id.begins_with("squad_"):
		return "squad"
	if id.begins_with("dash_"):
		return "dash"
	if id.begins_with("oc_"):
		return "overclock"
	if id.begins_with("speed_"):
		return "mobility"
	if id.begins_with("surge_") or id.find("conductor") >= 0:
		return "overclock"
	if id.begins_with("fusion_") or id.find("fusion_overload") >= 0:
		return "overclock"
	if id.begins_with("aether_") or id.find("mindforge") >= 0:
		return "overclock"
	if id.begins_with("static_drive_") or id.find("eldritch_drive") >= 0:
		return "overclock"
	if id.begins_with("execution_") or id.find("reaper_clause") >= 0:
		return "offense"
	if id.begins_with("execution_blast_") or id.find("butcher_protocol") >= 0:
		return "offense"
	if id.begins_with("momentum_") or id.find("reaper_momentum") >= 0:
		return "offense"
	if id.begins_with("anchor_") or id.find("phalanx") >= 0:
		return "squad"
	if id.begins_with("crit_weave_") or id.find("headhunter") >= 0:
		return "offense"
	if id.begins_with("aether_feedback_") or id.find("mirror_aegis") >= 0:
		return "overclock"
	if id.begins_with("overfeed_") or id.find("feedback_loop") >= 0 or id.find("capacitor_lord") >= 0:
		return "overclock"
	if id.begins_with("laststand_") or id.find("bloodforge_oath") >= 0:
		return "rally"
	if id.begins_with("doctrine_link_") or id.find("singularity_drive") >= 0:
		return "squad"
	return "misc"

func _protocol_node_depth(id: String, node_by_id: Dictionary, cache: Dictionary) -> int:
	if cache.has(id):
		return int(cache[id])
	if id == "core_0":
		cache[id] = 0
		return 0
	var node := node_by_id.get(id, {}) as Dictionary
	var prereq := node.get("prereq", []) as Array
	if prereq.is_empty():
		cache[id] = 1
		return 1
	var best := 0
	for p in prereq:
		var pid := String(p)
		if pid == "":
			continue
		best = maxi(best, _protocol_node_depth(pid, node_by_id, cache))
	cache[id] = best + 1
	return best + 1

func _protocol_is_major(node: Dictionary) -> bool:
	if _protocol_is_keystone(node):
		return false
	var tags := node.get("tags", []) as Array
	for t in tags:
		if String(t) == "notable" or String(t) == "major":
			return true
	var cost := int(node.get("cost", 0))
	var prereq := node.get("prereq", []) as Array
	return cost >= 450 or prereq.size() >= 2

func _protocol_short_name(name_txt: String) -> String:
	if name_txt.is_empty():
		return ""
	var parts := name_txt.split(" ", false)
	var out := ""
	for p in parts:
		if p.is_empty():
			continue
		out += p.substr(0, 1).to_upper()
		if out.length() >= 3:
			break
	if out.is_empty():
		out = name_txt.substr(0, mini(3, name_txt.length())).to_upper()
	return out

func _protocol_effects_bbcode(node: Dictionary) -> String:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp) or (not mp.has_method("tree_data")):
		return ""
	var td: Dictionary = mp.tree_data()
	var nodes: Array = td.get("nodes", []) as Array
	var target_id := String(node.get("id", ""))
	for n in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var d := n as Dictionary
		if String(d.get("id", "")) != target_id:
			continue
		var mods := d.get("mods", {}) as Dictionary
		if mods.is_empty():
			return "[color=#7f93aa]No direct stat changes[/color]"
		var lines: Array[String] = []
		for k in mods.keys():
			var key := String(k)
			var val := float(mods.get(k, 0.0))
			if key.ends_with("_mult"):
				var pct := (val - 1.0) * 100.0
				var sign := "+" if pct >= 0.0 else ""
				lines.append("• %s: %s%d%%" % [_protocol_label_for_mod(key), sign, int(round(pct))])
			else:
				var sign2 := "+" if val >= 0.0 else ""
				lines.append("• %s: %s%s" % [_protocol_label_for_mod(key), sign2, str(snappedf(val, 0.01))])
		return "[b]Node Effects[/b]\n%s" % "\n".join(lines)
	return ""

func _protocol_label_for_mod(key: String) -> String:
	match key:
		"squad_hp_mult": return "Squad HP"
		"squad_damage_mult": return "Squad Damage"
		"squad_speed_mult": return "Squad Speed"
		"squad_crit_add": return "Crit Chance"
		"essence_mult": return "Essence Gain"
		"draft_rarity_boost": return "Draft Rarity Bias"
		"starting_squad_add": return "Starting Squad Size"
		"focus_duration_mult": return "Focus Duration"
		"focus_lockout_s": return "Focus Swap Lockout"
		"rally_duration_mult": return "Rally Duration"
		"rally_speed_mult": return "Rally Speed"
		"rally_follow_mult": return "Rally Follow Aggression"
		"dash_cooldown_mult": return "Dash Cooldown"
		"dash_distance_mult": return "Dash Distance"
		"dash_follow_mult": return "Dash Cohesion"
		"overclock_unlocked": return "Unlock Overclock"
		"overclock_attack_speed_mult": return "Overclock Attack Speed"
		"overclock_move_speed_mult": return "Overclock Move Speed"
		"overclock_damage_mult": return "Overclock Damage"
		"overclock_focus_bias_mult": return "Overclock Focus Bias"
		"overclock_cooldown_mult": return "Overclock Cooldown"
		"overclock_duration_mult": return "Overclock Duration"
		"overclock_burst_damage_add": return "Overclock Burst Damage"
		"overclock_burst_radius_add": return "Overclock Burst Radius"
		"squad_attack_speed_mult": return "Squad Attack Speed"
		"squad_range_mult": return "Ranged Attack Range"
		"squad_damage_taken_mult": return "Damage Taken"
		"on_kill_heal_add": return "Heal on Kill"
		"overclock_chain_chance_add": return "Overclock Chain Chance"
		"overclock_chain_jumps_add": return "Overclock Chain Jumps"
		"overclock_chain_damage_mult": return "Overclock Chain Damage"
		"overclock_chain_radius_add": return "Overclock Chain Radius"
		"ranged_to_melee_add": return "Convert Ranged to Melee"
		"ranged_transfer_melee_mult": return "Ranged Buff Transfer to Melee"
		"focus_mark_damage_mult": return "Focus Mark Damage"
		"damage_taken_as_essence_add": return "Damage Taken As Essence"
		"execute_threshold_add": return "Execute Threshold"
		"overclock_always_on_add": return "Overclock Always On"
		"kill_chain_window_add": return "Kill Chain Window"
		"kill_chain_haste_per_stack_add": return "Kill Chain Haste per Stack"
		"kill_chain_max_stacks_add": return "Kill Chain Max Stacks"
		"overclock_extend_on_kill_add": return "Overclock Extend on Kill"
		"execute_blast_radius_add": return "Execute Blast Radius"
		"execute_blast_damage_mult": return "Execute Blast Damage"
		"execute_blast_mark_threshold_add": return "Execute Blast Mark Threshold"
		"essence_guard_reflect_ratio_add": return "Essence Guard Reflect Ratio"
		"essence_guard_reflect_radius_add": return "Essence Guard Reflect Radius"
		"guardian_intercept_ratio_add": return "Guardian Intercept Ratio"
		"non_guardian_hp_mult": return "Non-Guardian HP"
		"slowed_execute_threshold_add": return "Execute Threshold vs Slowed"
		"unslowed_enemy_damage_taken_mult": return "Damage vs Unslowed Enemies"
		"crit_execute_vuln_add": return "Crit Apply Execute Vulnerability"
		"noncrit_damage_mult": return "Non-Crit Damage"
		"point_blank_max_bonus_add": return "Point-Blank Max Bonus"
		"point_blank_far_penalty_add": return "Point-Blank Far Penalty"
		"farshot_max_bonus_add": return "Farshot Max Bonus"
		"farshot_near_penalty_add": return "Farshot Near Penalty"
		"near_enemy_damage_taken_mult": return "Damage Taken Near Enemies"
		"near_enemy_threat_radius_add": return "Near Enemy Threat Radius"
		"mage_chain_jumps_add": return "Mage Chain Jumps"
		"mage_chain_range_add": return "Mage Chain Range"
		"mage_single_target_mult": return "Mage Chain Isolated Damage"
		"chain_jumps_add": return "Chain Jumps"
		"chain_damage_falloff_mult": return "Chain Falloff"
		"chain_kill_shock_radius_add": return "Chain Kill Shock Radius"
		"chain_kill_shock_damage_mult": return "Chain Kill Shock Damage"
		"chain_can_rehit_targets": return "Chain Can Rehit Targets"
		"chain_rehit_damage_mult": return "Chain Rehit Damage"
		"burning_enemy_execute_threshold_add": return "Execute Threshold vs Burning"
		"burn_duration_mult": return "Burn Duration"
		"slowed_enemy_damage_mult": return "Slowed Enemy Contact Damage"
		"slow_initial_strength_mult": return "Initial Slow Strength"
		"slow_stacks_to_freeze_enabled": return "Slow Stacks Freeze"
		"freeze_after_slow_duration": return "Freeze After Slow Duration"
		"projectile_count_add": return "Projectile Count"
		"projectile_damage_mult": return "Projectile Damage"
		"projectile_pierce_add": return "Projectile Pierce"
		"projectile_spread_mult": return "Projectile Spread"
		"bomb_radius_add": return "Bomb Radius"
		"bomb_delay_mult": return "Bomb Delay"
		"bomb_damage_mult": return "Bomb Damage"
		"poison_duration_mult": return "Poison Duration"
		"frost_slow_duration_mult": return "Frost Slow Duration"
		"orbital_damage_mult": return "Orbital Damage"
		"orbital_delay_mult": return "Orbital Delay"
		"ricochet_damage_per_bounce_add": return "Ricochet Damage per Bounce"
		"direct_projectile_damage_mult": return "Direct Projectile Damage"
		"post_ricochet_projectile_damage_mult": return "Post-Ricochet Projectile Damage"
		"ricochet_count_add": return "Ricochet Count"
		"pierce_damage_per_enemy_hit_add": return "Pierce Damage per Enemy Hit"
		"piercing_hits_can_execute": return "Piercing Hits Can Execute"
		"bomb_cluster_count_add": return "Bomb Cluster Count"
		"bomb_cluster_damage_mult": return "Bomb Cluster Damage"
		"bomb_cluster_radius_mult": return "Bomb Cluster Radius"
		"beam_damage_ramp_per_second_add": return "Beam Damage Ramp per Second"
		"beam_damage_ramp_cap": return "Beam Damage Ramp Cap"
		"beam_initial_damage_mult": return "Beam Initial Damage"
		"beam_secondary_targets_add": return "Beam Secondary Targets"
		"beam_secondary_damage_mult": return "Beam Secondary Damage"
		"beam_target_swap_resets_ramp": return "Beam Target Swap Resets Ramp"
		"orbital_targets_player_trail": return "Orbital Targets Squad Trail"
		"berserk_threshold_add": return "Last-Stand HP Threshold"
		"berserk_damage_mult": return "Last-Stand Damage"
		"berserk_attack_speed_mult": return "Last-Stand Attack Speed"
		"berserk_damage_taken_mult": return "Last-Stand Damage Taken"
		_: return key

func _protocol_trace_ids(from_id: String) -> Dictionary:
	var out: Dictionary = {}
	if from_id == "":
		return out
	var stack: Array[String] = [from_id]
	while not stack.is_empty():
		var cur: String = String(stack.pop_back())
		if out.has(cur):
			continue
		out[cur] = true
		var nd := _protocol_node_by_id.get(cur, {}) as Dictionary
		var up := nd.get("upgrade", {}) as Dictionary
		var prereq := up.get("prereq", []) as Array
		for p in prereq:
			var pid := String(p)
			if pid != "" and not out.has(pid):
				stack.append(pid)
	return out

func _protocol_node_accent_color(node: Dictionary, id: String) -> Color:
	var cluster := String(node.get("cluster", ""))
	if cluster != "":
		return _protocol_cluster_color(cluster)
	return _protocol_family_color(id)

func _protocol_cluster_color(cluster: String) -> Color:
	match cluster:
		"storm": return Color(0.50, 0.82, 1.0, 1.0)
		"fire": return Color(1.0, 0.57, 0.32, 1.0)
		"frost": return Color(0.62, 0.90, 1.0, 1.0)
		"poison": return Color(0.54, 1.0, 0.60, 1.0)
		"projectile": return Color(1.0, 0.84, 0.56, 1.0)
		"scatter": return Color(1.0, 0.72, 0.45, 1.0)
		"ricochet": return Color(1.0, 0.78, 0.54, 1.0)
		"pierce": return Color(1.0, 0.90, 0.68, 1.0)
		"bomb": return Color(1.0, 0.54, 0.28, 1.0)
		"beam": return Color(0.90, 0.68, 1.0, 1.0)
		"orbital": return Color(1.0, 0.70, 0.38, 1.0)
		"hybrid": return Color(0.66, 0.96, 0.92, 1.0)
		_: return Color(0.62, 0.74, 0.92, 1.0)

func _protocol_family_color(id: String) -> Color:
	var f := _protocol_family_key(id)
	match f:
		"vitality": return Color(1.0, 0.47, 0.47, 1.0)
		"offense": return Color(1.0, 0.65, 0.35, 1.0)
		"focus": return Color(0.72, 0.62, 1.0, 1.0)
		"rally": return Color(0.37, 0.78, 1.0, 1.0)
		"squad": return Color(0.49, 1.0, 0.80, 1.0)
		"dash": return Color(0.40, 1.0, 0.60, 1.0)
		"overclock": return Color(0.76, 0.56, 1.0, 1.0)
		"mobility": return Color(0.56, 0.96, 0.84, 1.0)
		"core": return Color(0.82, 0.88, 1.0, 1.0)
		_: return Color(0.62, 0.74, 0.92, 1.0)

func _protocol_icon_texture_for_id(id: String, is_keystone: bool = false) -> Texture2D:
	var file := ""
	if is_keystone and PROTOCOL_KEYSTONE_ICON_BY_ID.has(id):
		file = String(PROTOCOL_KEYSTONE_ICON_BY_ID[id])
	if file == "":
		var family := _protocol_family_key(id)
		file = String(PROTOCOL_ICON_BY_FAMILY.get(family, "fam_offense_v2.webp"))
	var path := PROTOCOL_ICON_DIR + file
	if _protocol_icon_cache.has(path):
		return _protocol_icon_cache[path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_protocol_icon_cache[path] = tex
	return tex
