class_name ToastLayer
extends CanvasLayer

# Lightweight toast notifications (no scenes required).
# Usage: ToastLayer.new().show_toast("Unlocked: Epic • Striker", Color(...))

@export var max_toasts: int = 3
@export var toast_life: float = 2.2

var _box: VBoxContainer
var _active: Array[Dictionary] = [] # { "label": Label, "age": float, "life": float }

func _ready() -> void:
	layer = 180
	process_mode = Node.PROCESS_MODE_ALWAYS

	_box = VBoxContainer.new()
	_box.name = "ToastVBox"
	_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_box.offset_right = -18
	_box.offset_top = 18
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)

func show_toast(text: String, color: Color = Color(0.9, 0.95, 1.0, 1.0)) -> void:
	if _box == null:
		return

	# Cap number of visible toasts.
	while _active.size() >= max_toasts:
		var oldest: Dictionary = _active.pop_front()
		var l_old: Label = oldest.get("label", null)
		if l_old != null and is_instance_valid(l_old):
			l_old.queue_free()

	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)

	# Make sure it stays readable regardless of theme.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.78)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(color.r, color.g, color.b, 0.55)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	l.add_theme_stylebox_override("normal", sb)
	l.add_theme_constant_override("margin_left", 10)
	l.add_theme_constant_override("margin_right", 10)
	l.add_theme_constant_override("margin_top", 7)
	l.add_theme_constant_override("margin_bottom", 7)

	l.modulate.a = 0.0
	_box.add_child(l)

	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.10)
	tw.tween_property(l, "modulate:a", 1.0, maxf(0.05, toast_life - 0.25))
	tw.tween_property(l, "modulate:a", 0.0, 0.15)
	tw.finished.connect(func():
		if l != null and is_instance_valid(l):
			l.queue_free()
	)

	_active.append({"label": l, "age": 0.0, "life": toast_life})


