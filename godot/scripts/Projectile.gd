extends Area2D

@export var speed: float = 520.0
@export var damage: int = 10
@export var pierce_count: int = 0

var target: Node2D = null
var target_pos: Vector2 = Vector2.ZERO
var has_hit: bool = false
var is_crit: bool = false
var passive_ids: PackedStringArray = PackedStringArray()
var _pierced_enemies: Array[Node2D] = []

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var collision: CollisionShape2D = get_node_or_null("CollisionShape2D")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT

	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)
	# Placeholder bullet sprite (tinted by class)
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2(2.0, 2.0)
	sprite.z_index = 20

	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		add_child(collision)
		var shape := CircleShape2D.new()
		shape.radius = 10.0
		collision.shape = shape

	# Physics: projectiles = layer 1, hit enemies layer 2
	collision_layer = 1
	collision_mask = 1 << 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)

	# Auto cleanup
	await get_tree().create_timer(4.0).timeout
	queue_free()

func set_vfx_color(c: Color) -> void:
	if sprite:
		sprite.modulate = c

func setup(dest: Vector2, dmg: int) -> void:
	target = null
	target_pos = dest
	damage = dmg
	_update_rotation()

func setup_target(t: Node2D, dmg: int, p_is_crit: bool, p_passive_ids: PackedStringArray) -> void:
	target = t
	target_pos = t.global_position if t != null and is_instance_valid(t) else target_pos
	damage = dmg
	is_crit = p_is_crit
	passive_ids = p_passive_ids
	pierce_count += PassiveSystem.extra_pierce_count(passive_ids)
	_update_rotation()

func _physics_process(delta: float) -> void:
	if has_hit and pierce_count <= 0:
		return
	if target != null and is_instance_valid(target):
		target_pos = target.global_position
	var dir := (target_pos - global_position)
	var dist := dir.length()
	if dist <= 1.0:
		_explode()
		return
	dir = dir / dist
	global_position += dir * speed * delta
	rotation = dir.angle()
	if dist < 12.0:
		_explode()

func _on_body_entered(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group("enemies"):
		return
	_hit_enemy(body as Node2D)

func _hit_enemy(enemy: Node2D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if has_hit and pierce_count <= 0:
		return
	if _pierced_enemies.has(enemy):
		return

	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, is_crit, "ranged")
	_pierced_enemies.append(enemy)
	PassiveSystem.on_projectile_hit(passive_ids, self, enemy, damage, is_crit)

	if pierce_count > 0:
		pierce_count -= 1
		if pierce_count <= 0:
			_explode()
	else:
		_explode()

func _explode() -> void:
	queue_free()

func _update_rotation() -> void:
	var dir := (target_pos - global_position)
	if dir.length() > 0.0:
		rotation = dir.angle()
