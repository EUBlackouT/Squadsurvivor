extends Node

# Runs while paused and performs periodic run autosaves without ticking gameplay.
# Also drives the small "Autosaving..." HUD indicator.

var _main: Node = null
var _next_due_ms: int = 0
var _flash_until_ms: int = 0
var _last_save_ms: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_schedule_next()

func set_main(main_node: Node) -> void:
	_main = main_node
	_schedule_next()

func trigger_autosave(_reason: String = "") -> void:
	if _main == null or not is_instance_valid(_main):
		return
	if not bool(_main.get("autosave_enabled") if ("autosave_enabled" in _main) else true):
		return
	# Don't autosave after the run has ended.
	if bool(_main.get("_game_over") if ("_game_over" in _main) else false):
		return
	if bool(_main.get("_victory") if ("_victory" in _main) else false):
		return

	var now_ms: int = int(Time.get_ticks_msec())
	# Hard guard: never save more often than every 3 seconds.
	if _last_save_ms > 0 and (now_ms - _last_save_ms) < 3000:
		_flash_until_ms = now_ms + 450
		return

	var sv := get_node_or_null("/root/SaveManager")
	if sv == null or not is_instance_valid(sv) or not sv.has_method("save_run"):
		return

	sv.save_run(_main)
	_last_save_ms = now_ms
	_flash_until_ms = now_ms + 650
	_schedule_next()

func _process(_delta: float) -> void:
	var now_ms: int = int(Time.get_ticks_msec())
	if _next_due_ms > 0 and now_ms >= _next_due_ms:
		trigger_autosave("interval")

	_update_indicator(now_ms)

func _schedule_next() -> void:
	var now_ms: int = int(Time.get_ticks_msec())
	var interval_s := 25.0
	if _main != null and is_instance_valid(_main) and ("autosave_interval_seconds" in _main):
		interval_s = float(_main.get("autosave_interval_seconds"))
	interval_s = maxf(5.0, interval_s)
	_next_due_ms = now_ms + int(round(interval_s * 1000.0))

func _update_indicator(now_ms: int) -> void:
	if _main == null or not is_instance_valid(_main):
		return
	var al := _main.get_node_or_null("HUD/AutosaveLabel") as Label
	if al == null:
		return

	if now_ms < _flash_until_ms:
		al.visible = true
		var phase := int(now_ms / 200) % 4
		al.text = "Autosaving" + ".".repeat(phase)
		var rem := float(_flash_until_ms - now_ms)
		al.modulate.a = clampf(rem / 650.0, 0.0, 1.0)
	else:
		al.visible = false


