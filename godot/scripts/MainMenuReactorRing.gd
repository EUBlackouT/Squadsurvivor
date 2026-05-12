extends Node2D

# Decorative animated reactor ring for main menu background.
# Lightweight procedural draw so no extra texture slicing is needed.

@export var radius: float = 174.0
@export var thickness: float = 24.0
@export var glow_color: Color = Color(0.38, 0.98, 1.0, 0.66)
@export var frame_color: Color = Color(0.10, 0.16, 0.24, 0.72)

var _t: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	z_index = -165

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	# Outer ring frame
	draw_arc(Vector2.ZERO, radius + 8.0, 0.0, TAU, 88, frame_color, thickness + 8.0, true)
	draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 88, Color(0.42, 0.48, 0.56, 0.35), 2.0, true)

	# Rotating glow segments
	var seg_count := 12
	var seg_len := TAU / float(seg_count) * 0.58
	var base := _t * 0.42
	for i in range(seg_count):
		var a0 := base + float(i) * TAU / float(seg_count)
		var a1 := a0 + seg_len
		var alpha := 0.18 + 0.52 * (0.5 + 0.5 * sin(_t * 1.3 + float(i) * 0.9))
		var col := Color(glow_color.r, glow_color.g, glow_color.b, alpha)
		draw_arc(Vector2.ZERO, radius, a0, a1, 14, col, thickness, true)

	# Inner rotating marker ring
	var inner := radius - 38.0
	var marker_count := 18
	var m_base := -_t * 0.68
	for j in range(marker_count):
		var a := m_base + float(j) * TAU / float(marker_count)
		var p := Vector2(cos(a), sin(a)) * inner
		draw_circle(p, 2.0, Color(0.72, 0.86, 1.0, 0.46))

	# Center core pulse
	var core_r := 44.0 + sin(_t * 1.9) * 3.0
	draw_circle(Vector2.ZERO, core_r, Color(0.18, 0.54, 0.72, 0.10))
	draw_circle(Vector2.ZERO, core_r * 0.58, Color(0.34, 0.86, 1.0, 0.08))
