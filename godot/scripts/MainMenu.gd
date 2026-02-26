extends Control

@onready var bg_art: TextureRect = get_node_or_null("BgArt") as TextureRect
@onready var frame_art: TextureRect = get_node_or_null("FrameArt") as TextureRect
@onready var backdrop: CanvasItem = get_node_or_null("Backdrop") as CanvasItem
@onready var backdrop_shader: CanvasItem = get_node_or_null("BackdropShader") as CanvasItem
@onready var frame_shader: CanvasItem = get_node_or_null("FrameShader") as CanvasItem

@onready var resume_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Resume") as Button
@onready var play_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Play") as Button
@onready var armory_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Armory") as Button
@onready var protocol_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Protocol") as Button
@onready var settings_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Settings") as Button
@onready var quit_btn: Button = get_node_or_null("Root/Card/Pad/VBox/Quit") as Button

@onready var card: Control = get_node_or_null("Root/Card") as Control
@onready var title_lbl: Label = get_node_or_null("Root/Card/Pad/VBox/TitleStack/Title") as Label
@onready var title_glow_lbl: Label = get_node_or_null("Root/Card/Pad/VBox/TitleStack/Glow") as Label
@onready var title_bevel_lbl: Label = get_node_or_null("Root/Card/Pad/VBox/TitleStack/Bevel") as Label
@onready var subtitle_lbl: Label = get_node_or_null("Root/Card/Pad/VBox/Subtitle") as Label

@onready var map_overlay: Control = get_node_or_null("MapOverlay") as Control
@onready var map_list: ItemList = get_node_or_null("MapOverlay/Panel/Pad/VBox/HBox/LeftPanel/MapList") as ItemList
@onready var map_preview_vp: SubViewport = get_node_or_null("MapOverlay/Panel/Pad/VBox/HBox/RightPanel/MapPreviewFrame/Pad/Preview/VP") as SubViewport
@onready var map_tagline: Label = get_node_or_null("MapOverlay/Panel/Pad/VBox/HBox/RightPanel/MapTagline") as Label
@onready var map_details: RichTextLabel = get_node_or_null("MapOverlay/Panel/Pad/VBox/HBox/RightPanel/MapDetails") as RichTextLabel
@onready var map_back_btn: Button = get_node_or_null("MapOverlay/Panel/Pad/VBox/Buttons/Back") as Button
@onready var map_start_btn: Button = get_node_or_null("MapOverlay/Panel/Pad/VBox/Buttons/Start") as Button

var _map_ids: Array[String] = []
var _crowd: Node2D = null
var _preview_root: Node = null
var _selected_map_locked: bool = false

@export var game_title: String = "Squad Protocol"
@export var game_tagline: String = "Draft a squad. Survive the swarm."
@export var show_footer: bool = true
@export var footer_text: String = "v4.2 • Draft a squad • Survive the swarm"

@export var use_menu_art: bool = true
@export var bg_art_path: String = "res://assets/ui/mockups/main_menu.webp"
@export var frame_art_path: String = ""
@export var use_crowd_when_menu_art: bool = true

# Optional font overrides (drop .ttf into res://assets/ui/fonts/ and point these at it)
@export var title_font_path: String = "res://assets/ui/fonts/Orbitron-VariableFont_wght.ttf"
@export var subtitle_font_path: String = "res://assets/ui/fonts/Orbitron-VariableFont_wght.ttf"

const PROTOCOL_BG_PATH: String = "res://assets/ui/mockups/protocol_grid.webp"
const INTRO_BG_PATH: String = "res://assets/ui/mockups/intro.webp"

func _ready() -> void:
	UiSkin.apply_global_font(title_font_path, 14)
	_apply_menu_art()
	_play_intro_splash()

	# Menu music
	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm) and mm.has_method("play"):
		mm.play("menu", 1.0)

	_spawn_menu_crowd()
	_polish_menu_ui()

	if play_btn:
		play_btn.pressed.connect(func():
			_play_ui("ui.confirm")
			_open_map_overlay()
		)

	_setup_map_select_overlay()

	# Resume run (if available)
	var sv := get_node_or_null("/root/SaveManager")
	var has := false
	if sv and is_instance_valid(sv) and sv.has_method("has_saved_run"):
		has = bool(sv.has_saved_run())
	if resume_btn:
		resume_btn.visible = has
		if has:
			resume_btn.pressed.connect(func():
				_play_ui("ui.resume_load")
				if sv and is_instance_valid(sv) and sv.has_method("request_resume"):
					if bool(sv.request_resume()):
						get_tree().change_scene_to_file("res://scenes/Main.tscn")
			)

	if armory_btn:
		armory_btn.pressed.connect(func():
			_play_ui("ui.click")
			get_tree().change_scene_to_file("res://scenes/Menu.tscn")
		)

	if protocol_btn:
		protocol_btn.pressed.connect(func():
			_play_ui("ui.click")
			_open_protocol_grid()
		)
	else:
		# Create button dynamically if not in scene
		_create_protocol_button()

	if settings_btn:
		settings_btn.pressed.connect(func():
			_play_ui("ui.click")
			_open_settings()
		)

	if quit_btn:
		quit_btn.pressed.connect(func():
			_play_ui("ui.cancel")
			get_tree().quit()
		)

func _setup_map_select_overlay() -> void:
	if map_list == null:
		return
	var rc := get_node_or_null("/root/RunConfig")
	if rc == null or not is_instance_valid(rc):
		return
	if rc.has_method("ensure_loaded"):
		rc.ensure_loaded()

	# Style the map list
	_style_map_list()

	map_list.clear()
	_map_ids.clear()
	if rc.has_method("get_map_ids_ordered"):
		_map_ids = rc.get_map_ids_ordered()
	elif rc.has_method("get_map_ids"):
		_map_ids = rc.get_map_ids()
	for i in range(_map_ids.size()):
		var m: Dictionary = rc.get_map(_map_ids[i]) if rc.has_method("get_map") else {}
		var name := String(m.get("name", _map_ids[i]))
		var mult := float(m.get("meta_sigils_mult", 1.0))
		# Simpler list entry - details shown in right panel
		var tier := "★" if mult < 1.2 else ("★★" if mult < 1.5 else "★★★")
		var locked := not _is_map_unlocked(_map_ids[i])
		var label := ("🔒 " + name) if locked else name
		map_list.add_item("%s  %s" % [label, tier])
		map_list.set_item_disabled(i, locked)
		if locked:
			map_list.set_item_tooltip(i, "Locked. Win the previous map to unlock.")

	# Select current
	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	for i in range(_map_ids.size()):
		if _map_ids[i] == cur:
			map_list.select(i)
			break

	_update_map_tagline(rc)
	_update_map_preview(rc)
	_update_map_lock_state(rc)

	map_list.item_selected.connect(func(idx: int):
		if idx < 0 or idx >= _map_ids.size():
			return
		if map_list.is_item_disabled(idx):
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

	if map_back_btn:
		map_back_btn.pressed.connect(func():
			_play_ui("ui.cancel")
			_close_map_overlay()
		)
	if map_start_btn:
		map_start_btn.pressed.connect(func():
			_play_ui("ui.confirm")
			_start_run_with_selected_map()
		)

func _update_map_tagline(rc: Node) -> void:
	if map_tagline == null:
		return
	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	var m: Dictionary = rc.get_map(cur) if rc.has_method("get_map") else {}
	var t := String(m.get("tagline", ""))
	var mult := float(m.get("meta_sigils_mult", 1.0))
	if t == "":
		map_tagline.text = ""
	else:
		map_tagline.text = "%s\nSigils multiplier: x%.2f" % [t, mult]
	_update_map_details(m)
	_update_map_lock_state(rc)

func _update_map_lock_state(rc: Node) -> void:
	if rc == null:
		return
	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	_selected_map_locked = not _is_map_unlocked(cur)
	if map_start_btn:
		map_start_btn.disabled = _selected_map_locked
		if _selected_map_locked:
			map_start_btn.text = "Locked"
		else:
			map_start_btn.text = "Start"

func _danger_score(m: Dictionary) -> float:
	# Calculate difficulty 1-10 based on map multipliers
	# 1.0 = baseline (5), <1.0 = easier, >1.0 = harder
	var hp: float = float(m.get("enemy_hp_mult", 1.0))
	var dmg: float = float(m.get("enemy_damage_mult", 1.0))
	var spd: float = float(m.get("enemy_speed_mult", 1.0))
	var maxe: float = float(m.get("max_enemies_mult", 1.0))
	var si: float = float(m.get("spawn_interval_mult", 1.0))  # Higher = slower spawns = easier
	
	# Convert to deviation from 1.0 (baseline)
	# Graveyard: hp=0.95, dmg=0.85 → negative deviation → lower difficulty
	# Foundry: hp=2.10, dmg=1.55 → positive deviation → higher difficulty
	var hp_dev: float = (hp - 1.0) * 2.5
	var dmg_dev: float = (dmg - 1.0) * 3.0
	var spd_dev: float = (spd - 1.0) * 1.5
	var maxe_dev: float = (maxe - 1.0) * 2.0
	var si_dev: float = (1.0 - si) * 2.0  # Inverted: lower interval = harder
	
	# Base score of 5, modified by deviations
	var s: float = 5.0 + hp_dev + dmg_dev + spd_dev + maxe_dev + si_dev
	return clampf(s, 1.0, 10.0)

func _tier_color(score: float) -> String:
	if score < 3.5:
		return "#79ffd2" # chill
	if score < 6.5:
		return "#ffd86b" # spicy
	return "#ff6a55" # brutal

func _bar(score: float) -> String:
	var n := int(round(score))
	n = clampi(n, 0, 10)
	var s := ""
	for i in range(10):
		s += "■" if i < n else "·"
	return s

func _update_map_details(m: Dictionary) -> void:
	if map_details == null:
		return
	var score := _danger_score(m)
	var col := _tier_color(score)
	var sig := float(m.get("meta_sigils_mult", 1.0))
	var ess := float(m.get("essence_mult", 1.0))
	var boss := bool(m.get("boss_enabled", true))
	var boss_m := float(m.get("boss_spawn_minutes", 18.0))

	# More visually appealing details
	var diff_bar := "[color=%s]%s[/color]" % [col, _bar(score)]
	var diff_line := "[color=#8090a0]Danger:[/color] %s [color=%s]%.1f[/color]" % [diff_bar, col, score]
	var reward_line := "[color=#8090a0]Rewards:[/color] [color=#ffd070]★ x%.2f[/color]  [color=#70d0ff]◆ x%.2f[/color]" % [sig, ess]
	var boss_text := "[color=#ff7070]Yes @ %.0fm[/color]" % boss_m if boss else "[color=#70ff70]No[/color]"
	var boss_line := "[color=#8090a0]Boss:[/color] %s" % boss_text
	map_details.text = "%s\n%s\n%s" % [diff_line, reward_line, boss_line]

func _style_map_list() -> void:
	if map_list == null:
		return
	# Style the ItemList for better visibility
	map_list.add_theme_font_size_override("font_size", 15)
	map_list.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 1.0))
	map_list.add_theme_color_override("font_selected_color", Color(1.0, 1.0, 1.0, 1.0))
	map_list.add_theme_color_override("font_hovered_color", Color(0.9, 0.95, 1.0, 1.0))
	
	# Selection style
	var selected_sb := StyleBoxFlat.new()
	selected_sb.bg_color = Color(0.3, 0.5, 0.8, 0.4)
	selected_sb.corner_radius_top_left = 6
	selected_sb.corner_radius_top_right = 6
	selected_sb.corner_radius_bottom_left = 6
	selected_sb.corner_radius_bottom_right = 6
	selected_sb.border_width_left = 2
	selected_sb.border_width_right = 2
	selected_sb.border_width_top = 2
	selected_sb.border_width_bottom = 2
	selected_sb.border_color = Color(0.4, 0.7, 1.0, 0.8)
	map_list.add_theme_stylebox_override("selected", selected_sb)
	map_list.add_theme_stylebox_override("selected_focus", selected_sb)
	
	# Hover style
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(0.25, 0.4, 0.6, 0.25)
	hover_sb.corner_radius_top_left = 6
	hover_sb.corner_radius_top_right = 6
	hover_sb.corner_radius_bottom_left = 6
	hover_sb.corner_radius_bottom_right = 6
	map_list.add_theme_stylebox_override("hovered", hover_sb)

func _hash32(s: String) -> int:
	# Simple stable hash for deterministic previews.
	var h: int = 2166136261
	for i in range(s.length()):
		h = int((h ^ s.unicode_at(i)) * 16777619) & 0x7fffffff
	return h

func _update_map_preview(rc: Node) -> void:
	if map_preview_vp == null:
		return
	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	var m: Dictionary = rc.get_map(cur) if rc.has_method("get_map") else {}
	var vis: Dictionary = {}
	# Explicit type to avoid Variant inference warnings (warnings treated as errors).
	var vv: Variant = m.get("visuals", {})
	if typeof(vv) == TYPE_DICTIONARY:
		vis = vv as Dictionary

	# Rebuild preview scene (small + dense so it reads at a glance).
	if _preview_root != null and is_instance_valid(_preview_root):
		_preview_root.queue_free()
		_preview_root = null
	for c in map_preview_vp.get_children():
		(c as Node).queue_free()

	# Ensure the SubViewport renders correctly.
	map_preview_vp.transparent_bg = false
	map_preview_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	map_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Force a good size for the preview (matches new layout)
	map_preview_vp.size = Vector2i(560, 280)

	var root := Node2D.new()
	root.name = "PreviewRoot"
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	map_preview_vp.add_child(root)
	_preview_root = root

	# Add a Camera2D so the MapRenderer has something to follow
	var cam := Camera2D.new()
	cam.name = "PreviewCam"
	cam.position = Vector2.ZERO
	cam.zoom = Vector2(0.45, 0.45)  # Zoomed out to show more of the map
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	cam.enabled = true
	root.add_child(cam)
	cam.make_current()

	# Determine biome from map config
	var biome := cur
	if vis.has("theme_id"):
		biome = String(vis.get("theme_id"))
	
	# Use TileMapWorld for real tile-based maps
	var tmw := Node2D.new()
	tmw.set_script(preload("res://scripts/TileMapWorld.gd"))
	tmw.name = "TileMapWorld"
	tmw.process_mode = Node.PROCESS_MODE_ALWAYS
	tmw.set("map_size", Vector2(2400, 1800))
	tmw.set("biome", biome)
	tmw.set("seed_value", _hash32(cur))
	tmw.set("prop_count", 32)
	tmw.set("prop_min_dist_from_center", 60.0)

	# Add AFTER configuration so _ready() sees the right params on first run.
	root.add_child(tmw)

func _open_map_overlay() -> void:
	if map_overlay == null:
		# Fallback: if overlay is missing, still start the run.
		_start_run_with_selected_map()
		return
	map_overlay.visible = true
	if map_list:
		map_list.grab_focus()
	elif map_start_btn:
		map_start_btn.grab_focus()

func _close_map_overlay() -> void:
	if map_overlay == null:
		return
	map_overlay.visible = false
	if play_btn:
		play_btn.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE and map_overlay and map_overlay.visible:
			_close_map_overlay()
			get_viewport().set_input_as_handled()

func _start_run_with_selected_map() -> void:
	# RunConfig already holds selected_map_id; Main.gd reads it on _ready.
	if _selected_map_locked:
		_play_ui("ui.error")
		return
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _is_map_unlocked(map_id: String) -> bool:
	if map_id == "" or map_id == "graveyard":
		return true
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp):
		return map_id == "graveyard"
	if mp.has_method("is_map_unlocked"):
		return bool(mp.is_map_unlocked(map_id))
	return map_id == "graveyard"

func _play_ui(id: String) -> void:
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui(id)

func _open_settings() -> void:
	if has_node("SettingsMenu"):
		return
	var sm := preload("res://scripts/SettingsMenu.gd").new()
	sm.name = "SettingsMenu"
	add_child(sm)

func _spawn_menu_crowd() -> void:
	# Fill empty space with a fun wandering crowd behind the UI.
	# If menu art is active AND it loaded successfully, we optionally disable the crowd.
	if use_menu_art and bool(get_meta("_menu_art_loaded", false)) and not use_crowd_when_menu_art:
		return
	if _crowd != null and is_instance_valid(_crowd):
		return

	# Push backdrops behind everything so the crowd is visible but UI stays on top.
	var bd := get_node_or_null("Backdrop") as CanvasItem
	if bd:
		bd.z_index = -100
	var bds := get_node_or_null("BackdropShader") as CanvasItem
	if bds:
		bds.z_index = -90

	var c := preload("res://scripts/MainMenuCrowd.gd").new()
	c.name = "MenuCrowd"
	add_child(c)
	# Ensure it's drawn above backdrop but below Root/Card (which stays at z_index 0 by default).
	if c is CanvasItem:
		(c as CanvasItem).z_index = -50
	_crowd = c
	# Keep it behind Root in draw order.
	if has_node("Root"):
		move_child(_crowd, get_node("Root").get_index())

func _apply_menu_art() -> void:
	# If the user dropped the provided images into res://assets/ui/,
	# we can match the reference menu "exactly" using those textures.
	if not use_menu_art:
		set_meta("_menu_art_loaded", false)
		return

	# Default to procedural look unless BOTH textures load.
	var bg_ok := false
	var frame_ok := false

	# Ensure art layers start hidden; we'll enable them if files exist.
	if bg_art:
		bg_art.visible = false
	if frame_art:
		frame_art.visible = false

	# Background
	if bg_art != null and ResourceLoader.exists(bg_art_path):
		bg_art.texture = load(bg_art_path) as Texture2D
		bg_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_art.visible = true
		bg_ok = (bg_art.texture != null)

	# Frame overlay
	if frame_art != null and ResourceLoader.exists(frame_art_path):
		frame_art.texture = load(frame_art_path) as Texture2D
		frame_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# Godot 4 TextureRect has KEEP_ASPECT / KEEP_ASPECT_CENTERED / KEEP_ASPECT_COVERED.
		# We want "fit inside + centered" for the frame overlay.
		frame_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame_art.visible = true
		frame_ok = (frame_art.texture != null)

	# Use background art even if we don't have a matching frame overlay yet.
	var loaded := bg_ok
	set_meta("_menu_art_loaded", loaded)

	# Only hide procedural layers when the authored art is actually present.
	# This prevents "gray background + empty screen" if the files aren't in the project yet.
	if backdrop: backdrop.visible = not loaded
	if backdrop_shader: backdrop_shader.visible = not loaded
	if frame_shader: frame_shader.visible = not loaded

func _play_intro_splash() -> void:
	if not ResourceLoader.exists(INTRO_BG_PATH):
		return
	var splash := TextureRect.new()
	splash.name = "IntroSplash"
	splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash.texture = load(INTRO_BG_PATH) as Texture2D
	splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	splash.modulate = Color(1, 1, 1, 1)
	add_child(splash)
	move_child(splash, get_child_count() - 1)

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(splash, "modulate", Color(1, 1, 1, 0), 0.45)
	tw.tween_callback(splash.queue_free)

func _polish_menu_ui() -> void:
	# Title/subtitle (lets us rename without touching the scene file).
	_apply_title_fx()
	if title_lbl:
		title_lbl.text = game_title.to_upper()
	if subtitle_lbl:
		subtitle_lbl.text = game_tagline
		subtitle_lbl.add_theme_font_size_override("font_size", 18)
		subtitle_lbl.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0, 0.92))
		# Slight outline + shadow so it feels "printed" like the reference.
		subtitle_lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 0.80))
		subtitle_lbl.add_theme_constant_override("outline_size", 3)
		subtitle_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.45))
		subtitle_lbl.add_theme_constant_override("shadow_offset_x", 0)
		subtitle_lbl.add_theme_constant_override("shadow_offset_y", 3)

	# Card entrance: subtle slide + fade for “premium” feel.
	if card:
		card.modulate = Color(1, 1, 1, 0)
		var base := card.position
		card.position = base + Vector2(0, 18)
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "position", base, 0.22)
		tw.parallel().tween_property(card, "modulate", Color(1, 1, 1, 1), 0.22)

	# Buttons: consistent “fun” style, with a stronger primary (Start/Resume).
	var primary := UiSkin.ACCENT
	var secondary := Color(1, 1, 1, 0.12)
	_style_button(play_btn, true, primary, secondary)
	_style_button(resume_btn, true, primary, secondary)
	_style_button(armory_btn, false, primary, secondary)
	_style_button(protocol_btn, false, UiSkin.ACCENT_PURPLE, Color(0.55, 0.35, 0.8, 0.18))  # Purple accent
	_style_button(settings_btn, false, primary, secondary)
	_style_button(quit_btn, false, primary, secondary)

	# Footer line (small, helps communicate the loop).
	if show_footer and card and card.has_node("Pad/VBox"):
		var vb := card.get_node("Pad/VBox") as VBoxContainer
		if vb and vb.get_node_or_null("Footer") == null:
			vb.add_spacer(true)
			var ft := Label.new()
			ft.name = "Footer"
			ft.text = footer_text
			ft.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ft.add_theme_font_size_override("font_size", 12)
			ft.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 0.65))
			vb.add_child(ft)

func _style_button(btn: Button, is_primary: bool, primary: Color, secondary: Color) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal := StyleBoxFlat.new()
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.corner_radius_bottom_right = 12
	normal.bg_color = Color(primary.r, primary.g, primary.b, 0.16) if is_primary else Color(0.08, 0.09, 0.11, 0.70)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(primary.r, primary.g, primary.b, 0.55) if is_primary else secondary

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(primary.r, primary.g, primary.b, 0.22) if is_primary else Color(0.10, 0.11, 0.13, 0.78)
	hover.border_color = Color(primary.r, primary.g, primary.b, 0.85)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(primary.r, primary.g, primary.b, 0.28) if is_primary else Color(0.12, 0.13, 0.16, 0.85)
	pressed.border_color = Color(primary.r, primary.g, primary.b, 0.95)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))

func _apply_title_fx() -> void:
	# The "cool" look on the reference comes mostly from:
	# - a sci-fi font (not in repo yet)
	# - layered glow + bevel + crisp outline
	#
	# We implement the layering now so dropping a font later becomes instant.
	var text := game_title.to_upper()
	var title_font := _load_font_or_null(title_font_path)
	var subtitle_font := _load_font_or_null(subtitle_font_path)

	if title_lbl:
		title_lbl.text = text
		title_lbl.add_theme_font_size_override("font_size", 56)
		title_lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
		title_lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 0.95))
		title_lbl.add_theme_constant_override("outline_size", 4)
		title_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.45))
		title_lbl.add_theme_constant_override("shadow_offset_x", 0)
		title_lbl.add_theme_constant_override("shadow_offset_y", 6)
		_apply_font_override(title_lbl, title_font)

	if title_bevel_lbl:
		title_bevel_lbl.text = text
		title_bevel_lbl.add_theme_font_size_override("font_size", 56)
		# Dark inner stroke to simulate bevel/engrave.
		title_bevel_lbl.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0, 0.25))
		title_bevel_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.95))
		title_bevel_lbl.add_theme_constant_override("outline_size", 9)
		title_bevel_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
		_apply_font_override(title_bevel_lbl, title_font)

	if title_glow_lbl:
		title_glow_lbl.text = text
		title_glow_lbl.add_theme_font_size_override("font_size", 56)
		# Cyan outer glow ring.
		title_glow_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0, 0.16))
		title_glow_lbl.add_theme_color_override("font_outline_color", Color(0.35, 0.85, 1.0, 0.75))
		title_glow_lbl.add_theme_constant_override("outline_size", 16)
		title_glow_lbl.add_theme_color_override("font_shadow_color", Color(0.25, 0.70, 1.0, 0.16))
		title_glow_lbl.add_theme_constant_override("shadow_offset_x", 0)
		title_glow_lbl.add_theme_constant_override("shadow_offset_y", 0)
		_apply_font_override(title_glow_lbl, title_font)

	# Apply subtitle font if provided (keeps the "poster" vibe)
	if subtitle_lbl:
		_apply_font_override(subtitle_lbl, subtitle_font)

func _load_font_or_null(path: String) -> Font:
	if path == null or path == "":
		return null
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res is Font:
		return res as Font
	return null

func _apply_font_override(lbl: Label, f: Font) -> void:
	if lbl == null or f == null:
		return
	lbl.add_theme_font_override("font", f)

# ─────────────────────────────────────────────────────────────────────────────
# PROTOCOL GRID - Meta Progression System
# ─────────────────────────────────────────────────────────────────────────────

var _protocol_overlay: Control = null
var _protocol_nodes: Array[Dictionary] = []

const PROTOCOL_UPGRADES := [
	# Tier 1: Very cheap - buy after first run even if you die (~50-75 sigils)
	{"id": "hp_boost_1", "name": "Vitality I", "desc": "+10% Squad HP", "cost": 50, "icon": "♥", "row": 0, "col": 1, "color": "#ff6060", "prereq": []},
	{"id": "dmg_boost_1", "name": "Power I", "desc": "+8% Squad Damage", "cost": 60, "icon": "⚔", "row": 0, "col": 3, "color": "#ffa040", "prereq": []},
	{"id": "speed_1", "name": "Agility I", "desc": "+5% Move Speed", "cost": 40, "icon": "»", "row": 0, "col": 2, "color": "#60ff90", "prereq": []},
	
	# Tier 2: Affordable - 1-2 decent runs (~150-250 sigils)
	{"id": "hp_boost_2", "name": "Vitality II", "desc": "+15% Squad HP", "cost": 180, "icon": "♥♥", "row": 1, "col": 0, "color": "#ff4040", "prereq": ["hp_boost_1"]},
	{"id": "dmg_boost_2", "name": "Power II", "desc": "+12% Squad Damage", "cost": 200, "icon": "⚔⚔", "row": 1, "col": 4, "color": "#ff8020", "prereq": ["dmg_boost_1"]},
	{"id": "speed_2", "name": "Agility II", "desc": "+8% Move Speed", "cost": 150, "icon": "»»", "row": 1, "col": 2, "color": "#40ff70", "prereq": ["speed_1"]},
	{"id": "crit_1", "name": "Precision I", "desc": "+3% Crit Chance", "cost": 120, "icon": "✧", "row": 1, "col": 1, "color": "#ffff60", "prereq": ["hp_boost_1"]},
	{"id": "essence_1", "name": "Harvest I", "desc": "+10% Essence Gain", "cost": 100, "icon": "◆", "row": 1, "col": 3, "color": "#60d0ff", "prereq": ["dmg_boost_1"]},
	
	# Tier 3: Requires victories (~350-500 sigils)
	{"id": "hp_boost_3", "name": "Vitality III", "desc": "+20% Squad HP", "cost": 450, "icon": "♥♥♥", "row": 2, "col": 0, "color": "#ff2020", "prereq": ["hp_boost_2"]},
	{"id": "dmg_boost_3", "name": "Power III", "desc": "+18% Squad Damage", "cost": 500, "icon": "⚔⚔⚔", "row": 2, "col": 4, "color": "#ff6000", "prereq": ["dmg_boost_2"]},
	{"id": "crit_2", "name": "Precision II", "desc": "+5% Crit Chance", "cost": 350, "icon": "✧✧", "row": 2, "col": 1, "color": "#ffff40", "prereq": ["crit_1"]},
	{"id": "essence_2", "name": "Harvest II", "desc": "+15% Essence Gain", "cost": 300, "icon": "◆◆", "row": 2, "col": 3, "color": "#40b0ff", "prereq": ["essence_1"]},
	{"id": "draft_luck", "name": "Fortune", "desc": "+Higher Rarity Drafts", "cost": 400, "icon": "★", "row": 2, "col": 2, "color": "#c080ff", "prereq": ["speed_2"]},
	
	# Capstone: Major goal (~800 sigils = ~2 victories)
	{"id": "starting_unit", "name": "Reinforcement", "desc": "+1 Starting Squad", "cost": 800, "icon": "☗", "row": 3, "col": 2, "color": "#ff80c0", "prereq": ["draft_luck", "crit_2", "essence_2"]},
]

func _create_protocol_button() -> void:
	if card == null or not card.has_node("Pad/VBox"):
		return
	var vbox := card.get_node("Pad/VBox") as VBoxContainer
	if vbox == null:
		return
	
	# Find position after Armory
	var insert_idx := -1
	for i in range(vbox.get_child_count()):
		var child := vbox.get_child(i)
		if child.name == "Armory":
			insert_idx = i + 1
			break
	
	if insert_idx == -1:
		return
	
	# Create button
	protocol_btn = Button.new()
	protocol_btn.name = "Protocol"
	protocol_btn.text = "PROTOCOL GRID"
	protocol_btn.custom_minimum_size = Vector2(240, 48)
	vbox.add_child(protocol_btn)
	vbox.move_child(protocol_btn, insert_idx)
	
	protocol_btn.pressed.connect(func():
		_play_ui("ui.click")
		_open_protocol_grid()
	)
	
	# Style it with purple accent
	_style_button(protocol_btn, false, Color(0.8, 0.5, 1.0, 0.25), Color(0.6, 0.3, 0.9, 0.15))

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

	# Background art for the protocol grid screen.
	if ResourceLoader.exists(PROTOCOL_BG_PATH):
		var art := TextureRect.new()
		art.name = "ProtocolBgArt"
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.texture = load(PROTOCOL_BG_PATH) as Texture2D
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(1, 1, 1, 0.95)
		_protocol_overlay.add_child(art)
	
	# Dark backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.02, 0.06, 0.92)
	_protocol_overlay.add_child(bg)
	
	# Main panel
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(900, 650)
	panel.position = Vector2(-450, -325)
	
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.06, 0.07, 0.12, 0.98)
	panel_sb.corner_radius_top_left = 16
	panel_sb.corner_radius_top_right = 16
	panel_sb.corner_radius_bottom_left = 16
	panel_sb.corner_radius_bottom_right = 16
	panel_sb.border_width_left = 3
	panel_sb.border_width_right = 3
	panel_sb.border_width_top = 3
	panel_sb.border_width_bottom = 3
	panel_sb.border_color = Color(0.6, 0.4, 0.9, 0.6)
	panel_sb.shadow_color = Color(0.5, 0.3, 0.8, 0.3)
	panel_sb.shadow_size = 12
	panel.add_theme_stylebox_override("panel", panel_sb)
	_protocol_overlay.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	
	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	vbox.add_child(header)
	
	var title := Label.new()
	title.name = "Title"
	title.text = "⬡ PROTOCOL GRID ⬡"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	
	var sigils_lbl := Label.new()
	sigils_lbl.name = "SigilsLabel"
	sigils_lbl.text = "★ 0"
	sigils_lbl.add_theme_font_size_override("font_size", 26)
	sigils_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	header.add_child(sigils_lbl)
	
	# Subtitle
	var sub := Label.new()
	sub.text = "Permanent upgrades that persist across all runs"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.8))
	vbox.add_child(sub)
	
	# Grid container for nodes
	var grid_wrap := Control.new()
	grid_wrap.name = "GridWrap"
	grid_wrap.custom_minimum_size = Vector2(850, 420)
	grid_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid_wrap)
	
	# Create upgrade nodes
	_protocol_nodes.clear()
	for upgrade in PROTOCOL_UPGRADES:
		var node := _create_protocol_node(upgrade)
		grid_wrap.add_child(node["panel"])
		_protocol_nodes.append(node)
	
	# Draw connection lines
	_draw_protocol_lines(grid_wrap)
	
	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)
	
	var back_btn := Button.new()
	back_btn.name = "BackBtn"
	back_btn.text = "← BACK"
	back_btn.custom_minimum_size = Vector2(160, 44)
	back_btn.pressed.connect(func():
		_play_ui("ui.cancel")
		_protocol_overlay.visible = false
	)
	btn_row.add_child(back_btn)
	_style_button(back_btn, false, Color(0.6, 0.65, 0.7, 0.4), Color(0.5, 0.55, 0.6, 0.2))

func _create_protocol_node(upgrade: Dictionary) -> Dictionary:
	var col := int(upgrade.get("col", 0))
	var row := int(upgrade.get("row", 0))
	var node_color := Color.from_string(String(upgrade.get("color", "#ffffff")), Color.WHITE)
	
	var panel := PanelContainer.new()
	panel.name = String(upgrade.get("id", "node"))
	panel.custom_minimum_size = Vector2(140, 90)
	
	# Position based on grid
	var x := 80.0 + float(col) * 160.0
	var y := 20.0 + float(row) * 100.0
	panel.position = Vector2(x, y)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.14, 0.95)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(node_color.r, node_color.g, node_color.b, 0.5)
	panel.add_theme_stylebox_override("panel", sb)
	
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	panel.add_child(content)
	
	var icon_lbl := Label.new()
	icon_lbl.text = String(upgrade.get("icon", "?"))
	icon_lbl.add_theme_font_size_override("font_size", 22)
	icon_lbl.add_theme_color_override("font_color", node_color)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(icon_lbl)
	
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = String(upgrade.get("name", "?"))
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(name_lbl)
	
	var cost_lbl := Label.new()
	cost_lbl.name = "Cost"
	cost_lbl.text = "★ %d" % int(upgrade.get("cost", 0))
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 0.9))
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(cost_lbl)
	
	# Click handler
	var btn_overlay := Button.new()
	btn_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_overlay.flat = true
	btn_overlay.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_child(btn_overlay)
	
	var upgrade_id := String(upgrade.get("id", ""))
	btn_overlay.pressed.connect(func():
		_on_protocol_node_clicked(upgrade_id)
	)
	btn_overlay.mouse_entered.connect(func():
		_on_protocol_node_hovered(upgrade_id, true)
	)
	btn_overlay.mouse_exited.connect(func():
		_on_protocol_node_hovered(upgrade_id, false)
	)
	
	return {
		"id": upgrade_id,
		"panel": panel,
		"stylebox": sb,
		"color": node_color,
		"upgrade": upgrade
	}

func _draw_protocol_lines(container: Control) -> void:
	# Draw lines connecting prerequisites
	for node in _protocol_nodes:
		var upgrade: Dictionary = node.get("upgrade", {})
		var prereqs: Array = upgrade.get("prereq", [])
		var panel: Control = node.get("panel")
		if panel == null:
			continue
		
		var to_pos := panel.position + Vector2(70, 0)  # Top center
		
		for prereq_id in prereqs:
			# Find prereq node
			for pnode in _protocol_nodes:
				if String(pnode.get("id", "")) == String(prereq_id):
					var from_panel: Control = pnode.get("panel")
					if from_panel == null:
						continue
					var from_pos := from_panel.position + Vector2(70, 90)  # Bottom center
					
					var line := Line2D.new()
					line.width = 2.0
					line.default_color = Color(0.5, 0.4, 0.7, 0.4)
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
	
	# Update sigils display
	if _protocol_overlay:
		var sigils_lbl := _protocol_overlay.get_node_or_null("PanelContainer/VBoxContainer/HBoxContainer/SigilsLabel") as Label
		if sigils_lbl == null:
			# Try alternate path
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
	
	# Update node states
	for node in _protocol_nodes:
		var id := String(node.get("id", ""))
		var panel: PanelContainer = node.get("panel")
		var sb: StyleBoxFlat = node.get("stylebox")
		var color: Color = node.get("color", Color.WHITE)
		var upgrade: Dictionary = node.get("upgrade", {})
		
		if panel == null or sb == null:
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
			# Unlocked - bright and glowing
			sb.bg_color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.95)
			sb.border_color = color
			sb.border_width_left = 3
			sb.border_width_right = 3
			sb.border_width_top = 3
			sb.border_width_bottom = 3
			panel.modulate = Color(1, 1, 1, 1)
			# Update cost to show "OWNED"
			var cost_lbl := panel.get_node_or_null("VBoxContainer/Cost") as Label
			if cost_lbl:
				cost_lbl.text = "✓ OWNED"
				cost_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 1.0))
		elif prereqs_met and can_afford:
			# Available - normal
			sb.bg_color = Color(0.1, 0.11, 0.16, 0.95)
			sb.border_color = Color(color.r, color.g, color.b, 0.7)
			sb.border_width_left = 2
			sb.border_width_right = 2
			sb.border_width_top = 2
			sb.border_width_bottom = 2
			panel.modulate = Color(1, 1, 1, 1)
		elif prereqs_met:
			# Prereqs met but can't afford - dimmed
			sb.bg_color = Color(0.08, 0.09, 0.12, 0.95)
			sb.border_color = Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.5)
			panel.modulate = Color(0.7, 0.7, 0.7, 1)
		else:
			# Locked - very dim
			sb.bg_color = Color(0.05, 0.05, 0.08, 0.95)
			sb.border_color = Color(0.3, 0.3, 0.35, 0.3)
			panel.modulate = Color(0.4, 0.4, 0.4, 0.7)

func _on_protocol_node_clicked(upgrade_id: String) -> void:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp):
		return
	
	# Find upgrade
	var upgrade: Dictionary = {}
	for u in PROTOCOL_UPGRADES:
		if String(u.get("id", "")) == upgrade_id:
			upgrade = u
			break
	
	if upgrade.is_empty():
		return
	
	var unlocked: Array = []
	if mp.has_method("get_unlocked_upgrades"):
		unlocked = mp.get_unlocked_upgrades()
	
	# Already owned?
	if upgrade_id in unlocked:
		_play_ui("ui.error")
		return
	
	# Check prereqs
	var prereqs: Array = upgrade.get("prereq", [])
	for prereq_id in prereqs:
		if not String(prereq_id) in unlocked:
			_play_ui("ui.error")
			return
	
	# Check cost
	var cost := int(upgrade.get("cost", 0))
	var sigils := 0
	if mp.has_method("get_sigils"):
		sigils = int(mp.get_sigils())
	
	if sigils < cost:
		_play_ui("ui.error")
		return
	
	# Purchase!
	if mp.has_method("spend_sigils"):
		mp.spend_sigils(cost)
	if mp.has_method("unlock_upgrade"):
		mp.unlock_upgrade(upgrade_id)
	
	_play_ui("ui.levelup")
	_update_protocol_grid()
	
	# Celebration effect
	_spawn_purchase_vfx(upgrade_id)

func _on_protocol_node_hovered(upgrade_id: String, hovered: bool) -> void:
	# Find node
	for node in _protocol_nodes:
		if String(node.get("id", "")) == upgrade_id:
			var panel: PanelContainer = node.get("panel")
			if panel:
				if hovered:
					var tw := panel.create_tween()
					tw.tween_property(panel, "scale", Vector2(1.08, 1.08), 0.1)
				else:
					var tw := panel.create_tween()
					tw.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.1)
			break

func _spawn_purchase_vfx(upgrade_id: String) -> void:
	# Find node position
	for node in _protocol_nodes:
		if String(node.get("id", "")) == upgrade_id:
			var panel: PanelContainer = node.get("panel")
			var color: Color = node.get("color", Color.WHITE)
			if panel and panel.get_parent():
				var pos := panel.global_position + Vector2(70, 45)
				# Spawn particles
				for i in range(12):
					var p := ColorRect.new()
					p.size = Vector2(6, 6)
					p.color = color
					p.position = pos
					_protocol_overlay.add_child(p)
					
					var angle := randf() * TAU
					var dist := 60.0 + randf() * 40.0
					var target := pos + Vector2.from_angle(angle) * dist
					
					var tw := p.create_tween()
					tw.set_parallel(true)
					tw.tween_property(p, "position", target, 0.4).set_ease(Tween.EASE_OUT)
					tw.tween_property(p, "modulate:a", 0.0, 0.4)
					tw.chain().tween_callback(p.queue_free)
			break
