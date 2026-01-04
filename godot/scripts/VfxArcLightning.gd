extends Node2D

var _start: Vector2 = Vector2.ZERO
var _end: Vector2 = Vector2(64, 0)
var _color: Color = Color(0.55, 0.95, 1.0, 0.95)
var _life: float = 0.22
var _age: float = 0.0
var _segments: PackedVector2Array = PackedVector2Array()
var _branches: Array[PackedVector2Array] = []
var _mat: CanvasItemMaterial = null

func setup(start: Vector2, end: Vector2, color: Color) -> void:
	_start = start
	_end = end
	_color = color
	global_position = Vector2.ZERO
	_rebuild_segments()
	queue_redraw()

func _ready() -> void:
	top_level = true
	# IMPORTANT: this VFX must tick during gameplay; WHEN_PAUSED would freeze it on-screen.
	process_mode = Node.PROCESS_MODE_INHERIT
	set_process(true)
	# Additive blend makes lightning feel energetic without textures.
	_mat = CanvasItemMaterial.new()
	_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = _mat

func _process(delta: float) -> void:
	_age += delta
	var fade := 1.0 - clampf(_age / maxf(0.001, _life), 0.0, 1.0)
	var flicker := 0.78 + 0.22 * sin(_age * 48.0)
	modulate.a = fade * flicker
	if _age >= _life:
		queue_free()
		return
	# small jitter
	if int(_age * 90.0) % 2 == 0:
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

	# Branches: a couple of short offshoots to sell "electricity".
	_branches = []
	if n >= 5:
		var branch_count := rng.randi_range(1, 3)
		for b in range(branch_count):
			var idx := rng.randi_range(2, n - 2)
			var bp := _segments[idx]
			var base_dir := (_segments[idx + 1] - _segments[idx - 1]).normalized()
			var perp2 := Vector2(-base_dir.y, base_dir.x)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var out_dir := (base_dir.rotated(side * rng.randf_range(0.6, 1.2)) + perp2 * side * rng.randf_range(0.35, 0.85)).normalized()
			var blen := minf(28.0, len * rng.randf_range(0.12, 0.22))
			var bn := rng.randi_range(3, 5)
			var bsegs: Array[Vector2] = []
			for i in range(bn + 1):
				var t := float(i) / float(bn)
				var p := bp + out_dir * blen * t
				if i != 0 and i != bn:
					p += perp2 * side * (rng.randf() - 0.5) * 10.0 * (1.0 - t)
				bsegs.append(p)
			_branches.append(PackedVector2Array(bsegs))

func _draw() -> void:
	if _segments.size() < 2:
		return
	var col := _color
	# Core bolt (layered glow -> core)
	draw_polyline(_segments, Color(col.r, col.g, col.b, 0.18), 10.0, true)
	draw_polyline(_segments, Color(col.r, col.g, col.b, 0.55), 5.0, true)
	draw_polyline(_segments, Color(1, 1, 1, 0.95), 2.0, true)

	# Branches (thinner)
	for b in _branches:
		if b.size() < 2:
			continue
		draw_polyline(b, Color(col.r, col.g, col.b, 0.22), 6.0, true)
		draw_polyline(b, Color(1, 1, 1, 0.75), 1.5, true)


