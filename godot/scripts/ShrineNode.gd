extends Area2D

@export var shrine_id: String = "war"
@export var display_name: String = "War Shrine"
@export var rarity: String = "normal" # normal | ultra
@export var radius: float = 34.0
@export var one_shot: bool = true

var _spent: bool = false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 3 # player body layer
	_apply_profile()
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		cs = CollisionShape2D.new()
		cs.name = "CollisionShape2D"
		add_child(cs)
	var shape := CircleShape2D.new()
	shape.radius = maxf(12.0, radius)
	cs.shape = shape
	cs.debug_color = Color(0, 0, 0, 0)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _spent or body == null or not is_instance_valid(body):
		return
	if not body.is_in_group("player"):
		return
	var main := get_tree().get_first_node_in_group("main")
	if main and is_instance_valid(main) and main.has_method("activate_map_shrine"):
		var accepted := bool(main.activate_map_shrine(self, shrine_id, display_name, rarity))
		if accepted and one_shot:
			_mark_spent()

func _mark_spent() -> void:
	_spent = true
	monitoring = false
	monitorable = false
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null:
		cs.disabled = true
	var structure := get_node_or_null("StructureSprite")
	if structure != null and structure is CanvasItem:
		(structure as CanvasItem).modulate = Color(0.62, 0.62, 0.68, 0.75)

func _apply_profile() -> void:
	var st := get_node_or_null("StructureSprite")
	if st == null:
		return
	var sheet := "res://assets/structures/shrines/war_shrine_sheet.webp"
	var h := 20
	var pulse := 0.18
	var spark := true
	var is_ultra := rarity.strip_edges().to_lower() == "ultra"
	match shrine_id:
		"war":
			display_name = "War Shrine"
			sheet = "res://assets/structures/shrines/war_shrine_sheet.webp"
			h = 22
			pulse = 0.22
			spark = true
		"greed":
			display_name = "Greed Shrine"
			sheet = "res://assets/structures/shrines/greed_shrine_sheet.webp"
			h = 20
			pulse = 0.20
			spark = true
		"frost":
			display_name = "Frost Shrine"
			sheet = "res://assets/structures/shrines/frost_shrine_sheet.webp"
			h = 19
			pulse = 0.16
			spark = false
		_:
			pass
	if is_ultra:
		display_name = "Golden " + display_name
		h += 2
		pulse += 0.10
	st.set("sheet_path", sheet)
	st.set("auto_detect_layout", false)
	st.set("hframes", 4)
	st.set("vframes", 4)
	st.set("fps", 8.0)
	st.set("animate", true)
	st.set("target_height_px", h)
	st.set("enable_pulse", true)
	st.set("pulse_amplitude", pulse)
	st.set("pulse_speed", 1.0)
	st.set("enable_sparks", spark)
	if st is CanvasItem:
		(st as CanvasItem).modulate = Color(1.0, 0.92, 0.58, 1.0) if is_ultra else Color(1, 1, 1, 1)
