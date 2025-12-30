class_name EnemyBolt
extends Node2D

# Enemy projectile (no collision shapes). Hits squad units with take_damage(int).

@export var speed: float = 520.0
@export var damage: int = 6
@export var hit_radius: float = 12.0

var target: Node2D = null
var _main: Node2D = null

@onready var sprite: Sprite2D = null

func _ready() -> void:
	add_to_group("enemy_projectiles")
	_main = get_tree().get_first_node_in_group("main") as Node2D

	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	add_child(sprite)
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.scale = Vector2(1.6, 1.6)
	sprite.z_index = 22

	# Auto cleanup
	await get_tree().create_timer(2.2).timeout
	queue_free()

func setup_target(t: Node2D, dmg: int, tint: Color, p_speed: float = 520.0) -> void:
	target = t
	damage = dmg
	speed = p_speed
	if sprite != null:
		sprite.modulate = tint

func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	var dir := (target.global_position - global_position)
	var dist := dir.length()
	if dist <= 1.0:
		queue_free()
		return
	dir = dir / dist
	global_position += dir * speed * delta
	rotation = dir.angle()
	_manual_hit_check()

func _manual_hit_check() -> void:
	var r2 := hit_radius * hit_radius
	var squad: Array = []
	if _main and is_instance_valid(_main) and _main.has_method("get_cached_squad_units"):
		squad = _main.get_cached_squad_units()
	else:
		squad = get_tree().get_nodes_in_group("squad_units")
	for u in squad:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(global_position) <= r2:
			if n2.has_method("take_damage"):
				n2.take_damage(damage)
			queue_free()
			return


