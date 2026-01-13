extends Node
class_name WeaponSystem

# Weapon System - handles different attack patterns based on weapon type
# Each weapon defines a unique way to deal damage

const WP := preload("res://scripts/WeaponProjectiles.gd")

static var _weapons: Dictionary = {}
static var _loaded: bool = false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open("res://data/weapons.json", FileAccess.READ)
	if f == null:
		push_warning("WeaponSystem: Could not open weapons.json")
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		_weapons = parsed as Dictionary

static func get_weapon(weapon_id: String) -> Dictionary:
	ensure_loaded()
	return _weapons.get(weapon_id, {}) as Dictionary

static func weapon_name(weapon_id: String) -> String:
	var w := get_weapon(weapon_id)
	return String(w.get("name", weapon_id.capitalize()))

static func weapon_description(weapon_id: String) -> String:
	var w := get_weapon(weapon_id)
	return String(w.get("description", ""))

static func weapon_icon(weapon_id: String) -> String:
	var w := get_weapon(weapon_id)
	return String(w.get("icon", "•"))

static func weapon_tags(weapon_id: String) -> Array:
	var w := get_weapon(weapon_id)
	return w.get("tags", []) as Array

static func has_tag(weapon_id: String, tag: String) -> bool:
	return weapon_tags(weapon_id).has(tag)

static func all_weapon_ids() -> Array:
	ensure_loaded()
	return _weapons.keys()

# Execute an attack with the given weapon
static func execute_attack(
	weapon_id: String,
	attacker: Node2D,
	target: Node2D,
	damage: int,
	is_crit: bool,
	main_node: Node2D,
	character_data: CharacterData
) -> void:
	ensure_loaded()
	var w := get_weapon(weapon_id)
	if w.is_empty():
		# Fallback to standard projectile
		_fire_standard_projectile(attacker, target, damage, is_crit, main_node, character_data)
		return
	
	var wtype := String(w.get("type", "projectile"))
	
	match wtype:
		"projectile":
			_fire_standard_projectile(attacker, target, damage, is_crit, main_node, character_data)
		"melee_arc":
			_execute_melee_arc(attacker, target, damage, is_crit, main_node, character_data, w)
		"bomb":
			_fire_bomb(attacker, target, damage, is_crit, main_node, character_data, w)
		"chain":
			_fire_chain_lightning(attacker, target, damage, is_crit, main_node, character_data, w)
		"pierce":
			_fire_piercing_shot(attacker, target, damage, is_crit, main_node, character_data, w)
		"scatter":
			_fire_scatter_shot(attacker, target, damage, is_crit, main_node, character_data, w)
		"boomerang":
			_fire_boomerang(attacker, target, damage, is_crit, main_node, character_data, w)
		"beam":
			_fire_beam(attacker, target, damage, is_crit, main_node, character_data, w)
		"slam":
			_execute_ground_slam(attacker, damage, is_crit, main_node, character_data, w)
		"dot_projectile":
			_fire_dot_projectile(attacker, target, damage, is_crit, main_node, character_data, w)
		"slow_projectile":
			_fire_slow_projectile(attacker, target, damage, is_crit, main_node, character_data, w)
		"cone":
			_fire_cone(attacker, target, damage, is_crit, main_node, character_data, w)
		"delayed_strike":
			_fire_delayed_strike(attacker, target, damage, is_crit, main_node, character_data, w)
		"lifesteal_melee":
			_execute_lifesteal_melee(attacker, target, damage, is_crit, main_node, character_data, w)
		"ricochet":
			_fire_ricochet(attacker, target, damage, is_crit, main_node, character_data, w)
		"orbital":
			_fire_orbital_strike(attacker, target, damage, is_crit, main_node, character_data, w)
		_:
			_fire_standard_projectile(attacker, target, damage, is_crit, main_node, character_data)

# === WEAPON IMPLEMENTATIONS ===

static func _fire_standard_projectile(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData) -> void:
	var proj_scene: PackedScene = load("res://scenes/Projectile.tscn")
	if proj_scene == null:
		return
	var proj := proj_scene.instantiate()
	main_node.add_child(proj)
	proj.global_position = attacker.global_position
	if proj.has_method("setup_target"):
		proj.setup_target(target, damage, is_crit, cd.passive_ids if cd else [], cd, attacker)
	_play_sfx(main_node, "player.shot", attacker.global_position)

static func _execute_melee_arc(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var arc_radius := float(w.get("arc_radius", 85))
	var arc_angle := float(w.get("arc_angle", 120))
	var falloff := float(w.get("damage_falloff", 0.7))
	
	var dir := (target.global_position - attacker.global_position).normalized()
	var angle_to_target := dir.angle()
	var half_arc := deg_to_rad(arc_angle / 2.0)
	
	# Hit all enemies in the arc
	var enemies := _get_enemies(main_node)
	var hit_count := 0
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		var to_enemy := n2.global_position - attacker.global_position
		var dist := to_enemy.length()
		if dist > arc_radius:
			continue
		var angle_to_e := to_enemy.angle()
		var angle_diff := absf(angle_difference(angle_to_target, angle_to_e))
		if angle_diff > half_arc:
			continue
		# Hit this enemy
		var dmg := damage if hit_count == 0 else int(float(damage) * falloff)
		if n2.has_method("take_damage"):
			n2.take_damage(dmg, is_crit and hit_count == 0, "reaper_slash")
		hit_count += 1
	
	# VFX: big slash arc
	_play_vfx(main_node, "weapon.reaper_slash", attacker.global_position + dir * arc_radius * 0.5)
	_play_sfx(main_node, "weapon.reaper_slash", attacker.global_position)

static func _fire_bomb(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var bomb := WP.BombProjectile.new()
	bomb.setup(
		attacker.global_position,
		target.global_position,
		damage,
		is_crit,
		float(w.get("explosion_radius", 70)),
		float(w.get("projectile_speed", 380)),
		main_node,
		cd,
		attacker
	)
	main_node.add_child(bomb)
	_play_sfx(main_node, "weapon.bomb_launch", attacker.global_position)

static func _fire_chain_lightning(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var chain_count := int(w.get("chain_count", 3))
	var decay := float(w.get("chain_damage_decay", 0.75))
	var chain_range := float(w.get("chain_range", 120))
	
	var hit_targets: Array[Node2D] = []
	var current_target := target
	var current_pos := attacker.global_position
	var current_damage := damage
	
	for i in range(chain_count):
		if current_target == null or not is_instance_valid(current_target):
			break
		
		# Deal damage
		if current_target.has_method("take_damage"):
			current_target.take_damage(current_damage, is_crit and i == 0, "chain_lightning")
		hit_targets.append(current_target)
		
		# Lightning VFX between points
		_spawn_lightning_vfx(main_node, current_pos, current_target.global_position)
		_play_vfx(main_node, "weapon.chain_hit", current_target.global_position)
		_play_sfx(main_node, "weapon.chain_lightning", current_target.global_position)
		current_pos = current_target.global_position
		
		# Find next target
		current_damage = int(float(current_damage) * decay)
		current_target = _find_nearest_enemy_excluding(main_node, current_pos, hit_targets, chain_range)

static func _fire_piercing_shot(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var proj_scene: PackedScene = load("res://scenes/Projectile.tscn")
	if proj_scene == null:
		return
	var proj := proj_scene.instantiate()
	main_node.add_child(proj)
	proj.global_position = attacker.global_position
	
	var pierce := int(w.get("pierce_count", 4))
	if proj.has_method("add_pierce"):
		proj.add_pierce(pierce)
	if proj.has_method("set_speed"):
		proj.set_speed(float(w.get("projectile_speed", 750)))
	if proj.has_method("setup_target"):
		proj.setup_target(target, damage, is_crit, cd.passive_ids if cd else [], cd, attacker)
	_play_sfx(main_node, "player.shot", attacker.global_position)

static func _fire_scatter_shot(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var proj_count := int(w.get("projectile_count", 5))
	var spread := float(w.get("spread_angle", 45))
	var dmg_per := float(w.get("damage_per_proj", 0.4))
	
	var dir := (target.global_position - attacker.global_position).normalized()
	var base_angle := dir.angle()
	var half_spread := deg_to_rad(spread / 2.0)
	var angle_step := deg_to_rad(spread) / maxf(1.0, float(proj_count - 1))
	
	var proj_scene: PackedScene = load("res://scenes/Projectile.tscn")
	if proj_scene == null:
		return
	
	for i in range(proj_count):
		var angle := base_angle - half_spread + angle_step * float(i)
		var proj := proj_scene.instantiate()
		main_node.add_child(proj)
		proj.global_position = attacker.global_position
		if proj.has_method("setup_direction"):
			proj.setup_direction(Vector2.from_angle(angle), int(float(damage) * dmg_per), is_crit and i == proj_count / 2, cd, attacker)
		elif proj.has_method("setup_target"):
			proj.setup_target(target, int(float(damage) * dmg_per), is_crit and i == proj_count / 2, [], cd, attacker)
	
	_play_sfx(main_node, "player.shot", attacker.global_position)

static func _fire_boomerang(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var boomerang := WP.BoomerangProjectile.new()
	boomerang.setup(
		attacker,
		target.global_position,
		damage,
		is_crit,
		float(w.get("return_damage_mult", 0.6)),
		float(w.get("travel_distance", 200)),
		float(w.get("projectile_speed", 450)),
		main_node,
		cd
	)
	main_node.add_child(boomerang)
	_play_sfx(main_node, "player.shot", attacker.global_position)

static func _fire_beam(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var beam := WP.BeamAttack.new()
	beam.setup(
		attacker,
		(target.global_position - attacker.global_position).normalized(),
		damage,
		is_crit,
		float(w.get("beam_length", 350)),
		float(w.get("beam_width", 16)),
		float(w.get("duration", 0.5)),
		float(w.get("tick_rate", 0.1)),
		main_node,
		cd
	)
	main_node.add_child(beam)
	_play_sfx(main_node, "hit.crit", attacker.global_position)

static func _execute_ground_slam(attacker: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var inner_r := float(w.get("inner_radius", 40))
	var outer_r := float(w.get("outer_radius", 100))
	var inner_mult := float(w.get("inner_damage_mult", 1.2))
	var outer_mult := float(w.get("outer_damage_mult", 0.5))
	
	var pos := attacker.global_position
	var enemies := _get_enemies(main_node)
	
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		var dist := n2.global_position.distance_to(pos)
		if dist > outer_r:
			continue
		var dmg := int(float(damage) * (inner_mult if dist <= inner_r else outer_mult))
		if n2.has_method("take_damage"):
			n2.take_damage(dmg, is_crit, "ground_slam")
	
	# VFX: big shockwave
	_play_vfx(main_node, "weapon.ground_slam", pos, Color(0.8, 0.5, 0.2, 1.0), outer_r / 80.0)
	_play_vfx(main_node, "weapon.ground_slam_inner", pos, Color(0.9, 0.7, 0.4, 1.0), inner_r / 40.0)
	_play_sfx(main_node, "weapon.slam", pos)

static func _fire_dot_projectile(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var proj := WP.DotProjectile.new()
	proj.setup(
		attacker.global_position,
		target,
		damage,
		is_crit,
		float(w.get("dot_damage_percent", 0.30)),
		float(w.get("dot_duration", 4.0)),
		float(w.get("dot_tick", 0.5)),
		float(w.get("projectile_speed", 700)),
		main_node,
		cd,
		attacker
	)
	main_node.add_child(proj)
	_play_sfx(main_node, "player.shot", attacker.global_position)

static func _fire_slow_projectile(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var proj := WP.SlowProjectile.new()
	proj.setup(
		attacker.global_position,
		target,
		damage,
		is_crit,
		float(w.get("slow_percent", 0.40)),
		float(w.get("slow_duration", 2.5)),
		float(w.get("projectile_speed", 500)),
		main_node,
		cd,
		attacker
	)
	main_node.add_child(proj)
	_play_sfx(main_node, "player.shot", attacker.global_position)

static func _fire_cone(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var cone_angle := float(w.get("cone_angle", 60))
	var cone_range := float(w.get("cone_range", 150))
	var burn_pct := float(w.get("burn_damage_percent", 0.25))
	var burn_dur := float(w.get("burn_duration", 3.0))
	
	var dir := (target.global_position - attacker.global_position).normalized()
	var angle_to_target := dir.angle()
	var half_cone := deg_to_rad(cone_angle / 2.0)
	
	var enemies := _get_enemies(main_node)
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		var to_enemy := n2.global_position - attacker.global_position
		var dist := to_enemy.length()
		if dist > cone_range:
			continue
		var angle_diff := absf(angle_difference(angle_to_target, to_enemy.angle()))
		if angle_diff > half_cone:
			continue
		# Hit and burn
		if n2.has_method("take_damage"):
			n2.take_damage(damage, is_crit, "fire_cone")
		if n2.has_method("apply_burn"):
			var dps := float(damage) * burn_pct / burn_dur
			n2.apply_burn(dps, burn_dur, 0.5)
		# Per-enemy burn VFX
		_play_vfx(main_node, "weapon.fire_burn", n2.global_position)
	
	# Cone VFX
	_play_vfx(main_node, "weapon.fire_cone", attacker.global_position + dir * cone_range * 0.4, Color(1.0, 0.4, 0.1, 1.0), cone_range / 100.0)
	_play_sfx(main_node, "weapon.fire", attacker.global_position)

static func _fire_delayed_strike(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var delay := float(w.get("delay", 0.4))
	var radius := float(w.get("strike_radius", 35))
	var count := int(w.get("strike_count", 3))
	
	for i in range(count):
		var offset := Vector2(randf_range(-40, 40), randf_range(-40, 40))
		var strike_pos := target.global_position + offset
		var strike := WP.DelayedStrike.new()
		strike.setup(strike_pos, damage / count, is_crit and i == 0, radius, delay + float(i) * 0.15, main_node, cd, attacker)
		main_node.add_child(strike)
	
	_play_sfx(main_node, "player.shot", attacker.global_position)

static func _execute_lifesteal_melee(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var lifesteal := float(w.get("lifesteal_percent", 0.25))
	
	if target.has_method("take_damage"):
		target.take_damage(damage, is_crit, "vampiric_strike")
	
	# Heal attacker
	var heal_amount := int(float(damage) * lifesteal)
	if heal_amount > 0 and attacker.has_method("heal"):
		attacker.heal(heal_amount)
	
	# VFX
	_spawn_melee_vfx(main_node, target.global_position, (target.global_position - attacker.global_position).normalized(), Color(0.8, 0.1, 0.3, 1.0))
	_play_sfx(main_node, "hit.melee", target.global_position)

static func _fire_ricochet(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var ricochet := WP.RicochetProjectile.new()
	ricochet.setup(
		attacker.global_position,
		target,
		damage,
		is_crit,
		int(w.get("bounce_count", 4)),
		float(w.get("bounce_range", 150)),
		float(w.get("damage_per_bounce", 0.9)),
		main_node,
		cd,
		attacker
	)
	main_node.add_child(ricochet)
	_play_sfx(main_node, "player.shot", attacker.global_position)

static func _fire_orbital_strike(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var delay := float(w.get("delay", 1.2))
	var radius := float(w.get("explosion_radius", 90))
	var dmg_mult := float(w.get("damage_mult", 1.8))
	
	var strike := WP.OrbitalStrike.new()
	strike.setup(target.global_position, int(float(damage) * dmg_mult), is_crit, radius, delay, main_node, cd, attacker)
	main_node.add_child(strike)
	_play_sfx(main_node, "player.shot", attacker.global_position)

# === HELPERS ===

static func _get_enemies(main_node: Node2D) -> Array:
	if main_node and is_instance_valid(main_node) and main_node.has_method("get_cached_enemies"):
		return main_node.get_cached_enemies()
	return main_node.get_tree().get_nodes_in_group("enemies") if main_node else []

static func _find_nearest_enemy_excluding(main_node: Node2D, from_pos: Vector2, exclude: Array, max_range: float) -> Node2D:
	var enemies := _get_enemies(main_node)
	var best: Node2D = null
	var best_dist := max_range * max_range
	for e in enemies:
		if not is_instance_valid(e) or exclude.has(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		var d2 := n2.global_position.distance_squared_to(from_pos)
		if d2 < best_dist:
			best_dist = d2
			best = n2
	return best

static func _play_sfx(main_node: Node2D, event: String, pos: Vector2) -> void:
	if main_node == null:
		return
	var s := main_node.get_node_or_null("/root/SfxSystem")
	if s and is_instance_valid(s) and s.has_method("play_event"):
		s.play_event(event, pos, main_node)

static func _play_vfx(main_node: Node2D, event: String, pos: Vector2, tint: Color = Color.WHITE, scale: float = 1.0) -> void:
	if main_node == null:
		return
	var v := main_node.get_node_or_null("/root/VfxSystem")
	if v and is_instance_valid(v) and v.has_method("play_event"):
		v.play_event(event, pos, main_node, tint, scale)

static func _spawn_arc_vfx(main_node: Node2D, pos: Vector2, dir: Vector2, radius: float, color: Color) -> void:
	var v := main_node.get_node_or_null("/root/VfxSystem") if main_node else null
	if v and is_instance_valid(v) and v.has_method("play_event"):
		v.play_event("hit.melee", pos + dir * radius * 0.5, main_node, color, radius / 50.0)

static func _spawn_lightning_vfx(main_node: Node2D, from_pos: Vector2, to_pos: Vector2) -> void:
	var lightning := WP.LightningVfx.new()
	lightning.setup(from_pos, to_pos, Color(0.6, 0.8, 1.0, 1.0), 0.15)
	main_node.add_child(lightning)

static func _spawn_shockwave_vfx(main_node: Node2D, pos: Vector2, radius: float, color: Color) -> void:
	var sw := VfxShockwave.new()
	sw.setup(pos, color, 10.0, radius, 4.0, 0.25)
	main_node.add_child(sw)

static func _spawn_melee_vfx(main_node: Node2D, pos: Vector2, dir: Vector2, color: Color) -> void:
	var streak := VfxMeleeStreak.new()
	streak.setup(pos, dir, color, 50.0, 12.0, 0.12)
	main_node.add_child(streak)

static func _spawn_cone_vfx(main_node: Node2D, pos: Vector2, dir: Vector2, range_val: float, angle: float, color: Color) -> void:
	var v := main_node.get_node_or_null("/root/VfxSystem") if main_node else null
	if v and is_instance_valid(v) and v.has_method("play_event"):
		v.play_event("syn.flame", pos + dir * range_val * 0.4, main_node, color, range_val / 100.0)

