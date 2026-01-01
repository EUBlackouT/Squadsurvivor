extends Node

# Simple one-time tips. Saved to: user://tutorial.cfg

const SAVE_PATH := "user://tutorial.cfg"
const SECTION := "shown"

var _shown: Dictionary = {} # tip_id -> bool

var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _title: Label = null
var _text: RichTextLabel = null

const TIPS := {
	"movement": {
		"title": "Movement",
		"text": "Move with [b]WASD[/b] or [b]Arrow Keys[/b].\nYour squad follows your formation."
	},
	"combat": {
		"title": "Combat",
		"text": "Your squad attacks automatically.\nTry switching formation ([b]1–4[/b]) and targeting ([b]T[/b]) to adapt."
	},
	"formation": {
		"title": "Formation",
		"text": "[b]1–4[/b] changes formation.\nTight is safer; spread/wedge covers more area."
	},
	"draft": {
		"title": "Drafts",
		"text": "Drafts drop from kills. Choose upgrades or recruits—then keep moving."
	},
	"targeting": {
		"title": "Targeting",
		"text": "Press [b]T[/b] to cycle targeting.\nElites-first can stabilize midgame."
	}
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_build_ui()

func show_tip(tip_id: String) -> void:
	if not TIPS.has(tip_id):
		return
	if bool(_shown.get(tip_id, false)):
		return

	_shown[tip_id] = true
	_save()

	var tip: Dictionary = TIPS.get(tip_id, {}) as Dictionary
	if _title:
		_title.text = String(tip.get("title", tip_id))
	if _text:
		_text.text = String(tip.get("text", ""))

	if _layer:
		_layer.visible = true
	if _panel:
		_panel.modulate = Color(1, 1, 1, 0)
		var start_y := 40.0
		var end_y := 0.0
		_panel.position.y = start_y
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_panel, "position:y", end_y, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.18)
		tw.set_parallel(false)
		tw.tween_interval(4.0)
		tw.tween_property(_panel, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func():
			if _layer:
				_layer.visible = false
		)

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 220
	_layer.visible = false
	add_child(_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 80
	_panel.offset_right = -80
	_panel.offset_top = -150
	_panel.offset_bottom = -24
	root.add_child(_panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.92)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.4, 0.8, 1.0, 0.18)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	_panel.add_theme_stylebox_override("panel", sb)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pad.add_child(v)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
	v.add_child(_title)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.fit_content = true
	_text.add_theme_font_size_override("normal_font_size", 13)
	_text.add_theme_color_override("default_color", Color(0.82, 0.86, 0.92, 0.98))
	v.add_child(_text)

func _load() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		_shown = {}
		return
	var keys := cfg.get_section_keys(SECTION)
	for k in keys:
		_shown[String(k)] = bool(cfg.get_value(SECTION, k, false))

func _save() -> void:
	var cfg := ConfigFile.new()
	for k in _shown.keys():
		cfg.set_value(SECTION, String(k), bool(_shown[k]))
	cfg.save(SAVE_PATH)


