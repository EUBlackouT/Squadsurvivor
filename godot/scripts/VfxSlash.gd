extends Node2D

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")

var _tint: Color = Color(1, 0.95, 0.85, 0.95)
var _life: float = 0.22
var _age: float = 0.0

func _ready() -> void:
	top_level = true
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)
	sprite.texture = _make_tex()
	sprite.centered = true
	sprite.z_index = 50
	sprite.modulate = _tint
	sprite.scale = Vector2(0.85, 0.85)

func setup(world_pos: Vector2, dir: Vector2, tint: Color) -> void:
	global_position = world_pos + dir.normalized() * 12.0
	rotation = dir.angle()
	_tint = tint
	if sprite != null:
		sprite.modulate = _tint
	# Pop
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "scale", Vector2(1.20, 1.20), 0.10)
	tw.tween_property(sprite, "scale", Vector2(1.05, 1.05), 0.08)

func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / maxf(0.001, _life), 0.0, 1.0)
	modulate.a = 1.0 - t
	if _age >= _life:
		queue_free()

func _make_tex() -> Texture2D:
	var tex_size: int = 64
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var c := Vector2(float(tex_size) * 0.5, float(tex_size) * 0.5)
	var r_in: float = 12.0
	var r_out: float = 30.0
	var sweep_rad: float = deg_to_rad(150.0)
	var start_angle: float = -sweep_rad * 0.5

	# Pass 1: main fill
	for y in range(tex_size):
		for x in range(tex_size):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - c
			var r := p.length()
			var a := p.angle()

			var normalized_angle := wrapf(a - start_angle, 0.0, sweep_rad)
			var t_angle := normalized_angle / sweep_rad
			var t_radial := clampf((r - r_in) / maxf(0.0001, (r_out - r_in)), 0.0, 1.0)

			var alpha: float = (1.0 - t_radial) * (1.0 - absf(t_angle - 0.5) * 1.8)
			alpha = pow(alpha, 1.15)
			if r >= r_in and r <= r_out and alpha > 0.01:
				img.set_pixel(x, y, Color(1, 1, 1, alpha))

	# Pass 2: outline dilation
	var out_img := img.duplicate()
	var outline_color: Color = Color(0, 0, 0, 1)
	var outline_size_px: int = 2
	for y in range(tex_size):
		for x in range(tex_size):
			if img.get_pixel(x, y).a > 0.01:
				continue
			var found := false
			for oy in range(-outline_size_px, outline_size_px + 1):
				for ox in range(-outline_size_px, outline_size_px + 1):
					var nx: int = clampi(x + ox, 0, tex_size - 1)
					var ny: int = clampi(y + oy, 0, tex_size - 1)
					if img.get_pixel(nx, ny).a > 0.01:
						found = true
						break
				if found:
					break
			if found:
				out_img.set_pixel(x, y, outline_color)

	# Pass 3: highlight inner edge
	var highlight_color: Color = Color(1.0, 1.0, 0.85, 0.75)
	for y in range(tex_size):
		for x in range(tex_size):
			var cur: Color = out_img.get_pixel(x, y)
			if cur.a <= 0.01:
				continue
			if cur.r == outline_color.r and cur.g == outline_color.g and cur.b == outline_color.b:
				continue
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - c
			var r := p.length()
			var inner_bias := clampf(1.0 - ((r - r_in) / maxf(0.0001, (r_out - r_in))), 0.0, 1.0)
			var hl_a := cur.a * inner_bias * 0.60
			if hl_a > 0.05:
				out_img.set_pixel(x, y, Color(
					maxf(cur.r, highlight_color.r),
					maxf(cur.g, highlight_color.g),
					maxf(cur.b, highlight_color.b),
					maxf(cur.a, hl_a)
				))

	return ImageTexture.create_from_image(out_img)
