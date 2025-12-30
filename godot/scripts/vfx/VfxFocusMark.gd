class_name VfxFocusMark
extends Node2D

# Target marker for Focus Fire: bracket corners + optional stack pips.

var _color: Color = Color(0.92, 0.85, 0.30, 1.0)
var _duration: float = 0.22
var _size: float = 24.0
var _stacks: int = 0
var _t: float = 0.0

func setup(world_pos: Vector2, color: Color, size: float = 24.0, stacks: int = 0, duration: float = 0.22) -> void:
	global_position = world_pos
	_color = color
	_size = size
	_stacks = clampi(stacks, 0, 10)
	_duration = maxf(0.08, duration)

func _ready() -> void:
	top_level = true
	z_index = 60
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
	var s := lerpf(_size * 0.7, _size, t)
	var w := 2.0
	var l := 10.0

	# corners
	_draw_corner(Vector2(-s, -s), Vector2(1, 0), Vector2(0, 1), l, w, col)
	_draw_corner(Vector2(s, -s), Vector2(-1, 0), Vector2(0, 1), l, w, col)
	_draw_corner(Vector2(-s, s), Vector2(1, 0), Vector2(0, -1), l, w, col)
	_draw_corner(Vector2(s, s), Vector2(-1, 0), Vector2(0, -1), l, w, col)

	# stack pips (top)
	for i in range(_stacks):
		var x := -s + 6.0 + float(i) * 5.0
		draw_rect(Rect2(Vector2(x, -s - 8.0), Vector2(3, 3)), Color(col.r, col.g, col.b, col.a * 0.85))

func _draw_corner(p: Vector2, ex: Vector2, ey: Vector2, len: float, width: float, col: Color) -> void:
	draw_line(p, p + ex * len, col, width, true)
	draw_line(p, p + ey * len, col, width, true)


