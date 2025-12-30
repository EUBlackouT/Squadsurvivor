extends Area2D

@export var radius: float = 36.0

func _ready() -> void:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		cs = CollisionShape2D.new()
		cs.name = "CollisionShape2D"
		add_child(cs)
	var shape := CircleShape2D.new()
	shape.radius = radius
	cs.shape = shape
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group("player"):
		return
	var main := get_tree().get_first_node_in_group("main")
	if main and is_instance_valid(main) and main.has_method("start_rift_encounter"):
		main.start_rift_encounter(self)


