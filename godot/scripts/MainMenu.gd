extends Control

# Main Menu — "command deck": the zone select IS the menu.
# Full-bleed map art hero, zone carousel, mission detail panel, slim nav rail.

# Command deck
var _codex_ui: Control = null
var _protocol_ui: Control = null
var _deck: Control = null
var _deploy_btn: Button = null
var _zone_scroll: float = 0.0

@export var game_title: String = "SQUADSURVIVOR"
@export var game_tagline: String = "Recruit • Draft • Survive"
@export var footer_text: String = "Build 4.4 • Tactical Operations"

# ─────────────────────────────────────────────────────────────────────────────
# ASSETS (put the generated PNGs here)
# ─────────────────────────────────────────────────────────────────────────────
const _CommandDeckUI := preload("res://scripts/menu/CommandDeckUI.gd")
const _ProtocolGridUI := preload("res://scripts/menu/ProtocolGridUI.gd")
const _MenuCodexUI := preload("res://scripts/menu/MenuCodexUI.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const ARMORY_SCENE: PackedScene = preload("res://scenes/Menu.tscn")

# Pixel UI font (menus + HUD labels). Orbitron kept as optional display fallback.
const FONT_PATH: String = UiSkin.FONT_PATH

# ─────────────────────────────────────────────────────────────────────────────
# COLORS — aliases onto shared UiSkin tokens (single source of truth)
# ─────────────────────────────────────────────────────────────────────────────
const TITLE_COLOR: Color = UiSkin.TEXT
const SUBTITLE_COLOR: Color = UiSkin.TEXT_SOFT

const ACCENT_SUN: Color = UiSkin.ACCENT_GOLD
const ACCENT_BERRY: Color = UiSkin.ACCENT_PURPLE

# Readability surfaces for map overlay
const SURFACE_BG := Color(0.08, 0.06, 0.09, 0.92)
const SURFACE_BORDER := Color(0.52, 0.46, 0.38, 0.45)

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	UiSkin.apply_global_font(FONT_PATH, 12)

	# Hide any legacy scene decor
	for legacy_name in ["MenuBackground", "MenuSunwash", "Backdrop", "BackdropShader", "FrameShader", "MenuRoot"]:
		var legacy := get_node_or_null(legacy_name) as CanvasItem
		if legacy != null:
			legacy.visible = false

	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm) and mm.has_method("play"):
		mm.play("menu", 1.0)

	_deck = _CommandDeckUI.attach(self)
	await get_tree().process_frame
	if _deck != null and _deck.has_method("populate_zones"):
		_deck.call("populate_zones")
	await get_tree().process_frame
	await get_tree().process_frame
	_prewarm_protocol_runtime()
	await get_tree().process_frame
	_prewarm_info_overlay()

func _prewarm_protocol_runtime() -> void:
	_protocol_ui = _ProtocolGridUI.attach(self)
	if _protocol_ui.has_method("prewarm"):
		_protocol_ui.prewarm()

func _cycle_zone(dir: int) -> void:
	if _deck != null and _deck.has_method("cycle_zone"):
		_deck.call("cycle_zone", dir)

func _on_zone_strip_input(ev: InputEvent) -> void:
	if _deck != null and _deck.has_method("_on_zone_strip_input"):
		_deck.call("_on_zone_strip_input", ev)

func _refresh_sigils() -> void:
	if _deck != null and _deck.has_method("refresh_sigils"):
		_deck.call("refresh_sigils")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		if _codex_ui != null and _codex_ui.visible:
			_close_info_overlay()
			get_viewport().set_input_as_handled()
		elif _protocol_ui != null and _protocol_ui.visible:
			_close_protocol_overlay()
			get_viewport().set_input_as_handled()
		return
	# Zone navigation only on the deck itself.
	if (_codex_ui != null and _codex_ui.visible) or (_protocol_ui != null and _protocol_ui.visible):
		return
	match key:
		KEY_LEFT, KEY_A:
			_cycle_zone(-1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_D:
			_cycle_zone(1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _deck != null and _deck.has_method("try_deploy"):
				_deck.call("try_deploy")
			get_viewport().set_input_as_handled()


func _make_menu_button(text: String, is_primary: bool, accent: Color = UiSkin.ACCENT_GOLD) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, UiSkin.BUTTON_HEIGHT)
	if is_primary:
		UiSkin.style_primary_button(btn, accent)
	else:
		UiSkin.style_secondary_button(btn, accent)
	btn.add_theme_font_size_override("font_size", 12)
	_apply_font(btn)
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

func _play_ui(id: String) -> void:
	var s := get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_ui"):
		s.play_ui(id)

func _prewarm_info_overlay() -> void:
	_codex_ui = _MenuCodexUI.attach(self)
	if _codex_ui.has_method("prewarm"):
		_codex_ui.prewarm()

func _open_info_overlay() -> void:
	if _codex_ui == null or not is_instance_valid(_codex_ui):
		_codex_ui = _MenuCodexUI.attach(self)
	if _codex_ui.has_method("open"):
		_codex_ui.open()

func _close_info_overlay() -> void:
	if _codex_ui != null and is_instance_valid(_codex_ui) and _codex_ui.has_method("close"):
		_codex_ui.close()

func _open_settings() -> void:
	if has_node("SettingsMenu"):
		return
	var sm := preload("res://scripts/SettingsMenu.gd").new()
	sm.name = "SettingsMenu"
	add_child(sm)

func _open_protocol_grid() -> void:
	if _protocol_ui == null or not is_instance_valid(_protocol_ui):
		_protocol_ui = _ProtocolGridUI.attach(self)
	if _protocol_ui.has_method("open"):
		_protocol_ui.open()

func _close_protocol_overlay() -> void:
	if _protocol_ui != null and is_instance_valid(_protocol_ui) and _protocol_ui.has_method("close"):
		_protocol_ui.close()

