"""Extract RunHudUI from Main.gd into run/RunHudUI.gd."""
from pathlib import Path

MAIN = Path(r"E:/SplitCode/godot/scripts/Main.gd")
OUT = Path(r"E:/SplitCode/godot/scripts/run/RunHudUI.gd")

lines = MAIN.read_text(encoding="utf-8").splitlines(keepends=True)

START_MARKERS = [
    "func _setup_hud() -> void:",
]
END_MARKER = "func _strip_circle_collision_shapes() -> void:"

start = end = None
for i, line in enumerate(lines):
    if start is None and line.startswith("func _setup_hud() -> void:"):
        start = i
    if start is not None and line.startswith(END_MARKER):
        end = i
        break

if start is None or end is None:
    raise SystemExit(f"bounds not found start={start} end={end}")

body = "".join(lines[start:end])

# Rename entry points
body = body.replace("func _setup_hud() -> void:", "func _build() -> void:", 1)
body = body.replace("func _update_hud_labels() -> void:", "func refresh() -> void:", 1)
body = body.replace("func _show_passive_overlay() -> void:", "func show_passive_overlay() -> void:", 1)
body = body.replace("func _hide_passive_overlay() -> void:", "func hide_passive_overlay() -> void:", 1)

# Remove hud canvas layer wrapper — RunHudUI *is* the HUD layer
body = body.replace("\tvar hud := CanvasLayer.new()\n\thud.name = \"HUD\"\n\thud.layer = 10\n\tadd_child(hud)\n\n", "")
body = body.replace("hud.add_child(", "add_child(")
body = body.replace("_create_passive_overlay(hud)", "_create_passive_overlay()")
body = body.replace("func _create_passive_overlay(hud: CanvasLayer) -> void:", "func _create_passive_overlay() -> void:", 1)

# Node paths
body = body.replace('get_node_or_null("HUD/SquadStrip")', 'get_node_or_null("SquadStrip")')
body = body.replace('get_node_or_null("HUD") == null', "false")
body = body.replace('get_node_or_null("HUD")', "self")
body = body.replace("_collect_debug_counts(self)", "_collect_debug_counts(_host)")

# Host field access (longer names first)
HOST_FIELDS = [
    "_multi_boss_schedule_enabled",
    "_objective_event_index",
    "_boss_fight_active",
    "_boss_deadline_s",
    "_boss_wave_index",
    "_boss_wave_times",
    "_callout_until_s",
    "_overclock_cd_s",
    "_focus_until_s",
    "_rally_until_s",
    "_callout_cd_s",
    "_callout_class",
    "_boss_spawned",
    "_hide_projectiles",
    "_boss_node",
    "_game_over",
    "_victory",
    "debug_perf_overlay_enabled",
    "debug_hud_enabled",
    "live_squad_units",
    "run_start_time",
    "_objective_events",
    "run_timer_max_minutes",
    "enable_bosses",
    "_perf_text",
    "essence",
]
for field in HOST_FIELDS:
    body = body.replace(field, f"_host.{field}")

# Methods still on Main
body = body.replace("get_focus_target()", "_host.get_focus_target()")
body = body.replace("_overclock_unlocked()", "_host._overclock_unlocked()")
body = body.replace("_class_name(", "_class_name(")  # keep local static

# get_tree from host where Main context was implied
body = body.replace("get_tree().get_first_node_in_group", "_host.get_tree().get_first_node_in_group")
body = body.replace("get_tree().get_nodes_in_group", "_host.get_tree().get_nodes_in_group")
body = body.replace("get_tree().paused", "_host.get_tree().paused")
body = body.replace("has_node(\"RecruitDraftUI\")", "_host.has_node(\"RecruitDraftUI\")")
body = body.replace("has_node(\"PauseMenu\")", "_host.has_node(\"PauseMenu\")")

header = '''extends CanvasLayer
class_name RunHudUI

var _host: Node
var _passive_overlay: PanelContainer = null
var _squad_strip_sig: String = ""
var _hud_label_cache: Dictionary = {}
var _dbg_cd: float = 0.0
var _dbg_text: String = ""

static func attach(host: Node) -> CanvasLayer:
	if host.has_node("HUD"):
		return host.get_node("HUD") as CanvasLayer
	var hud: CanvasLayer = load("res://scripts/run/RunHudUI.gd").new()
	hud.name = "HUD"
	hud.layer = 10
	hud.set("_host", host)
	host.add_child(hud)
	hud.call("_build")
	return hud

static func _class_name(c: int) -> String:
	match c:
		CharacterData.Class.WARRIOR: return "Warrior"
		CharacterData.Class.MAGE: return "Mage"
		CharacterData.Class.ROGUE: return "Rogue"
		CharacterData.Class.GUARDIAN: return "Guardian"
		CharacterData.Class.HEALER: return "Healer"
		CharacterData.Class.SUMMONER: return "Summoner"
		_: return "Unknown"

func sync_passive_overlay_hotkey() -> void:
	if _passive_overlay == null:
		return
	var blocked := _host._game_over or _host._victory or _host.get_tree().paused \\
		or _host.has_node("RecruitDraftUI") or _host.has_node("PauseMenu")
	var wants_overlay := (not blocked) and Input.is_key_pressed(KEY_TAB)
	if wants_overlay and not _passive_overlay.visible:
		show_passive_overlay()
	elif (not wants_overlay) and _passive_overlay.visible:
		hide_passive_overlay()

'''

# Drop duplicate var declarations moved to header
for decl in [
    "var _passive_overlay: PanelContainer = null\n",
    "var _squad_strip_sig: String = \"\"\n\n",
    "var _hud_label_cache: Dictionary = {}\n\n",
]:
    body = body.replace(decl, "")

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(header + body, encoding="utf-8")
print(f"Wrote {OUT} ({len(header + body.splitlines())} lines)")
