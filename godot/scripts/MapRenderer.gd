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

# Optional per-map visuals (from RunConfig maps.json). If provided, overrides theme_id defaults.
# Expected keys (all optional):
# - theme_id: String
# - base_color/alt_color/accent_color/fog_color/rune_color: "#RRGGBB" strings or Color
# - fog_strength: float
# - prop_count: int
# - prop_sheets: Array[String]
# - rune_strength: float
# - light_strength: float
# - vignette: float
@export var map_visuals: Dictionary = {}

@export var follow_margin_px: float = 260.0

@export var fog_enabled: bool = true
@export var fog_strength: float = 0.16

# For UI previews: adds gentle animated pan so the preview feels alive.
@export var preview_pan_px: float = 0.0
@export var preview_pan_speed: float = 0.18

@export var spawn_props: bool = true
@export var prop_count: int = 42
@export var prop_min_dist_from_center: float = 260.0

@onready var ground: Sprite2D = get_node_or_null("Ground") as Sprite2D
@onready var fog: Sprite2D = get_node_or_null("Fog") as Sprite2D
@onready var props: Node2D = get_node_or_null("Props") as Node2D
@onready var bg_image: Sprite2D = get_node_or_null("BgImage") as Sprite2D
@onready var rays: Sprite2D = get_node_or_null("Rays") as Sprite2D
@onready var atmo: Sprite2D = get_node_or_null("Atmosphere") as Sprite2D

var _rng: RandomNumberGenerator
var _ground_mat: ShaderMaterial
var _fog_mat: ShaderMaterial
var _rays_mat: ShaderMaterial
var _atmo_mat: ShaderMaterial
var _white_tex: Texture2D
var _t: float = 0.0

static var _bg_cache: Dictionary = {} # key:String -> Texture2D

func _ready() -> void:
	_init_rng()
	_setup_textures()
	_setup_bg_image()
	_setup_ground()
	_setup_fog()
	_setup_rays()
	_setup_atmosphere()
	# Apply map-provided visuals first; fallback to built-in theme defaults.
	if not map_visuals.is_empty():
		_apply_visuals(map_visuals)
	else:
		_apply_theme(theme_id)
	if spawn_props:
		_spawn_world_props()

func _color_from(v: Variant, fallback: Color) -> Color:
	if typeof(v) == TYPE_COLOR:
		return v as Color
	if typeof(v) == TYPE_STRING:
		var s := String(v).strip_edges()
		if s != "":
			return Color(s)
	return fallback

func _float_from(v: Variant, fallback: float) -> float:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v)
	return fallback

func _int_from(v: Variant, fallback: int) -> int:
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT:
		return int(round(float(v)))
	return fallback

func _strings_from(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_ARRAY:
		for it in (v as Array):
			out.append(String(it))
	return out

# Math helpers (GDScript, not shaders)
func _fracf(v: float) -> float:
	return v - floor(v)

func _stepf(edge: float, v: float) -> float:
	return 1.0 if v >= edge else 0.0

func _smoothstepf(edge0: float, edge1: float, x: float) -> float:
	var d := edge1 - edge0
	if absf(d) < 0.0000001:
		return 0.0
	var t := clampf((x - edge0) / d, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _apply_visuals(vis: Dictionary) -> void:
	if _ground_mat == null:
		return

	# Allow visuals to override theme_id for prop defaults.
	var tid := String(vis.get("theme_id", theme_id))
	theme_id = tid

	# Colors
	var base := _color_from(vis.get("base_color"), Color(0.08, 0.10, 0.12, 1.0))
	var alt := _color_from(vis.get("alt_color"), Color(0.12, 0.13, 0.16, 1.0))
	var acc := _color_from(vis.get("accent_color"), Color(0.18, 0.22, 0.18, 1.0))
	_ground_mat.set_shader_parameter("u_base_color", base)
	_ground_mat.set_shader_parameter("u_alt_color", alt)
	_ground_mat.set_shader_parameter("u_accent_color", acc)

	# Background image (hybrid approach):
	# - If `bg_image_path` exists, load it.
	# - Otherwise, generate a procedural backdrop texture (no external assets).
	if bg_image != null:
		var p := String(vis.get("bg_image_path", ""))
		if p != "" and ResourceLoader.exists(p):
			bg_image.texture = load(p) as Texture2D
			bg_image.visible = (bg_image.texture != null)
			bg_image.modulate = Color(1, 1, 1, _float_from(vis.get("bg_image_alpha"), 0.75))
		else:
			var style := String(vis.get("bg_style", theme_id))
			var alpha := _float_from(vis.get("bg_image_alpha"), 0.75)
			bg_image.texture = _get_or_make_bg(style, seed, base, alt, acc)
			bg_image.visible = (bg_image.texture != null)
			bg_image.modulate = Color(1, 1, 1, alpha)

	# Optional richness params (safe even if shader doesn't expose them).
	if vis.has("scale"):
		_ground_mat.set_shader_parameter("u_scale", _float_from(vis.get("scale"), 0.020))
	if vis.has("detail_scale"):
		_ground_mat.set_shader_parameter("u_detail_scale", _float_from(vis.get("detail_scale"), 0.092))
	if vis.has("crack_strength"):
		_ground_mat.set_shader_parameter("u_crack_strength", _float_from(vis.get("crack_strength"), 1.05))
	if vis.has("grit_strength"):
		_ground_mat.set_shader_parameter("u_grit_strength", _float_from(vis.get("grit_strength"), 0.85))
	if vis.has("vignette"):
		_ground_mat.set_shader_parameter("u_vignette", _float_from(vis.get("vignette"), 0.40))
	if vis.has("light_strength"):
		_ground_mat.set_shader_parameter("u_light_strength", _float_from(vis.get("light_strength"), 0.14))
	if vis.has("rune_strength"):
		_ground_mat.set_shader_parameter("u_rune_strength", _float_from(vis.get("rune_strength"), 0.0))
	if vis.has("rune_color"):
		_ground_mat.set_shader_parameter("u_rune_color", _color_from(vis.get("rune_color"), Color(0.36, 1.0, 0.78, 1.0)))

	# Fog
	if vis.has("fog_strength"):
		fog_strength = _float_from(vis.get("fog_strength"), fog_strength)
	if _fog_mat != null and vis.has("fog_color"):
		_fog_mat.set_shader_parameter("u_fog_color", _color_from(vis.get("fog_color"), Color(0.60, 0.74, 0.66, 1.0)))

	# Rays (light wash)
	if _rays_mat != null:
		if vis.has("rays_strength"):
			_rays_mat.set_shader_parameter("u_strength", _float_from(vis.get("rays_strength"), 0.14))
		if vis.has("rays_color"):
			_rays_mat.set_shader_parameter("u_color", _color_from(vis.get("rays_color"), Color(0.80, 0.92, 1.00, 1.0)))
		if vis.has("rays_scale"):
			_rays_mat.set_shader_parameter("u_scale", _float_from(vis.get("rays_scale"), 1.0))

	# Atmosphere particles (motes/embers/wisps)
	if _atmo_mat != null:
		if vis.has("atmo_strength"):
			_atmo_mat.set_shader_parameter("u_strength", _float_from(vis.get("atmo_strength"), 0.22))
		if vis.has("atmo_density"):
			_atmo_mat.set_shader_parameter("u_density", _float_from(vis.get("atmo_density"), 1.0))
		if vis.has("atmo_scale"):
			_atmo_mat.set_shader_parameter("u_scale", _float_from(vis.get("atmo_scale"), 0.010))
		if vis.has("atmo_speed"):
			_atmo_mat.set_shader_parameter("u_speed", _float_from(vis.get("atmo_speed"), 0.35))
		if vis.has("atmo_color"):
			_atmo_mat.set_shader_parameter("u_color", _color_from(vis.get("atmo_color"), Color(0.75, 0.85, 1.0, 1.0)))
		if vis.has("atmo_style"):
			_atmo_mat.set_shader_parameter("u_style", _float_from(vis.get("atmo_style"), 0.0))

	# Props
	if vis.has("prop_count"):
		prop_count = _int_from(vis.get("prop_count"), prop_count)
	# If prop_sheets is provided, prefer it over theme defaults.
	if vis.has("prop_sheets"):
		set_meta("_prop_sheets_override", _strings_from(vis.get("prop_sheets")))

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

func _setup_bg_image() -> void:
	if bg_image == null:
		bg_image = Sprite2D.new()
		bg_image.name = "BgImage"
		add_child(bg_image)
		# Keep it behind everything else
		move_child(bg_image, 0)
	bg_image.centered = true
	bg_image.z_index = -120
	bg_image.visible = false

func _get_or_make_bg(style: String, seed_value: int, base: Color, alt: Color, acc: Color) -> Texture2D:
	var key := "%s|%d|%s|%s|%s" % [style, seed_value, base.to_html(), alt.to_html(), acc.to_html()]
	if _bg_cache.has(key):
		return _bg_cache[key] as Texture2D
	var tex := _make_bg_texture(style, seed_value, base, alt, acc, 512)
	_bg_cache[key] = tex
	return tex

func _make_bg_texture(style: String, seed_value: int, base: Color, alt: Color, acc: Color, size: int) -> Texture2D:
	# Fully procedural “wow” backdrops: distinct per biome.
	# This runs once per map selection (cached), so 512×512 is safe.
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.05
	noise.fractal_gain = 0.52
	noise.frequency = 0.010

	var n2 := FastNoiseLite.new()
	n2.seed = noise.seed ^ 0x51a3c9
	n2.noise_type = FastNoiseLite.TYPE_CELLULAR
	n2.frequency = 0.030

	# Style knobs
	var is_foundry := (style == "foundry" or style == "iron_foundry")
	var is_library := (style == "arcane_ruins" or style == "library" or style == "arcane_library")

	# Precompute some big “room” centers for arcs / stains.
	var centers: Array[Vector2] = []
	var rr := RandomNumberGenerator.new()
	rr.seed = noise.seed ^ 0x9e3779b9
	for i in range(6):
		centers.append(Vector2(rr.randf_range(0.15, 0.85), rr.randf_range(0.15, 0.85)) * float(size))

	for y in range(size):
		var fy := float(y) / float(size)
		for x in range(size):
			var fx := float(x) / float(size)
			var wp := Vector2(float(x), float(y))

			# Base terrain noise
			var a := noise.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5
			var b := noise.get_noise_2d(wp.x * 1.9 + 200.0, wp.y * 1.9 + 80.0) * 0.5 + 0.5
			var c := n2.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5

			var col := base.lerp(alt, clampf(a * 0.85 + b * 0.15, 0.0, 1.0))

			# Macro shapes for instant differentiation
			if is_library:
				# Arcane tiled feel + ring glyphs
				var grid := absf(_fracf(fx * 18.0) - 0.5) + absf(_fracf(fy * 10.0) - 0.5)
				var seams := _smoothstepf(0.96, 1.00, grid * 1.8)
				col = col.lerp(alt, seams * 0.65)

				for cc in centers:
					var d := wp.distance_to(cc) / float(size)
					var ring := 1.0 - _smoothstepf(0.002, 0.010, absf(d - 0.22))
					var ring2 := 1.0 - _smoothstepf(0.002, 0.010, absf(d - 0.35))
					var r := maxf(ring, ring2) * (0.25 + 0.40 * b)
					col = col.lerp(acc, clampf(r, 0.0, 0.55))

			elif is_foundry:
				# Metal plates + lava cracks
				var plate := absf(_fracf(fx * 8.0) - 0.5) + absf(_fracf(fy * 6.0) - 0.5)
				var plate_seam := _smoothstepf(0.92, 1.00, plate * 1.9)
				col = col.lerp(alt, plate_seam * 0.75)

				var crack := _smoothstepf(0.78, 0.90, 1.0 - absf(a - 0.50)) * (0.25 + 0.75 * c)
				var hot := acc.lerp(Color(1.0, 0.55, 0.20, 1.0), 0.55)
				col = col.lerp(hot, clampf(crack * 0.60, 0.0, 0.65))

				# Hazard stripe hint
				var stripe: float = _stepf(0.5, _fracf((fx * 10.0 + fy * 3.0) * 0.85))
				var stripe_mask := _smoothstepf(0.45, 0.90, b) * 0.08
				col = col.lerp(Color(1.0, 0.75, 0.20, 1.0), stripe * stripe_mask)

			else:
				# Graveyard: damp stains + mossy veins
				for cc in centers:
					var d := wp.distance_to(cc) / float(size)
					var stain := _smoothstepf(0.32, 0.02, d) * (0.15 + 0.35 * a)
					col = col.lerp(alt, stain * 0.35)

				var moss := _smoothstepf(0.62, 0.78, b) * (0.15 + 0.35 * c)
				col = col.lerp(acc, clampf(moss * 0.55, 0.0, 0.55))

			# Vignette (helps depth)
			var uv := Vector2(fx * 2.0 - 1.0, fy * 2.0 - 1.0)
			var v := clampf(1.0 - _smoothstepf(0.55, 1.15, uv.length()), 0.0, 1.0)
			col = col.lerp(Color(0, 0, 0, 1), (1.0 - v) * 0.35)

			img.set_pixel(x, y, col)

	var tex := ImageTexture.create_from_image(img)
	return tex

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

func _setup_rays() -> void:
	if rays == null:
		rays = Sprite2D.new()
		rays.name = "Rays"
		add_child(rays)
	rays.texture = _white_tex
	rays.centered = true
	# Slightly behind fog/atmo so it reads as a background wash.
	rays.z_index = -65
	rays.visible = true

	_rays_mat = ShaderMaterial.new()
	_rays_mat.shader = preload("res://shaders/map_light_rays.gdshader")
	_rays_mat.set_shader_parameter("u_strength", 0.14)
	rays.material = _rays_mat

func _setup_atmosphere() -> void:
	if atmo == null:
		atmo = Sprite2D.new()
		atmo.name = "Atmosphere"
		add_child(atmo)
	atmo.texture = _white_tex
	atmo.centered = true
	atmo.z_index = -55
	atmo.visible = true

	_atmo_mat = ShaderMaterial.new()
	_atmo_mat.shader = preload("res://shaders/map_atmosphere_particles.gdshader")
	_atmo_mat.set_shader_parameter("u_strength", 0.22)
	_atmo_mat.set_shader_parameter("u_density", 1.0)
	_atmo_mat.set_shader_parameter("u_style", 0.0)
	atmo.material = _atmo_mat

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
	_t += delta
	_update_ground_follow()
	_update_fog_follow(delta)

func _find_camera() -> Camera2D:
	var player := get_tree().get_first_node_in_group("player") as Node
	if player != null and is_instance_valid(player) and player.has_node("Camera2D"):
		return player.get_node("Camera2D") as Camera2D
	return null

func _effective_margin_px() -> float:
	# If preview pan is enabled, we need extra coverage so the edges never reveal empty viewport.
	var extra := absf(preview_pan_px)
	# Small constant padding prevents tiny gaps from rounding / camera jitter.
	return follow_margin_px + extra + 8.0

func _update_ground_follow() -> void:
	if ground == null or _ground_mat == null:
		return

	var cam := _find_camera()
	var cam_pos := cam.global_position if cam != null else Vector2.ZERO
	if preview_pan_px > 0.001:
		# Gentle motion for menu previews; off by default during gameplay.
		cam_pos += Vector2(sin(_t * preview_pan_speed), cos(_t * (preview_pan_speed * 0.91))) * preview_pan_px
	var zoom := cam.zoom if cam != null else Vector2.ONE
	zoom.x = maxf(0.0001, zoom.x)
	zoom.y = maxf(0.0001, zoom.y)

	# For SubViewport previews, use the actual Viewport size. This avoids partial coverage/gray clears.
	var vp_px := Vector2(get_viewport().size)
	var world_vp := Vector2(vp_px.x / zoom.x, vp_px.y / zoom.y)
	var m := _effective_margin_px()
	var size := world_vp + Vector2(m * 2.0, m * 2.0)

	# Authored background image (optional) uses "cover" scaling.
	if bg_image != null and bg_image.visible and bg_image.texture != null:
		var ts := bg_image.texture.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			var sx := size.x / ts.x
			var sy := size.y / ts.y
			var sc := maxf(sx, sy)
			bg_image.global_position = cam_pos
			bg_image.scale = Vector2(sc, sc)

	ground.global_position = cam_pos
	ground.scale = size # texture is 1×1
	_ground_mat.set_shader_parameter("u_world_origin", cam_pos - size * 0.5)
	_ground_mat.set_shader_parameter("u_world_size", size)

	# Keep overlays aligned with ground (same coverage).
	if rays != null:
		rays.global_position = cam_pos
		rays.scale = size
	if atmo != null:
		atmo.global_position = cam_pos
		atmo.scale = size
	if _atmo_mat != null:
		_atmo_mat.set_shader_parameter("u_world_origin", cam_pos - size * 0.5)
		_atmo_mat.set_shader_parameter("u_world_size", size)
		_atmo_mat.set_shader_parameter("u_time", _t)
	if _rays_mat != null:
		_rays_mat.set_shader_parameter("u_time", _t)

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

	var vp_px := Vector2(get_viewport().size)
	var world_vp := Vector2(vp_px.x / zoom.x, vp_px.y / zoom.y)
	var m := _effective_margin_px()
	var size := world_vp + Vector2(m * 2.0, m * 2.0)

	fog.global_position = cam_pos
	fog.scale = size

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
	if has_meta("_prop_sheets_override"):
		# Explicit type to avoid "Variant inference" warning (warnings are treated as errors in this project).
		var v: Variant = get_meta("_prop_sheets_override")
		if typeof(v) == TYPE_ARRAY:
			for it in (v as Array):
				sheets.append(String(it))
	if sheets.is_empty():
		if theme_id == "arcane_ruins":
			sheets = [
				"res://assets/structures/arcane_cube_sheet.png",
				"res://assets/structures/obelisk_sheet.png",
			]
		elif theme_id == "foundry":
			sheets = [
				"res://assets/structures/obelisk_sheet.png",
				"res://assets/structures/arcane_cube_sheet.png",
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

		# Small variation for richness
		if n is Node2D:
			var s := _rng.randf_range(0.88, 1.12)
			(n as Node2D).scale = Vector2(s, s)
			(n as Node2D).rotation = _rng.randf_range(-0.10, 0.10)

		n.z_index = int(round(n.global_position.y / 10.0))
		placed += 1
