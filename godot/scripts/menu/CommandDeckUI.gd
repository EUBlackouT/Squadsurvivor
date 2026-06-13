extends Control

const _MenuMapPreview := preload("res://scripts/ui/MenuMapPreview.gd")
const _PixelUi := preload("res://scripts/ui/PixelUi.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const ARMORY_SCENE: PackedScene = preload("res://scenes/Menu.tscn")
const ASSET_PANEL: String = "res://assets/ui/revamp/codex_panel.png"

const SURFACE_BG := Color(0.08, 0.06, 0.09, 0.92)
const SURFACE_BORDER := Color(0.52, 0.46, 0.38, 0.45)
const ACCENT_SUN: Color = UiSkin.ACCENT_GOLD

var _host: Control
var _built: bool = false

var _hero_a = null
var _hero_b = null
var _hero_front_is_a: bool = true
var _zone_strip: Control = null
var _zone_row: HBoxContainer = null
var _zone_tiles: Dictionary = {}
var _zone_ids: Array[String] = []
var _zone_scroll: float = 0.0
var _zone_scroll_target: float = 0.0
var _zone_scroll_tween: Tween = null
var _zone_row_y: float = 0.0
var _zone_dragging: bool = false
var _zone_drag_moved: float = 0.0
var _zone_drag_vel: float = 0.0
var _zone_hover_tile: PanelContainer = null
var _zone_panel: PanelContainer = null
var _zone_name_lbl: Label = null
var _zone_tag_lbl: Label = null
var _zone_info: RichTextLabel = null
var _deploy_btn: Button = null
var _sigils_lbl: Label = null
var _resume_btn: Button = null
var _armory_btn: Button = null
var _protocol_btn: Button = null
var _info_btn: Button = null
var _settings_btn: Button = null
var _quit_btn: Button = null
var _zone_art_cache: Dictionary = {}
var _selected_map_locked: bool = false
var _map_preview_tex_cache: Dictionary = {}
var _hero_tex_cache: Dictionary = {}
var _menu_anim_t: float = 0.0

static func attach(host: Control) -> Control:
	var existing := host.get_node_or_null("CommandDeckUI") as Control
	if existing != null:
		return existing
	var ui: Control = load("res://scripts/menu/CommandDeckUI.gd").new()
	ui.name = "CommandDeckUI"
	ui._host = host
	host.add_child(ui)
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui._build()
	host.set("_deploy_btn", ui._deploy_btn)
	host.set("_zone_scroll", ui._zone_scroll)
	return ui

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	if _zone_row != null and is_instance_valid(_zone_row) and _zone_strip != null:
		_zone_row.position = Vector2(-_zone_scroll, _zone_row_y)
	if _host != null:
		_host.set("_zone_scroll", _zone_scroll)

func _title_text() -> String:
	return String(_host.get("game_title")) if _host != null else "SQUADSURVIVOR"

func _tagline_text() -> String:
	return String(_host.get("game_tagline")) if _host != null else ""

func _footer_text() -> String:
	return String(_host.get("footer_text")) if _host != null else ""

func _play_ui(id: String) -> void:
	if _host != null and _host.has_method("_play_ui"):
		_host.call("_play_ui", id)

func _load_tex(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

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

func _sb_inset(radius: int = 12, alpha: float = 0.86) -> StyleBoxFlat:
	return UiSkin.inset_style(radius, alpha, SURFACE_BG, SURFACE_BORDER)

func try_deploy() -> void:
	if _selected_map_locked:
		_play_ui("ui.error")
		return
	_play_ui("ui.confirm")
	_start_run_with_selected_map()

func _build() -> void:
	# Hero art layers (crossfaded on zone change).
	_hero_a = _make_hero_layer()
	_hero_b = _make_hero_layer()
	add_child(_hero_a)
	move_child(_hero_a, 0)
	add_child(_hero_b)
	move_child(_hero_b, 1)
	_hero_b.modulate.a = 0.0
	_hero_front_is_a = true

	# Readability scrims.
	var bottom_scrim := _make_scrim(0.0, 0.94)
	bottom_scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_scrim.offset_top = -430
	add_child(bottom_scrim)
	var top_scrim := _make_scrim(0.74, 0.0)
	top_scrim.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_scrim.offset_bottom = 170
	add_child(top_scrim)

	# Title block (top-left).
	var title_box := VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title_box.offset_left = 32
	title_box.offset_top = 22
	title_box.add_theme_constant_override("separation", 2)
	add_child(title_box)

	var title := Label.new()
	title.text = _title_text()
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiSkin.TEXT)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	_apply_font(title)
	title_box.add_child(title)

	var tagline := Label.new()
	tagline.text = _tagline_text().to_upper()
	tagline.add_theme_font_size_override("font_size", 10)
	tagline.add_theme_color_override("font_color", UiSkin.ACCENT)
	_apply_font(tagline)
	title_box.add_child(tagline)

	# Sigils pill (top-right).
	var sig_panel := PanelContainer.new()
	sig_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sig_panel.offset_left = -236
	sig_panel.offset_right = -28
	sig_panel.offset_top = 26
	sig_panel.offset_bottom = 62
	sig_panel.add_theme_stylebox_override("panel", UiSkin.chip_style(UiSkin.ACCENT_GOLD))
	add_child(sig_panel)
	_sigils_lbl = Label.new()
	_sigils_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sigils_lbl.add_theme_font_size_override("font_size", 15)
	_sigils_lbl.add_theme_color_override("font_color", UiSkin.ACCENT_GOLD)
	_apply_font(_sigils_lbl)
	sig_panel.add_child(_sigils_lbl)
	refresh_sigils()

	# Mission detail panel (right column; never overlaps the filmstrip below).
	_zone_panel = PanelContainer.new()
	_zone_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_zone_panel.offset_left = -464
	_zone_panel.offset_right = -28
	_zone_panel.offset_top = 92
	_zone_panel.offset_bottom = -262
	_zone_panel.add_theme_stylebox_override("panel", UiSkin.pixel_panel(UiSkin.ACCENT, 0.68))
	add_child(_zone_panel)

	var zp_pad := MarginContainer.new()
	zp_pad.add_theme_constant_override("margin_left", UiSkin.SPACE_MD)
	zp_pad.add_theme_constant_override("margin_right", UiSkin.SPACE_MD)
	zp_pad.add_theme_constant_override("margin_top", UiSkin.SPACE_MD)
	zp_pad.add_theme_constant_override("margin_bottom", UiSkin.SPACE_MD)
	_zone_panel.add_child(zp_pad)

	var zp_v := VBoxContainer.new()
	zp_v.add_theme_constant_override("separation", UiSkin.SPACE_XS)
	zp_pad.add_child(zp_v)

	var mission_hdr := Label.new()
	mission_hdr.text = "— NEXT DEPLOYMENT —"
	mission_hdr.add_theme_font_size_override("font_size", 12)
	mission_hdr.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
	_apply_font(mission_hdr)
	zp_v.add_child(mission_hdr)

	_zone_name_lbl = Label.new()
	_zone_name_lbl.add_theme_font_size_override("font_size", 14)
	_zone_name_lbl.add_theme_color_override("font_color", UiSkin.TEXT)
	_zone_name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_font(_zone_name_lbl)
	zp_v.add_child(_zone_name_lbl)

	_zone_tag_lbl = Label.new()
	_zone_tag_lbl.add_theme_font_size_override("font_size", 13)
	_zone_tag_lbl.add_theme_color_override("font_color", UiSkin.TEXT_SOFT)
	_zone_tag_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_font(_zone_tag_lbl)
	zp_v.add_child(_zone_tag_lbl)

	_zone_info = RichTextLabel.new()
	_zone_info.bbcode_enabled = true
	_zone_info.fit_content = true
	_zone_info.scroll_active = false
	_zone_info.add_theme_font_size_override("normal_font_size", 13)
	_zone_info.add_theme_color_override("default_color", UiSkin.TEXT_SOFT)
	_zone_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_font(_zone_info)
	zp_v.add_child(_zone_info)

	var sv := get_node_or_null("/root/SaveManager")
	var has_resume: bool = sv != null and is_instance_valid(sv) \
		and sv.has_method("has_saved_run") and bool(sv.has_saved_run())
	_resume_btn = _make_menu_button("⟳ Resume Last Run", false, UiSkin.ACCENT_GOLD)
	_resume_btn.custom_minimum_size = Vector2(0, 40)
	_resume_btn.visible = has_resume
	zp_v.add_child(_resume_btn)
	if has_resume:
		_resume_btn.pressed.connect(func():
			_play_ui("ui.resume_load")
			if sv and sv.has_method("request_resume") and bool(sv.request_resume()):
				_host.get_tree().change_scene_to_packed(MAIN_SCENE)
		)

	_deploy_btn = _make_menu_button("▶ DEPLOY", true)
	_deploy_btn.custom_minimum_size = Vector2(0, 54)
	zp_v.add_child(_deploy_btn)
	_deploy_btn.pressed.connect(func(): try_deploy())

	# Zone filmstrip (bottom band, above the nav rail). Drag, wheel, or use
	# the chevrons / arrow keys; the selected tile auto-centers.
	_zone_strip = Control.new()
	_zone_strip.name = "ZoneStrip"
	_zone_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_zone_strip.offset_left = 76
	_zone_strip.offset_right = -76
	_zone_strip.offset_top = -254
	_zone_strip.offset_bottom = -94
	_zone_strip.clip_contents = true
	_zone_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_zone_strip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_zone_strip.gui_input.connect(_on_zone_strip_input)
	_zone_strip.mouse_exited.connect(func(): _set_zone_hover(null))
	_zone_strip.resized.connect(_sync_zone_row_y)
	add_child(_zone_strip)

	_zone_row = HBoxContainer.new()
	_zone_row.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	_zone_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_strip.add_child(_zone_row)

	# Edge fades hint that the strip continues past the viewport.
	for left_side in [true, false]:
		var fade_g := Gradient.new()
		fade_g.offsets = PackedFloat32Array([0.0, 1.0])
		var solid := Color(0, 0, 0, 0.85)
		var clear := Color(0, 0, 0, 0.0)
		fade_g.colors = PackedColorArray([solid, clear] if left_side else [clear, solid])
		var fade_gt := GradientTexture2D.new()
		fade_gt.gradient = fade_g
		fade_gt.fill_from = Vector2(0, 0)
		fade_gt.fill_to = Vector2(1, 0)
		var fade_tr := TextureRect.new()
		fade_tr.texture = fade_gt
		fade_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade_tr.stretch_mode = TextureRect.STRETCH_SCALE
		fade_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if left_side:
			fade_tr.set_anchors_preset(Control.PRESET_LEFT_WIDE)
			fade_tr.offset_right = 44
		else:
			fade_tr.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
			fade_tr.offset_left = -44
		_zone_strip.add_child(fade_tr)

	# Chevron paddles flanking the strip.
	for left_side in [true, false]:
		var chev := Button.new()
		chev.text = "‹" if left_side else "›"
		chev.focus_mode = Control.FOCUS_NONE
		chev.custom_minimum_size = Vector2(40, 96)
		chev.add_theme_font_size_override("font_size", 34)
		chev.add_theme_color_override("font_color", UiSkin.TEXT_SOFT)
		chev.add_theme_stylebox_override("normal", UiSkin.chip_style(UiSkin.ACCENT))
		chev.add_theme_stylebox_override("hover", UiSkin.chip_style(UiSkin.ACCENT_GOLD))
		chev.add_theme_stylebox_override("pressed", UiSkin.chip_style(UiSkin.ACCENT_GOLD))
		chev.set_anchors_preset(Control.PRESET_BOTTOM_LEFT if left_side else Control.PRESET_BOTTOM_RIGHT)
		if left_side:
			chev.offset_left = 28
			chev.offset_right = 68
		else:
			chev.offset_left = -68
			chev.offset_right = -28
		chev.offset_top = -224
		chev.offset_bottom = -128
		var dir := -1 if left_side else 1
		chev.pressed.connect(func(): cycle_zone(dir))
		add_child(chev)

	# Keyboard hint.
	var hint := Label.new()
	hint.text = "◀ ▶  switch zone      drag / wheel  browse      ENTER  deploy"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -88
	hint.offset_bottom = -72
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
	_apply_font(hint)
	add_child(hint)

	# Nav rail (bottom-left).
	var nav := HBoxContainer.new()
	nav.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	nav.offset_left = 28
	nav.offset_top = -70
	nav.offset_bottom = -24
	nav.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	add_child(nav)

	_armory_btn = _nav_button("COLLECTION")
	nav.add_child(_armory_btn)
	_armory_btn.pressed.connect(func():
		_play_ui("ui.click")
		_host.get_tree().change_scene_to_packed(ARMORY_SCENE)
	)

	_protocol_btn = _nav_button("PROTOCOL GRID", UiSkin.ACCENT_PURPLE)
	nav.add_child(_protocol_btn)
	_protocol_btn.pressed.connect(func():
		_play_ui("ui.click")
		_host.call("_open_protocol_grid")
	)

	_info_btn = _nav_button("CODEX")
	nav.add_child(_info_btn)
	_info_btn.pressed.connect(func():
		_play_ui("ui.click")
		_host.call("_open_info_overlay")
	)

	_settings_btn = _nav_button("SETTINGS")
	nav.add_child(_settings_btn)
	_settings_btn.pressed.connect(func():
		_play_ui("ui.click")
		_host.call("_open_settings")
	)

	_quit_btn = _nav_button("QUIT", UiSkin.ACCENT_RED)
	nav.add_child(_quit_btn)
	_quit_btn.pressed.connect(func():
		_play_ui("ui.cancel")
		_host.get_tree().quit()
	)

	# Footer (bottom-right).
	var footer := Label.new()
	footer.text = _footer_text()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.offset_left = -360
	footer.offset_top = -42
	footer.offset_right = -24
	footer.offset_bottom = -22
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
	_apply_font(footer)
	add_child(footer)

	# Boot fade-in: first frame is instant, art fades up from black.
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	var ftw := fade.create_tween()
	ftw.tween_property(fade, "color:a", 0.0, 0.55)
	ftw.tween_callback(fade.queue_free)

	# Panel entrance.
	_zone_panel.modulate.a = 0.0
	var ptw := _zone_panel.create_tween()
	ptw.tween_interval(0.10)
	ptw.tween_property(_zone_panel, "modulate:a", 1.0, UiSkin.DUR_MED)

func _make_hero_layer():
	var tr = _MenuMapPreview.new()
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	return tr

func _make_scrim(from_a: float, to_a: float) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, from_a), Color(0, 0, 0, to_a)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _nav_button(text: String, accent: Color = UiSkin.ACCENT) -> Button:
	var btn := _make_menu_button(text, false, accent)
	btn.custom_minimum_size = Vector2(0, 44)
	btn.add_theme_font_size_override("font_size", 10)
	return btn

func refresh_sigils() -> void:
	if _sigils_lbl == null or not is_instance_valid(_sigils_lbl):
		return
	var mp := get_node_or_null("/root/MetaProgression")
	var sig := 0
	if mp != null and is_instance_valid(mp) and "sigils" in mp:
		sig = int(mp.get("sigils"))
	_sigils_lbl.text = "✦ %d SIGILS" % sig

func populate_zones() -> void:
	if _zone_row == null:
		return
	var rc := get_node_or_null("/root/RunConfig")
	if rc == null or not is_instance_valid(rc):
		return
	if rc.has_method("ensure_loaded"):
		rc.ensure_loaded()

	for c in _zone_row.get_children():
		(c as Node).queue_free()
	_zone_tiles.clear()
	_zone_ids.clear()
	if rc.has_method("get_map_ids_ordered"):
		_zone_ids = rc.get_map_ids_ordered()
	elif rc.has_method("get_map_ids"):
		_zone_ids = rc.get_map_ids()

	var i := 0
	for id in _zone_ids:
		var m: Dictionary = rc.get_map(id) if rc.has_method("get_map") else {}
		var locked := not _is_map_unlocked(id)
		var tile := _make_zone_tile(id, m, locked)
		_zone_row.add_child(tile)
		_zone_tiles[id] = tile
		tile.modulate.a = 0.0
		var tw := tile.create_tween()
		tw.tween_interval(0.05 + 0.05 * float(i))
		tw.tween_property(tile, "modulate:a", 1.0, UiSkin.DUR_MED)
		i += 1

	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else ""
	if cur == "" or not _zone_ids.has(cur):
		cur = _zone_ids[0] if not _zone_ids.is_empty() else ""
	if cur != "":
		_select_zone(cur, false)
		# Layout needs a frame before tile positions are valid for centering.
		await _host.get_tree().process_frame
		_sync_zone_row_y()
		_center_selected_tile(false)

func _make_zone_tile(id: String, m: Dictionary, locked: bool) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.name = "ZoneTile_" + id
	tile.custom_minimum_size = Vector2(236, 150)
	# Input is handled by the filmstrip itself (drag vs click disambiguation).
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.set_meta("locked", locked)
	tile.set_meta("map_id", id)
	tile.add_theme_stylebox_override("panel", _zone_tile_style(false, locked))
	tile.set_meta("base_modulate", Color.WHITE if not locked else Color(0.82, 0.84, 0.88, 1.0))
	tile.modulate = tile.get_meta("base_modulate")

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 3)
	pad.add_theme_constant_override("margin_right", 3)
	pad.add_theme_constant_override("margin_top", 3)
	pad.add_theme_constant_override("margin_bottom", 3)
	tile.add_child(pad)

	var clipper := Control.new()
	clipper.clip_contents = true
	clipper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(clipper)

	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture = _zone_art(id, m)
	if locked:
		art.modulate = Color(0.45, 0.48, 0.55, 1.0)
	clipper.add_child(art)

	var scrim := _make_scrim(0.0, 0.92)
	scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scrim.offset_top = -76
	clipper.add_child(scrim)

	var info := VBoxContainer.new()
	info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info.offset_left = 10
	info.offset_right = -10
	info.offset_top = -52
	info.offset_bottom = -8
	info.add_theme_constant_override("separation", 1)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clipper.add_child(info)

	var nm := Label.new()
	nm.text = String(m.get("name", m.get("display_name", id))).to_upper()
	nm.add_theme_font_size_override("font_size", 14)
	nm.add_theme_color_override("font_color", UiSkin.TEXT)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	nm.add_theme_constant_override("outline_size", 4)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_font(nm)
	info.add_child(nm)

	var score := _danger_score(m)
	var stars_n := clampi(int(ceil(score / 2.0)), 1, 5)
	var stars := Label.new()
	stars.text = "★".repeat(stars_n) + "☆".repeat(5 - stars_n)
	stars.add_theme_font_size_override("font_size", 12)
	stars.add_theme_color_override("font_color", Color.html(_tier_color(score)))
	stars.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	stars.add_theme_constant_override("outline_size", 3)
	_apply_font(stars)
	info.add_child(stars)

	if locked:
		var lock := Label.new()
		lock.text = "🔒"
		lock.set_anchors_preset(Control.PRESET_CENTER)
		lock.offset_top = -34
		lock.add_theme_font_size_override("font_size", 30)
		lock.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		clipper.add_child(lock)

	return tile

# ── Filmstrip input: left-drag pans, wheel scrolls, short click selects ──────

func _on_zone_strip_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_kill_zone_scroll_tween()
				_zone_dragging = true
				_zone_drag_moved = 0.0
				_zone_drag_vel = 0.0
			else:
				_zone_dragging = false
				if _zone_drag_moved < 8.0:
					var tile := _tile_at_strip_pos(mb.position)
					if tile != null:
						_on_zone_tile_clicked(String(tile.get_meta("map_id", "")))
				else:
					# Fling: carry drag velocity into a smooth decelerating scroll.
					var fling := clampf(
						_zone_scroll + _zone_drag_vel * 0.22, 0.0, _zone_scroll_max())
					_animate_zone_scroll(fling, 0.55)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_animate_zone_scroll(
				clampf(_zone_scroll - 252.0, 0.0, _zone_scroll_max()), 0.38)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_animate_zone_scroll(
				clampf(_zone_scroll + 252.0, 0.0, _zone_scroll_max()), 0.38)
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _zone_dragging:
			_kill_zone_scroll_tween()
			_zone_drag_moved += absf(mm.relative.x)
			_zone_scroll = clampf(_zone_scroll - mm.relative.x, -40.0, _zone_scroll_max() + 40.0)
			_zone_scroll_target = clampf(_zone_scroll, 0.0, _zone_scroll_max())
			_zone_drag_vel = lerpf(_zone_drag_vel, -mm.relative.x * 60.0, 0.35)
			if _zone_drag_moved >= 8.0:
				_set_zone_hover(null)
		else:
			_set_zone_hover(_tile_at_strip_pos(mm.position))

func _tile_at_strip_pos(strip_pos: Vector2) -> PanelContainer:
	if _zone_row == null:
		return null
	var local := strip_pos - _zone_row.position
	for c in _zone_row.get_children():
		var tile := c as PanelContainer
		if tile == null:
			continue
		if Rect2(tile.position, tile.size).has_point(local):
			return tile
	return null

func _set_zone_hover(tile: PanelContainer) -> void:
	if _zone_hover_tile == tile:
		return
	if _zone_hover_tile != null and is_instance_valid(_zone_hover_tile) \
			and not bool(_zone_hover_tile.get_meta("selected", false)):
		var prev_base: Color = _zone_hover_tile.get_meta("base_modulate", Color.WHITE)
		_zone_hover_tile.modulate = prev_base
	_zone_hover_tile = tile
	if tile != null and not bool(tile.get_meta("selected", false)):
		var base: Color = tile.get_meta("base_modulate", Color.WHITE)
		tile.modulate = Color(base.r * 1.06, base.g * 1.06, base.b * 1.10, base.a)

func _zone_scroll_max() -> float:
	if _zone_row == null or _zone_strip == null:
		return 0.0
	return maxf(0.0, _zone_row.size.x - _zone_strip.size.x)

func _sync_zone_row_y() -> void:
	if _zone_row == null or _zone_strip == null:
		return
	_zone_row_y = maxf(0.0, (_zone_strip.size.y - _zone_row.size.y) * 0.5)

func _kill_zone_scroll_tween() -> void:
	if _zone_scroll_tween != null and is_instance_valid(_zone_scroll_tween):
		_zone_scroll_tween.kill()
	_zone_scroll_tween = null

func _animate_zone_scroll(target: float, duration: float = 0.45) -> void:
	target = clampf(target, 0.0, _zone_scroll_max())
	_zone_scroll_target = target
	if _zone_dragging:
		_zone_scroll = target
		return
	if absf(target - _zone_scroll) < 0.5:
		_zone_scroll = target
		return
	_kill_zone_scroll_tween()
	_zone_scroll_tween = create_tween()
	_zone_scroll_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_zone_scroll_tween.tween_method(
		func(v: float) -> void:
			_zone_scroll = v,
		_zone_scroll, target, duration)

func _center_selected_tile(animate: bool) -> void:
	var rc := get_node_or_null("/root/RunConfig")
	var cur := String(rc.selected_map_id) if (rc != null and "selected_map_id" in rc) else ""
	var tile: PanelContainer = _zone_tiles.get(cur) as PanelContainer
	if tile == null or not is_instance_valid(tile) or _zone_strip == null:
		return
	var want := tile.position.x + tile.size.x * 0.5 - _zone_strip.size.x * 0.5
	if animate:
		_animate_zone_scroll(want, 0.48)
	else:
		_kill_zone_scroll_tween()
		_zone_scroll = clampf(want, 0.0, _zone_scroll_max())
		_zone_scroll_target = _zone_scroll

func _zone_tile_style(selected: bool, locked: bool) -> StyleBox:
	if selected:
		return UiSkin.pixel_card(UiSkin.ACCENT_GOLD, true)
	if locked:
		var sb := UiSkin.pixel_inset(0.62)
		sb.border_color = Color(0.25, 0.26, 0.30, 0.35)
		return sb
	return UiSkin.pixel_card(UiSkin.ACCENT, false)

func _on_zone_tile_clicked(id: String) -> void:
	_play_ui("ui.click")
	_select_zone(id, true)

func cycle_zone(dir: int) -> void:
	if _zone_ids.is_empty():
		return
	var rc := get_node_or_null("/root/RunConfig")
	var cur := String(rc.selected_map_id) if (rc != null and "selected_map_id" in rc) else ""
	var idx := _zone_ids.find(cur)
	idx = (idx + dir + _zone_ids.size()) % _zone_ids.size() if idx >= 0 else 0
	_play_ui("ui.click")
	_select_zone(_zone_ids[idx], true)

func _select_zone(id: String, animate: bool) -> void:
	var rc := get_node_or_null("/root/RunConfig")
	if rc == null or not is_instance_valid(rc):
		return
	if rc.has_method("set_selected_map_id"):
		rc.set_selected_map_id(id)
	_selected_map_locked = not _is_map_unlocked(id)

	for tid in _zone_tiles.keys():
		var tile: PanelContainer = _zone_tiles[tid]
		if tile == null or not is_instance_valid(tile):
			continue
		var sel: bool = String(tid) == id
		tile.set_meta("selected", sel)
		tile.add_theme_stylebox_override("panel", _zone_tile_style(sel, bool(tile.get_meta("locked", false))))
		var base: Color = tile.get_meta("base_modulate", Color.WHITE)
		tile.modulate = Color(base.r * 1.08, base.g * 1.08, base.b * 1.12, base.a) if sel else base

	var m: Dictionary = rc.get_map(id) if rc.has_method("get_map") else {}
	_update_zone_panel(m)
	_swap_hero(_hero_texture(id, m), animate)
	refresh_sigils()
	_center_selected_tile(animate)

func _zone_art(map_id: String, m: Dictionary) -> Texture2D:
	if _zone_art_cache.has(map_id):
		return _zone_art_cache[map_id] as Texture2D
	var tex: Texture2D = null
	var thumb := "res://assets/maps/thumbs/%s.webp" % map_id
	if ResourceLoader.exists(thumb):
		tex = load(thumb) as Texture2D
	if tex == null:
		var vis: Dictionary = {}
		var vv: Variant = m.get("visuals", {})
		if typeof(vv) == TYPE_DICTIONARY:
			vis = vv as Dictionary
		tex = _map_preview_texture(m, vis, map_id)
	_zone_art_cache[map_id] = tex
	return tex

func _hero_texture(map_id: String, m: Dictionary) -> Texture2D:
	if _hero_tex_cache.has(map_id):
		return _hero_tex_cache[map_id] as Texture2D
	var tex := _MenuMapPreview.load_map_texture(map_id, m)
	if tex == null:
		tex = _zone_art(map_id, m)
	_hero_tex_cache[map_id] = tex
	return tex

func _swap_hero(tex: Texture2D, animate: bool) -> void:
	if tex == null or _hero_a == null or _hero_b == null:
		return
	var front = _hero_a if _hero_front_is_a else _hero_b
	var back = _hero_b if _hero_front_is_a else _hero_a
	if front.texture == tex:
		return
	if not animate:
		front.set_preview_texture(tex)
		front.modulate.a = 1.0
		back.modulate.a = 0.0
		return
	back.set_preview_texture(tex)
	back.modulate.a = 0.0
	var tw = back.create_tween()
	tw.tween_property(back, "modulate:a", 1.0, 0.40)
	tw.tween_callback(func():
		front.modulate.a = 0.0
		_hero_front_is_a = not _hero_front_is_a
	)

func _update_zone_panel(m: Dictionary) -> void:
	if _zone_name_lbl == null:
		return
	_zone_name_lbl.text = String(m.get("name", m.get("display_name", "UNKNOWN ZONE"))).to_upper()
	_zone_tag_lbl.text = String(m.get("tagline", ""))
	_zone_tag_lbl.visible = _zone_tag_lbl.text != ""

	var score := _danger_score(m)
	var col := _tier_color(score)
	var sig := float(m.get("meta_sigils_mult", 1.0))
	var ess := float(m.get("essence_mult", 1.0))
	var boss := bool(m.get("boss_enabled", true))
	var boss_m := float(m.get("boss_spawn_minutes", 18.0))
	var lines: Array[String] = []
	lines.append("[color=#7a8a9a]DANGER[/color]   [color=%s]%s  %.1f[/color]" % [col, _bar(score), score])
	lines.append("[color=#7a8a9a]REWARDS[/color]  [color=#ffd070]✦ Sigils x%.2f[/color]   [color=#70d0ff]✧ Essence x%.2f[/color]" % [sig, ess])
	if boss:
		lines.append("[color=#7a8a9a]BOSS[/color]     [color=#ff7070]Arrives at %.0f min[/color]" % boss_m)
	else:
		lines.append("[color=#7a8a9a]BOSS[/color]     [color=#70ff70]None detected[/color]")
	var races := _races_bbcode(m)
	if races != "":
		lines.append("")
		lines.append("[color=#7a8a9a]HOSTILE RACES[/color]")
		lines.append(races)
	if _selected_map_locked:
		lines.append("")
		lines.append("[color=#ff8a70]🔒 LOCKED — win the previous zone to unlock.[/color]")
	_zone_info.text = "\n".join(lines)

	if _deploy_btn != null:
		_deploy_btn.disabled = _selected_map_locked
		_deploy_btn.text = "🔒 LOCKED" if _selected_map_locked else "▶ DEPLOY"

func _races_bbcode(m: Dictionary) -> String:
	var pool_v: Variant = m.get("race_pool_enemy", m.get("race_pool", []))
	if typeof(pool_v) != TYPE_ARRAY:
		return ""
	var pool := pool_v as Array
	if pool.is_empty():
		return ""
	var parts: Array[String] = []
	for r in pool:
		var rid := String(r).to_upper()
		parts.append("[color=%s]%s[/color]" % [UiSkin.race_hex(rid), rid.capitalize()])
	return "[color=#7a8a9a]☉[/color] " + " [color=#55636f]•[/color] ".join(parts)

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

func _map_preview_texture(map_data: Dictionary, vis: Dictionary, map_id: String) -> Texture2D:
	if _map_preview_tex_cache.has(map_id):
		return _map_preview_tex_cache[map_id] as Texture2D
	var metadata_img := String(map_data.get("metadata_image_path", ""))
	var md_path := String(map_data.get("metadata_path", ""))
	if metadata_img != "":
		var t := _load_preview_texture(metadata_img)
		if t != null:
			_map_preview_tex_cache[map_id] = t
			return t
	if md_path != "":
		var t2 := _load_preview_from_metadata(md_path)
		if t2 != null:
			_map_preview_tex_cache[map_id] = t2
			return t2
	var proc := _build_map_preview_fallback(vis, map_id)
	_map_preview_tex_cache[map_id] = proc
	return proc

func _load_preview_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

func _load_preview_from_metadata(metadata_path: String) -> Texture2D:
	if metadata_path == "" or not ResourceLoader.exists(metadata_path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var d := parsed as Dictionary
	var base_dir := metadata_path.get_base_dir()
	var src := String(d.get("source_image", ""))
	if src != "":
		var p := base_dir.path_join(src)
		var tex := _load_preview_texture(p)
		if tex != null:
			return tex
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return null
	var best := ""
	var best_score := -999
	for f in dir.get_files():
		var low := f.to_lower()
		if not (low.ends_with(".png") or low.ends_with(".webp")):
			continue
		var score := 0
		if low.find("mask") >= 0: score -= 20
		if low.find("overlay") >= 0: score -= 20
		if low.find("metadata") >= 0: score -= 20
		if low.find("clean") >= 0: score += 20
		if low.find("upscaled") >= 0: score += 10
		if low.find("chatgpt") >= 0: score += 5
		if score > best_score:
			best_score = score
			best = base_dir.path_join(f)
	if best != "":
		return _load_preview_texture(best)
	return null

func _build_map_preview_fallback(vis: Dictionary, map_id: String) -> Texture2D:
	# Atmospheric backdrop for zones without baked art: vertical gradient in the
	# map's palette, an accent horizon glow, dithering noise, and a vignette.
	var w := 384
	var h := 216
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var base := Color(0.10, 0.12, 0.16, 1.0)
	var alt := Color(0.13, 0.16, 0.22, 1.0)
	var accent := Color(0.35, 0.45, 0.62, 1.0)
	if vis.has("base_color"):
		base = Color.html(String(vis.get("base_color")))
	if vis.has("alt_color"):
		alt = Color.html(String(vis.get("alt_color")))
	if vis.has("accent_color"):
		accent = Color.html(String(vis.get("accent_color")))
	var rng_l := RandomNumberGenerator.new()
	rng_l.seed = hash(map_id)
	var horizon := 0.62
	for y in range(h):
		var ty := float(y) / float(h)
		var row := alt.lerp(base, ty)
		# Accent glow band around the horizon line.
		var glow := exp(-pow((ty - horizon) * 5.0, 2.0)) * 0.35
		row = row.lerp(accent, glow)
		for x in range(w):
			var tx := float(x) / float(w)
			var c := row
			# Faint vertical light shafts.
			var shaft := (sin(tx * 21.0 + float(hash(map_id) % 7)) * 0.5 + 0.5)
			c = c.lerp(accent, shaft * 0.06 * (1.0 - ty))
			# Dither noise so the gradient never bands.
			var n := (rng_l.randf() - 0.5) * 0.035
			c = Color(c.r + n, c.g + n, c.b + n, 1.0)
			# Vignette.
			var dx := tx - 0.5
			var dy := ty - 0.5
			var vig := clampf(1.0 - (dx * dx + dy * dy) * 1.1, 0.55, 1.0)
			img.set_pixel(x, y, Color(c.r * vig, c.g * vig, c.b * vig, 1.0))
	return ImageTexture.create_from_image(img)

func _start_run_with_selected_map() -> void:
	if _selected_map_locked:
		_play_ui("ui.error")
		return
	var rc := get_node_or_null("/root/RunConfig")
	var mid := ""
	var m: Dictionary = {}
	if rc != null and is_instance_valid(rc):
		mid = String(rc.get("selected_map_id"))
		if rc.has_method("get_selected_map"):
			m = rc.get_selected_map() as Dictionary
	print("DEPLOY_TRACE click map=%s t_ms=%d" % [mid, int(Time.get_ticks_msec())])
	# Start decoding the full map background on a worker thread now, so the
	# scene boot finds it ready (or nearly ready) instead of blocking.
	var vis_v: Variant = m.get("visuals", {})
	if typeof(vis_v) == TYPE_DICTIONARY:
		var bg_path := String((vis_v as Dictionary).get("bg_image_path", ""))
		if bg_path.begins_with("res://") and ResourceLoader.exists(bg_path):
			ResourceLoader.load_threaded_request(bg_path, "", true)
	_show_deploy_overlay(m)
	# Let the overlay paint before the scene build blocks the main thread.
	await _host.get_tree().process_frame
	await _host.get_tree().process_frame
	_host.get_tree().change_scene_to_packed(MAIN_SCENE)

func _show_deploy_overlay(m: Dictionary) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	_host.add_child(layer)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.015, 0.025, 0.045, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UiSkin.SPACE_MD)
	v.offset_left = -360
	v.offset_right = 360
	v.offset_top = -120
	v.offset_bottom = 120
	layer.add_child(v)

	var deploying := Label.new()
	deploying.text = "— DEPLOYING —"
	deploying.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiSkin.style_label(deploying, UiSkin.FONT_SM, UiSkin.ACCENT)
	v.add_child(deploying)

	var map_name := Label.new()
	map_name.text = String(m.get("display_name", "UNKNOWN ZONE")).to_upper()
	map_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiSkin.style_label(map_name, UiSkin.FONT_H1, UiSkin.TEXT)
	v.add_child(map_name)

	var races := _races_bbcode(m)
	if races != "":
		var races_rt := RichTextLabel.new()
		races_rt.bbcode_enabled = true
		races_rt.fit_content = true
		races_rt.scroll_active = false
		races_rt.text = "[center]%s[/center]" % races
		races_rt.add_theme_font_size_override("normal_font_size", UiSkin.FONT_LEAD)
		races_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(races_rt)

	var hint := Label.new()
	hint.text = "Stabilizing combat zone..."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiSkin.style_label(hint, UiSkin.FONT_XS, UiSkin.TEXT_DIM)
	v.add_child(hint)

func _is_map_unlocked(map_id: String) -> bool:
	var rc := get_node_or_null("/root/RunConfig")
	if rc != null and is_instance_valid(rc) and rc.has_method("get_map"):
		var md: Dictionary = rc.get_map(map_id) as Dictionary
		if not md.is_empty() and bool(md.get("always_unlocked", false)):
			return true
	if map_id == "" or map_id == "church":
		return true
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp):
		return map_id == "church"
	return bool(mp.is_map_unlocked(map_id)) if mp.has_method("is_map_unlocked") else (map_id == "church")

