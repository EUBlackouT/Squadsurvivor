class_name VfxHolyPulse
extends Node2D

# Holy/green pulse: diamond ring + sparkle lines.

var _color: Color = Color(0.55, 1.0, 0.65, 1.0)
var _duration: float = 0.24
var _size0: float = 18.0
var _size1: float = 54.0
var _t: float = 0.0

func setup(world_pos: Vector2, color: Color, size0: float = 18.0, size1: float = 54.0, duration: float = 0.24) -> void:
	global_position = world_pos
	_color = color
	_size0 = size0
	_size1 = size1
	_duration = maxf(0.08, duration)

func _ready() -> void:
	top_level = true
	z_index = 55
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_t", 1.0, _duration)
	tw.finished.connect(queue_free)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var t := clampf(_t, 0.0, 1.0)
	var a := (1.0 - t)
	var col := Color(_color.r, _color.g, _color.b, _color.a * a)
	var s := lerpf(_size0, _size1, t)

	var p := PackedVector2Array([
		Vector2(0, -s),
		Vector2(s, 0),
		Vector2(0, s),
		Vector2(-s, 0),
		Vector2(0, -s)
	])
	draw_polyline(p, col, 3.0, true)
	draw_polyline(p, Color(col.r, col.g, col.b, col.a * 0.45), 6.0, true)

	# sparkles
	draw_line(Vector2(-s * 0.6, -s * 0.15), Vector2(-s * 0.9, -s * 0.45), Color(col.r, col.g, col.b, col.a * 0.75), 1.0, true)
	draw_line(Vector2(s * 0.25, -s * 0.55), Vector2(s * 0.45, -s * 0.85), Color(col.r, col.g, col.b, col.a * 0.75), 1.0, true)


