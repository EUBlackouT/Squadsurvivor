class_name VfxShockwave
extends Node2D

# Pixel-friendly shockwave ring (jagged, not a perfect circle).
# Uses only draw calls + a tween; no collision shapes, no particles.

var _color: Color = Color(0.82, 0.65, 1.0, 1.0)
var _r0: float = 18.0
var _r1: float = 84.0
var _width: float = 5.0
var _duration: float = 0.22
var _segments: int = 18
var _jitter: float = 0.18
var _t: float = 0.0

func setup(world_pos: Vector2, color: Color, r0: float = 18.0, r1: float = 84.0, width: float = 5.0, duration: float = 0.22) -> void:
	global_position = world_pos
	_color = color
	_r0 = r0
	_r1 = r1
	_width = width
	_duration = maxf(0.05, duration)

func _ready() -> void:
	top_level = true
	z_index = 50
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_t", 1.0, _duration)
	tw.finished.connect(queue_free)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Build a jagged polyline ring.
	var r: float = lerpf(_r0, _r1, clampf(_t, 0.0, 1.0))
	var a: float = (1.0 - _t)
	var col: Color = Color(_color.r, _color.g, _color.b, _color.a * a)

	var pts := PackedVector2Array()
	var n: int = maxi(8, _segments)
	for i in range(n + 1):
		var ang: float = TAU * float(i) / float(n)
		var spike: float = 1.0 + sin(ang * 3.0 + 1.3) * _jitter + sin(ang * 7.0 + 0.4) * (_jitter * 0.55)
		var rr: float = r * spike
		pts.append(Vector2(cos(ang), sin(ang)) * rr)
	draw_polyline(pts, col, _width, true)


