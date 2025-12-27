class_name DamageNumbersLayer
extends CanvasLayer

# Screen-space damage numbers (no physics, no sprites, no collisions).
# Designed to avoid “orb” artifacts entirely by drawing only Labels in UI space.

const STYLE_DEFAULT := 0
const STYLE_CRIT := 1
const STYLE_DOT := 2
const STYLE_ARC := 3
const STYLE_ECHO := 4

class Floating:
	var label: Label
	var vel: Vector2
	var age: float
	var life: float

var _root: Control
var _pool: Array[Label] = []
var _active: Array[Floating] = []

# Aggregation: key -> { amount:int, is_crit:bool, style:int, timer:float, world_pos:Vector2 }
var _pending: Dictionary = {}
const PENDING_WINDOW := 0.12

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

func spawn(amount: int, world_pos: Vector2, style: int = STYLE_DEFAULT, is_crit: bool = false) -> void:
	# Immediate, non-aggregated.
	_spawn_label(amount, _world_to_screen(world_pos), style, is_crit)

func spawn_aggregated(source_id: int, channel: String, amount: int, world_pos: Vector2, style: int, is_crit: bool) -> void:
	var key := "%d:%s" % [source_id, channel]
	var cur: Dictionary = _pending.get(key, {}) as Dictionary
	cur["amount"] = int(cur.get("amount", 0)) + amount
	cur["is_crit"] = bool(cur.get("is_crit", false)) or is_crit
	cur["style"] = style
	cur["timer"] = PENDING_WINDOW
	cur["world_pos"] = world_pos
	_pending[key] = cur

func _process(delta: float) -> void:
	# Flush pending aggregates
	var keys: Array = _pending.keys()
	for k in keys:
		var key: String = String(k)
		var d: Dictionary = _pending.get(key, {}) as Dictionary
		var t := float(d.get("timer", 0.0)) - delta
		d["timer"] = t
		_pending[key] = d
		if t <= 0.0:
			var amt := int(d.get("amount", 0))
			if amt > 0:
				var pos_v: Variant = d.get("world_pos", Vector2.ZERO)
				var pos: Vector2 = pos_v if pos_v is Vector2 else Vector2.ZERO
				var style := int(d.get("style", STYLE_DEFAULT))
				var crit := bool(d.get("is_crit", false))
				_spawn_label(amt, _world_to_screen(pos), style, crit)
			_pending.erase(key)

	# Update actives
	for i in range(_active.size() - 1, -1, -1):
		var f := _active[i]
		f.age += delta
		var t := clampf(f.age / maxf(0.001, f.life), 0.0, 1.0)
		f.label.position += f.vel * delta
		f.vel *= pow(0.10, delta)
		f.label.modulate.a = 1.0 - pow(t, 1.5)
		if f.age >= f.life:
			_recycle_label(f.label)
			_active.remove_at(i)

func _spawn_label(amount: int, screen_pos: Vector2, style: int, is_crit: bool) -> void:
	var l := _alloc_label()
	l.text = str(amount)
	l.position = screen_pos + Vector2(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0))

	_apply_style(l, style, is_crit)

	var f := Floating.new()
	f.label = l
	f.age = 0.0
	f.life = 0.75 if not is_crit else 0.9
	f.vel = Vector2(randf_range(-8.0, 8.0), -70.0 if not is_crit else -92.0)
	_active.append(f)

	# Pop
	l.scale = Vector2(0.88, 0.88)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2(1.10, 1.10), 0.12)
	tw.tween_property(l, "scale", Vector2(1.0, 1.0), 0.14)

func _apply_style(l: Label, style: int, is_crit: bool) -> void:
	# Ensure no theme backgrounds/badges.
	l.theme = Theme.new()
	var empty := StyleBoxEmpty.new()
	l.add_theme_stylebox_override("normal", empty)
	l.add_theme_stylebox_override("focus", empty)

	var col := Color(0.92, 0.95, 1.0, 1.0)
	match style:
		STYLE_DOT:
			col = Color(1.0, 0.25, 0.35, 1.0)
		STYLE_ARC:
			col = Color(0.55, 0.95, 1.0, 1.0)
		STYLE_ECHO:
			col = Color(1.0, 0.85, 0.30, 1.0)
		_:
			col = Color(0.92, 0.95, 1.0, 1.0)
	if is_crit:
		col = Color(1.0, 0.88, 0.28, 1.0)

	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)

	if is_crit:
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_constant_override("outline_size", 4)
	else:
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_constant_override("outline_size", 3)

func _alloc_label() -> Label:
	var l: Label
	if _pool.size() > 0:
		l = _pool.pop_back()
	else:
		l = Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(l)
	l.visible = true
	l.modulate = Color(1, 1, 1, 1)
	l.z_index = 999
	return l

func _recycle_label(l: Label) -> void:
	l.visible = false
	_pool.append(l)

func _world_to_screen(world_pos: Vector2) -> Vector2:
	# Canvas transform maps world (canvas) -> viewport/screen.
	return get_viewport().get_canvas_transform() * world_pos


