class_name VfxMeleeStreak
extends Node2D

# Directional melee streak (NOT a half-circle): a fast angled slash bar + glow.
# Pure draw calls + tween, designed to read well over busy maps.

var _color: Color = Color(1, 1, 1, 1)
var _dir: Vector2 = Vector2.RIGHT
var _len: float = 42.0
var _width: float = 10.0
var _duration: float = 0.10
var _t: float = 0.0

func setup(world_pos: Vector2, dir: Vector2, color: Color, length: float = 42.0, width: float = 10.0, duration: float = 0.10) -> void:
	global_position = world_pos
	_dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	_color = color
	_len = maxf(18.0, length)
	_width = maxf(3.0, width)
	_duration = maxf(0.06, duration)
	rotation = _dir.angle()

func _ready() -> void:
	top_level = true
	z_index = 57
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_t", 1.0, _duration)
	tw.finished.connect(queue_free)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var t := clampf(_t, 0.0, 1.0)
	var a := 1.0 - t
	var col := Color(_color.r, _color.g, _color.b, _color.a * a)

	# Streak is a tapered quad along +X (rotation set in setup).
	var len := lerpf(_len * 0.85, _len, t)
	var w0 := lerpf(_width * 1.10, _width * 0.75, t)
	var w1 := lerpf(_width * 0.65, _width * 0.35, t)

	var p0 := Vector2(0, -w0)
	var p1 := Vector2(len, -w1)
	var p2 := Vector2(len, w1)
	var p3 := Vector2(0, w0)

	# Outer glow
	draw_colored_polygon(PackedVector2Array([p0 * 1.25, p1 * 1.15, p2 * 1.15, p3 * 1.25]), Color(col.r, col.g, col.b, col.a * 0.22))
	# Core streak
	draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]), Color(col.r, col.g, col.b, col.a * 0.75))
	# Hot highlight line
	draw_line(Vector2(len * 0.15, 0), Vector2(len * 0.92, 0), Color(1, 1, 1, col.a * 0.25), 2.0, true)


