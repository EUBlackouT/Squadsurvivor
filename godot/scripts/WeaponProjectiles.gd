extends Node
# Collection of specialized weapon projectile types

# === BOMB PROJECTILE ===
class BombProjectile extends Node2D:
	var _start_pos: Vector2
	var _target_pos: Vector2
	var _damage: int
	var _is_crit: bool
	var _radius: float
	var _burn_dur: float
	var _burn_dps_mult: float
	var _speed: float
	var _main: Node2D
	var _cd: CharacterData
	var _attacker: Node2D
	var _t: float = 0.0
	var _duration: float = 0.0
	var _sprite: Sprite2D
	
	func setup(start: Vector2, target: Vector2, dmg: int, crit: bool, radius: float, burn_dur: float, burn_dps_mult: float, speed: float, main: Node2D, cd: CharacterData, attacker: Node2D) -> void:
		_start_pos = start
		_target_pos = target
		_damage = dmg
		_is_crit = crit
		_radius = radius
		_burn_dur = burn_dur
		_burn_dps_mult = burn_dps_mult
		_speed = speed
		_main = main
		_cd = cd
		_attacker = attacker
		_duration = start.distance_to(target) / maxf(speed, 1.0)
		global_position = start
		
		_sprite = Sprite2D.new()
		_sprite.texture = _make_bomb_tex()
		add_child(_sprite)
	
	func _make_bomb_tex() -> ImageTexture:
		var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 0.2, 0.2, 1))
		for x in range(3, 9):
			for y in range(3, 9):
				img.set_pixel(x, y, Color(0.3, 0.3, 0.3, 1))
		img.set_pixel(6, 1, Color(1.0, 0.5, 0.1, 1))
		img.set_pixel(6, 2, Color(1.0, 0.3, 0.1, 1))
		return ImageTexture.create_from_image(img)
	
	func _process(delta: float) -> void:
		_t += delta
		var progress := clampf(_t / _duration, 0.0, 1.0)
		
		# Arc trajectory
		var lerped := _start_pos.lerp(_target_pos, progress)
		var arc_height := 60.0 * sin(progress * PI)
		global_position = lerped + Vector2(0, -arc_height)
		_sprite.rotation += delta * 8.0
		
		if progress >= 1.0:
			_explode()
	
	func _explode() -> void:
		var enemies: Array = []
		if _main and is_instance_valid(_main) and _main.has_method("get_cached_enemies"):
			enemies = _main.get_cached_enemies()
		else:
			enemies = get_tree().get_nodes_in_group("enemies")
		
		var r2 := _radius * _radius
		for e in enemies:
			if not is_instance_valid(e):
				continue
			var n2 := e as Node2D
			if n2 == null:
				continue
			if n2.global_position.distance_squared_to(global_position) <= r2:
				if n2.has_method("take_damage"):
					n2.take_damage(_damage, _is_crit, "bomb")
				if _burn_dur > 0.0 and _burn_dps_mult > 0.0 and n2.has_method("apply_burn"):
					var dps := float(_damage) * _burn_dps_mult
					n2.apply_burn(dps, _burn_dur, 0.5)
					PassiveSystem.mark_burn(n2, _burn_dur)
					if _main != null and is_instance_valid(_main):
						var fb := VfxFlameBurst.new()
						fb.setup(global_position, Color(1.0, 0.55, 0.2, 1.0), _radius * 0.55, 12, 0.22, Vector2.ZERO)
						_main.add_child(fb)
						var s := _main.get_node_or_null("/root/SfxSystem")
						if s and is_instance_valid(s) and s.has_method("play_event"):
							s.play_event("passive.bomb_expert", global_position, self)
		
		# VFX - use weapon.bomb_explode event
		var v := _main.get_node_or_null("/root/VfxSystem") if _main else null
		if v and is_instance_valid(v) and v.has_method("play_event"):
			v.play_event("weapon.bomb_explode", global_position, _main, Color(1.0, 0.5, 0.1, 1.0), _radius / 60.0)
		else:
			# Fallback
			var sw := VfxShockwave.new()
			sw.setup(global_position, Color(1.0, 0.5, 0.1, 1.0), 15.0, _radius, 5.0, 0.2)
			_main.add_child(sw)
		
		# SFX
		var s := _main.get_node_or_null("/root/SfxSystem") if _main else null
		if s and is_instance_valid(s) and s.has_method("play_event"):
			s.play_event("weapon.bomb_explode", global_position, self)
		
		# Screen shake
		var shake := _main.get_node_or_null("/root/ScreenShake") if _main else null
		if shake and is_instance_valid(shake) and shake.has_method("shake"):
			shake.shake(5.0, 0.12)
		
		queue_free()


# === BOOMERANG PROJECTILE ===
class BoomerangProjectile extends Node2D:
	var _owner_ref: WeakRef
	var _target_pos: Vector2
	var _damage: int
	var _is_crit: bool
	var _return_mult: float
	var _max_dist: float
	var _speed: float
	var _main: Node2D
	var _cd: CharacterData
	var _returning: bool = false
	var _hit_targets: Array[Node2D] = []
	var _sprite: Sprite2D
	
	func setup(owner: Node2D, target: Vector2, dmg: int, crit: bool, ret_mult: float, dist: float, speed: float, main: Node2D, cd: CharacterData) -> void:
		_owner_ref = weakref(owner)
		_target_pos = target
		_damage = dmg
		_is_crit = crit
		_return_mult = ret_mult
		_max_dist = dist
		_speed = speed
		_main = main
		_cd = cd
		global_position = owner.global_position
		
		_sprite = Sprite2D.new()
		_sprite.texture = _make_chakram_tex()
		add_child(_sprite)
	
	func _make_chakram_tex() -> ImageTexture:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		var center := Vector2(8, 8)
		for x in range(16):
			for y in range(16):
				var d := Vector2(x, y).distance_to(center)
				if d >= 5 and d <= 7:
					img.set_pixel(x, y, Color(0.8, 0.9, 1.0, 1.0))
				elif d >= 3 and d < 5:
					img.set_pixel(x, y, Color(0.5, 0.6, 0.8, 0.8))
		return ImageTexture.create_from_image(img)
	
	func _process(delta: float) -> void:
		_sprite.rotation += delta * 15.0
		
		var owner_node := _owner_ref.get_ref() as Node2D
		var move_target := _target_pos if not _returning else (owner_node.global_position if owner_node and is_instance_valid(owner_node) else _target_pos)
		
		var dir := (move_target - global_position).normalized()
		global_position += dir * _speed * delta
		
		# Check if reached target
		if not _returning and global_position.distance_to(_target_pos) < 20:
			_returning = true
			_hit_targets.clear()
		elif _returning and owner_node and is_instance_valid(owner_node) and global_position.distance_to(owner_node.global_position) < 30:
			queue_free()
			return
		
		# Hit enemies
		_check_hits()
		
		# Timeout
		if not _returning and global_position.distance_to(_owner_ref.get_ref().global_position if _owner_ref.get_ref() else global_position) > _max_dist * 1.5:
			_returning = true
	
	func _check_hits() -> void:
		var enemies: Array = []
		if _main and is_instance_valid(_main) and _main.has_method("get_cached_enemies"):
			enemies = _main.get_cached_enemies()
		
		var hit_radius := 20.0
		for e in enemies:
			if not is_instance_valid(e) or _hit_targets.has(e):
				continue
			var n2 := e as Node2D
			if n2 == null:
				continue
			if n2.global_position.distance_to(global_position) <= hit_radius:
				var dmg := _damage if not _returning else int(float(_damage) * _return_mult)
				if n2.has_method("take_damage"):
					n2.take_damage(dmg, _is_crit, "boomerang")
				_hit_targets.append(n2)


# === BEAM ATTACK ===
class BeamAttack extends Node2D:
	var _owner_ref: WeakRef
	var _direction: Vector2
	var _damage: int
	var _is_crit: bool
	var _length: float
	var _width: float
	var _width_growth: float
	var _duration: float
	var _tick_rate: float
	var _main: Node2D
	var _cd: CharacterData
	var _elapsed: float = 0.0
	var _tick_t: float = 0.0
	var _line: Line2D
	var _ramp_per_second: float = 0.0
	var _ramp_cap: float = 1.0
	var _initial_mult: float = 1.0
	var _secondary_targets_add: int = 0
	var _secondary_damage_mult: float = 0.0
	var _lock_focus_target: bool = false
	var _focus_target_id: int = -1
	var _focus_ramp_t: float = 0.0
	
	func setup(owner: Node2D, dir: Vector2, dmg: int, crit: bool, length: float, width: float, width_growth: float, duration: float, tick: float, main: Node2D, cd: CharacterData, ramp_per_second: float = 0.0, ramp_cap: float = 1.0, initial_mult: float = 1.0, secondary_targets_add: int = 0, secondary_damage_mult: float = 0.0, lock_focus_target: bool = false) -> void:
		_owner_ref = weakref(owner)
		_direction = dir.normalized()
		_damage = dmg
		_is_crit = crit
		_length = length
		_width = width
		_width_growth = width_growth
		_duration = duration
		_tick_rate = tick
		_main = main
		_cd = cd
		_ramp_per_second = maxf(0.0, ramp_per_second)
		_ramp_cap = maxf(0.2, ramp_cap)
		_initial_mult = clampf(initial_mult, 0.1, _ramp_cap)
		_secondary_targets_add = maxi(0, secondary_targets_add)
		_secondary_damage_mult = clampf(secondary_damage_mult, 0.0, 2.5)
		_lock_focus_target = lock_focus_target
		
		_line = Line2D.new()
		_line.width = width
		_line.default_color = Color(1.0, 0.3, 0.3, 0.9)
		_line.add_point(Vector2.ZERO)
		_line.add_point(_direction * _length)
		add_child(_line)
	
	func _process(delta: float) -> void:
		_elapsed += delta
		_tick_t += delta
		
		var owner_node := _owner_ref.get_ref() as Node2D
		if owner_node and is_instance_valid(owner_node):
			global_position = owner_node.global_position
		
		# Pulse effect + optional growth
		_line.default_color.a = 0.6 + 0.4 * sin(_elapsed * 20.0)
		if _width_growth > 0.0 and _duration > 0.0:
			var t := clampf(_elapsed / _duration, 0.0, 1.0)
			_line.width = _width * (1.0 + _width_growth * t)
		
		if _tick_t >= _tick_rate:
			_tick_t = 0.0
			_damage_enemies()
		
		if _elapsed >= _duration:
			queue_free()
	
	func _damage_enemies() -> void:
		var enemies: Array = []
		if _main and is_instance_valid(_main) and _main.has_method("get_cached_enemies"):
			enemies = _main.get_cached_enemies()
		
		var tick_dmg := int(float(_damage) * _tick_rate / maxf(0.05, _duration))
		var hit_list: Array[Node2D] = []
		for e in enemies:
			if not is_instance_valid(e):
				continue
			var n2 := e as Node2D
			if n2 == null:
				continue
			# Check if enemy is in beam path
			var to_enemy := n2.global_position - global_position
			var proj := to_enemy.dot(_direction)
			if proj < 0 or proj > _length:
				continue
			var closest := global_position + _direction * proj
			if n2.global_position.distance_to(closest) <= _width:
				hit_list.append(n2)
		if hit_list.is_empty():
			_focus_target_id = -1
			_focus_ramp_t = 0.0
			return
		hit_list.sort_custom(func(a: Node2D, b: Node2D) -> bool:
			return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position)
		)
		var primary: Node2D = hit_list[0]
		if _lock_focus_target:
			if _focus_target_id != primary.get_instance_id():
				_focus_target_id = primary.get_instance_id()
				_focus_ramp_t = 0.0
			else:
				_focus_ramp_t += _tick_rate
		else:
			_focus_target_id = primary.get_instance_id()
			_focus_ramp_t += _tick_rate
		var ramp_mult := clampf(_initial_mult + _ramp_per_second * _focus_ramp_t, 0.1, _ramp_cap)
		if primary.has_method("take_damage"):
			primary.take_damage(maxi(1, int(round(float(tick_dmg) * ramp_mult))), _is_crit, "beam")
		var sec_n := mini(_secondary_targets_add, maxi(0, hit_list.size() - 1))
		for i in range(sec_n):
			var n := hit_list[i + 1]
			if n != null and is_instance_valid(n) and n.has_method("take_damage"):
				n.take_damage(maxi(1, int(round(float(tick_dmg) * _secondary_damage_mult))), false, "beam_split")


# === DOT PROJECTILE (Poison) ===
class DotProjectile extends Node2D:
	var _target_ref: WeakRef
	var _damage: int
	var _is_crit: bool
	var _dot_pct: float
	var _poison_mult: float
	var _spread_radius: float
	var _dot_dur: float
	var _dot_tick: float
	var _speed: float
	var _main: Node2D
	var _cd: CharacterData
	var _attacker: Node2D
	var _sprite: Sprite2D
	
	func setup(start: Vector2, target: Node2D, dmg: int, crit: bool, dot_pct: float, poison_mult: float, spread_radius: float, dot_dur: float, dot_tick: float, speed: float, main: Node2D, cd: CharacterData, attacker: Node2D) -> void:
		global_position = start
		_target_ref = weakref(target)
		_damage = dmg
		_is_crit = crit
		_dot_pct = dot_pct
		_poison_mult = poison_mult
		_spread_radius = spread_radius
		_dot_dur = dot_dur
		_dot_tick = dot_tick
		_speed = speed
		_main = main
		_cd = cd
		_attacker = attacker
		
		_sprite = Sprite2D.new()
		_sprite.texture = _make_dart_tex()
		add_child(_sprite)
	
	func _make_dart_tex() -> ImageTexture:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.set_pixel(4, 0, Color(0.3, 0.9, 0.3, 1))
		img.set_pixel(3, 1, Color(0.3, 0.9, 0.3, 1))
		img.set_pixel(4, 1, Color(0.3, 0.9, 0.3, 1))
		img.set_pixel(5, 1, Color(0.3, 0.9, 0.3, 1))
		for y in range(2, 7):
			img.set_pixel(4, y, Color(0.2, 0.6, 0.2, 1))
		return ImageTexture.create_from_image(img)
	
	func _process(delta: float) -> void:
		var target := _target_ref.get_ref() as Node2D
		if target == null or not is_instance_valid(target):
			queue_free()
			return
		
		var dir := (target.global_position - global_position).normalized()
		global_position += dir * _speed * delta
		_sprite.rotation = dir.angle() + PI/2
		
		if global_position.distance_to(target.global_position) < 16:
			_hit(target)
	
	func _hit(target: Node2D) -> void:
		if target.has_method("take_damage"):
			target.take_damage(_damage, _is_crit, "poison_dart")
		
		# Apply DOT
		if target.has_method("apply_burn"):
			var dps := float(_damage) * _dot_pct / _dot_dur * _poison_mult
			target.apply_burn(dps, _dot_dur, _dot_tick)
			if _spread_radius > 0.0:
				target.set_meta("_poison_spread_dps", dps)
				target.set_meta("_poison_spread_dur", _dot_dur)
				target.set_meta("_poison_spread_tick", _dot_tick)
				target.set_meta("_poison_spread_count", 2)
				target.set_meta("_poison_spread_radius", _spread_radius)
				target.set_meta("_poison_spread_until_ms", int(Time.get_ticks_msec()) + int(round(_dot_dur * 1000.0)))
		
		# Green poison visual
		if target.has_method("pulse_vfx"):
			target.pulse_vfx(Color(0.3, 0.9, 0.3, 1.0))
		var v := _main.get_node_or_null("/root/VfxSystem") if _main else null
		if v and is_instance_valid(v) and v.has_method("play_event"):
			v.play_event("weapon.poison_hit", target.global_position, _main, Color(0.45, 1.0, 0.45, 1.0), 0.95)
		var s := _main.get_node_or_null("/root/SfxSystem") if _main else null
		if s and is_instance_valid(s) and s.has_method("play_event"):
			s.play_event("weapon.poison", target.global_position, self)
		
		queue_free()


# === SLOW PROJECTILE (Frost) ===
class SlowProjectile extends Node2D:
	var _target_ref: WeakRef
	var _damage: int
	var _is_crit: bool
	var _slow_pct: float
	var _slow_bonus: float
	var _shatter_radius: float
	var _shatter_damage: float
	var _slow_dur: float
	var _speed: float
	var _main: Node2D
	var _cd: CharacterData
	var _attacker: Node2D
	var _sprite: Sprite2D
	
	func setup(start: Vector2, target: Node2D, dmg: int, crit: bool, slow_pct: float, slow_bonus: float, shatter_radius: float, shatter_damage: float, slow_dur: float, speed: float, main: Node2D, cd: CharacterData, attacker: Node2D) -> void:
		global_position = start
		_target_ref = weakref(target)
		_damage = dmg
		_is_crit = crit
		_slow_pct = slow_pct
		_slow_bonus = slow_bonus
		_shatter_radius = shatter_radius
		_shatter_damage = shatter_damage
		_slow_dur = slow_dur
		_speed = speed
		_main = main
		_cd = cd
		_attacker = attacker
		
		_sprite = Sprite2D.new()
		_sprite.texture = _make_frost_tex()
		add_child(_sprite)
	
	func _make_frost_tex() -> ImageTexture:
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		var center := Vector2(5, 5)
		for x in range(10):
			for y in range(10):
				var d := Vector2(x, y).distance_to(center)
				if d <= 4:
					var alpha := 1.0 - d / 4.0
					img.set_pixel(x, y, Color(0.6, 0.85, 1.0, alpha))
		return ImageTexture.create_from_image(img)
	
	func _process(delta: float) -> void:
		var target := _target_ref.get_ref() as Node2D
		if target == null or not is_instance_valid(target):
			queue_free()
			return
		
		var dir := (target.global_position - global_position).normalized()
		global_position += dir * _speed * delta
		
		if global_position.distance_to(target.global_position) < 16:
			_hit(target)
	
	func _hit(target: Node2D) -> void:
		if target.has_method("take_damage"):
			target.take_damage(_damage, _is_crit, "frost_bolt")
		
		# Apply slow
		if target.has_method("apply_slow"):
			var slow_val := minf(0.95, _slow_pct + _slow_bonus)
			target.apply_slow(slow_val, _slow_dur)
		if _shatter_radius > 0.0 and _shatter_damage > 0.0:
			target.set_meta("_frost_shatter_radius", _shatter_radius)
			target.set_meta("_frost_shatter_dmg", int(round(float(_damage) * _shatter_damage)))
			target.set_meta("_frost_shatter_until_ms", int(Time.get_ticks_msec()) + int(round(_slow_dur * 1000.0)))
		
		# Frost visual
		if target.has_method("pulse_vfx"):
			target.pulse_vfx(Color(0.6, 0.85, 1.0, 1.0))
		var v := _main.get_node_or_null("/root/VfxSystem") if _main else null
		if v and is_instance_valid(v) and v.has_method("play_event"):
			v.play_event("weapon.frost_hit", target.global_position, _main, Color(0.72, 0.9, 1.0, 1.0), 0.9)
		var s := _main.get_node_or_null("/root/SfxSystem") if _main else null
		if s and is_instance_valid(s) and s.has_method("play_event"):
			s.play_event("weapon.frost", target.global_position, self)
		
		queue_free()


# === RICOCHET PROJECTILE ===
class RicochetProjectile extends Node2D:
	var _target_ref: WeakRef
	var _damage: int
	var _is_crit: bool
	var _bounces_left: int
	var _bounce_range: float
	var _dmg_decay: float
	var _main: Node2D
	var _cd: CharacterData
	var _attacker: Node2D
	var _hit_targets: Array[Node2D] = []
	var _speed: float = 600.0
	var _sprite: Sprite2D
	var _direct_mult: float = 1.0
	var _post_bounce_mult: float = 1.0
	var _damage_per_bounce_add: float = 0.0
	var _hit_index: int = 0
	
	func setup(start: Vector2, target: Node2D, dmg: int, crit: bool, bounces: int, bounce_range: float, decay: float, main: Node2D, cd: CharacterData, attacker: Node2D, direct_mult: float = 1.0, post_bounce_mult: float = 1.0, dmg_per_bounce_add: float = 0.0) -> void:
		global_position = start
		_target_ref = weakref(target)
		_damage = dmg
		_is_crit = crit
		_bounces_left = bounces
		_bounce_range = bounce_range
		_dmg_decay = decay
		_main = main
		_cd = cd
		_attacker = attacker
		_direct_mult = maxf(0.1, direct_mult)
		_post_bounce_mult = maxf(0.1, post_bounce_mult)
		_damage_per_bounce_add = maxf(0.0, dmg_per_bounce_add)
		
		_sprite = Sprite2D.new()
		_sprite.texture = _make_bullet_tex()
		add_child(_sprite)
	
	func _make_bullet_tex() -> ImageTexture:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		var center := Vector2(4, 4)
		for x in range(8):
			for y in range(8):
				var d := Vector2(x, y).distance_to(center)
				if d <= 3:
					img.set_pixel(x, y, Color(1.0, 0.9, 0.5, 1.0))
		return ImageTexture.create_from_image(img)
	
	func _process(delta: float) -> void:
		var target := _target_ref.get_ref() as Node2D
		if target == null or not is_instance_valid(target):
			_find_new_target()
			target = _target_ref.get_ref() as Node2D
			if target == null:
				queue_free()
				return
		
		var dir := (target.global_position - global_position).normalized()
		global_position += dir * _speed * delta
		_sprite.rotation = dir.angle()
		
		if global_position.distance_to(target.global_position) < 16:
			_hit(target)
	
	func _hit(target: Node2D) -> void:
		if target.has_method("take_damage"):
			var dealt := _damage
			if _hit_index == 0:
				dealt = maxi(1, int(round(float(dealt) * _direct_mult)))
			else:
				dealt = maxi(1, int(round(float(dealt) * _post_bounce_mult * (1.0 + float(_hit_index) * _damage_per_bounce_add))))
			target.take_damage(dealt, _is_crit and _hit_index == 0, "ricochet")
		if _main != null and is_instance_valid(_main):
			var v := _main.get_node_or_null("/root/VfxSystem")
			if v and is_instance_valid(v) and v.has_method("play_event"):
				v.play_event("weapon.ricochet_bounce", target.global_position, _main, Color(1.0, 0.9, 0.45, 1.0), 0.85)
			var sfx := _main.get_node_or_null("/root/SfxSystem")
			if sfx and is_instance_valid(sfx) and sfx.has_method("play_event"):
				sfx.play_event("weapon.ricochet", target.global_position, self)
		_hit_targets.append(target)
		if _cd != null and PassiveSystem.has_passive(_cd.passive_ids, "ricochet_master"):
			if _main != null and is_instance_valid(_main):
				var f := VfxImpactFlash.new()
				f.setup(target.global_position + Vector2(0, -10), Color(1.0, 0.85, 0.35, 1.0), 12.0, 0.10)
				_main.add_child(f)
				var s := _main.get_node_or_null("/root/SfxSystem")
				if s and is_instance_valid(s) and s.has_method("play_event"):
					s.play_event("passive.ricochet_master", target.global_position, self)
		
		_bounces_left -= 1
		_hit_index += 1
		_damage = int(float(_damage) * _dmg_decay)
		
		if _bounces_left <= 0 or _damage <= 0:
			queue_free()
			return
		
		_find_new_target()
		if _target_ref.get_ref() == null:
			queue_free()
	
	func _find_new_target() -> void:
		var enemies: Array = []
		if _main and is_instance_valid(_main) and _main.has_method("get_cached_enemies"):
			enemies = _main.get_cached_enemies()
		
		var best: Node2D = null
		var best_dist := _bounce_range * _bounce_range
		for e in enemies:
			if not is_instance_valid(e) or _hit_targets.has(e):
				continue
			var n2 := e as Node2D
			if n2 == null:
				continue
			var d2 := n2.global_position.distance_squared_to(global_position)
			if d2 < best_dist:
				best_dist = d2
				best = n2
		_target_ref = weakref(best) if best else weakref(null)


# === DELAYED STRIKE ===
class DelayedStrike extends Node2D:
	var _target_pos: Vector2
	var _damage: int
	var _is_crit: bool
	var _radius: float
	var _delay: float
	var _main: Node2D
	var _cd: CharacterData
	var _attacker: Node2D
	var _elapsed: float = 0.0
	var _indicator: Sprite2D
	
	func setup(pos: Vector2, dmg: int, crit: bool, radius: float, delay: float, main: Node2D, cd: CharacterData, attacker: Node2D) -> void:
		_target_pos = pos
		_damage = dmg
		_is_crit = crit
		_radius = radius
		_delay = delay
		_main = main
		_cd = cd
		_attacker = attacker
		global_position = pos
		
		_indicator = Sprite2D.new()
		_indicator.texture = _make_indicator_tex()
		_indicator.modulate = Color(0.8, 0.6, 1.0, 0.5)
		add_child(_indicator)
	
	func _make_indicator_tex() -> ImageTexture:
		var size := int(_radius * 2)
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var center := Vector2(size / 2, size / 2)
		for x in range(size):
			for y in range(size):
				var d := Vector2(x, y).distance_to(center)
				if d <= _radius and d >= _radius - 3:
					img.set_pixel(x, y, Color(1, 1, 1, 0.8))
		return ImageTexture.create_from_image(img)
	
	func _process(delta: float) -> void:
		_elapsed += delta
		_indicator.modulate.a = 0.3 + 0.4 * sin(_elapsed * 10.0)
		
		if _elapsed >= _delay:
			_strike()
	
	func _strike() -> void:
		var enemies: Array = []
		if _main and is_instance_valid(_main) and _main.has_method("get_cached_enemies"):
			enemies = _main.get_cached_enemies()
		
		var r2 := _radius * _radius
		for e in enemies:
			if not is_instance_valid(e):
				continue
			var n2 := e as Node2D
			if n2 == null:
				continue
			if n2.global_position.distance_squared_to(global_position) <= r2:
				if n2.has_method("take_damage"):
					n2.take_damage(_damage, _is_crit, "spirit_lance")
		
		# VFX
		var flash := VfxImpactFlash.new()
		flash.setup(global_position, Color(0.8, 0.6, 1.0, 1.0), _radius * 0.8, 0.15)
		_main.add_child(flash)
		var v := _main.get_node_or_null("/root/VfxSystem") if _main else null
		if v and is_instance_valid(v) and v.has_method("play_event"):
			v.play_event("weapon.spirit_strike", global_position, _main, Color(0.85, 0.7, 1.0, 1.0), maxf(0.7, _radius / 40.0))
		var s := _main.get_node_or_null("/root/SfxSystem") if _main else null
		if s and is_instance_valid(s) and s.has_method("play_event"):
			s.play_event("weapon.spirit", global_position, self)
		
		queue_free()


# === ORBITAL STRIKE ===
class OrbitalStrike extends Node2D:
	var _target_pos: Vector2
	var _damage: int
	var _is_crit: bool
	var _radius: float
	var _delay: float
	var _cluster_bonus: float
	var _main: Node2D
	var _cd: CharacterData
	var _attacker: Node2D
	var _elapsed: float = 0.0
	var _indicator: Sprite2D
	var _warning_line: Line2D
	var _played_charge_sfx: bool = false
	
	func setup(pos: Vector2, dmg: int, crit: bool, radius: float, delay: float, cluster_bonus: float, main: Node2D, cd: CharacterData, attacker: Node2D) -> void:
		_target_pos = pos
		_damage = dmg
		_is_crit = crit
		_radius = radius
		_delay = delay
		_cluster_bonus = cluster_bonus
		_main = main
		_cd = cd
		_attacker = attacker
		global_position = pos
		
		# Warning indicator
		_indicator = Sprite2D.new()
		_indicator.texture = _make_target_tex()
		_indicator.modulate = Color(1.0, 0.3, 0.1, 0.6)
		add_child(_indicator)
		
		# Beam line from sky
		_warning_line = Line2D.new()
		_warning_line.add_point(Vector2(0, -400))
		_warning_line.add_point(Vector2.ZERO)
		_warning_line.width = 4
		_warning_line.default_color = Color(1.0, 0.5, 0.2, 0.3)
		add_child(_warning_line)
		
		# Play warning VFX
		var v := _main.get_node_or_null("/root/VfxSystem") if _main else null
		if v and is_instance_valid(v) and v.has_method("play_event"):
			v.play_event("weapon.orbital_warning", pos, _main, Color(1.0, 0.3, 0.1, 0.8), _radius / 80.0)
	
	func _make_target_tex() -> ImageTexture:
		var size := int(_radius * 2)
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var center := Vector2(size / 2, size / 2)
		for x in range(size):
			for y in range(size):
				var d := Vector2(x, y).distance_to(center)
				if d <= _radius and d >= _radius - 4:
					img.set_pixel(x, y, Color(1, 1, 1, 0.9))
				elif absf(x - size/2) < 2 or absf(y - size/2) < 2:
					if d < _radius:
						img.set_pixel(x, y, Color(1, 1, 1, 0.5))
		return ImageTexture.create_from_image(img)
	
	func _process(delta: float) -> void:
		_elapsed += delta
		var progress := _elapsed / _delay
		
		# Intensify warning
		_indicator.modulate.a = 0.3 + 0.5 * progress
		_warning_line.default_color.a = 0.2 + 0.6 * progress
		_warning_line.width = 4 + 12 * progress
		
		# Play charge SFX midway
		if not _played_charge_sfx and progress > 0.3:
			_played_charge_sfx = true
			var s := _main.get_node_or_null("/root/SfxSystem") if _main else null
			if s and is_instance_valid(s) and s.has_method("play_event"):
				s.play_event("weapon.orbital_charge", global_position, self)
			var v2 := _main.get_node_or_null("/root/VfxSystem") if _main else null
			if v2 and is_instance_valid(v2) and v2.has_method("play_event"):
				v2.play_event("weapon.orbital_charge", global_position, _main, Color(1.0, 0.55, 0.25, 0.95), maxf(0.8, _radius / 90.0))
		
		if _elapsed >= _delay:
			_strike()
	
	func _strike() -> void:
		var enemies: Array = []
		if _main and is_instance_valid(_main) and _main.has_method("get_cached_enemies"):
			enemies = _main.get_cached_enemies()
		
		var r2 := _radius * _radius
		var in_range: Array[Node2D] = []
		for e in enemies:
			if not is_instance_valid(e):
				continue
			var n2 := e as Node2D
			if n2 == null:
				continue
			if n2.global_position.distance_squared_to(global_position) <= r2:
				in_range.append(n2)
		var dmg := _damage
		if _cluster_bonus > 0.0 and in_range.size() >= 3:
			dmg = int(round(float(_damage) * (1.0 + _cluster_bonus)))
			if _main != null and is_instance_valid(_main):
				var fm := VfxFocusMark.new()
				fm.setup(global_position + Vector2(0, -10), Color(1.0, 0.7, 0.35, 1.0), 22.0, 0, 0.22)
				_main.add_child(fm)
				var s := _main.get_node_or_null("/root/SfxSystem")
				if s and is_instance_valid(s) and s.has_method("play_event"):
					s.play_event("passive.orbital_precision", global_position, self)
		for n in in_range:
			if n.has_method("take_damage"):
				n.take_damage(dmg, _is_crit, "orbital_strike")
		
		# Big explosion VFX
		var v := _main.get_node_or_null("/root/VfxSystem") if _main else null
		if v and is_instance_valid(v) and v.has_method("play_event"):
			v.play_event("weapon.orbital_strike", global_position, _main, Color(1.0, 0.5, 0.1, 1.0), _radius / 60.0)
			v.play_event("weapon.orbital_beam", global_position + Vector2(0, -200), _main, Color(1.0, 0.7, 0.3, 1.0), 1.5)
		else:
			# Fallback
			var sw := VfxShockwave.new()
			sw.setup(global_position, Color(1.0, 0.5, 0.1, 1.0), 20.0, _radius * 1.5, 6.0, 0.3)
			_main.add_child(sw)
		
		# Screen shake - BIG
		var shake := _main.get_node_or_null("/root/ScreenShake")
		if shake and is_instance_valid(shake) and shake.has_method("shake"):
			shake.shake(12.0, 0.25)
		
		# SFX
		var s := _main.get_node_or_null("/root/SfxSystem")
		if s and is_instance_valid(s) and s.has_method("play_event"):
			s.play_event("weapon.orbital_strike", global_position, self)
		
		queue_free()


# === LIGHTNING VFX ===
class LightningVfx extends Node2D:
	var _from: Vector2
	var _to: Vector2
	var _color: Color
	var _duration: float
	var _elapsed: float = 0.0
	var _line: Line2D
	
	func setup(from: Vector2, to: Vector2, color: Color, duration: float) -> void:
		_from = from
		_to = to
		_color = color
		_duration = duration
		
		_line = Line2D.new()
		_line.width = 3
		_line.default_color = color
		_generate_lightning_points()
		add_child(_line)
	
	func _generate_lightning_points() -> void:
		_line.clear_points()
		_line.add_point(_from)
		
		var dist := _from.distance_to(_to)
		var segments := int(dist / 20.0)
		var dir := (_to - _from).normalized()
		var perp := Vector2(-dir.y, dir.x)
		
		for i in range(1, segments):
			var t := float(i) / float(segments)
			var base := _from.lerp(_to, t)
			var offset := perp * randf_range(-15, 15)
			_line.add_point(base + offset)
		
		_line.add_point(_to)
	
	func _process(delta: float) -> void:
		_elapsed += delta
		_line.default_color.a = 1.0 - (_elapsed / _duration)
		
		if _elapsed >= _duration:
			queue_free()

