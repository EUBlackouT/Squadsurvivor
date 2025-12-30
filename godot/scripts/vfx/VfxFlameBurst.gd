class_name VfxFlameBurst
extends Node2D

# Flame burst: a few pixel embers + a quick cone flash.
# No particles; uses Sprite2D squares and a tween.

var _color: Color = Color(1.0, 0.55, 0.18, 1.0)
var _duration: float = 0.22
var _count: int = 10
var _radius: float = 34.0
var _dir: Vector2 = Vector2.ZERO

func setup(world_pos: Vector2, color: Color, radius: float = 34.0, count: int = 10, duration: float = 0.22, dir: Vector2 = Vector2.ZERO) -> void:
	global_position = world_pos
	_color = color
	_radius = radius
	_count = clampi(count, 6, 18)
	_duration = maxf(0.08, duration)
	_dir = dir

func _ready() -> void:
	top_level = true
	z_index = 55
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())

	# Tiny square texture
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var tex := ImageTexture.create_from_image(img)

	for i in range(_count):
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = true
		s.scale = Vector2(2.0, 2.0) * rng.randf_range(0.85, 1.35)
		var heat := rng.randf_range(0.0, 1.0)
		var c := _color.lerp(Color(1.0, 0.25, 0.15, 1.0), heat)
		s.modulate = c
		add_child(s)

		var ang := rng.randf_range(0.0, TAU)
		var v := Vector2(cos(ang), sin(ang)) * rng.randf_range(_radius * 0.55, _radius * 1.05)
		if _dir.length() > 0.1:
			v = v.lerp(_dir.normalized() * _radius * 1.15, 0.55)
		s.position = Vector2.ZERO

		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "position", v, _duration)
		tw.parallel().tween_property(s, "modulate", Color(c.r, c.g, c.b, 0.0), _duration)

	# A quick cone flash (drawn)
	var tw2 := create_tween()
	tw2.tween_property(self, "scale", Vector2(1.25, 1.25), _duration * 0.55)
	tw2.finished.connect(queue_free)

func _draw() -> void:
	# Optional: a little triangular flash, oriented by dir if provided.
	var d := _dir.normalized() if _dir.length() > 0.1 else Vector2(0, -1)
	var right := d.rotated(0.85)
	var left := d.rotated(-0.85)
	var col := Color(_color.r, _color.g, _color.b, 0.18)
	var p0 := Vector2.ZERO
	var p1 := right * 22.0
	var p2 := left * 22.0
	draw_colored_polygon(PackedVector2Array([p0, p1, p2]), col)


