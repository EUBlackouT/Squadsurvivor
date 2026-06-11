extends Control

@onready var start_btn: Button = get_node_or_null("Root/Right/RightPad/RightVBox/RunCard/Pad/RunVBox/StartRun") as Button
@onready var resume_btn: Button = get_node_or_null("Root/Right/RightPad/RightVBox/RunCard/Pad/RunVBox/ResumeRun") as Button
@onready var settings_btn: Button = get_node_or_null("Root/Right/RightPad/RightVBox/RunCard/Pad/RunVBox/BottomRow/SettingsBtn") as Button
@onready var back_btn: Button = get_node_or_null("Root/Right/RightPad/RightVBox/RunCard/Pad/RunVBox/BottomRow/BackBtn") as Button
@onready var roster_box: VBoxContainer = get_node_or_null("Root/Right/RightPad/RightVBox/SquadCard/Pad/SquadVBox/RosterScroll/RosterVBox") as VBoxContainer
@onready var collection_box: VBoxContainer = get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/CollectionScroll/CollectionBox") as VBoxContainer
@onready var map_select: OptionButton = get_node_or_null("Root/Right/RightPad/RightVBox/RunCard/Pad/RunVBox/MapSelect") as OptionButton

@onready var _search: LineEdit = get_node_or_null("Root/Left/LeftPad/LeftVBox/SearchRow/Search") as LineEdit
@onready var _search_clear: Button = get_node_or_null("Root/Left/LeftPad/LeftVBox/SearchRow/Clear") as Button

@onready var _inspector_card: PanelContainer = get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/InspectorCard") as PanelContainer
@onready var _inspector_portrait: Control = get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/InspectorCard/InspectorPad/InspectorVBox/InspectorBody/InspectorPortrait") as Control
@onready var _inspector_name: Label = get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/InspectorCard/InspectorPad/InspectorVBox/InspectorBody/InspectorInfo/InspectorName") as Label
@onready var _inspector_stats: Label = get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/InspectorCard/InspectorPad/InspectorVBox/InspectorBody/InspectorInfo/InspectorStats") as Label
@onready var _inspector_passives: Label = get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/InspectorCard/InspectorPad/InspectorVBox/InspectorBody/InspectorInfo/InspectorPassives") as Label
@onready var _inspector_synergies_title: Label = get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/InspectorCard/InspectorPad/InspectorVBox/InspectorBody/InspectorInfo/InspectorSynergiesTitle") as Label
@onready var _inspector_synergy_chips: FlowContainer = get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/InspectorCard/InspectorPad/InspectorVBox/InspectorBody/InspectorInfo/InspectorSynergyChips") as FlowContainer
@onready var _inspector_details_btn: Button = get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/InspectorCard/InspectorPad/InspectorVBox/InspectorButtons/InspectorDetails") as Button
@onready var _inspector_primary_btn: Button = get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/InspectorCard/InspectorPad/InspectorVBox/InspectorButtons/InspectorPrimary") as Button

var _selected_unlock: Dictionary = {}
var _toast: ToastLayer = null
var _last_unlocked_map_id: String = "graveyard"

# Tactical/dark skin (shared with revamped main menu)
const BG_FANTASY_PATH := "res://assets/ui/revamp/menu_bg.png"

# === Readability palette (dark UI content over fantasy background) ===
const TEXT_LIGHT := Color(0.93, 0.97, 1.0, 1.0)
const TEXT_SOFT := Color(0.78, 0.88, 1.0, 0.92)
const TEXT_DIM := Color(0.58, 0.68, 0.78, 0.90)
const TITLE_GOLD := Color(0.95, 0.78, 0.44, 1.0)
const BORDER_SUBTLE := Color(0.20, 0.46, 0.72, 0.32)
const SURFACE_INSET := Color(0.02, 0.04, 0.07, 0.76)
const SURFACE_CARD := Color(0.04, 0.06, 0.10, 0.88)
const SURFACE_CARD_OPAQUE := Color(0.04, 0.06, 0.10, 0.95)
# Dark ink for inputs (light textbox)
const INK_DARK := Color(0.11, 0.13, 0.18, 1.0)
const PLACEHOLDER := Color(0.42, 0.56, 0.72, 0.85)
# Accents (status / actions)
const ACCENT_FULL := Color(0.35, 0.55, 0.35, 1.0)      # squad full ok
const ACCENT_REMOVE := Color(0.9, 0.4, 0.35, 1.0)     # remove button
const OUTLINE_DARK := Color(0, 0, 0, 0.35)            # label outline on dark bg
# Labels on dark surfaces use light text
const INK := TEXT_LIGHT
const INK_SOFT := TEXT_SOFT

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

func _sb_panel() -> StyleBox:
	# Cohesive with the shared design system (was a brown wood fallback).
	return UiSkin.panel_style(UiSkin.ACCENT, false)

## Flat fill for right-side cards (no texture - readable text)
func _sb_card_flat() -> StyleBox:
	var f := StyleBoxFlat.new()
	f.bg_color = SURFACE_CARD_OPAQUE
	f.border_width_left = 1
	f.border_width_right = 1
	f.border_width_top = 1
	f.border_width_bottom = 1
	f.border_color = BORDER_SUBTLE
	f.corner_radius_top_left = 12
	f.corner_radius_top_right = 12
	f.corner_radius_bottom_left = 12
	f.corner_radius_bottom_right = 12
	return f

## Roster row: dark translucent, readable
func _sb_row_flat() -> StyleBox:
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.06, 0.08, 0.11, 0.88)
	f.border_width_left = 0
	f.border_width_right = 0
	f.border_width_top = 0
	f.border_width_bottom = 1
	f.border_color = Color(0.30, 0.45, 0.60, 0.25)
	f.corner_radius_top_left = 6
	f.corner_radius_top_right = 6
	f.corner_radius_bottom_left = 6
	f.corner_radius_bottom_right = 6
	return f

## Dark inset for scroll/content areas (readable, one consistent style)
func _sb_inset() -> StyleBox:
	var f := StyleBoxFlat.new()
	f.bg_color = SURFACE_INSET
	f.border_width_left = 1
	f.border_width_right = 1
	f.border_width_top = 1
	f.border_width_bottom = 1
	f.border_color = BORDER_SUBTLE
	f.corner_radius_top_left = 14
	f.corner_radius_top_right = 14
	f.corner_radius_bottom_left = 14
	f.corner_radius_bottom_right = 14
	f.content_margin_left = 10
	f.content_margin_right = 10
	f.content_margin_top = 10
	f.content_margin_bottom = 10
	return f

func _sb_card(selected: bool, accent_color: Color = Color(0.45, 0.55, 0.35, 0.7)) -> StyleBox:
	# Texture cards are noisy; use dark flat for readability
	var f := StyleBoxFlat.new()
	f.bg_color = SURFACE_CARD
	f.border_width_left = 1
	f.border_width_right = 1
	f.border_width_top = 1
	f.border_width_bottom = 1
	f.border_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.45)
	f.corner_radius_top_left = 12
	f.corner_radius_top_right = 12
	f.corner_radius_bottom_left = 12
	f.corner_radius_bottom_right = 12
	if selected:
		f.border_width_left = 2
		f.border_width_right = 2
		f.border_width_top = 2
		f.border_width_bottom = 2
		f.border_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.9)
		f.shadow_size = 10
		f.shadow_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.18)
	return f

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

## Clear input field: light background, dark text, readable placeholder
func _sb_input() -> StyleBox:
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.96, 0.94, 0.90, 0.95)
	f.border_width_left = 1
	f.border_width_right = 1
	f.border_width_top = 1
	f.border_width_bottom = 1
	f.border_color = Color(0.25, 0.22, 0.18, 0.35)
	f.corner_radius_top_left = 8
	f.corner_radius_top_right = 8
	f.corner_radius_bottom_left = 8
	f.corner_radius_bottom_right = 8
	f.shadow_size = 4
	f.shadow_color = Color(0, 0, 0, 0.08)
	return f

func _style_btn(b: Button, primary: bool) -> void:
	if b == null:
		return
	# Shared design-system buttons (was brown wood fallback styleboxes).
	if primary:
		UiSkin.style_primary_button(b, UiSkin.ACCENT_GOLD)
	else:
		UiSkin.style_secondary_button(b, UiSkin.ACCENT)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)

func _style_line_edit(le: LineEdit) -> void:
	if le == null:
		return
	le.add_theme_stylebox_override("normal", _sb_input())
	le.add_theme_stylebox_override("focus", _sb_input())
	le.add_theme_color_override("font_color", INK_DARK)
	le.add_theme_color_override("font_placeholder_color", PLACEHOLDER)

func _style_option_button(ob: OptionButton) -> void:
	if ob == null:
		return
	ob.add_theme_stylebox_override("normal", _sb_input())
	ob.add_theme_stylebox_override("focus", _sb_input())
	ob.add_theme_stylebox_override("hover", _sb_input())
	ob.add_theme_font_size_override("font_size", 14)
	ob.add_theme_color_override("font_color", INK_DARK)
	ob.add_theme_color_override("font_hover_color", INK_DARK)

func _apply_layout_fixes() -> void:
	var root := get_node_or_null("Root") as HBoxContainer
	if root:
		root.add_theme_constant_override("separation", 24)
	var left := get_node_or_null("Root/Left") as Control
	var right := get_node_or_null("Root/Right") as Control
	if left:
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_stretch_ratio = 2.4
	if right:
		right.custom_minimum_size.x = 460  # Critical: give right side width
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.size_flags_stretch_ratio = 1.0
	var right_vbox := get_node_or_null("Root/Right/RightPad/RightVBox") as VBoxContainer
	if right_vbox:
		right_vbox.add_theme_constant_override("separation", 10)

func _apply_left_balance() -> void:
	var cs := get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/CollectionScroll") as Control
	if cs:
		cs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _inspector_card:
		_inspector_card.custom_minimum_size.x = 320
		_inspector_card.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	UiSkin.apply_global_font()
	_apply_layout_fixes()
	_apply_left_balance()
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

func _apply_background_art() -> void:
	if has_node("BgArt"):
		return

	var bg := TextureRect.new()
	bg.name = "BgArt"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.z_index = -200
	bg.texture = load(BG_FANTASY_PATH) as Texture2D if ResourceLoader.exists(BG_FANTASY_PATH) else null
	add_child(bg)
	move_child(bg, 0)

	# Kill purple overlay layers
	var backdrop := get_node_or_null("Backdrop") as CanvasItem
	if backdrop:
		backdrop.visible = false
	var backdrop_shader := get_node_or_null("BackdropShader") as CanvasItem
	if backdrop_shader:
		backdrop_shader.visible = false

	# Subtle forest haze so UI pops
	var haze := ColorRect.new()
	haze.name = "ForestHaze"
	haze.set_anchors_preset(Control.PRESET_FULL_RECT)
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	haze.color = Color(0.04, 0.06, 0.05, 0.22)
	add_child(haze)
	move_child(haze, 1)

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
	var cur := _obj_get_str(rc, "selected_map_id", "graveyard")
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
	)

func _is_map_unlocked(map_id: String) -> bool:
	if map_id == "" or map_id == "graveyard" or map_id == "cathedral":
		return true
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp):
		return map_id == "graveyard" or map_id == "cathedral"
	if mp.has_method("is_map_unlocked"):
		return bool(mp.is_map_unlocked(map_id))
	return map_id == "graveyard" or map_id == "cathedral"

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
		l.text = "No unlocked characters yet.\n(Play a run, unlock trophies in the draft.)"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		var arch := String(data.get("archetype_id", "bruiser"))
		var cls := int(data.get("class_type", int(CharacterData.Class.WARRIOR)))
		var cls_name := _class_name(cls)
		var cls_tag := _class_tag(cls)

		# Card row with glow and hover effects
		var card := PanelContainer.new()
		var card_ref := card # PATCH: avoid loop-capture weirdness
		var data_ref := data.duplicate(true) # PATCH: stable per-card reference

		card_ref.mouse_filter = Control.MOUSE_FILTER_PASS
		card_ref.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var selected_pid := String(_selected_unlock.get("pixellab_id", ""))
		var is_selected := (selected_pid != "" and selected_pid == String(data_ref.get("pixellab_id", "")))
		card_ref.add_theme_stylebox_override("panel", _sb_card(is_selected, UnitFactory.rarity_color(rarity)))
		collection_box.add_child(card_ref)

		if is_selected:
			var tws := card_ref.create_tween()
			tws.set_loops()
			tws.tween_property(card_ref, "scale", Vector2(1.01, 1.01), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tws.tween_property(card_ref, "scale", Vector2(1.0, 1.0), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		# Add subtle scale on hover
		card_ref.pivot_offset = Vector2(card_ref.size.x * 0.5, card_ref.size.y * 0.5) if card_ref.size.x > 0 else Vector2.ZERO
		card_ref.mouse_entered.connect(func():
			var tw := card_ref.create_tween()
			tw.set_trans(Tween.TRANS_BACK)
			tw.set_ease(Tween.EASE_OUT)
			tw.tween_property(card_ref, "scale", Vector2(1.01, 1.01), 0.1)
		)
		card_ref.mouse_exited.connect(func():
			var tw := card_ref.create_tween()
			tw.set_trans(Tween.TRANS_SINE)
			tw.set_ease(Tween.EASE_OUT)
			tw.tween_property(card_ref, "scale", Vector2.ONE, 0.08)
		)

		card_ref.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_select_unlock(data_ref)
				# Click feedback
				var s := get_node_or_null("/root/SfxSystem")
				if s and s.has_method("play_ui"):
					s.play_ui("ui.click")
		)

		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 10)
		pad.add_theme_constant_override("margin_right", 10)
		pad.add_theme_constant_override("margin_top", 8)
		pad.add_theme_constant_override("margin_bottom", 8)
		card_ref.add_child(pad)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_theme_constant_override("separation", 10)
		pad.add_child(row)

		row.add_child(_make_collection_preview(data_ref))

		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 2)
		row.add_child(mid)

		var name := Label.new()
		var race_name := _race_name_from_data(data_ref)
		var show_arch := (arch.strip_edges().to_lower() != cls_tag)
		var name_base := "%s • %s%s" % [
			race_name,
			cls_name,
			(" • %s" % arch) if show_arch else ""
		]
		name.text = "● " + name_base
		name.add_theme_font_size_override("font_size", 15)
		name.add_theme_color_override("font_color", TEXT_LIGHT)
		name.add_theme_color_override("font_outline_color", OUTLINE_DARK)
		name.add_theme_constant_override("outline_size", 2)
		mid.add_child(name)

		var small := Label.new()
		small.text = "HP %d  DMG %d  CD %.2f  RNG %d" % [
			int(data_ref.get("max_hp", 100)),
			int(data_ref.get("attack_damage", 10)),
			float(data_ref.get("attack_cooldown", 1.0)),
			int(float(data_ref.get("attack_range", 300.0)))
		]
		small.add_theme_font_size_override("font_size", 11)
		small.add_theme_color_override("font_color", TEXT_SOFT)
		mid.add_child(small)

func _make_collection_preview(data: Dictionary) -> Control:
	var rarity := String(data.get("rarity_id", "common"))

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(56, 56)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	frame.add_theme_stylebox_override("panel", UiSkin.panel_style(UnitFactory.rarity_color(rarity), false))

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 4)
	pad.add_theme_constant_override("margin_right", 4)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	frame.add_child(pad)

	var sprite_path := String(data.get("sprite_path", ""))
	var frames := PixellabUtil.walk_frames_from_south_path(sprite_path)

	# Animated preview (preferred)
	if frames != null and frames.has_animation("walk_south") and frames.get_frame_count("walk_south") > 0:
		var svc := SubViewportContainer.new()
		svc.custom_minimum_size = Vector2(48, 48)
		svc.stretch = true
		svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(svc)

		var vp := SubViewport.new()
		vp.size = Vector2i(48, 48)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		svc.add_child(vp)

		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames
		spr.animation = "walk_south"
		spr.centered = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Framing: keep head visible while showing more body.
		spr.position = Vector2(24, 30)
		var scale := PixellabUtil.scale_for_target_height(frames, 32.0, 0.40, 0.80)
		spr.scale = Vector2.ONE * scale
		spr.play()
		vp.add_child(spr)
		return frame

	# Static fallback
	var tex := PixellabUtil.load_rotation_texture(sprite_path)
	if tex == null:
		var pid := String(data.get("pixellab_id", ""))
		if pid != "":
			tex = PixellabUtil.load_rotation_texture("res://assets/pixellab/%s/rotations/south.png" % pid)
	if tex != null:
		# Use SubViewport even for static so we can bias upward.
		var svc2 := SubViewportContainer.new()
		svc2.custom_minimum_size = Vector2(48, 48)
		svc2.stretch = true
		svc2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(svc2)

		var vp2 := SubViewport.new()
		vp2.size = Vector2i(48, 48)
		vp2.transparent_bg = true
		vp2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp2.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		svc2.add_child(vp2)

		var spr2 := Sprite2D.new()
		spr2.texture = tex
		spr2.centered = true
		spr2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Match animated framing: keep head visible while showing more body.
		spr2.position = Vector2(24, 30)
		# Scale to fit nicely in the box.
		var ts := tex.get_size()
		var max_dim := maxf(1.0, maxf(ts.x, ts.y))
		var scale2 := (32.0 / max_dim)
		spr2.scale = Vector2.ONE * clampf(scale2, 0.40, 0.80)
		vp2.add_child(spr2)
	return frame

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
	var squad_count := get_node_or_null("Root/Right/RightPad/RightVBox/SquadCard/Pad/SquadVBox/HeaderRow/SquadCount") as Label
	if squad_count:
		var filled := mini(roster.size(), cap)
		squad_count.text = "%d / %d" % [filled, cap]
		if filled >= cap:
			squad_count.add_theme_color_override("font_color", ACCENT_FULL)
		else:
			squad_count.add_theme_color_override("font_color", TEXT_SOFT)

	# Unlock hint visibility
	var unlock_hint := get_node_or_null("Root/Right/RightPad/RightVBox/SquadCard/Pad/SquadVBox/UnlockHint") as Label
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
		row_card.custom_minimum_size.y = 56
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
			info_vbox.add_theme_constant_override("separation", 2)
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
		_inspector_name.text = "Click a character to preview."
		_inspector_stats.text = ""
		_inspector_passives.text = ""
		_clear_synergy_ui()
		_inspector_primary_btn.disabled = true
		return

	var arch := String(_selected_unlock.get("archetype_id", "bruiser"))
	var cls := int(_selected_unlock.get("class_type", int(CharacterData.Class.WARRIOR)))
	var cls_name := _class_name(cls)
	var race_name := _race_name_from_data(_selected_unlock)
	var cls_tag := _class_tag(cls)
	var show_arch := (arch.strip_edges().to_lower() != cls_tag)
	# Compact name line (light text on dark card)
	_inspector_name.text = "● %s • %s%s" % [race_name, cls_name, (" • %s" % arch) if show_arch else ""]
	_inspector_name.add_theme_color_override("font_color", TEXT_LIGHT)
	_inspector_name.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	_inspector_name.add_theme_constant_override("outline_size", 2)

	# Weapon and stats on one compact line
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
		var p := _make_detail_portrait(_selected_unlock)
		p.custom_minimum_size = Vector2(72, 72)
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
		_inspector_primary_btn.text = "In Squad ✓"
		_inspector_primary_btn.disabled = true
		_style_btn(_inspector_primary_btn, false)
	elif squad_full:
		_inspector_primary_btn.text = "Squad Full"
		_inspector_primary_btn.disabled = true
		_style_btn(_inspector_primary_btn, false)
	else:
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
	var left_panel := get_node_or_null("Root/Left") as PanelContainer
	var right_panel := get_node_or_null("Root/Right") as PanelContainer
	if left_panel:
		left_panel.add_theme_stylebox_override("panel", _sb_panel())
	if right_panel:
		right_panel.add_theme_stylebox_override("panel", _sb_panel())

	# Scroll containers: strip scrollbar chrome but give content a readable dark inset
	var col_sc := get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/CollectionScroll") as ScrollContainer
	_strip_scroll_frames(col_sc)
	if col_sc:
		col_sc.add_theme_stylebox_override("panel", _sb_inset())
	var ros_sc := get_node_or_null("Root/Right/RightPad/RightVBox/SquadCard/Pad/SquadVBox/RosterScroll") as ScrollContainer
	_strip_scroll_frames(ros_sc)
	if ros_sc:
		ros_sc.add_theme_stylebox_override("panel", _sb_inset())

	# InspectorCard: dark like the rest (no light wood panel)
	if _inspector_card:
		_inspector_card.add_theme_stylebox_override("panel", _sb_card(false))

	# Right cards: flat readable
	var squad_card := get_node_or_null("Root/Right/RightPad/RightVBox/SquadCard") as PanelContainer
	if squad_card:
		squad_card.add_theme_stylebox_override("panel", _sb_card_flat())
	var run_card := get_node_or_null("Root/Right/RightPad/RightVBox/RunCard") as PanelContainer
	if run_card:
		run_card.add_theme_stylebox_override("panel", _sb_card_flat())

	# Titles: gold accent on dark
	var title_lbl := get_node_or_null("Root/Left/LeftPad/LeftVBox/Title") as Label
	if title_lbl:
		title_lbl.add_theme_font_size_override("font_size", 28)
		title_lbl.add_theme_color_override("font_color", TITLE_GOLD)
		title_lbl.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04, 1.0))
		title_lbl.add_theme_constant_override("outline_size", 4)
	var squad_title := get_node_or_null("Root/Right/RightPad/RightVBox/SquadCard/Pad/SquadVBox/HeaderRow/SquadTitle") as Label
	if squad_title:
		squad_title.add_theme_font_size_override("font_size", 18)
		squad_title.add_theme_color_override("font_color", TITLE_GOLD)
		squad_title.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04, 1.0))
		squad_title.add_theme_constant_override("outline_size", 2)

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

	# Inspector labels: light text
	if _inspector_name:
		_inspector_name.add_theme_color_override("font_color", TEXT_LIGHT)
	if _inspector_stats:
		_inspector_stats.add_theme_color_override("font_color", TEXT_SOFT)
	if _inspector_passives:
		_inspector_passives.add_theme_color_override("font_color", TEXT_SOFT)
	if _inspector_synergies_title:
		_inspector_synergies_title.add_theme_color_override("font_color", TEXT_LIGHT)
	var map_lbl := get_node_or_null("Root/Right/RightPad/RightVBox/RunCard/Pad/RunVBox/MapLabel") as Label
	if map_lbl:
		map_lbl.add_theme_color_override("font_color", TEXT_LIGHT)
	var inspector_title := get_node_or_null("Root/Left/LeftPad/LeftVBox/MainRow/InspectorCard/InspectorPad/InspectorVBox/InspectorTitle") as Label
	if inspector_title:
		inspector_title.add_theme_color_override("font_color", TEXT_SOFT)

func _on_start_run() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _show_details(data: Dictionary) -> void:
	# Polished details modal (portrait + stat chips + styled passive list).
	if has_node("DetailsModal"):
		get_node("DetailsModal").queue_free()
	var layer := CanvasLayer.new()
	layer.name = "DetailsModal"
	layer.layer = 170
	add_child(layer)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.72)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -420
	panel.offset_top = -260
	panel.offset_right = 420
	panel.offset_bottom = 260
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(panel)

	var rarity := String(data.get("rarity_id", "common"))
	panel.add_theme_stylebox_override("panel", UiSkin.panel_style(UnitFactory.rarity_color(rarity), true))
	var neon := ShaderMaterial.new()
	neon.shader = preload("res://shaders/ui_neon_frame.gdshader")
	neon.set_shader_parameter("base_color", Color(0.08, 0.09, 0.11, 0.96))
	neon.set_shader_parameter("glow_color", UnitFactory.rarity_color(rarity))
	neon.set_shader_parameter("glow_width", 0.022)
	neon.set_shader_parameter("pulse_speed", 1.1)
	panel.material = neon

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)

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

	var portrait := _make_detail_portrait(data)
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
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", UnitFactory.rarity_color(rarity))
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

	var close := Button.new()
	close.text = "Close"
	UiSkin.style_secondary_button(close)
	close.pressed.connect(func(): layer.queue_free())
	v.add_child(close)

func _make_detail_portrait(data: Dictionary) -> Control:
	# Larger portrait for details modal.
	var rarity := String(data.get("rarity_id", "common"))
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(110, 110)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UiSkin.card_style(UnitFactory.rarity_color(rarity), false))

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	frame.add_child(pad)

	var sprite_path := String(data.get("sprite_path", ""))
	var frames := PixellabUtil.walk_frames_from_south_path(sprite_path)
	if frames != null and frames.has_animation("walk_south") and frames.get_frame_count("walk_south") > 0:
		var svc := SubViewportContainer.new()
		svc.custom_minimum_size = Vector2(96, 96)
		svc.stretch = true
		svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(svc)

		var vp := SubViewport.new()
		vp.size = Vector2i(96, 96)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		svc.add_child(vp)

		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames
		spr.animation = "walk_south"
		spr.centered = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Framing: keep head visible while reducing overall zoom.
		spr.position = Vector2(48, 60)
		var scale3 := PixellabUtil.scale_for_target_height(frames, 64.0, 0.45, 0.85)
		spr.scale = Vector2.ONE * scale3
		spr.play()
		vp.add_child(spr)
		return frame

	# Static fallback
	var tex := PixellabUtil.load_rotation_texture(sprite_path)
	if tex == null:
		var pid := String(data.get("pixellab_id", ""))
		if pid != "":
			tex = PixellabUtil.load_rotation_texture("res://assets/pixellab/%s/rotations/south.png" % pid)
	if tex != null:
		var svc2 := SubViewportContainer.new()
		svc2.custom_minimum_size = Vector2(96, 96)
		svc2.stretch = true
		svc2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(svc2)

		var vp2 := SubViewport.new()
		vp2.size = Vector2i(96, 96)
		vp2.transparent_bg = true
		vp2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp2.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		svc2.add_child(vp2)

		var spr2 := Sprite2D.new()
		spr2.texture = tex
		spr2.centered = true
		spr2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr2.position = Vector2(48, 64)
		var ts := tex.get_size()
		var max_dim := maxf(1.0, maxf(ts.x, ts.y))
		var scale := (86.0 / max_dim)
		spr2.scale = Vector2.ONE * scale
		vp2.add_child(spr2)
	return frame

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

	var b: TooltipButton = TooltipButton.new()
	b.text = txt
	b.tooltip_text = SynergySystem.synergy_tooltip_bbcode(state)
	b.tooltip_accent = (Color(0.65, 0.85, 1.0, 1.0) if tier_n > 0 else Color(0.75, 0.80, 0.86, 1.0))
	b.mouse_default_cursor_shape = Control.CURSOR_HELP
	b.add_theme_font_size_override("font_size", 10)
	b.custom_minimum_size = Vector2(0, 22)

	# Styling: compact "pill" chip with subtle glow when active.
	var active: bool = tier_n > 0
	var accent: Color = (Color(0.65, 0.85, 1.0, 1.0) if active else Color(0.75, 0.80, 0.86, 1.0))
	var sb: StyleBoxFlat = UiSkin.chip_style(accent)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	if active:
		sb.shadow_size = 6
		sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.12)
	b.add_theme_stylebox_override("normal", sb)
	var hov: StyleBoxFlat = (sb.duplicate() as StyleBoxFlat)
	hov.bg_color = Color(sb.bg_color.r, sb.bg_color.g, sb.bg_color.b, minf(1.0, sb.bg_color.a + 0.10))
	hov.border_color = Color(sb.border_color.r, sb.border_color.g, sb.border_color.b, minf(1.0, sb.border_color.a + 0.18))
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("focus", hov)
	b.add_theme_stylebox_override("pressed", hov)

	# Chips are informational (no action), but keep enabled so tooltip always works.
	b.pressed.connect(func(): pass)
	return b

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
