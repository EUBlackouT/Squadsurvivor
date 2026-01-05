class_name VfxSmokeField
extends Node2D

# Soft smoky field (Rogue callout). Pure draw + tween, no particles.

var _color: Color = Color(0.70, 0.78, 0.90, 0.55)
var _radius: float = 240.0
var _duration: float = 3.5
var _t: float = 0.0

func setup(world_pos: Vector2, color: Color, radius: float, duration: float) -> void:
	global_position = world_pos
	_color = color
	_radius = maxf(24.0, radius)
	_duration = maxf(0.20, duration)

func _ready() -> void:
	top_level = true
	z_index = 35
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_t", 1.0, _duration)
	tw.finished.connect(queue_free)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var a := clampf(1.0 - _t, 0.0, 1.0)
	var base := Color(_color.r, _color.g, _color.b, _color.a * a)
	# Layered circles to feel "foggy".
	for i in range(6):
		var rr := lerpf(_radius * 0.25, _radius, (float(i) / 5.0))
		var aa := base.a * lerpf(0.30, 0.06, float(i) / 5.0)
		draw_circle(Vector2.ZERO, rr, Color(base.r, base.g, base.b, aa))



