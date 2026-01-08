class_name VfxFlipbook2D
extends Node2D

var _frames: Array[Texture2D] = []
var _fps: float = 12.0
var _t: float = 0.0
var _idx: int = 0
var _loop: bool = false

var _sprite: Sprite2D = null

func setup(frames: Array[Texture2D], fps: float = 12.0, loop: bool = false, tint: Color = Color(1, 1, 1, 1), scale_mult: float = 1.0) -> void:
	_frames = frames
	_fps = maxf(1.0, fps)
	_loop = loop
	_t = 0.0
	_idx = 0

	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = true
		add_child(_sprite)

	_sprite.modulate = tint
	_sprite.scale = Vector2.ONE * scale_mult
	if not _frames.is_empty():
		_sprite.texture = _frames[0]

func set_tint(tint: Color) -> void:
	if _sprite != null:
		_sprite.modulate = tint

func set_scale_mult(scale_mult: float) -> void:
	if _sprite != null:
		_sprite.scale = Vector2.ONE * scale_mult

func _process(delta: float) -> void:
	if _frames.is_empty() or _sprite == null:
		queue_free()
		return
	_t += delta
	var step := 1.0 / _fps
	while _t >= step:
		_t -= step
		_idx += 1
		if _idx >= _frames.size():
			if _loop:
				_idx = 0
			else:
				queue_free()
				return
		_sprite.texture = _frames[_idx]


