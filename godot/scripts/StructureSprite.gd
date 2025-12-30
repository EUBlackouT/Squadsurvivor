extends Node2D

@export_file("*.png") var sheet_path: String
@export var hframes: int = 8
@export var vframes: int = 1
@export var fps: float = 10.0
@export var scale_percent: int = 100
@export var animate: bool = false
@export var auto_detect_layout: bool = true
@export var pad_px: int = 0
@export var enable_pulse: bool = true
@export var pulse_amplitude: float = 0.12
@export var pulse_speed: float = 0.9
@export var enable_sparks: bool = false
@export var target_height_px: int = 0

@onready var anim: AnimatedSprite2D = get_node_or_null("Anim")
@onready var sprite: Sprite2D = get_node_or_null("Sprite")

var frame_count: int = 8
var frame_w: int = 1
var frame_h: int = 1
var frame_index: int = 0
var time_accum: float = 0.0
var pulse_time: float = 0.0
var vfx_particles: GPUParticles2D

func _detect_layout(tex: Texture2D) -> void:
	# Decide hframes/vframes from texture dimensions to avoid slicing incorrectly
	if not auto_detect_layout:
		return
	var w := tex.get_width()
	var h := tex.get_height()
	# Prefer orientation by aspect ratio first, then divisibility
	var is_wide := w >= h * 2
	var is_tall := h >= w * 2
	if is_wide and w % 8 == 0:
		hframes = 8; vframes = 1
	elif is_tall and h % 8 == 0:
		hframes = 1; vframes = 8
	elif w >= h and w % 4 == 0 and h % 2 == 0:
		hframes = 4; vframes = 2
	elif h > w and w % 2 == 0 and h % 4 == 0:
		hframes = 2; vframes = 4
	else:
		# Fallback: treat as single image to avoid cropping
		hframes = 1; vframes = 1

func _ready() -> void:
	if sheet_path == "" or not ResourceLoader.exists(sheet_path):
		push_warning("StructureSprite: sheet not found: %s" % sheet_path)
		set_process(false)
		return
	var tex := load(sheet_path) as Texture2D
	_detect_layout(tex)
	frame_count = maxi(1, hframes * vframes)
	# Use ceil division to avoid narrowing due to truncation
	frame_w = int(ceil(float(tex.get_width()) / float(maxi(1, hframes))))
	frame_h = int(ceil(float(tex.get_height()) / float(maxi(1, vframes))))
	if anim != null:
		# AnimatedSprite2D path
		var frames := SpriteFrames.new()
		var anim_name := "idle"
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, fps)
		for i in range(frame_count):
			var fx := (i % hframes) * frame_w
			var fy := int(i / hframes) * frame_h
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(fx, fy, frame_w, frame_h)
			frames.add_frame(anim_name, atlas)
		anim.sprite_frames = frames
		anim.centered = true
		anim.position = Vector2(0, -frame_h / 2.0) # anchor to floor
		var sc: float
		if target_height_px > 0 and frame_h > 0:
			sc = clamp(float(target_height_px) / float(frame_h), 0.1, 3.0)
		else:
			sc = maxf(0.1, float(scale_percent) / 100.0)
		anim.scale = Vector2(sc, sc)
		anim.animation = anim_name
		anim.stop()
		anim.frame = 0
		set_process(false) # no animation by default
	elif sprite != null:
		# Sprite2D path
		sprite.texture = tex
		# Render a single region for frame 0 explicitly to avoid engine grid rounding
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.region_enabled = true
		var rx := 0
		var ry := 0
		var rw := frame_w
		var rh := frame_h
		# optional padding to counter previous narrow cuts
		if pad_px > 0:
			rx = maxi(0, rx - pad_px)
			ry = maxi(0, ry - pad_px)
			rw = mini(tex.get_width() - rx, rw + pad_px * 2)
			rh = mini(tex.get_height() - ry, rh + pad_px * 2)
		sprite.region_rect = Rect2(rx, ry, rw, rh)
		sprite.centered = true
		sprite.position = Vector2(0, -frame_h / 2.0)
		var sc2: float
		if target_height_px > 0 and frame_h > 0:
			sc2 = clamp(float(target_height_px) / float(frame_h), 0.1, 3.0)
		else:
			sc2 = maxf(0.1, float(scale_percent) / 100.0)
		sprite.scale = Vector2(sc2, sc2)
		sprite.frame = 0
		# Optional lightweight VFX
		_setup_pulse_shader_if_needed()
		_setup_sparks_if_needed()
		# Process if either frame animation or pulse requires it
		set_process(animate or enable_pulse)
	else:
		push_warning("StructureSprite: No child node named 'Anim' or 'Sprite'.")
		set_process(false)

func _process(delta: float) -> void:
	if sprite == null:
		return
	# Drive optional pulse effect
	if enable_pulse and sprite.material is ShaderMaterial:
		pulse_time += delta
		var sm := sprite.material as ShaderMaterial
		sm.set_shader_parameter("u_time", pulse_time * pulse_speed)
		sm.set_shader_parameter("u_amp", pulse_amplitude)
	# Drive optional frame animation (disabled by default)
	if animate:
		time_accum += delta
		var step := 1.0 / maxf(fps, 1.0)
		while time_accum >= step:
			time_accum -= step
			frame_index = (frame_index + 1) % frame_count
			sprite.frame = frame_index

func _setup_pulse_shader_if_needed() -> void:
	if not enable_pulse or sprite == null:
		return
	# Simple brightness pulse; safe without project-level bloom
	var shader_code := """
		shader_type canvas_item;
		uniform float u_time = 0.0;
		uniform float u_amp : hint_range(0.0, 1.0) = 0.12;
		void fragment() {
			vec4 c = texture(TEXTURE, UV);
			// Pulse between 1.0 and 1.0 + u_amp
			float k = 1.0 + (sin(u_time * 6.28318) * 0.5 + 0.5) * u_amp;
			COLOR = vec4(c.rgb * k, c.a);
		}
	"""
	var sh := Shader.new()
	sh.code = shader_code
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sprite.material = sm

func _setup_sparks_if_needed() -> void:
	if not enable_sparks:
		return
	if vfx_particles != null:
		return
	vfx_particles = GPUParticles2D.new()
	vfx_particles.name = "VFX_Sparks"
	vfx_particles.emitting = true
	vfx_particles.amount = 40
	vfx_particles.lifetime = 0.8
	vfx_particles.randomness = 0.5
	# Place around the upper section of the sprite
	vfx_particles.position = Vector2(0, -frame_h * 0.75)
	var mat := ParticleProcessMaterial.new()
	# Godot 4 uses Vector3 for ParticleProcessMaterial even in 2D
	mat.gravity = Vector3(0.0, -10.0, 0.0)
	mat.direction = Vector3(0.0, -1.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 28.0
	mat.scale_min = 0.3
	mat.scale_max = 0.7
	mat.color = Color(1.0, 1.0, 1.0, 0.85)
	mat.color_ramp = _make_soft_fade_ramp()
	vfx_particles.process_material = mat
	add_child(vfx_particles)

func _make_soft_fade_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.2, Color(1, 1, 1, 0.8))
	grad.add_point(0.6, Color(1, 1, 1, 0.4))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	return ramp
