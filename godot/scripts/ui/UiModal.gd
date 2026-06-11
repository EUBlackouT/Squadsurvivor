class_name UiModal
extends CanvasLayer

# Shared modal shell: backdrop + centered panel + padded content column.
# Single source of truth for modal structure, dim, animation, and Esc handling.
#
# Usage:
#   var modal := UiModal.build({
#       "size": Vector2(560, 420),
#       "accent": UiSkin.ACCENT,
#       "process_mode": Node.PROCESS_MODE_WHEN_PAUSED,
#       "esc_closes": true,
#       "click_outside_closes": true,
#   })
#   add_child(modal)
#   modal.content.add_child(...)
#   modal.closed.connect(func(): ...)
#
# Close programmatically with modal.close(); `closed` fires exactly once.

signal closed

var backdrop: ColorRect = null
var panel: PanelContainer = null
var content: VBoxContainer = null

var _root: Control = null
var _esc_closes: bool = true
var _click_outside_closes: bool = false
var _animate: bool = true
var _closing: bool = false

static func build(opts: Dictionary = {}) -> UiModal:
	UiSkin.apply_global_font()
	var m := UiModal.new()
	m.layer = int(opts.get("layer", 220))
	m.process_mode = int(opts.get("process_mode", Node.PROCESS_MODE_ALWAYS)) as Node.ProcessMode
	m._esc_closes = bool(opts.get("esc_closes", true))
	m._click_outside_closes = bool(opts.get("click_outside_closes", false))
	m._animate = bool(opts.get("animate", true))
	m._build_shell(opts)
	return m

func _build_shell(opts: Dictionary) -> void:
	var size: Vector2 = opts.get("size", Vector2(640, 480))
	var accent: Color = opts.get("accent", UiSkin.ACCENT)
	var dim: Color = opts.get("dim", UiSkin.BACKDROP_DIM)

	_root = Control.new()
	_root.name = "ModalRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = dim
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(backdrop)
	if _click_outside_closes:
		backdrop.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
				close()
		)

	panel = PanelContainer.new()
	panel.name = "ModalPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -size.x * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_bottom = size.y * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UiSkin.panel_style(accent, true))
	_root.add_child(panel)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_theme_constant_override("margin_left", UiSkin.SPACE_LG)
	pad.add_theme_constant_override("margin_right", UiSkin.SPACE_LG)
	pad.add_theme_constant_override("margin_top", UiSkin.SPACE_LG)
	pad.add_theme_constant_override("margin_bottom", UiSkin.SPACE_LG)
	panel.add_child(pad)

	content = VBoxContainer.new()
	content.name = "ModalContent"
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_theme_constant_override("separation", UiSkin.SPACE_MD)
	pad.add_child(content)

func _ready() -> void:
	if not _animate:
		return
	# Standard open animation: backdrop fade + panel pop.
	backdrop.modulate.a = 0.0
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.94, 0.94)
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(backdrop, "modulate:a", 1.0, UiSkin.DUR_FAST)
	tw.tween_property(panel, "modulate:a", 1.0, UiSkin.DUR_FAST)
	tw.tween_property(panel, "scale", Vector2.ONE, UiSkin.DUR_MED) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _unhandled_input(event: InputEvent) -> void:
	if not _esc_closes:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	if not _animate or not is_inside_tree():
		queue_free()
		return
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.pivot_offset = panel.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(backdrop, "modulate:a", 0.0, UiSkin.DUR_FAST)
	tw.tween_property(panel, "modulate:a", 0.0, UiSkin.DUR_FAST)
	tw.tween_property(panel, "scale", Vector2(0.96, 0.96), UiSkin.DUR_FAST)
	tw.chain().tween_callback(queue_free)
