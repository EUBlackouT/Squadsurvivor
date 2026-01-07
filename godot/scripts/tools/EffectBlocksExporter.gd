extends Node3D

# One-click exporter for EffectBlocks → 2D flipbooks.
# Run the scene `res://scenes/EffectBlocksExport.tscn` from the editor.
#
# Reads `res://data/effectblocks_export.json` and exports PNG sequences into:
#   res://assets/vfx/effectblocks/<effect_key>/<effect_key>_0000.png ...

const CFG := "res://data/effectblocks_export.json"

@export var clear_existing: bool = true
@export var camera_size: float = 4.0 # Orthographic size; tweak if frames are too zoomed.
@export var light_energy: float = 1.0

var _cfg: Dictionary = {}

var _sub: SubViewport
var _cam: Camera3D
var _root3d: Node3D
var _preview_layer: CanvasLayer
var _preview_rect: TextureRect
var _dir_root: String = "res://assets/vfx/effectblocks"

func _ready() -> void:
	_load_cfg()
	_setup_render()
	await get_tree().process_frame
	# Sanity check: ensure the SubViewport can render ANY 3D content.
	if not await _probe_viewport():
		push_error("EffectBlocksExporter: SubViewport probe failed (captured blank image). Aborting export.")
		return
	await _export_all()
	# If the game/editor is open, clear VfxSystem cache so new exports show immediately.
	var v := get_node_or_null("/root/VfxSystem")
	if v and is_instance_valid(v) and v.has_method("clear_cache"):
		v.clear_cache()
	print("EffectBlocksExporter: done")

func _load_cfg() -> void:
	if not ResourceLoader.exists(CFG):
		push_error("EffectBlocksExporter: missing " + CFG)
		return
	var txt := FileAccess.get_file_as_string(CFG)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("EffectBlocksExporter: invalid JSON in " + CFG)
		return
	_cfg = parsed as Dictionary
	_dir_root = String(_cfg.get("export_root", _dir_root))

func _setup_render() -> void:
	_sub = SubViewport.new()
	_sub.name = "CaptureViewport"
	_sub.size = Vector2i(512, 512)
	_sub.transparent_bg = true
	# IMPORTANT: SubViewport won't render 3D without a current Camera3D for that viewport.
	_sub.own_world_3d = true
	_sub.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub)

	_root3d = Node3D.new()
	_root3d.name = "Root3D"
	_sub.add_child(_root3d)

	# Ensure the SubViewport texture is actually "used" (some builds won't render otherwise).
	_preview_layer = CanvasLayer.new()
	_preview_layer.name = "ViewportPreviewLayer"
	add_child(_preview_layer)
	_preview_rect = TextureRect.new()
	_preview_rect.name = "ViewportPreview"
	_preview_rect.texture = _sub.get_texture()
	_preview_rect.position = Vector2.ZERO
	_preview_rect.size = Vector2(8, 8)
	_preview_rect.custom_minimum_size = Vector2(8, 8)
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_rect.modulate = Color(1, 1, 1, 0.02) # effectively invisible, but still drawn
	_preview_layer.add_child(_preview_rect)

	# Camera
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = camera_size
	_cam.near = 0.01
	_cam.far = 200.0
	# Top-down-ish angle
	_root3d.add_child(_cam)
	_cam.position = Vector3(0, 6, 6)
	# `look_at()` requires the node to be inside the tree in some builds.
	_cam.look_at_from_position(_cam.position, Vector3.ZERO, Vector3.UP)
	_cam.make_current()

	# Light
	var sun := DirectionalLight3D.new()
	sun.light_energy = light_energy
	sun.rotation_degrees = Vector3(-55, 35, 0)
	_root3d.add_child(sun)

func _export_all() -> void:
	var jobs: Array = _cfg.get("jobs", [])
	for j in jobs:
		if typeof(j) != TYPE_DICTIONARY:
			continue
		var d := j as Dictionary
		await _export_job(d)

func _export_job(d: Dictionary) -> void:
	var effect_key := String(d.get("effect_key", ""))
	var scene_path := String(d.get("scene", ""))
	var frames := int(d.get("frames", 16))
	var fps := int(d.get("fps", 12))
	var res := int(d.get("resolution", 192))
	if effect_key == "" or scene_path == "" or frames <= 0:
		return
	if not ResourceLoader.exists(scene_path):
		push_warning("EffectBlocksExporter: missing scene " + scene_path)
		return

	# Resize viewport for this job.
	_sub.size = Vector2i(res, res)

	var out_dir := "%s/%s" % [_dir_root, effect_key]
	if clear_existing:
		_clear_dir(out_dir)
	_ensure_dir(out_dir)

	# Instantiate effect
	for c in _root3d.get_children():
		if c != _cam and not (c is DirectionalLight3D):
			c.queue_free()
	await get_tree().process_frame

	var ps := load(scene_path) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate()
	_root3d.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).position = Vector3.ZERO
		(inst as Node3D).rotation = Vector3.ZERO

	# Kick particles on (many EffectBlocks scenes start with emitting=false)
	_force_emit(inst)
	# Give particles/shaders time to initialize.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.10).timeout

	# Capture frames
	print("Exporting %s (%s) -> %s  frames=%d fps=%d res=%d" % [effect_key, scene_path, out_dir, frames, fps, res])
	var step_s := 1.0 / maxf(1.0, float(fps))
	for i in range(frames):
		# Let the renderer breathe
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := _sub.get_texture().get_image()
		if img == null:
			continue
		# Sanity check: if the viewport isn't rendering, images will be fully transparent.
		if i == 0 and img.get_used_rect().size == Vector2i.ZERO:
			push_warning("EffectBlocksExporter: captured blank frame for %s. Camera/viewport not rendering." % effect_key)
		img.convert(Image.FORMAT_RGBA8)
		var fname := "%s_%04d.png" % [effect_key, i]
		var p := out_dir.path_join(fname)
		var err := img.save_png(p)
		if err != OK:
			push_warning("EffectBlocksExporter: failed save " + p + " err=" + str(err))
		# Advance time for effect
		await get_tree().create_timer(step_s).timeout

func _probe_viewport() -> bool:
	# Render a bright unshaded cube and confirm pixels are non-empty.
	# If this fails, all exports will be blank regardless of effect scenes.
	# Remove any existing non-camera children
	for c in _root3d.get_children():
		if c != _cam and not (c is DirectionalLight3D):
			c.queue_free()
	await get_tree().process_frame

	var mi := MeshInstance3D.new()
	mi.name = "ProbeCube"
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.2, 0.9, 1.0)
	mi.material_override = mat
	_root3d.add_child(mi)

	# Wait a few frames for render
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _sub.get_texture().get_image()
	if img == null:
		return false
	# If used rect is empty, nothing was drawn.
	if img.get_used_rect().size == Vector2i.ZERO:
		return false
	return true

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

func _ensure_dir(dir_path: String) -> void:
	# Support res://, user:// and absolute OS paths.
	var abs_path := ProjectSettings.globalize_path(dir_path)
	if DirAccess.dir_exists_absolute(abs_path):
		return
	var err := DirAccess.make_dir_recursive_absolute(abs_path)
	if err != OK:
		push_warning("EffectBlocksExporter: failed to create dir " + dir_path + " err=" + str(err))

func _clear_dir(dir_path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	d.list_dir_begin()
	while true:
		var f := d.get_next()
		if f == "":
			break
		if d.current_is_dir():
			continue
		var lf := f.to_lower()
		if lf.ends_with(".png") or lf.ends_with(".png.import"):
			d.remove(f)
	d.list_dir_end()


