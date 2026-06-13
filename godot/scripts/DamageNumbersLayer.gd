class_name DamageNumbersLayer
extends CanvasLayer

# Screen-space damage numbers with satisfying "juicy" animations.
# No physics, no sprites - pure Labels with style.

const STYLE_DEFAULT := 0
const STYLE_CRIT := 1
const STYLE_DOT := 2
const STYLE_ARC := 3
const STYLE_ECHO := 4
const STYLE_HEAL := 5

# Visual presets per style
const STYLE_COLORS: Dictionary = {
	STYLE_DEFAULT: Color(1.0, 0.98, 0.92),      # Warm white
	STYLE_CRIT: Color(1.0, 0.75, 0.15),         # Golden yellow
	STYLE_DOT: Color(1.0, 0.30, 0.35),          # Blood red
	STYLE_ARC: Color(0.40, 0.85, 1.0),          # Electric cyan
	STYLE_ECHO: Color(0.95, 0.65, 1.0),         # Mystic purple
	STYLE_HEAL: Color(0.35, 1.0, 0.55),         # Vibrant green
}

class Floating:
	var label: Label
	var vel: Vector2
	var age: float
	var life: float
	var is_crit: bool
	var style: int
	var shake_offset: Vector2
	var base_pos: Vector2

var _root: Control
var _pool: Array[Label] = []
var _active: Array[Floating] = []
var _font: Font = null

# Aggregation: key -> { amount:int, is_crit:bool, style:int, timer:float, world_pos:Vector2 }
var _pending: Dictionary = {}
const PENDING_WINDOW := 0.07
const MAX_ACTIVE_LABELS := 220
const MAX_PENDING_BUCKETS := 1024

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	
	# Load bold font for impactful numbers
	var font_path := UiSkin.FONT_PATH
	if ResourceLoader.exists(font_path):
		_font = load(font_path) as Font

func spawn(amount: int, world_pos: Vector2, style: int = STYLE_DEFAULT, is_crit: bool = false) -> void:
	_spawn_label(amount, _world_to_screen(world_pos), style, is_crit)

func spawn_aggregated(source_id: int, channel: String, amount: int, world_pos: Vector2, style: int, is_crit: bool) -> void:
	if _pending.size() > MAX_PENDING_BUCKETS:
		# Emergency pressure valve for pathological scenes.
		_pending.clear()
	var key := "%d:%s" % [source_id, channel]
	var cur: Dictionary = _pending.get(key, {}) as Dictionary
	cur["amount"] = int(cur.get("amount", 0)) + amount
	cur["hits"] = int(cur.get("hits", 0)) + 1
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
				var hits := maxi(1, int(d.get("hits", 1)))
				_spawn_label(amt, _world_to_screen(pos), style, crit, hits)
			_pending.erase(key)

	# Update active damage numbers
	for i in range(_active.size() - 1, -1, -1):
		var f := _active[i]
		f.age += delta
		var t := clampf(f.age / maxf(0.001, f.life), 0.0, 1.0)
		
		# Update position with velocity
		f.base_pos += f.vel * delta
		
		# Apply gravity curve - starts fast, slows down
		f.vel.y += 180.0 * delta  # Gentle gravity
		f.vel.x *= pow(0.15, delta)  # Horizontal drag
		
		# Crit shake that decays
		if f.is_crit and t < 0.3:
			var shake_intensity := (1.0 - t / 0.3) * 3.0
			f.shake_offset = Vector2(
				randf_range(-shake_intensity, shake_intensity),
				randf_range(-shake_intensity, shake_intensity)
			)
		else:
			f.shake_offset = Vector2.ZERO
		
		f.label.position = f.base_pos + f.shake_offset
		
		# Fade out with smooth curve
		var fade_start := 0.5
		if t > fade_start:
			var fade_t := (t - fade_start) / (1.0 - fade_start)
			f.label.modulate.a = 1.0 - ease(fade_t, 2.0)
		
		# Cleanup
		if f.age >= f.life:
			_recycle_label(f.label)
			_active.remove_at(i)

func _spawn_label(amount: int, screen_pos: Vector2, style: int, is_crit: bool, hit_count: int = 1) -> void:
	if _active.size() >= MAX_ACTIVE_LABELS:
		var overflow := _active.size() - MAX_ACTIVE_LABELS + 1
		for i in range(mini(overflow, _active.size())):
			var oldest: Floating = _active.pop_front() as Floating
			if oldest != null and oldest.label != null and is_instance_valid(oldest.label):
				_recycle_label(oldest.label)
	var l := _alloc_label()
	
	# Format number with style
	var txt := _format_amount(amount)
	if hit_count >= 3:
		txt += " x%d" % hit_count
	if is_crit:
		txt += "!"
	l.text = txt
	
	# Offset based on damage magnitude for visual variety
	var spread := 16.0 if is_crit else 10.0
	spread += minf(12.0, float(hit_count) * 1.4)
	var start_pos := screen_pos + Vector2(randf_range(-spread, spread), randf_range(-8.0, 4.0))
	l.position = start_pos
	
	_apply_style(l, style, is_crit, amount, hit_count)
	
	var f := Floating.new()
	f.label = l
	f.base_pos = start_pos
	f.age = 0.0
	f.is_crit = is_crit
	f.style = style
	f.shake_offset = Vector2.ZERO
	
	# Crits: longer life, faster initial velocity, more dramatic
	if is_crit:
		f.life = 1.1 + minf(0.25, float(hit_count) * 0.02)
		f.vel = Vector2(randf_range(-25.0, 25.0), randf_range(-140.0, -110.0))
	else:
		f.life = 0.85 + minf(0.18, float(hit_count) * 0.018)
		f.vel = Vector2(randf_range(-15.0, 15.0), randf_range(-90.0, -65.0))
	
	_active.append(f)
	
	# ===== JUICY POP ANIMATION =====
	# Start small, overshoot big, settle
	var base_scale := 1.0 if not is_crit else 1.25
	l.scale = Vector2(0.3, 0.3)
	l.pivot_offset = l.size / 2.0  # Scale from center
	
	var tw := create_tween()
	tw.set_parallel(false)
	
	# Phase 1: Pop up big with overshoot
	tw.set_trans(Tween.TRANS_BACK)
	tw.set_ease(Tween.EASE_OUT)
	var overshoot := base_scale * 1.35 if is_crit else base_scale * 1.2
	tw.tween_property(l, "scale", Vector2(overshoot, overshoot), 0.12)
	
	# Phase 2: Bounce back slightly smaller
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(l, "scale", Vector2(base_scale * 0.95, base_scale * 0.95), 0.08)
	
	# Phase 3: Settle to final size
	tw.tween_property(l, "scale", Vector2(base_scale, base_scale), 0.06)
	
	# Crit: Extra flash effect + screen shake
	if is_crit:
		_spawn_crit_flash(screen_pos)
		var ss := get_node_or_null("/root/ScreenShake")
		if ss and is_instance_valid(ss) and ss.has_method("shake"):
			ss.shake(3.5, 0.08)  # Quick, punchy shake
	elif hit_count >= 6 or amount >= 180:
		_spawn_power_echoes(screen_pos, style, amount, hit_count)

func _spawn_crit_flash(pos: Vector2) -> void:
	# Burst of particles/stars around the crit
	var particles := ["✦", "★", "✧", "◆"]
	var num_particles := 4
	
	for i in range(num_particles):
		var flash := Label.new()
		flash.text = particles[i % particles.size()]
		
		# Spread around the number
		var angle := (float(i) / float(num_particles)) * TAU + randf_range(-0.3, 0.3)
		var dist := randf_range(8.0, 16.0)
		flash.position = pos + Vector2(cos(angle), sin(angle)) * dist + Vector2(-8, -12)
		
		flash.add_theme_font_size_override("font_size", randi_range(16, 24))
		flash.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
		flash.add_theme_color_override("font_outline_color", Color(1.0, 0.5, 0.1, 1.0))
		flash.add_theme_constant_override("outline_size", 2)
		flash.modulate = Color(1, 1, 1, 0.95)
		flash.z_index = 998
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash.scale = Vector2(0.5, 0.5)
		_root.add_child(flash)
		
		# Animate outward and fade
		var end_pos := flash.position + Vector2(cos(angle), sin(angle)) * randf_range(25.0, 45.0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(flash, "position", end_pos, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(flash, "scale", Vector2(1.2, 1.2), 0.15).set_ease(Tween.EASE_OUT)
		tw.tween_property(flash, "modulate:a", 0.0, 0.35).set_ease(Tween.EASE_IN).set_delay(0.1)
		tw.tween_property(flash, "rotation", randf_range(-0.8, 0.8), 0.35)
		tw.chain().tween_callback(flash.queue_free)
	
	# Central glow burst
	var glow := ColorRect.new()
	glow.size = Vector2(60, 60)
	glow.position = pos - Vector2(30, 30)
	glow.color = Color(1.0, 0.85, 0.3, 0.5)
	glow.z_index = 997
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(glow)
	
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(glow, "scale", Vector2(2.0, 2.0), 0.2).set_ease(Tween.EASE_OUT)
	tw2.tween_property(glow, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_OUT)
	tw2.chain().tween_callback(glow.queue_free)

func _apply_style(l: Label, style: int, is_crit: bool, amount: int, hit_count: int = 1) -> void:
	# Clean slate - no theme artifacts
	l.theme = Theme.new()
	var empty := StyleBoxEmpty.new()
	l.add_theme_stylebox_override("normal", empty)
	l.add_theme_stylebox_override("focus", empty)
	l.use_parent_material = false
	l.material = null
	
	# Apply bold font
	if _font != null:
		l.add_theme_font_override("font", _font)
	
	# Get base color from style
	var col: Color = STYLE_COLORS.get(style, STYLE_COLORS[STYLE_DEFAULT])
	if is_crit:
		col = STYLE_COLORS[STYLE_CRIT]
	
	# Outline color - darker, more contrasty
	var outline_col := col.darkened(0.8)
	outline_col.a = 1.0
	
	# Add glow effect via shadow (offset 0 = glow)
	var glow_col := col
	glow_col.a = 0.5
	
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline_col)
	l.add_theme_color_override("font_shadow_color", glow_col if is_crit else Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_x", 0 if is_crit else 2)
	l.add_theme_constant_override("shadow_offset_y", 0 if is_crit else 2)
	
	# Dynamic font size based on damage amount and crit status
	var base_size := 18
	if amount >= 100:
		base_size = 24
	elif amount >= 50:
		base_size = 21
	elif amount >= 25:
		base_size = 19
	
	if is_crit:
		base_size = int(base_size * 1.5)
		l.add_theme_constant_override("outline_size", 6)
	else:
		l.add_theme_constant_override("outline_size", 4)
	
	if hit_count >= 4:
		base_size += mini(8, int(hit_count / 2))
	
	l.add_theme_font_size_override("font_size", base_size)
	
	# DOT numbers are smaller and more subtle
	if style == STYLE_DOT and not is_crit:
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_constant_override("outline_size", 3)

func _format_amount(amount: int) -> String:
	if amount >= 1000000:
		return "%.1fM" % (float(amount) / 1000000.0)
	if amount >= 10000:
		return "%.1fK" % (float(amount) / 1000.0)
	return str(amount)

func _spawn_power_echoes(screen_pos: Vector2, style: int, amount: int, hit_count: int) -> void:
	var echoes := mini(3, 1 + int(hit_count / 4))
	for i in range(echoes):
		var e := Label.new()
		e.text = "+"
		e.add_theme_font_size_override("font_size", 16 + i * 2)
		var col: Color = STYLE_COLORS.get(style, STYLE_COLORS[STYLE_DEFAULT])
		e.add_theme_color_override("font_color", Color(col.r, col.g, col.b, 0.75))
		e.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 0.85))
		e.add_theme_constant_override("outline_size", 2)
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		e.z_index = 995
		e.position = screen_pos + Vector2(randf_range(-22.0, 22.0), randf_range(-30.0, 8.0))
		_root.add_child(e)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(e, "position:y", e.position.y - randf_range(18.0, 36.0), 0.26).set_ease(Tween.EASE_OUT)
		tw.tween_property(e, "modulate:a", 0.0, 0.24).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(e.queue_free)

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
	l.scale = Vector2(1, 1)
	l.rotation = 0.0
	l.z_index = 999
	return l

func _recycle_label(l: Label) -> void:
	l.visible = false
	_pool.append(l)

func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos
