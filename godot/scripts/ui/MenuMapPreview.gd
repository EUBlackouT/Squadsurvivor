class_name MenuMapPreview
extends TextureRect

## Full-screen map preview with shader-driven smooth pan (no chunky node motion).

const _PAN_SHADER := preload("res://shaders/menu_map_pan.gdshader")

static var _map_tex_cache: Dictionary = {}

var _mat: ShaderMaterial
var _anim_t: float = 0.0
var pan_speed: float = 1.0
var zoom_base: float = 1.04
var vignette_strength: float = 0.12
var brightness: float = 1.14
var saturation: float = 1.18
var crisp_pixels: bool = false

static func load_map_texture(map_id: String, m: Dictionary) -> Texture2D:
	if _map_tex_cache.has(map_id):
		return _map_tex_cache[map_id] as Texture2D
	var tex: Texture2D = null
	var meta_path := String(m.get("metadata_path", ""))
	if not meta_path.is_empty() and FileAccess.file_exists(meta_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			var src := String((parsed as Dictionary).get("source_image", ""))
			if not src.is_empty():
				var full := meta_path.get_base_dir().path_join(src)
				if ResourceLoader.exists(full):
					tex = load(full) as Texture2D
	if tex == null:
		var thumb := "res://assets/maps/thumbs/%s.webp" % map_id
		if ResourceLoader.exists(thumb):
			tex = load(thumb) as Texture2D
	_map_tex_cache[map_id] = tex
	return tex

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if crisp_pixels else CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = _PAN_SHADER
	_mat.set_shader_parameter("vignette_strength", vignette_strength)
	_mat.set_shader_parameter("brightness", brightness)
	_mat.set_shader_parameter("saturation", saturation)
	material = _mat
	set_process(true)
	call_deferred("_sync_shader_sizes")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_shader_sizes()

func _sync_shader_sizes() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("rect_size", size)
	if texture != null:
		_mat.set_shader_parameter("tex_size", texture.get_size())

func _process(delta: float) -> void:
	if _mat == null:
		return
	_anim_t += delta * pan_speed
	# Lissajous drift — continuous sub-pixel motion, no stepped node translation.
	var t := _anim_t
	_mat.set_shader_parameter("pan", Vector2(
		sin(t * 0.11) * 0.11 + sin(t * 0.047) * 0.04,
		cos(t * 0.093) * 0.08 + cos(t * 0.051) * 0.035
	))
	_mat.set_shader_parameter("zoom", zoom_base + sin(t * 0.061) * 0.028)

func set_preview_texture(tex: Texture2D) -> void:
	texture = tex
	if _mat != null:
		_sync_shader_sizes()
	else:
		call_deferred("_sync_shader_sizes")
