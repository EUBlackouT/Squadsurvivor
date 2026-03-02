extends Node2D

# Minimal test harness for TestMarine.tscn to avoid missing script errors.
# Keeps behavior simple: move DummyTarget with WASD.

@export var move_speed: float = 260.0

var _dummy: Node2D = null

func _ready() -> void:
	_dummy = get_node_or_null("DummyTarget") as Node2D

func _process(delta: float) -> void:
	if _dummy == null:
		return
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("ui_right"):
		dir.x += 1.0
	if Input.is_action_pressed("ui_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("ui_down"):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		_dummy.position += dir.normalized() * move_speed * delta
