extends Node2D

@onready var label: Label = get_node_or_null("Label")

var _life: float = 0.75
var _age: float = 0.0
var _vel: Vector2 = Vector2(0, -65)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if label == null:
		label = Label.new()
		label.name = "Label"
		add_child(label)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)

func setup(amount: int, color: Color, is_crit: bool) -> void:
	if label == null:
		return
	label.text = str(amount)
	label.add_theme_color_override("font_color", color)
	if is_crit:
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_constant_override("outline_size", 7)
		_vel = Vector2(0, -90)
		_life = 0.85

	# Pop scale
	scale = Vector2(0.85, 0.85)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.05, 1.05), 0.12)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.14)

func _process(delta: float) -> void:
	_age += delta
	position += _vel * delta
	_vel *= pow(0.25, delta) # damp
	var t := clampf(_age / maxf(0.001, _life), 0.0, 1.0)
	modulate.a = 1.0 - pow(t, 1.6)
	if _age >= _life:
		queue_free()


