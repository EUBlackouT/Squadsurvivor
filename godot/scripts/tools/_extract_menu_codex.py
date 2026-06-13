"""Extract MenuCodexUI from MainMenu.gd."""
from pathlib import Path
import re

MAIN = Path(r"E:/SplitCode/godot/scripts/MainMenu.gd")
OUT = Path(r"E:/SplitCode/godot/scripts/menu/MenuCodexUI.gd")

lines = MAIN.read_text(encoding="utf-8").splitlines(keepends=True)
start = end = None
for i, line in enumerate(lines):
    if line.startswith("func _open_info_overlay()"):
        start = i
    if start is not None and line.startswith("func _open_settings()"):
        end = i
        break
if start is None or end is None:
    raise SystemExit(f"bounds not found start={start} end={end}")

body = "".join(lines[start:end])

body = body.replace("func _open_info_overlay() -> void:", "func open() -> void:", 1)
body = body.replace("func _close_info_overlay() -> void:", "func close() -> void:", 1)
body = body.replace("func _create_info_overlay() -> void:", "func _build_overlay() -> void:", 1)
body = body.replace("_close_info_overlay()", "close()")
body = body.replace("_open_info_overlay()", "open()")

# open(): simplify duplicate build paths
body = re.sub(
    r"func open\(\) -> void:.*?func close\(\) -> void:",
    """func open() -> void:
\t_ensure_built()
\tvisible = true
\tvar shell := get_node_or_null("FullscreenShell") as UiFullscreenShell
\tif shell != null:
\t\tshell.animate_in()
\telse:
\t\t_animate_open()
\t_reload_info_entries()
\tif _info_search != null:
\t\t_info_search.grab_focus()

func close() -> void:""",
    body,
    count=1,
    flags=re.DOTALL,
)

body = re.sub(
    r"func close\(\) -> void:.*?func _build_overlay\(\) -> void:",
    """func close() -> void:
\tvisible = false
\t_focus_deploy_button()

func _animate_open() -> void:
\tmodulate.a = 0.0
\tvar tw := create_tween()
\ttw.tween_property(self, "modulate:a", 1.0, UiSkin.DUR_FAST)

func _build_overlay() -> void:""",
    body,
    count=1,
    flags=re.DOTALL,
)

# Overlay root is self
body = re.sub(
    r"func _build_overlay\(\) -> void:\n\t_info_overlay = Control\.new\(\)\n\t_info_overlay\.name = \"InfoOverlay\"\n\t_info_overlay\.visible = false\n\t_info_overlay\.set_anchors_preset\(Control\.PRESET_FULL_RECT\)\n\t_info_overlay\.mouse_filter = Control\.MOUSE_FILTER_STOP\n\tadd_child\(_info_overlay\)\n\n",
    "func _build_overlay() -> void:\n",
    body,
    count=1,
)
body = body.replace("_info_overlay.add_child(shell)", "add_child(shell)")
body = body.replace("_animate_overlay_open(_info_overlay)", "_animate_open()")
body = body.replace("\n\t_info_overlay.visible = true\n", "\n")

body = re.sub(
    r"func close\(\) -> void:\n\tif _info_overlay == null:\n\t\treturn\n\t_info_overlay\.visible = false\n\tif _deploy_btn:\n\t\t_deploy_btn\.grab_focus\(\)\n",
    "",
    body,
    count=1,
)

header = '''extends Control

var _host: Control
var _built: bool = false

var _info_search: LineEdit = null
var _info_section: OptionButton = null
var _info_list: ItemList = null
var _info_details: RichTextLabel = null
var _info_hint: Label = null
var _info_entries: Array[Dictionary] = []

static func attach(host: Control) -> Control:
	var existing := host.get_node_or_null("MenuCodexUI") as Control
	if existing != null:
		return existing
	var ui: Control = load("res://scripts/menu/MenuCodexUI.gd").new()
	ui.name = "MenuCodexUI"
	ui._host = host
	host.add_child(ui)
	ui._ensure_built()
	ui.visible = false
	return ui

func prewarm() -> void:
	_ensure_built()
	visible = false

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_overlay()

func _apply_font(c: Control) -> void:
	if _host != null and _host.has_method("_apply_font"):
		_host.call("_apply_font", c)

func _play_ui(id: String) -> void:
	if _host != null and _host.has_method("_play_ui"):
		_host.call("_play_ui", id)

func _focus_deploy_button() -> void:
	if _host == null:
		return
	var btn: Button = _host.get("_deploy_btn") as Button
	if btn != null:
		btn.grab_focus()

func _sb_inset(radius: int = 12, alpha: float = 0.86) -> StyleBoxFlat:
	return UiSkin.inset_style(radius, alpha, Color(0.08, 0.06, 0.09, 0.92), Color(0.52, 0.46, 0.38, 0.45))

'''

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(header + body, encoding="utf-8")
print(f"Wrote {OUT} ({len((header + body).splitlines())} lines)")
