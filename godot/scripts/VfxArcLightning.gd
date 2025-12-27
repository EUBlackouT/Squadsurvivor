extends Node2D

var _start: Vector2 = Vector2.ZERO
var _end: Vector2 = Vector2(64, 0)
var _color: Color = Color(0.55, 0.95, 1.0, 0.95)
var _life: float = 0.22
var _age: float = 0.0
var _segments: PackedVector2Array = PackedVector2Array()

func setup(start: Vector2, end: Vector2, color: Color) -> void:
	_start = start
	_end = end
	_color = color
	global_position = Vector2.ZERO
	_rebuild_segments()
	queue_redraw()

func _ready() -> void:
	top_level = true
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

func _process(delta: float) -> void:
	_age += delta
	modulate.a = 1.0 - clampf(_age / maxf(0.001, _life), 0.0, 1.0)
	if _age >= _life:
		queue_free()
		return
	# small jitter
	if int(_age * 60.0) % 2 == 0:
		_rebuild_segments()
		queue_redraw()

func _rebuild_segments() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	var segs: Array[Vector2] = []
	var dir := _end - _start
	var len := dir.length()
	var n: int = int(clampf(len / 18.0, 4.0, 14.0))
	for i in range(n + 1):
		var t := float(i) / float(n)
		var p := _start.lerp(_end, t)
		var jitter := (rng.randf() - 0.5) * 14.0
		var perp := Vector2(-dir.y, dir.x).normalized()
		if i != 0 and i != n:
			p += perp * jitter
		segs.append(p)
	_segments = PackedVector2Array(segs)

func _draw() -> void:
	if _segments.size() < 2:
		return
	var col := _color
	# thick glow underlay
	draw_polyline(_segments, Color(col.r, col.g, col.b, 0.35), 6.0, true)
	draw_polyline(_segments, Color(col.r, col.g, col.b, 0.75), 3.0, true)
	draw_polyline(_segments, Color(1, 1, 1, 0.9), 1.5, true)


