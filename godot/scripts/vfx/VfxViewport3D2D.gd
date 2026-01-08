class_name VfxViewport3D2D
extends Node2D

# Renders a 3D effect scene into a SubViewport and displays it in 2D via Sprite2D.
# Use for effects that must look exactly like the original 3D EffectBlocks scene (e.g. healing aura).

var _sub: SubViewport
var _root3d: Node3D
var _cam: Camera3D
var _sprite: Sprite2D
var _env: WorldEnvironment = null
var _hide_node_names: PackedStringArray = PackedStringArray()

var _lifetime_s: float = 1.0
var _t: float = 0.0
var _loop: bool = false

func setup(scene_3d: PackedScene, viewport_size: int = 256, ortho_size: float = 4.0, cam_pos: Vector3 = Vector3(0, 0, 100), cam_target: Vector3 = Vector3.ZERO, cam_up: Vector3 = Vector3.UP, light_energy: float = 1.0, duration_s: float = 1.0, loop: bool = false, force_emit: bool = true, pixel_material: ShaderMaterial = null, pixel_target_px: int = 256, hide_node_names: PackedStringArray = PackedStringArray(), pixel_params: Dictionary = {}) -> void:
	_loop = loop
	_lifetime_s = maxf(0.05, duration_s)
	_t = 0.0
	_hide_node_names = hide_node_names

	_sub = SubViewport.new()
	_sub.name = "VfxViewport"
	_sub.size = Vector2i(viewport_size, viewport_size)
	_sub.transparent_bg = true
	_sub.own_world_3d = true
	_sub.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub)

	_root3d = Node3D.new()
	_root3d.name = "Root3D"
	_sub.add_child(_root3d)

	# Match PixelRenderer's "glow" look (helps ring/aura read, reduces harsh particles).
	_env = WorldEnvironment.new()
	var e := Environment.new()
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	_env.environment = e
	_root3d.add_child(_env)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = ortho_size
	_cam.near = 0.01
	_cam.far = 200.0
	_root3d.add_child(_cam)
	_cam.position = cam_pos
	_cam.look_at_from_position(cam_pos, cam_target, cam_up)
	_cam.make_current()

	var sun := DirectionalLight3D.new()
	sun.light_energy = light_energy
	sun.rotation_degrees = Vector3(-75, 0, 0)
	_root3d.add_child(sun)

	if scene_3d != null:
		var inst := scene_3d.instantiate()
		_root3d.add_child(inst)
		if inst is Node3D:
			(inst as Node3D).position = Vector3.ZERO
			(inst as Node3D).rotation = Vector3.ZERO
		_apply_hide_list(inst)
		if force_emit:
			_force_emit(inst)

	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_sprite.centered = true
	_sprite.texture = _sub.get_texture()
	_sprite.z_index = 2000
	if pixel_material != null:
		var pm := pixel_material.duplicate() as ShaderMaterial
		if pm != null:
			pm.set_shader_parameter("target_pixel_count", int(pixel_target_px))
			# Optional PixelArt shader tuning for visibility/readability.
			for k in pixel_params.keys():
				pm.set_shader_parameter(StringName(String(k)), pixel_params.get(k))
			_sprite.material = pm
	add_child(_sprite)

func _process(delta: float) -> void:
	_t += delta
	if _loop:
		return
	if _t >= _lifetime_s:
		queue_free()

func _force_emit(n: Node) -> void:
	if n == null:
		return
	if n is GPUParticles3D:
		var p := n as GPUParticles3D
		p.emitting = true
		p.restart()
	elif n is CPUParticles3D:
		var p2 := n as CPUParticles3D
		p2.emitting = true
		p2.restart()
	for c in n.get_children():
		_force_emit(c)

func _apply_hide_list(n: Node) -> void:
	# Hide specific sub-nodes by name (used to remove "flame blob" particles while keeping ring/aura).
	if n == null or _hide_node_names.is_empty():
		return
	_apply_hide_list_rec(n)

func _apply_hide_list_rec(n: Node) -> void:
	if n == null:
		return
	if _hide_node_names.has(n.name):
		if n is GPUParticles3D:
			(n as GPUParticles3D).emitting = false
		if n is CPUParticles3D:
			(n as CPUParticles3D).emitting = false
		if n is Node3D:
			(n as Node3D).visible = false
		elif n is CanvasItem:
			(n as CanvasItem).visible = false
	for c in n.get_children():
		_apply_hide_list_rec(c)


