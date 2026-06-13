"""Extract CommandDeckUI from MainMenu.gd."""
from pathlib import Path
import re

MAIN = Path(r"E:/SplitCode/godot/scripts/MainMenu.gd")
OUT = Path(r"E:/SplitCode/godot/scripts/menu/CommandDeckUI.gd")

lines = MAIN.read_text(encoding="utf-8").splitlines(keepends=True)

helper_start = None
deck_start = None
deck_end = None
for i, line in enumerate(lines):
    if line.startswith("func _load_tex(path: String)"):
        helper_start = i
    if line.startswith("func _build_command_deck()"):
        deck_start = i
    if deck_start is not None and line.startswith("func _unhandled_input(event: InputEvent)"):
        deck_end = i
        break

if helper_start is None or deck_start is None or deck_end is None:
    raise SystemExit(f"bounds helper={helper_start} deck={deck_start} end={deck_end}")

body = "".join(lines[helper_start:deck_end])

# Skip dead codex panel helper in helper block
body = re.sub(
    r"func _make_codex_panel_style\(\) -> StyleBox:.*?func _apply_font\(c: Control\)",
    "func _apply_font(c: Control)",
    body,
    count=1,
    flags=re.DOTALL,
)

body = body.replace("func _build_command_deck() -> void:", "func _build() -> void:", 1)
body = body.replace("func _populate_zone_carousel() -> void:", "func populate_zones() -> void:", 1)
body = body.replace("func _refresh_sigils() -> void:", "func refresh_sigils() -> void:", 1)
body = body.replace("func _cycle_zone(dir: int) -> void:", "func cycle_zone(dir: int) -> void:", 1)
body = body.replace("_refresh_sigils()", "refresh_sigils()")
body = body.replace("_populate_zone_carousel()", "populate_zones()")
body = body.replace("_cycle_zone(dir)", "cycle_zone(dir)")
body = body.replace("_open_protocol_grid()", "_host.call(\"_open_protocol_grid\")")
body = body.replace("_open_info_overlay()", "_host.call(\"_open_info_overlay\")")
body = body.replace("_open_settings()", "_host.call(\"_open_settings\")")
body = body.replace("_start_run_with_selected_map()", "_start_run_with_selected_map()")

body = body.replace("game_title", "_title_text()")
body = body.replace("game_tagline", "_tagline_text()")
body = body.replace("footer_text", "_footer_text()")

body = body.replace("get_tree()", "_host.get_tree()")

header = '''extends Control

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

'''

# Remove duplicate var block if present in body (from MainMenu copy)
body = re.sub(
    r"func _load_tex\(path: String\).*?# COMMAND DECK.*?\n\n",
    "func _load_tex(path: String) -> Texture2D:\n",
    body,
    count=1,
    flags=re.DOTALL,
)
body = body.replace("# ─────────────────────────────────────────────────────────────────────────────\n# COMMAND DECK — the zone select IS the menu\n# ─────────────────────────────────────────────────────────────────────────────\n\n", "")

# Append deploy helpers at end if not in extracted range - they should be included
# _start_run_with_selected_map is AFTER _unhandled_input - need to include it
deploy_start = deploy_end = None
for i, line in enumerate(lines):
    if line.startswith("func _start_run_with_selected_map()"):
        deploy_start = i
    if deploy_start is not None and line.startswith("func _is_map_unlocked"):
        deploy_end = i
        break

deploy_body = ""
if deploy_start is not None and deploy_end is not None:
    deploy_body = "".join(lines[deploy_start:deploy_end])
    deploy_body = deploy_body.replace("get_tree()", "_host.get_tree()")
    deploy_body = deploy_body.replace("add_child(layer)", "_host.add_child(layer)")

is_unlock = ""
for i, line in enumerate(lines):
    if line.startswith("func _is_map_unlocked"):
        j = i
        while j < len(lines) and not lines[j].startswith("func _play_ui"):
            is_unlock += lines[j]
            j += 1
        break

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(header + body + deploy_body + is_unlock, encoding="utf-8")
print(f"Wrote {OUT} ({len((header + body + deploy_body + is_unlock).splitlines())} lines)")
