"""Extract ProtocolGridUI from MainMenu.gd."""
from pathlib import Path
import re

MAIN = Path(r"E:/SplitCode/godot/scripts/MainMenu.gd")
OUT = Path(r"E:/SplitCode/godot/scripts/menu/ProtocolGridUI.gd")

lines = MAIN.read_text(encoding="utf-8").splitlines(keepends=True)

start = end = None
for i, line in enumerate(lines):
    if line.startswith("const PROTOCOL_GRID_BG_PATH:"):
        start = i
    if start is not None and i > start and not line.strip():
        # end at EOF - file ends with protocol code
        pass
start = start  # from constants
end = len(lines)

body = "".join(lines[start:end])

# Entry points
body = body.replace("func _open_protocol_grid() -> void:", "func open() -> void:", 1)
body = body.replace("func _close_protocol_overlay() -> void:", "func close() -> void:", 1)
body = body.replace("func _animate_protocol_open() -> void:", "func _animate_open() -> void:", 1)

# Overlay root is this Control
body = body.replace("_protocol_overlay", "_root")
body = re.sub(
    r"func _create_protocol_overlay\(\) -> void:\n\t_root = Control\.new\(\)\n\t_root\.name = \"ProtocolOverlay\"\n\t_root\.set_anchors_preset\(Control\.PRESET_FULL_RECT\)\n\t_root\.mouse_filter = Control\.MOUSE_FILTER_STOP\n\t_host\.add_child\(_root\)\n\n",
    "func _ensure_built() -> void:\n\tif _built:\n\t\treturn\n\t_built = true\n\tname = \"ProtocolGridUI\"\n\tset_anchors_preset(Control.PRESET_FULL_RECT)\n\tmouse_filter = Control.MOUSE_FILTER_STOP\n\tvisible = false\n\n",
    body,
    count=1,
)
body = body.replace("_root.add_child(", "add_child(")
body = body.replace("_root.visible", "visible")
body = body.replace("_root.modulate", "modulate")
body = body.replace("_root.create_tween()", "create_tween()")
body = body.replace("_root.get_node_or_null", "get_node_or_null")
body = body.replace("if _root == null:\n\t\treturn\n", "")
body = body.replace("if _root != null and is_instance_valid(_root):", "if _built:")
body = body.replace("_create_protocol_overlay()\n", "_ensure_built()\n")
body = body.replace("_close_protocol_overlay()", "close()")
body = body.replace("_animate_protocol_open()", "_animate_open()")

# Host helpers
body = body.replace("_apply_font(", "_apply_font(")
body = body.replace("ACCENT_SUN", "UiSkin.ACCENT_GOLD")
body = body.replace("TITLE_COLOR", "UiSkin.TEXT")

# Insert _apply_font helper that delegates
header = '''extends Control

const _MainMenuScript := preload("res://scripts/MainMenu.gd")

var _host: Control
var _built: bool = false

static func attach(host: Control) -> Control:
	var existing := host.get_node_or_null("ProtocolGridUI") as Control
	if existing != null:
		return existing
	var ui: Control = load("res://scripts/menu/ProtocolGridUI.gd").new()
	ui.name = "ProtocolGridUI"
	ui._host = host
	host.add_child(ui)
	ui._ensure_built()
	return ui

func prewarm() -> void:
	_ensure_built()
	if _protocol_upgrades_runtime.is_empty():
		_protocol_upgrades_runtime = _protocol_data()

func _apply_font(c: Control) -> void:
	if _host != null and _host.has_method("_apply_font"):
		_host.call("_apply_font", c)

func _play_ui(id: String) -> void:
	if _host != null and _host.has_method("_play_ui"):
		_host.call("_play_ui", id)

'''

# Fix open() to use _ensure_built
body = body.replace(
    "func open() -> void:\n\tif _built:",
    "func open() -> void:\n\t_ensure_built()\n\tif false:",
)
body = body.replace(
    "\tif false:\n\t\t_root.visible = true",
    "\tif false:\n\t\tvisible = true",
)

# Clean botched open() - rewrite open/close manually after extraction
body = re.sub(
    r"func open\(\) -> void:.*?func _animate_open\(\)",
    "func open() -> void:\n\t_ensure_built()\n\tvisible = true\n\t_animate_open()\n\t_update_protocol_grid()\n\nfunc _animate_open()",
    body,
    count=1,
    flags=re.DOTALL,
)

body = re.sub(
    r"func close\(\) -> void:.*?func _build_protocol_graph",
    lambda m: '''func close() -> void:
\tvisible = false
\t_play_ui("ui.cancel")

func _build_protocol_graph''',
    body,
    count=1,
    flags=re.DOTALL,
)

# Remove stray _root references if any left as null checks on overlay creation path
body = body.replace("_host.add_child(_root)\n", "")

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(header + body, encoding="utf-8")
print(f"Wrote {OUT} ({len((header + body).splitlines())} lines)")
