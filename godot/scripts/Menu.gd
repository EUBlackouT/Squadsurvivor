extends Control

const _MenuMapPreview := preload("res://scripts/ui/MenuMapPreview.gd")
const _PixelUi := preload("res://scripts/ui/PixelUi.gd")

# Populated by _build_pixel_collection_ui()
var start_btn: Button
var resume_btn: Button
var settings_btn: Button
var back_btn: Button
var roster_box: VBoxContainer
var collection_box: HBoxContainer
var map_select: OptionButton
var _search: LineEdit
var _search_clear: Button
var _inspector_card: PanelContainer
var _inspector_portrait: Control
var _inspector_name: Label
var _inspector_stats: Label
var _inspector_passives: Label
var _inspector_synergies_title: Label
var _inspector_synergy_chips: FlowContainer
var _inspector_details_btn: Button
var _inspector_primary_btn: Button
var _inspector_status_lbl: Label
var _squad_count_lbl: Label
var _unlock_hint_lbl: Label

var _selected_unlock: Dictionary = {}
var _toast: ToastLayer = null
var _last_unlocked_map_id: String = "church"
var _map_preview = null
var _map_preview_back = null
var _bg_fill: TextureRect
var _bg_atmosphere: ColorRect
var _bg_atmosphere_mat: ShaderMaterial
var _atmos_t: float = 0.0

const _ATMOS_SHADER := preload("res://shaders/menu_collection_atmosphere.gdshader")

const MAP_BACKDROP_TINTS: Dictionary = {
	"default": Color(0.62, 0.48, 0.32, 0.55),
	"church": Color(0.58, 0.46, 0.34, 0.50),
	"library": Color(0.42, 0.38, 0.58, 0.52),
	"foundry": Color(0.72, 0.38, 0.22, 0.58),
	"cathedral": Color(0.62, 0.42, 0.28, 0.54),
	"mansion_grounds": Color(0.38, 0.52, 0.30, 0.48),
	"emerald_sanctum": Color(0.28, 0.62, 0.38, 0.52),
	"infernal_reliquary": Color(0.92, 0.32, 0.16, 0.62),
	"grand_basilica": Color(0.78, 0.36, 0.20, 0.56),
	"aurelian_court": Color(0.82, 0.58, 0.24, 0.54),
}

const TEXT_LIGHT := UiSkin.TEXT
const TEXT_SOFT := UiSkin.TEXT_SOFT
const TEXT_DIM := UiSkin.TEXT_DIM
const ACCENT_FULL := UiSkin.ACCENT_GREEN
const ACCENT_REMOVE := UiSkin.ACCENT_RED
const INK := UiSkin.TEXT
const INK_SOFT := UiSkin.TEXT_SOFT

# -------------------------
# PATCH HELPERS (safe props + autoload access)
# -------------------------
func _get_collection_manager() -> Node:
	return get_node_or_null("/root/CollectionManager")

func _obj_has_prop(o: Object, prop: String) -> bool:
	if o == null or not is_instance_valid(o):
		return false
	for p in o.get_property_list():
		if typeof(p) == TYPE_DICTIONARY:
			var d := p as Dictionary
			if String(d.get("name", "")) == prop:
				return true
	return false

func _obj_get(o: Object, prop: String, default_val: Variant) -> Variant:
	if _obj_has_prop(o, prop):
		return o.get(prop)
	return default_val

func _obj_get_int(o: Object, prop: String, default_val: int = 0) -> int:
	return int(_obj_get(o, prop, default_val))

func _obj_get_str(o: Object, prop: String, default_val: String = "") -> String:
	return String(_obj_get(o, prop, default_val))

func _sb_card(selected: bool, accent_color: Color) -> StyleBox:
	return UiSkin.card_style_hover(accent_color) if selected else UiSkin.card_style(accent_color, false)

func _sb_row_flat() -> StyleBox:
	return UiSkin.pixel_inset(0.86)

func _sb_inset() -> StyleBox:
	return UiSkin.inset_style(UiSkin.RADIUS_MD, 0.90)

func _style_btn(b: Button, primary: bool) -> void:
	if b == null:
		return
	if primary:
		UiSkin.style_pixel_primary_button(b, UiSkin.ACCENT_GOLD)
	else:
		UiSkin.style_pixel_secondary_button(b, UiSkin.ACCENT)
	b.add_theme_font_size_override("font_size", 11 if primary else 10)

func _style_line_edit(le: LineEdit) -> void:
	_PixelUi.style_line_edit(le)

func _style_option_button(ob: OptionButton) -> void:
	_PixelUi.style_option_button(ob)

func _style_lbl(lbl: Label, size: int, color: Color = UiSkin.TEXT) -> void:
	UiSkin.style_label(lbl, size, color)

func _strip_scroll_frames(sc: ScrollContainer) -> void:
	if sc == null:
		return
	sc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	sc.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var h := sc.get_h_scroll_bar()
	var v := sc.get_v_scroll_bar()
	if h:
		h.add_theme_stylebox_override("scroll", StyleBoxEmpty.new())
		h.add_theme_stylebox_override("scroll_focus", StyleBoxEmpty.new())
		h.add_theme_stylebox_override("grabber", StyleBoxEmpty.new())
		h.add_theme_stylebox_override("grabber_highlight", StyleBoxEmpty.new())
		h.add_theme_stylebox_override("grabber_pressed", StyleBoxEmpty.new())
	if v:
		v.add_theme_stylebox_override("scroll", StyleBoxEmpty.new())
		v.add_theme_stylebox_override("scroll_focus", StyleBoxEmpty.new())
		v.add_theme_stylebox_override("grabber", StyleBoxEmpty.new())
		v.add_theme_stylebox_override("grabber_highlight", StyleBoxEmpty.new())
		v.add_theme_stylebox_override("grabber_pressed", StyleBoxEmpty.new())

func _apply_layout_fixes() -> void:
	pass

func _apply_left_balance() -> void:
	pass

const STRIP_HEIGHT := 148
const STRIP_GAP := 24

func _build_collection_deck() -> void:
	for legacy in ["Root", "Deck"]:
		var n := get_node_or_null(legacy)
		if n:
			n.queue_free()

	var deck := Control.new()
	deck.name = "Deck"
	deck.set_anchors_preset(Control.PRESET_FULL_RECT)
	deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deck)

	# ── Title block (top-left, same language as main menu) ──
	var title_box := VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title_box.offset_left = 28
	title_box.offset_top = 18
	title_box.add_theme_constant_override("separation", 2)
	deck.add_child(title_box)

	var title := Label.new()
	title.text = "COLLECTION"
	UiSkin.style_label(title, 20, UiSkin.TEXT)
	title_box.add_child(title)

	var tagline := Label.new()
	tagline.text = "BUILD · DRAFT · DEPLOY"
	UiSkin.style_label(tagline, 10, UiSkin.ACCENT)
	title_box.add_child(tagline)

	var search_row := HBoxContainer.new()
	search_row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	search_row.offset_left = 28
	search_row.offset_top = 92
	search_row.offset_right = 420
	search_row.add_theme_constant_override("separation", 8)
	deck.add_child(search_row)

	_search = LineEdit.new()
	_search.placeholder_text = "Filter operatives..."
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.y = 36
	search_row.add_child(_search)

	_search_clear = Button.new()
	_search_clear.text = "✕"
	_search_clear.custom_minimum_size = Vector2(40, 36)
	search_row.add_child(_search_clear)

	# ── Hero stage (center-left) ──
	_inspector_card = PanelContainer.new()
	_inspector_card.name = "HeroStage"
	_inspector_card.clip_contents = true
	_inspector_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspector_card.offset_left = 28
	_inspector_card.offset_top = 136
	_inspector_card.offset_right = -404
	_inspector_card.offset_bottom = -(STRIP_HEIGHT + STRIP_GAP)
	_inspector_card.add_theme_stylebox_override("panel", UiSkin.pixel_panel(UiSkin.ACCENT, 0.52))
	deck.add_child(_inspector_card)

	var hero_v := VBoxContainer.new()
	hero_v.set_anchors_preset(Control.PRESET_FULL_RECT)
	hero_v.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	_inspector_card.add_child(hero_v)

	var hero_pad := MarginContainer.new()
	hero_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_pad.add_theme_constant_override("margin_left", UiSkin.SPACE_MD)
	hero_pad.add_theme_constant_override("margin_right", UiSkin.SPACE_MD)
	hero_pad.add_theme_constant_override("margin_top", UiSkin.SPACE_SM)
	hero_pad.add_theme_constant_override("margin_bottom", UiSkin.SPACE_XS)
	hero_v.add_child(hero_pad)

	var hero_body := VBoxContainer.new()
	hero_body.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	hero_pad.add_child(hero_body)

	var hero_top := HBoxContainer.new()
	hero_top.add_theme_constant_override("separation", UiSkin.SPACE_MD)
	hero_body.add_child(hero_top)

	var portrait_box := CenterContainer.new()
	portrait_box.custom_minimum_size = Vector2(168, 168)
	portrait_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hero_top.add_child(portrait_box)

	_inspector_portrait = Control.new()
	_inspector_portrait.custom_minimum_size = Vector2(168, 168)
	portrait_box.add_child(_inspector_portrait)

	var info_v := VBoxContainer.new()
	info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_v.add_theme_constant_override("separation", 4)
	hero_top.add_child(info_v)

	var hdr := Label.new()
	hdr.text = "SELECTED"
	UiSkin.style_label(hdr, 10, UiSkin.TEXT_DIM)
	info_v.add_child(hdr)

	_inspector_name = Label.new()
	_inspector_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector_name.text = "Pick from the strip below."
	UiSkin.style_label(_inspector_name, 13, UiSkin.TEXT)
	info_v.add_child(_inspector_name)

	_inspector_stats = Label.new()
	_inspector_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiSkin.style_label(_inspector_stats, 12, UiSkin.TEXT_SOFT)
	info_v.add_child(_inspector_stats)

	_inspector_passives = Label.new()
	_inspector_passives.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiSkin.style_label(_inspector_passives, 11, UiSkin.TEXT_DIM)
	info_v.add_child(_inspector_passives)

	_inspector_synergies_title = Label.new()
	_inspector_synergies_title.text = "Synergies"
	UiSkin.style_label(_inspector_synergies_title, 10, UiSkin.ACCENT)
	hero_body.add_child(_inspector_synergies_title)

	var syn_scroll := ScrollContainer.new()
	syn_scroll.custom_minimum_size = Vector2(0, 76)
	syn_scroll.size_flags_vertical = Control.SIZE_SHRINK_END
	syn_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	syn_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_strip_scroll_frames(syn_scroll)
	hero_body.add_child(syn_scroll)

	_inspector_synergy_chips = FlowContainer.new()
	_inspector_synergy_chips.add_theme_constant_override("h_separation", 8)
	_inspector_synergy_chips.add_theme_constant_override("v_separation", 6)
	_inspector_synergy_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	syn_scroll.add_child(_inspector_synergy_chips)

	var btn_pad := MarginContainer.new()
	btn_pad.add_theme_constant_override("margin_left", UiSkin.SPACE_MD)
	btn_pad.add_theme_constant_override("margin_right", UiSkin.SPACE_MD)
	btn_pad.add_theme_constant_override("margin_bottom", UiSkin.SPACE_SM)
	hero_v.add_child(btn_pad)

	var btn_inner := HBoxContainer.new()
	btn_inner.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	btn_pad.add_child(btn_inner)

	_inspector_details_btn = Button.new()
	_inspector_details_btn.text = "Dossier"
	_inspector_details_btn.custom_minimum_size = Vector2(100, 40)
	btn_inner.add_child(_inspector_details_btn)

	_inspector_status_lbl = Label.new()
	_inspector_status_lbl.visible = false
	_inspector_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiSkin.style_label(_inspector_status_lbl, 13, UiSkin.TEXT_DIM)
	btn_inner.add_child(_inspector_status_lbl)

	_inspector_primary_btn = Button.new()
	_inspector_primary_btn.text = "Add to Squad"
	_inspector_primary_btn.custom_minimum_size = Vector2(0, 40)
	_inspector_primary_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_inner.add_child(_inspector_primary_btn)

	# ── Command rail (right) — squad + deploy, mirrors main-menu zone panel ──
	var command := PanelContainer.new()
	command.name = "CommandRail"
	command.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	command.offset_left = -388
	command.offset_right = -24
	command.offset_top = 88
	command.offset_bottom = -(STRIP_HEIGHT + STRIP_GAP)
	command.add_theme_stylebox_override("panel", UiSkin.pixel_panel(UiSkin.ACCENT_GOLD, 0.52))
	deck.add_child(command)

	var cmd_pad := MarginContainer.new()
	cmd_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	cmd_pad.add_theme_constant_override("margin_left", UiSkin.SPACE_MD)
	cmd_pad.add_theme_constant_override("margin_right", UiSkin.SPACE_MD)
	cmd_pad.add_theme_constant_override("margin_top", UiSkin.SPACE_MD)
	cmd_pad.add_theme_constant_override("margin_bottom", UiSkin.SPACE_MD)
	command.add_child(cmd_pad)

	var cmd_v := VBoxContainer.new()
	cmd_v.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	cmd_pad.add_child(cmd_v)

	var squad_hdr := Label.new()
	squad_hdr.text = "— ACTIVE SQUAD —"
	UiSkin.style_label(squad_hdr, 11, UiSkin.TEXT_DIM)
	cmd_v.add_child(squad_hdr)

	var header_row := HBoxContainer.new()
	cmd_v.add_child(header_row)

	var squad_title := Label.new()
	squad_title.text = "YOUR SQUAD"
	UiSkin.style_label(squad_title, 18, UiSkin.TEXT)
	header_row.add_child(squad_title)

	header_row.add_spacer(true)

	var squad_count := Label.new()
	squad_count.name = "SquadCount"
	squad_count.text = "0 / 3"
	UiSkin.style_label(squad_count, 16, UiSkin.ACCENT_GOLD)
	header_row.add_child(squad_count)
	_squad_count_lbl = squad_count

	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.custom_minimum_size.y = 120
	_strip_scroll_frames(roster_scroll)
	roster_scroll.add_theme_stylebox_override("panel", UiSkin.pixel_inset(0.85))
	cmd_v.add_child(roster_scroll)

	roster_box = VBoxContainer.new()
	roster_box.add_theme_constant_override("separation", 8)
	roster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(roster_box)

	var unlock_hint := Label.new()
	unlock_hint.name = "UnlockHint"
	unlock_hint.visible = false
	unlock_hint.text = "↳ Unlock more slots in Protocol Grid"
	UiSkin.style_label(unlock_hint, 10, UiSkin.ACCENT_GREEN)
	cmd_v.add_child(unlock_hint)
	_unlock_hint_lbl = unlock_hint

	var deploy_hdr := Label.new()
	deploy_hdr.text = "— DEPLOYMENT —"
	UiSkin.style_label(deploy_hdr, 11, UiSkin.TEXT_DIM)
	cmd_v.add_child(deploy_hdr)

	map_select = OptionButton.new()
	map_select.custom_minimum_size.y = 40
	cmd_v.add_child(map_select)

	resume_btn = Button.new()
	resume_btn.text = "⟳ Resume Run"
	resume_btn.visible = false
	resume_btn.custom_minimum_size.y = 44
	cmd_v.add_child(resume_btn)

	start_btn = Button.new()
	start_btn.text = "▶ START RUN"
	start_btn.custom_minimum_size.y = 52
	cmd_v.add_child(start_btn)

	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	cmd_v.add_child(bottom_row)

	settings_btn = Button.new()
	settings_btn.text = "Settings"
	settings_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_btn.custom_minimum_size.y = 40
	bottom_row.add_child(settings_btn)

	back_btn = Button.new()
	back_btn.text = "← Back"
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.custom_minimum_size.y = 40
	bottom_row.add_child(back_btn)

	# ── Operative filmstrip (bottom) — like main-menu zone carousel ──
	var strip_panel := PanelContainer.new()
	strip_panel.name = "OperativeStrip"
	strip_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip_panel.offset_left = 24
	strip_panel.offset_right = -24
	strip_panel.offset_top = -STRIP_HEIGHT
	strip_panel.add_theme_stylebox_override("panel", UiSkin.pixel_inset(0.72))
	deck.add_child(strip_panel)

	var strip_pad := MarginContainer.new()
	strip_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip_pad.add_theme_constant_override("margin_left", 10)
	strip_pad.add_theme_constant_override("margin_right", 10)
	strip_pad.add_theme_constant_override("margin_top", 8)
	strip_pad.add_theme_constant_override("margin_bottom", 12)
	strip_panel.add_child(strip_pad)

	var strip_v := VBoxContainer.new()
	strip_v.add_theme_constant_override("separation", 4)
	strip_pad.add_child(strip_v)

	var strip_lbl := Label.new()
	strip_lbl.text = "OPERATIVES  ·  click to inspect"
	UiSkin.style_label(strip_lbl, 10, UiSkin.TEXT_DIM)
	strip_v.add_child(strip_lbl)

	var strip_scroll := ScrollContainer.new()
	strip_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_strip_scroll_frames(strip_scroll)
	strip_v.add_child(strip_scroll)

	collection_box = HBoxContainer.new()
	collection_box.name = "OperativeRow"
	collection_box.add_theme_constant_override("separation", 10)
	collection_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	strip_scroll.add_child(collection_box)

func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	UiSkin.apply_global_font()
	_purge_legacy_scene_backdrop()
	_apply_background_art()
	_build_collection_deck()
	# Force load save
	var cm := _get_collection_manager()
	if cm and is_instance_valid(cm) and cm.has_method("load_save"):
		cm.load_save()

	# One-time weapon re-roll for existing characters (uses flag in save)
	_maybe_reroll_weapons_once(cm)

	_toast = ToastLayer.new()
	add_child(_toast)
	_apply_background_art()
	_apply_skin()
	_refresh()

	_setup_map_select()
	call_deferred("_refresh_map_backdrop")
	# Meta Progress removed - belongs on MainMenu, not Collection page

	if _search:
		_search.text_changed.connect(func(_t: String):
			_refresh_collection()
		)
	if _search_clear:
		_search_clear.pressed.connect(func():
			if _search: _search.text = ""
			_refresh_collection()
		)

	if _inspector_details_btn:
		_inspector_details_btn.pressed.connect(func():
			if not _selected_unlock.is_empty():
				_show_details(_selected_unlock)
		)
	if _inspector_primary_btn:
		_inspector_primary_btn.pressed.connect(func():
			if not _selected_unlock.is_empty():
				_add_unlock_to_roster(_selected_unlock)
		)

	# Menu music
	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm) and mm.has_method("play"):
		mm.play("menu", 0.35)

	if start_btn:
		start_btn.pressed.connect(func():
			var s := get_node_or_null("/root/SfxSystem")
			if s and s.has_method("play_ui"):
				s.play_ui("ui.confirm")
			_on_start_run()
		)

	if settings_btn:
		settings_btn.pressed.connect(func():
			var s := get_node_or_null("/root/SfxSystem")
			if s and s.has_method("play_ui"):
				s.play_ui("ui.click")
			_open_settings()
		)

	if back_btn:
		back_btn.pressed.connect(func():
			var s := get_node_or_null("/root/SfxSystem")
			if s and s.has_method("play_ui"):
				s.play_ui("ui.cancel")
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		)

	var sv := get_node_or_null("/root/SaveManager")
	if sv and is_instance_valid(sv) and sv.has_method("load_meta"):
		# Optional: if meta_save.json exists, treat it as a higher-priority snapshot.
		sv.load_meta()

	# Resume run (if available)
	if resume_btn:
		var has := false
		if sv and is_instance_valid(sv) and sv.has_method("has_saved_run"):
			has = bool(sv.has_saved_run())
		resume_btn.visible = has
		if has:
			resume_btn.pressed.connect(func():
				var s := get_node_or_null("/root/SfxSystem")
				if s and s.has_method("play_ui"):
					s.play_ui("ui.resume_load")
				if sv and is_instance_valid(sv) and sv.has_method("request_resume"):
					if bool(sv.request_resume()):
						_on_start_run()
			)

func _squad_slots() -> int:
	# Active roster is limited by squad_slots (what you bring into a run)
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_squad_slots"):
		return int(mp.get_squad_slots())
	return 3

const WEAPON_REROLL_FLAG_PATH := "user://weapon_reroll_done.flag"

func _maybe_reroll_weapons_once(cm: Node) -> void:
	# One-time weapon re-roll for existing characters that have "standard_bolt"
	if FileAccess.file_exists(WEAPON_REROLL_FLAG_PATH):
		return
	if cm == null or not is_instance_valid(cm):
		return
	if not cm.has_method("reroll_all_weapons"):
		return
	var rerolled: int = cm.reroll_all_weapons()
	if rerolled > 0:
		print("Menu: One-time weapon re-roll for %d characters" % rerolled)
		if _toast:
			_toast.show_toast("🔫 Weapons re-rolled for testing!", UiSkin.ACCENT_GOLD)
	# Write flag so we don't do this again
	var f := FileAccess.open(WEAPON_REROLL_FLAG_PATH, FileAccess.WRITE)
	if f:
		f.store_string("done")

	if back_btn:
		back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))

func _process(delta: float) -> void:
	if _bg_atmosphere_mat != null:
		_atmos_t += delta
		_bg_atmosphere_mat.set_shader_parameter("time", _atmos_t)

func _purge_legacy_scene_backdrop() -> void:
	for legacy_name in ["Backdrop", "BackdropShader", "Root", "Deck"]:
		var legacy := get_node_or_null(legacy_name)
		if legacy:
			legacy.queue_free()

func _apply_background_art() -> void:
	if has_node("BgPreview"):
		return

	# Solid fill — always shows map pixels even if shader fails (no grey letterbox).
	_bg_fill = TextureRect.new()
	_bg_fill.name = "BgFill"
	_bg_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_fill.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_fill.z_index = -204
	add_child(_bg_fill)

	# Deep parallax — zoomed duplicate for depth.
	_map_preview_back = _MenuMapPreview.new()
	_map_preview_back.name = "BgPreviewBack"
	_map_preview_back.z_index = -203
	_map_preview_back.pan_speed = 0.35
	_map_preview_back.zoom_base = 1.28
	_map_preview_back.vignette_strength = 0.06
	_map_preview_back.brightness = 1.08
	_map_preview_back.saturation = 1.12
	_map_preview_back.modulate = Color(1.0, 0.96, 0.92, 0.72)
	_map_preview_back.crisp_pixels = true
	add_child(_map_preview_back)

	# Hero map — deployment zone, slow Ken Burns pan.
	_map_preview = _MenuMapPreview.new()
	_map_preview.name = "BgPreview"
	_map_preview.z_index = -202
	_map_preview.pan_speed = 0.9
	_map_preview.zoom_base = 1.02
	_map_preview.vignette_strength = 0.08
	_map_preview.brightness = 1.18
	_map_preview.saturation = 1.22
	_map_preview.crisp_pixels = true
	add_child(_map_preview)

	# Rim embers + zone tint (edges only — center stays clear).
	_bg_atmosphere = ColorRect.new()
	_bg_atmosphere.name = "BgAtmosphere"
	_bg_atmosphere.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_atmosphere.z_index = -201
	_bg_atmosphere_mat = ShaderMaterial.new()
	_bg_atmosphere_mat.shader = _ATMOS_SHADER
	_bg_atmosphere_mat.set_shader_parameter("tint", MAP_BACKDROP_TINTS["default"])
	_bg_atmosphere.material = _bg_atmosphere_mat
	add_child(_bg_atmosphere)

	# Light scrims for title + strip readability only.
	var top_scrim := _make_menu_scrim(Color(0.04, 0.03, 0.04, 0.38), Color(0.04, 0.03, 0.04, 0.0))
	top_scrim.name = "TopScrim"
	top_scrim.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_scrim.offset_bottom = 130
	top_scrim.z_index = -200
	add_child(top_scrim)

	var bottom_scrim := _make_menu_scrim(Color(0.03, 0.02, 0.03, 0.0), Color(0.03, 0.02, 0.03, 0.52))
	bottom_scrim.name = "BottomScrim"
	bottom_scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_scrim.offset_top = -360
	bottom_scrim.z_index = -200
	add_child(bottom_scrim)

	set_process(true)
	call_deferred("_refresh_map_backdrop")

func _refresh_map_backdrop() -> void:
	var map_id := "church"
	var m: Dictionary = {}
	var rc := get_node_or_null("/root/RunConfig")
	if rc != null and is_instance_valid(rc):
		if rc.has_method("ensure_loaded"):
			rc.ensure_loaded()
		map_id = _obj_get_str(rc, "selected_map_id", "church")
		m = rc.get_map(map_id) if rc.has_method("get_map") else {}
	var tex := _MenuMapPreview.load_map_texture(map_id, m)
	if tex == null:
		var authored := "res://assets/maps/authored/%s.webp" % map_id
		if ResourceLoader.exists(authored):
			tex = load(authored) as Texture2D
	if tex == null:
		var thumb := "res://assets/maps/thumbs/%s.webp" % map_id
		if ResourceLoader.exists(thumb):
			tex = load(thumb) as Texture2D
	if tex == null:
		tex = _MenuMapPreview.load_map_texture("church", {})
	if tex == null:
		return
	if _bg_fill != null and is_instance_valid(_bg_fill):
		_bg_fill.texture = tex
	if _map_preview != null and is_instance_valid(_map_preview):
		_map_preview.set_preview_texture(tex)
	if _map_preview_back != null and is_instance_valid(_map_preview_back):
		_map_preview_back.set_preview_texture(tex)
	if _bg_atmosphere_mat != null:
		var tint: Color = MAP_BACKDROP_TINTS.get(map_id, MAP_BACKDROP_TINTS["default"])
		_bg_atmosphere_mat.set_shader_parameter("tint", tint)

func _make_menu_scrim(from_col: Color, to_col: Color) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([from_col, to_col])
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

func _open_settings() -> void:
	if has_node("SettingsMenu"):
		return
	var sm := preload("res://scripts/SettingsMenu.gd").new()
	sm.name = "SettingsMenu"
	add_child(sm)

func _setup_map_select() -> void:
	if map_select == null:
		return
	var rc := get_node_or_null("/root/RunConfig")
	if rc == null or not is_instance_valid(rc):
		return
	if rc.has_method("ensure_loaded"):
		rc.ensure_loaded()

	map_select.clear()

	var ids: Array[String] = []
	if rc.has_method("get_map_ids_ordered"):
		ids = rc.get_map_ids_ordered()
	elif rc.has_method("get_map_ids"):
		ids = rc.get_map_ids()
	for i in range(ids.size()):
		var m: Dictionary = rc.get_map(ids[i]) if rc.has_method("get_map") else {}
		var name := String(m.get("name", ids[i]))
		var locked := not _is_map_unlocked(ids[i])
		var label := ("🔒 " + name) if locked else name
		map_select.add_item(label, i)
		map_select.set_item_metadata(i, ids[i])
		map_select.set_item_disabled(i, locked)

	# Select current
	var cur := _obj_get_str(rc, "selected_map_id", "church")
	for i in range(map_select.item_count):
		if String(map_select.get_item_metadata(i)) == cur:
			map_select.select(i)
			break
	_last_unlocked_map_id = cur if _is_map_unlocked(cur) else _last_unlocked_map_id

	map_select.item_selected.connect(func(idx: int):
		var id := String(map_select.get_item_metadata(idx))
		if map_select.is_item_disabled(idx):
			if _toast:
				_toast.show_toast("Map locked. Win the previous map to unlock.", UiSkin.ACCENT_RED)
			# Revert selection to last unlocked map.
			for i in range(map_select.item_count):
				if String(map_select.get_item_metadata(i)) == _last_unlocked_map_id:
					map_select.select(i)
					break
			return
		var s := get_node_or_null("/root/SfxSystem")
		if s and s.has_method("play_ui"):
			s.play_ui("ui.click")
		if rc.has_method("set_selected_map_id"):
			rc.set_selected_map_id(id)
		var m2: Dictionary = rc.get_map(id) if rc.has_method("get_map") else {}
		if _toast:
			_toast.show_toast("Selected: %s — %s" % [String(m2.get("name", id)), String(m2.get("tagline", ""))], Color(0.65, 0.85, 1.0, 1.0))
		_last_unlocked_map_id = id
		_refresh_map_backdrop()
	)

func _is_map_unlocked(map_id: String) -> bool:
	if map_id == "" or map_id == "church":
		return true
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp):
		return map_id == "church"
	if mp.has_method("is_map_unlocked"):
		return bool(mp.is_map_unlocked(map_id))
	return map_id == "church"

func _refresh() -> void:
	_sync_synergy_system()
	_refresh_collection()
	_refresh_roster()
	# Meta UI removed from this page - it's in MainMenu now

func _refresh_collection() -> void:
	if collection_box == null:
		return
	for c in collection_box.get_children():
		c.queue_free()

	var cm := _get_collection_manager()
	if cm == null or not is_instance_valid(cm):
		return

	var unlocked: Array = cm.unlocked
	if unlocked.is_empty():
		var l := Label.new()
		l.text = "No operatives yet — win trophies during runs."
		UiSkin.style_label(l, 13, UiSkin.TEXT_DIM)
		collection_box.add_child(l)
		return

	var q := _search.text.strip_edges().to_lower() if _search != null else ""

	for e in unlocked:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var data: Dictionary = d.get("data", {}) as Dictionary
		if not _matches_query(data, q):
			continue

		var rarity := String(data.get("rarity_id", "common"))
		var race_name := _race_name_from_data(data)
		var cls_name := _class_name(int(data.get("class_type", int(CharacterData.Class.WARRIOR))))

		var card := PanelContainer.new()
		var card_ref := card
		var data_ref := data.duplicate(true)
		card_ref.custom_minimum_size = Vector2(92, 124)
		card_ref.mouse_filter = Control.MOUSE_FILTER_PASS
		card_ref.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var selected_pid := String(_selected_unlock.get("pixellab_id", ""))
		var is_sel := selected_pid != "" and selected_pid == String(data_ref.get("pixellab_id", ""))
		var r_col := UnitFactory.rarity_color(rarity)
		card_ref.add_theme_stylebox_override("panel", UiSkin.pixel_card(r_col, is_sel))
		collection_box.add_child(card_ref)

		card_ref.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
					and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_select_unlock(data_ref)
				_refresh_collection()
				var s := get_node_or_null("/root/SfxSystem")
				if s and s.has_method("play_ui"):
					s.play_ui("ui.click")
		)

		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 4)
		pad.add_theme_constant_override("margin_right", 4)
		pad.add_theme_constant_override("margin_top", 4)
		pad.add_theme_constant_override("margin_bottom", 4)
		card_ref.add_child(pad)

		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 2)
		pad.add_child(col)

		col.add_child(_PixelUi.portrait_frame(data_ref, Vector2i(72, 72), true))

		var nm := Label.new()
		nm.text = race_name
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiSkin.style_label(nm, 10, UiSkin.TEXT)
		col.add_child(nm)

		var sub := Label.new()
		sub.text = cls_name
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiSkin.style_label(sub, 9, UiSkin.TEXT_DIM)
		col.add_child(sub)

func _make_collection_preview(data: Dictionary) -> Control:
	return _PixelUi.portrait_frame(data, Vector2i(48, 48), true)

func _refresh_roster() -> void:
	if roster_box == null:
		return
	for c in roster_box.get_children():
		c.queue_free()

	var cm := _get_collection_manager()
	if cm == null or not is_instance_valid(cm):
		return

	var roster: Array = cm.active_roster
	var cap := _squad_slots()

	# Update squad header counter (in scene)
	var squad_count := _squad_count_lbl
	if squad_count:
		var filled := mini(roster.size(), cap)
		squad_count.text = "%d / %d" % [filled, cap]
		if filled >= cap:
			squad_count.add_theme_color_override("font_color", ACCENT_FULL)
		else:
			squad_count.add_theme_color_override("font_color", TEXT_SOFT)

	# Unlock hint visibility
	var unlock_hint := _unlock_hint_lbl
	if unlock_hint:
		var mp := get_node_or_null("/root/MetaProgression")
		var show_hint := false
		if mp and is_instance_valid(mp) and mp.has_method("get_squad_slots"):
			var cur_slots := int(mp.get_squad_slots())
			var max_slots := _obj_get_int(mp, "max_squad_slots_cap", 8)
			show_hint = cur_slots < max_slots
		unlock_hint.visible = show_hint
		if show_hint:
			unlock_hint.add_theme_color_override("font_color", ACCENT_FULL)

	for i in range(cap):
		var row_card := PanelContainer.new()
		row_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_card.custom_minimum_size.y = 62
		row_card.add_theme_stylebox_override("panel", _sb_row_flat())
		roster_box.add_child(row_card)

		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 8)
		pad.add_theme_constant_override("margin_right", 8)
		pad.add_theme_constant_override("margin_top", 6)
		pad.add_theme_constant_override("margin_bottom", 6)
		row_card.add_child(pad)

		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 8)
		pad.add_child(hbox)

		# Slot label (24px)
		var slot_lbl := Label.new()
		slot_lbl.text = "%d" % (i + 1)
		slot_lbl.add_theme_font_size_override("font_size", 13)
		slot_lbl.add_theme_color_override("font_color", TEXT_DIM)
		slot_lbl.custom_minimum_size = Vector2(24, 0)
		hbox.add_child(slot_lbl)

		var is_filled := i < roster.size() and typeof(roster[i]) == TYPE_DICTIONARY
		if is_filled:
			var d: Dictionary = roster[i]
			var arch := String(d.get("archetype_id", "bruiser"))
			var cls := int(d.get("class_type", int(CharacterData.Class.WARRIOR)))
			var cls_name := _class_name(cls)
			var cls_tag := _class_tag(cls)
			var arch_display := arch if arch.strip_edges().to_lower() != cls_tag else ""

			# Portrait (40-44)
			var portrait := _make_collection_preview(d)
			portrait.custom_minimum_size = Vector2(44, 44)
			hbox.add_child(portrait)

			# InfoVBox: 2 labels (name + subline)
			var info_vbox := VBoxContainer.new()
			info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info_vbox.add_theme_constant_override("separation", 4)
			hbox.add_child(info_vbox)

			var name_lbl := Label.new()
			name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
			name_lbl.clip_text = true
			name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_lbl.text = "%s • %s" % [_race_name_from_data(d), cls_name]
			name_lbl.add_theme_font_size_override("font_size", 13)
			name_lbl.add_theme_color_override("font_color", TEXT_LIGHT)
			info_vbox.add_child(name_lbl)

			var sub_lbl := Label.new()
			sub_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
			sub_lbl.clip_text = true
			sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			sub_lbl.text = "%s HP %d DMG %d" % [
				arch_display if arch_display != "" else "—",
				int(d.get("max_hp", 100)),
				int(d.get("attack_damage", 10))
			]
			sub_lbl.add_theme_font_size_override("font_size", 11)
			sub_lbl.add_theme_color_override("font_color", TEXT_SOFT)
			info_vbox.add_child(sub_lbl)

			# Remove button (30x30)
			var remove := Button.new()
			remove.text = "✕"
			remove.tooltip_text = "Remove from squad"
			remove.custom_minimum_size = Vector2(30, 30)
			_style_btn(remove, false)
			remove.add_theme_color_override("font_color", ACCENT_REMOVE)
			hbox.add_child(remove)

			var slot_index := i # PATCH: avoid loop-capture weirdness
			remove.pressed.connect(func():
				cm.remove_from_roster(slot_index)
				_refresh()
			)
		else:
			var info_vbox := VBoxContainer.new()
			info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(info_vbox)
			var empty_lbl := Label.new()
			empty_lbl.text = "Empty slot"
			empty_lbl.add_theme_font_size_override("font_size", 13)
			empty_lbl.add_theme_color_override("font_color", TEXT_DIM)
			info_vbox.add_child(empty_lbl)

func _add_unlock_to_roster(data: Dictionary) -> void:
	var cm := _get_collection_manager()
	if cm == null or not is_instance_valid(cm):
		return
	var cap := _squad_slots()
	if cm.active_roster.size() >= cap:
		if _toast:
			_toast.show_toast("Squad full (%d/%d). Remove someone or unlock more slots." % [cap, cap], Color(1.0, 0.55, 0.45, 1.0))
		return
	var cd: CharacterData = (cm._dict_to_cd(data) as CharacterData) if cm.has_method("_dict_to_cd") else null
	if cd == null:
		return
	cm.add_to_roster(cd)
	if _toast:
		var arch := String(data.get("archetype_id", "bruiser"))
		var cls := int(data.get("class_type", int(CharacterData.Class.WARRIOR)))
		var cls_name := _class_name(cls)
		var cls_tag := _class_tag(cls)
		var show_arch := (arch.strip_edges().to_lower() != cls_tag)
		_toast.show_toast(
			"Added to roster: %s • %s%s" % [_race_name_from_data(data), cls_name, (" • %s" % arch) if show_arch else ""],
			UnitFactory.rarity_color(String(data.get("rarity_id", "common")))
		)
	_refresh()

func _select_unlock(data: Dictionary) -> void:
	_selected_unlock = data
	_refresh_inspector()

func _refresh_inspector() -> void:
	if _inspector_name == null or _inspector_primary_btn == null:
		return
	# Clear portrait slot
	if _inspector_portrait != null:
		for ch in _inspector_portrait.get_children():
			ch.queue_free()

	if _selected_unlock.is_empty():
		_inspector_name.text = "Pick an operative from the strip below."
		_inspector_stats.text = ""
		_inspector_passives.text = ""
		_clear_synergy_ui()
		_inspector_primary_btn.disabled = true
		_inspector_primary_btn.visible = false
		_inspector_status_lbl.visible = false
		return

	var arch := String(_selected_unlock.get("archetype_id", "bruiser"))
	var cls := int(_selected_unlock.get("class_type", int(CharacterData.Class.WARRIOR)))
	var cls_name := _class_name(cls)
	var race_name := _race_name_from_data(_selected_unlock)
	var cls_tag := _class_tag(cls)
	var show_arch := (arch.strip_edges().to_lower() != cls_tag)
	_inspector_name.text = "%s · %s%s" % [race_name, cls_name, (" · " + arch) if show_arch else ""]
	UiSkin.style_label(_inspector_name, 14, UiSkin.TEXT)

	# Weapon and stats
	var weapon_id := String(_selected_unlock.get("weapon_id", "standard_bolt"))
	var weapon_name := WeaponSystem.weapon_name(weapon_id) if weapon_id != "" else ("Melee" if int(_selected_unlock.get("attack_style", 1)) == 0 else "Ranged")
	_inspector_stats.text = "%s | HP %d  DMG %d  CD %.1f" % [
		weapon_name,
		int(_selected_unlock.get("max_hp", 100)),
		int(_selected_unlock.get("attack_damage", 10)),
		float(_selected_unlock.get("attack_cooldown", 1.0))
	]

	# Compact passives
	var pids: Array = _selected_unlock.get("passive_ids", [])
	var pnames: Array[String] = []
	for pid in pids:
		pnames.append(PassiveSystem.passive_name(String(pid)))
	_inspector_passives.text = (", ".join(pnames) if not pnames.is_empty() else "No passives")
	_refresh_synergy_ui_for_unlock(_selected_unlock)

	if _inspector_portrait != null:
		var p := _PixelUi.portrait_frame(_selected_unlock, Vector2i(156, 156), true)
		_inspector_portrait.add_child(p)

	# Determine primary action: Add if not in roster, else show hint.
	var cm := _get_collection_manager()
	var in_roster := false
	var squad_full := false
	if cm and is_instance_valid(cm):
		# Check if squad is full
		var cap := _squad_slots()
		squad_full = cm.active_roster.size() >= cap
		# Check if already in roster
		for r in cm.active_roster:
			if typeof(r) == TYPE_DICTIONARY:
				var rd := r as Dictionary
				if String(rd.get("pixellab_id", "")) == String(_selected_unlock.get("pixellab_id", "")) and String(_selected_unlock.get("pixellab_id", "")) != "":
					in_roster = true
					break
	if in_roster:
		_inspector_primary_btn.visible = false
		_inspector_status_lbl.visible = true
		_inspector_status_lbl.text = "In Squad"
		UiSkin.style_label(_inspector_status_lbl, 13, UiSkin.ACCENT_GREEN)
	elif squad_full:
		_inspector_primary_btn.visible = false
		_inspector_status_lbl.visible = true
		_inspector_status_lbl.text = "Squad Full"
		UiSkin.style_label(_inspector_status_lbl, 13, UiSkin.TEXT_DIM)
	else:
		_inspector_primary_btn.visible = true
		_inspector_status_lbl.visible = false
		_inspector_primary_btn.text = "Add to Squad"
		_inspector_primary_btn.disabled = false
		_style_btn(_inspector_primary_btn, true)

func _matches_query(data: Dictionary, q: String) -> bool:
	if q == "":
		return true
	var parts := q.split(" ", false)
	var hay := PackedStringArray()
	hay.append(String(data.get("rarity_id", "")))
	hay.append(String(data.get("archetype_id", "")))
	hay.append(_class_name(int(data.get("class_type", int(CharacterData.Class.WARRIOR)))).to_lower())
	hay.append("class:" + _class_tag(int(data.get("class_type", int(CharacterData.Class.WARRIOR)))))
	for pid in data.get("passive_ids", []):
		hay.append(PassiveSystem.passive_name(String(pid)).to_lower())
		hay.append(String(pid).to_lower())
	var blob := " ".join(hay).to_lower()
	for p in parts:
		if p == "":
			continue
		if blob.find(p.to_lower()) < 0:
			return false
	return true

func _apply_skin() -> void:
	_style_line_edit(_search)
	_style_btn(start_btn, true)
	_style_btn(resume_btn, false)
	_style_btn(settings_btn, false)
	_style_btn(back_btn, false)
	_style_btn(_search_clear, false)
	_style_btn(_inspector_details_btn, false)
	_style_btn(_inspector_primary_btn, true)
	if map_select:
		_style_option_button(map_select)

func _on_start_run() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _show_details(data: Dictionary) -> void:
	if has_node("DetailsModal"):
		get_node("DetailsModal").queue_free()
	var layer := CanvasLayer.new()
	layer.name = "DetailsModal"
	layer.layer = 170
	add_child(layer)

	var rarity := String(data.get("rarity_id", "common"))
	var shell := _PixelUi.modal_shell(
		"Operative Dossier",
		UnitFactory.rarity_name(rarity).to_upper(),
		UnitFactory.rarity_color(rarity))
	layer.add_child(shell.root)
	shell.root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_PixelUi.animate_modal_in(shell)
	shell.close_btn.pressed.connect(func():
		layer.queue_free()
	)

	var v := shell.body as VBoxContainer

	var arch := String(data.get("archetype_id", "bruiser"))
	var weapon_id := String(data.get("weapon_id", "standard_bolt"))
	var weapon_name := WeaponSystem.weapon_name(weapon_id) if weapon_id != "" else ("MELEE" if int(data.get("attack_style", 1)) == 0 else "RANGED")
	var cls := int(data.get("class_type", int(CharacterData.Class.WARRIOR)))
	var cls_name := _class_name(cls)
	var cls_tag := _class_tag(cls)
	var show_arch := (arch.strip_edges().to_lower() != cls_tag)

	# Header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	v.add_child(header)

	var portrait := _PixelUi.portrait_frame(data, Vector2i(96, 96), true)
	header.add_child(portrait)

	var header_right := VBoxContainer.new()
	header_right.add_theme_constant_override("separation", 6)
	header_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_right)

	var t := Label.new()
	t.text = "%s • %s%s • %s" % [
		_race_name_from_data(data),
		cls_name,
		(" • %s" % arch) if show_arch else "",
		weapon_name
	]
	_PixelUi.style_label(t, 22, UnitFactory.rarity_color(rarity), 2)
	header_right.add_child(t)

	var cchip := Label.new()
	cchip.text = "Class: %s" % cls_name
	cchip.add_theme_font_size_override("font_size", 13)
	cchip.add_theme_color_override("font_color", _class_color(cls))
	header_right.add_child(cchip)

	var stats_grid := GridContainer.new()
	stats_grid.columns = 3
	stats_grid.add_theme_constant_override("h_separation", 8)
	stats_grid.add_theme_constant_override("v_separation", 8)
	header_right.add_child(stats_grid)

	_add_stat_chip(stats_grid, "HP", str(int(data.get("max_hp", 100))), Color(0.55, 1.0, 0.65, 1.0))
	_add_stat_chip(stats_grid, "DMG", str(int(data.get("attack_damage", 10))), Color(1.0, 0.55, 0.45, 1.0))
	_add_stat_chip(stats_grid, "CD", "%.2f" % float(data.get("attack_cooldown", 1.0)), Color(0.75, 0.80, 0.86, 1.0))
	_add_stat_chip(stats_grid, "RNG", str(int(float(data.get("attack_range", 300.0)))), Color(0.60, 1.0, 0.80, 1.0))
	_add_stat_chip(stats_grid, "CRIT", "%.0f%%" % (float(data.get("crit_chance", 0.0)) * 100.0), Color(1.0, 0.85, 0.30, 1.0))
	_add_stat_chip(stats_grid, "MULT", "x%.2f" % float(data.get("crit_mult", 1.5)), Color(1.0, 0.85, 0.30, 1.0))

	var sep := HSeparator.new()
	v.add_child(sep)

	# Synergies
	var stitle := Label.new()
	stitle.text = "Synergies"
	stitle.add_theme_font_size_override("font_size", 16)
	stitle.add_theme_color_override("font_color", TEXT_LIGHT)
	v.add_child(stitle)

	var syn_flow := FlowContainer.new()
	syn_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	syn_flow.add_theme_constant_override("h_separation", 8)
	syn_flow.add_theme_constant_override("v_separation", 8)
	v.add_child(syn_flow)
	_populate_synergy_chips_for_unlock(syn_flow, data)

	var sep2 := HSeparator.new()
	v.add_child(sep2)

	var ptitle := Label.new()
	ptitle.text = "Passives"
	ptitle.add_theme_font_size_override("font_size", 16)
	ptitle.add_theme_color_override("font_color", TEXT_LIGHT)
	v.add_child(ptitle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 160)
	v.add_child(scroll)

	var pbox := VBoxContainer.new()
	pbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pbox.add_theme_constant_override("separation", 8)
	scroll.add_child(pbox)

	var pids: Array = data.get("passive_ids", [])
	if pids.is_empty():
		var none := Label.new()
		none.text = "(No passives)"
		none.add_theme_color_override("font_color", TEXT_SOFT)
		pbox.add_child(none)
	else:
		for pid in pids:
			pbox.add_child(_make_passive_row(String(pid)))

func _add_stat_chip(parent: Control, label: String, value: String, tint: Color) -> void:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiSkin.chip_style(tint)
	chip.add_theme_stylebox_override("panel", sb)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	chip.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pad.add_child(v)

	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", TEXT_SOFT)
	v.add_child(l)

	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", tint)
	v.add_child(val)

	parent.add_child(chip)

func _sync_synergy_system() -> void:
	# Keep SynergySystem roster in sync with the Armory roster so chip counts are correct.
	SynergySystem.ensure_loaded()
	var cm := _get_collection_manager()
	if cm != null and is_instance_valid(cm) and cm.has_method("get_active_roster_character_data"):
		var cds: Array = cm.get_active_roster_character_data()
		SynergySystem.set_roster(cds)

func _clear_synergy_ui() -> void:
	if _inspector_synergy_chips != null:
		for c in _inspector_synergy_chips.get_children():
			c.queue_free()
	if _inspector_synergies_title != null:
		_inspector_synergies_title.visible = false
	if _inspector_synergy_chips != null:
		_inspector_synergy_chips.visible = false

func _refresh_synergy_ui_for_unlock(unlock_data: Dictionary) -> void:
	if _inspector_synergy_chips == null:
		return
	# Clear and repopulate
	for c in _inspector_synergy_chips.get_children():
		c.queue_free()
	_populate_synergy_chips_for_unlock(_inspector_synergy_chips, unlock_data)
	var has_any := _inspector_synergy_chips.get_child_count() > 0
	if _inspector_synergies_title != null:
		_inspector_synergies_title.visible = true
	if _inspector_synergy_chips != null:
		_inspector_synergy_chips.visible = true
	# If empty, show a soft placeholder chip so section isn't confusing.
	if not has_any:
		var l := Label.new()
		l.text = "—"
		l.add_theme_color_override("font_color", UiSkin.TEXT_SOFT)
		_inspector_synergy_chips.add_child(l)

func _populate_synergy_chips_for_unlock(parent: Control, unlock_data: Dictionary) -> void:
	if parent == null:
		return
	var cm := _get_collection_manager()
	var cd: CharacterData = (cm._dict_to_cd(unlock_data) as CharacterData) if (cm != null and is_instance_valid(cm) and cm.has_method("_dict_to_cd")) else null
	if cd == null:
		return
	SynergySystem.ensure_loaded()
	var states := SynergySystem.synergy_states_for_cd(cd)
	# Sort by "most complete" first for readability.
	states.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ar := float(a.get("count", 0)) / float(max(1, int(a.get("tier_count", 0)) if int(a.get("tier_count", 0)) > 0 else int(a.get("next_tier_count", 1))))
		var br := float(b.get("count", 0)) / float(max(1, int(b.get("tier_count", 0)) if int(b.get("tier_count", 0)) > 0 else int(b.get("next_tier_count", 1))))
		return ar > br
	)
	for st in states:
		if typeof(st) != TYPE_DICTIONARY:
			continue
		parent.add_child(_make_synergy_chip(st as Dictionary))

func _make_synergy_chip(state: Dictionary) -> Control:
	var name: String = String(state.get("name", "Synergy"))
	var count: int = int(state.get("count", 0))
	var tier_n: int = int(state.get("tier_count", 0))
	var next_n: int = int(state.get("next_tier_count", 0))
	var denom: int = (tier_n if tier_n > 0 else (next_n if next_n > 0 else max(1, count)))
	var txt: String = "%s (%d/%d)" % [name, count, denom]

	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var active: bool = tier_n > 0
	var accent: Color = (Color(0.72, 0.88, 0.78, 1.0) if active else Color(0.62, 0.64, 0.70, 1.0))
	var sb := UiSkin.pixel_inset(0.95 if active else 0.88)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.75 if active else 0.45)
	chip.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = txt
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSkin.style_label(lbl, 10, accent)
	chip.add_child(lbl)

	var tip := TooltipButton.new()
	tip.text = ""
	tip.tooltip_text = SynergySystem.synergy_tooltip_bbcode(state)
	tip.tooltip_accent = accent
	tip.mouse_default_cursor_shape = Control.CURSOR_HELP
	tip.set_anchors_preset(Control.PRESET_FULL_RECT)
	tip.flat = true
	tip.pressed.connect(func(): pass)
	chip.add_child(tip)
	return chip

func _make_passive_row(pid: String) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := UiSkin.card_style(PassiveSystem.passive_color(pid), false)
	row.add_theme_stylebox_override("panel", sb)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	row.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pad.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)

	var name := Label.new()
	name.text = PassiveSystem.passive_name(pid)
	name.add_theme_font_size_override("font_size", 14)
	name.add_theme_color_override("font_color", PassiveSystem.passive_color(pid))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)

	# Tag pills
	var tags := PassiveSystem.passive_tags(pid)
	for t in tags:
		if String(t) == "":
			continue
		top.add_child(_make_tag_pill(String(t)))

	var desc := Label.new()
	desc.text = PassiveSystem.passive_description(pid)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", TEXT_SOFT)
	v.add_child(desc)
	return row

func _make_tag_pill(tag: String) -> Control:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiSkin.chip_style(UiSkin.ACCENT)
	pill.add_theme_stylebox_override("panel", sb)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 7)
	pad.add_theme_constant_override("margin_right", 7)
	pad.add_theme_constant_override("margin_top", 3)
	pad.add_theme_constant_override("margin_bottom", 3)
	pill.add_child(pad)

	var l := Label.new()
	l.text = tag.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", TEXT_SOFT)
	pad.add_child(l)
	return pill

static func _class_name(c: int) -> String:
	match c:
		CharacterData.Class.WARRIOR: return "Warrior"
		CharacterData.Class.MAGE: return "Mage"
		CharacterData.Class.ROGUE: return "Rogue"
		CharacterData.Class.GUARDIAN: return "Guardian"
		CharacterData.Class.HEALER: return "Healer"
		CharacterData.Class.SUMMONER: return "Summoner"
		_: return "Unknown"

static func _class_tag(c: int) -> String:
	match c:
		CharacterData.Class.WARRIOR: return "warrior"
		CharacterData.Class.MAGE: return "mage"
		CharacterData.Class.ROGUE: return "rogue"
		CharacterData.Class.GUARDIAN: return "guardian"
		CharacterData.Class.HEALER: return "healer"
		CharacterData.Class.SUMMONER: return "summoner"
		_: return "unknown"

static func _race_name_from_data(data: Dictionary) -> String:
	var race := String(data.get("race_id", "")).strip_edges()
	if race != "":
		return race.capitalize()
	var origin_id := String(data.get("origin_id", "")).strip_edges()
	if origin_id != "":
		return origin_id.capitalize()
	return "Unknown"

static func _class_color(c: int) -> Color:
	# Matches the projectile tint mapping in SquadUnit (keeps the UI consistent with combat colors).
	match c:
		CharacterData.Class.WARRIOR: return Color(1.0, 0.35, 0.35, 1.0)
		CharacterData.Class.MAGE: return Color(0.85, 0.45, 1.0, 1.0)
		CharacterData.Class.ROGUE: return Color(1.0, 0.90, 0.35, 1.0)
		CharacterData.Class.GUARDIAN: return Color(0.40, 1.0, 0.55, 1.0)
		CharacterData.Class.HEALER: return Color(0.65, 0.85, 1.0, 1.0)
		CharacterData.Class.SUMMONER: return Color(0.95, 0.35, 0.95, 1.0)
		_: return Color(0.75, 0.85, 1.0, 1.0)
