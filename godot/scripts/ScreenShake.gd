extends Node

# Lightweight camera shake + hit stop.

var _cam: Camera2D = null
var _base_offset: Vector2 = Vector2.ZERO

var _shake_t: float = 0.0
var _shake_dur: float = 0.0
var _shake_intensity: float = 0.0

var _hit_stop_running: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func shake(intensity: float = 8.0, duration: float = 0.15) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and is_instance_valid(sm):
		if sm.has_method("get") and bool(sm.get("screen_shake_enabled")) == false:
			return
		# Multiply by user slider if present.
		if sm.has_method("get"):
			intensity *= float(sm.get("screen_shake_intensity"))

	_ensure_camera()
	if _cam == null:
		return

	_shake_t = 0.0
	_shake_dur = maxf(0.01, duration)
	_shake_intensity = maxf(0.0, intensity)

func hit_stop(duration: float = 0.05) -> void:
	if _hit_stop_running:
		return
	_hit_stop_running = true
	var prev := Engine.time_scale
	Engine.time_scale = 0.1
	await get_tree().create_timer(maxf(0.01, duration), true, false, true).timeout
	Engine.time_scale = prev
	_hit_stop_running = false

func _process(delta: float) -> void:
	if _shake_dur <= 0.0 or _cam == null:
		return
	_shake_t += delta
	var a := clampf(_shake_t / _shake_dur, 0.0, 1.0)
	var fade := 1.0 - a
	var ox := randf_range(-1.0, 1.0)
	var oy := randf_range(-1.0, 1.0)
	_cam.offset = _base_offset + Vector2(ox, oy) * (_shake_intensity * fade)
	if a >= 1.0:
		_cam.offset = _base_offset
		_shake_dur = 0.0

func _ensure_camera() -> void:
	if _cam != null and is_instance_valid(_cam):
		return
	var p := get_tree().get_first_node_in_group("player") as Node
	if p != null and is_instance_valid(p) and p.has_node("Camera2D"):
		_cam = p.get_node("Camera2D") as Camera2D
		if _cam != null:
			_base_offset = _cam.offset



