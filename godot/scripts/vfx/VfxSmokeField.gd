class_name VfxSmokeField
extends Node2D

# Soft smoky field (Rogue callout). Pure draw + tween, no particles.

var _color: Color = Color(0.70, 0.78, 0.90, 0.55)
var _radius: float = 240.0
var _duration: float = 3.5
var _t: float = 0.0
var _use_flipbook: bool = false
var _flipbook: VfxFlipbook2D = null

func setup(world_pos: Vector2, color: Color, radius: float, duration: float) -> void:
	global_position = world_pos
	_color = color
	_radius = maxf(24.0, radius)
	_duration = maxf(0.20, duration)

func _ready() -> void:
	top_level = true
	z_index = 35

	# Prefer EffectBlocks flipbook if exported (callout.smoke).
	var vfx := get_node_or_null("/root/VfxSystem")
	if vfx and is_instance_valid(vfx) and vfx.has_method("get_event_cfg") and vfx.has_method("get_frames_for_key"):
		var cfg: Dictionary = vfx.get_event_cfg("callout.smoke") as Dictionary
		var key := String(cfg.get("effect_key", ""))
		var frames: Array = vfx.get_frames_for_key(key) as Array
		if not frames.is_empty():
			_flipbook = VfxFlipbook2D.new()
			_flipbook.name = "SmokeFlipbook"
			add_child(_flipbook)
			_flipbook.z_index = int(cfg.get("z", z_index))
			var fps := float(cfg.get("fps", 12))
			var sc := float(cfg.get("scale", 1.0))
			var tint := Color(1, 1, 1, 1)
			var tint_cfg: Variant = cfg.get("tint", null)
			if typeof(tint_cfg) == TYPE_STRING:
				tint = tint * Color.html(String(tint_cfg))
			# also include call-site color (smoke opacity)
			tint = tint * _color
			_flipbook.setup(frames as Array[Texture2D], fps, true, tint, sc)
			_use_flipbook = true

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_t", 1.0, _duration)
	tw.finished.connect(queue_free)

func _process(_delta: float) -> void:
	if not _use_flipbook:
		queue_redraw()

func _draw() -> void:
	if _use_flipbook:
		return
	var a := clampf(1.0 - _t, 0.0, 1.0)
	var base := Color(_color.r, _color.g, _color.b, _color.a * a)
	# Layered circles to feel "foggy".
	for i in range(6):
		var rr := lerpf(_radius * 0.25, _radius, (float(i) / 5.0))
		var aa := base.a * lerpf(0.30, 0.06, float(i) / 5.0)
		draw_circle(Vector2.ZERO, rr, Color(base.r, base.g, base.b, aa))






