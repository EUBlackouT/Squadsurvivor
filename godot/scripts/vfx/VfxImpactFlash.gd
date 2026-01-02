class_name VfxImpactFlash
extends Node2D

# Quick impact flash: a small starburst + soft disc.
# Pure draw calls + tween (no textures/particles).

var _color: Color = Color(1, 1, 1, 1)
var _radius: float = 18.0
var _duration: float = 0.12
var _t: float = 0.0

func setup(world_pos: Vector2, color: Color, radius: float = 18.0, duration: float = 0.12) -> void:
	global_position = world_pos
	_color = color
	_radius = maxf(6.0, radius)
	_duration = maxf(0.06, duration)

func _ready() -> void:
	top_level = true
	z_index = 58
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
	var c := Color(_color.r, _color.g, _color.b, _color.a * a)
	var r := lerpf(_radius * 0.55, _radius, t)

	# soft disc
	draw_circle(Vector2.ZERO, r * 0.55, Color(c.r, c.g, c.b, c.a * 0.18))
	draw_circle(Vector2.ZERO, r * 0.25, Color(1, 1, 1, c.a * 0.16))

	# starburst lines
	var spikes := 7
	var w := 2.0
	for i in range(spikes):
		var ang := (TAU * float(i) / float(spikes)) + t * 0.6
		var dir := Vector2(cos(ang), sin(ang))
		var p0 := dir * (r * 0.15)
		var p1 := dir * (r * (0.90 + 0.20 * sin(float(i) * 2.2)))
		draw_line(p0, p1, Color(c.r, c.g, c.b, c.a * 0.65), w, true)


