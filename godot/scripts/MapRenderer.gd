extends Node2D

# Removable "pretty map" layer:
# - Procedural ground (shader) that follows the camera so it fills the screen.
# - Optional soft fog overlay.
# - Optional world props (StructureSprite) sprinkled across the map for richness.
#
# To remove later: delete MapRenderer scene and set Main.gd `use_rich_map = false`.

@export var map_size: Vector2 = Vector2(4800, 3600)
@export var theme_id: String = "graveyard" # graveyard | arcane_ruins
@export var seed: int = 0

@export var follow_margin_px: float = 260.0

@export var fog_enabled: bool = true
@export var fog_strength: float = 0.16

@export var spawn_props: bool = true
@export var prop_count: int = 42
@export var prop_min_dist_from_center: float = 260.0

@onready var ground: Sprite2D = get_node_or_null("Ground") as Sprite2D
@onready var fog: Sprite2D = get_node_or_null("Fog") as Sprite2D
@onready var props: Node2D = get_node_or_null("Props") as Node2D

var _rng: RandomNumberGenerator
var _ground_mat: ShaderMaterial
var _fog_mat: ShaderMaterial
var _white_tex: Texture2D
var _t: float = 0.0

func _ready() -> void:
	_init_rng()
	_setup_textures()
	_setup_ground()
	_setup_fog()
	_apply_theme(theme_id)
	if spawn_props:
		_spawn_world_props()

func _init_rng() -> void:
	_rng = RandomNumberGenerator.new()
	if seed == 0:
		_rng.seed = int(Time.get_unix_time_from_system())
	else:
		_rng.seed = seed

func _setup_textures() -> void:
	if _white_tex != null:
		return
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white_tex = ImageTexture.create_from_image(img)

func _setup_ground() -> void:
	if ground == null:
		ground = Sprite2D.new()
		ground.name = "Ground"
		add_child(ground)
	ground.texture = _white_tex
	ground.centered = true
	ground.z_index = -100

	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = preload("res://shaders/map_ground_rich.gdshader")
	ground.material = _ground_mat

func _setup_fog() -> void:
	if fog == null:
		fog = Sprite2D.new()
		fog.name = "Fog"
		add_child(fog)
	fog.texture = _white_tex
	fog.centered = true
	fog.z_index = -50
	fog.visible = fog_enabled

	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = preload("res://shaders/map_fog_soft.gdshader")
	_fog_mat.set_shader_parameter("u_strength", fog_strength)
	fog.material = _fog_mat

func _apply_theme(id: String) -> void:
	if _ground_mat == null:
		return

	match id:
		"arcane_ruins":
			_ground_mat.set_shader_parameter("u_base_color", Color(0.07, 0.10, 0.13, 1.0))
			_ground_mat.set_shader_parameter("u_alt_color", Color(0.10, 0.13, 0.18, 1.0))
			_ground_mat.set_shader_parameter("u_accent_color", Color(0.22, 0.35, 0.48, 1.0))
			_ground_mat.set_shader_parameter("u_scale", 0.018)
			_ground_mat.set_shader_parameter("u_detail_scale", 0.10)
			_ground_mat.set_shader_parameter("u_crack_strength", 0.95)
			_ground_mat.set_shader_parameter("u_grit_strength", 0.65)
			_ground_mat.set_shader_parameter("u_vignette", 0.30)
			if _fog_mat != null:
				_fog_mat.set_shader_parameter("u_fog_color", Color(0.55, 0.75, 0.95, 1.0))
		_:
			# graveyard default: slate + mossy accents
			_ground_mat.set_shader_parameter("u_base_color", Color(0.08, 0.10, 0.12, 1.0))
			_ground_mat.set_shader_parameter("u_alt_color", Color(0.12, 0.13, 0.16, 1.0))
			_ground_mat.set_shader_parameter("u_accent_color", Color(0.18, 0.22, 0.18, 1.0))
			_ground_mat.set_shader_parameter("u_scale", 0.020)
			_ground_mat.set_shader_parameter("u_detail_scale", 0.092)
			_ground_mat.set_shader_parameter("u_crack_strength", 1.05)
			_ground_mat.set_shader_parameter("u_grit_strength", 0.85)
			_ground_mat.set_shader_parameter("u_vignette", 0.40)
			if _fog_mat != null:
				_fog_mat.set_shader_parameter("u_fog_color", Color(0.60, 0.74, 0.66, 1.0))

func _process(delta: float) -> void:
	_update_ground_follow()
	_update_fog_follow(delta)

func _find_camera() -> Camera2D:
	var player := get_tree().get_first_node_in_group("player") as Node
	if player != null and is_instance_valid(player) and player.has_node("Camera2D"):
		return player.get_node("Camera2D") as Camera2D
	return null

func _update_ground_follow() -> void:
	if ground == null or _ground_mat == null:
		return

	var cam := _find_camera()
	var cam_pos := cam.global_position if cam != null else Vector2.ZERO
	var zoom := cam.zoom if cam != null else Vector2.ONE
	zoom.x = maxf(0.0001, zoom.x)
	zoom.y = maxf(0.0001, zoom.y)

	var vp_px := get_viewport().get_visible_rect().size
	var world_vp := Vector2(vp_px.x / zoom.x, vp_px.y / zoom.y)
	var size := world_vp + Vector2(follow_margin_px * 2.0, follow_margin_px * 2.0)

	ground.global_position = cam_pos
	ground.scale = size # texture is 1×1
	_ground_mat.set_shader_parameter("u_world_origin", cam_pos - size * 0.5)
	_ground_mat.set_shader_parameter("u_world_size", size)

func _update_fog_follow(delta: float) -> void:
	if fog == null or _fog_mat == null:
		return
	if not fog_enabled:
		fog.visible = false
		return

	fog.visible = true
	_fog_mat.set_shader_parameter("u_strength", fog_strength)

	var cam := _find_camera()
	var cam_pos := cam.global_position if cam != null else Vector2.ZERO
	var zoom := cam.zoom if cam != null else Vector2.ONE
	zoom.x = maxf(0.0001, zoom.x)
	zoom.y = maxf(0.0001, zoom.y)

	var vp_px := get_viewport().get_visible_rect().size
	var world_vp := Vector2(vp_px.x / zoom.x, vp_px.y / zoom.y)
	var size := world_vp + Vector2(follow_margin_px * 2.0, follow_margin_px * 2.0)

	fog.global_position = cam_pos
	fog.scale = size

	_t += delta
	_fog_mat.set_shader_parameter("u_time", _t)
	_fog_mat.set_shader_parameter("u_world_origin", cam_pos - size * 0.5)
	_fog_mat.set_shader_parameter("u_world_size", size)

func _try_set(obj: Object, prop: StringName, value: Variant) -> void:
	# Safe optional property sets (avoids hard dependency on exact node script).
	if obj == null:
		return
	for pd in obj.get_property_list():
		if StringName(String((pd as Dictionary).get("name", ""))) == prop:
			obj.set(prop, value)
			return

func _spawn_world_props() -> void:
	if props == null:
		props = Node2D.new()
		props.name = "Props"
		add_child(props)

	# Reuse existing structure sheets in repo.
	var sheets: Array[String] = []
	if theme_id == "arcane_ruins":
		sheets = [
			"res://assets/structures/arcane_cube_sheet.png",
			"res://assets/structures/obelisk_sheet.png",
		]
	else:
		sheets = [
			"res://assets/structures/obelisk_sheet.png",
			"res://assets/structures/green_fountain_sheet.png",
		]

	var structure_scene := preload("res://scenes/StructureSprite.tscn")
	var half := map_size * 0.5

	var tries: int = 0
	var placed: int = 0
	while placed < prop_count and tries < prop_count * 20:
		tries += 1

		var p := Vector2(
			_rng.randf_range(-half.x, half.x),
			_rng.randf_range(-half.y, half.y)
		)
		if p.length() < prop_min_dist_from_center:
			continue

		var n := structure_scene.instantiate()
		props.add_child(n)
		n.global_position = p

		var sheet := sheets[_rng.randi_range(0, sheets.size() - 1)]
		_try_set(n, &"sheet_path", sheet)
		_try_set(n, &"animate", false)
		_try_set(n, &"enable_pulse", true)
		_try_set(n, &"pulse_amplitude", 0.08)
		_try_set(n, &"pulse_speed", _rng.randf_range(0.65, 1.1))
		_try_set(n, &"target_height_px", _rng.randi_range(48, 92))
		_try_set(n, &"pad_px", 1)

		n.z_index = int(round(n.global_position.y / 10.0))
		placed += 1
