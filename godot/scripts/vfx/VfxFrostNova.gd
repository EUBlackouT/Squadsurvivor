class_name VfxFrostNova
extends Node2D

# Frost nova: radial shards + a faint ring. Cheap, tintable, pixel-friendly.

var _color: Color = Color(0.55, 0.85, 1.0, 1.0)
var _duration: float = 0.26
var _radius: float = 86.0
var _shards: int = 8
var _t: float = 0.0

func setup(world_pos: Vector2, color: Color, radius: float = 86.0, shards: int = 8, duration: float = 0.26) -> void:
	global_position = world_pos
	_color = color
	_radius = radius
	_shards = clampi(shards, 4, 16)
	_duration = maxf(0.08, duration)

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
	var t := clampf(_t, 0.0, 1.0)
	var a := (1.0 - t)
	var col := Color(_color.r, _color.g, _color.b, _color.a * a)
	var r := lerpf(_radius * 0.35, _radius, t)

	# Shards
	for i in range(_shards):
		var ang := TAU * float(i) / float(_shards) + 0.12
		var dir := Vector2(cos(ang), sin(ang))
		var len := r * lerpf(0.55, 1.0, float((i % 3) + 1) / 3.0)
		var p0 := dir * (r * 0.18)
		var p1 := dir * len
		draw_line(p0, p1, col, 2.0, true)
		draw_line(p0 + dir.rotated(0.22) * 6.0, p1 + dir.rotated(0.10) * 3.0, Color(col.r, col.g, col.b, col.a * 0.65), 1.0, true)

	# faint ring (jagged)
	var pts := PackedVector2Array()
	var n := 16
	for j in range(n + 1):
		var a2 := TAU * float(j) / float(n)
		var wob := 1.0 + sin(a2 * 5.0 + 0.3) * 0.08
		pts.append(Vector2(cos(a2), sin(a2)) * (r * wob))
	draw_polyline(pts, Color(col.r, col.g, col.b, col.a * 0.65), 3.0, true)


