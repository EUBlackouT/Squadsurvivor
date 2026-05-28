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
		_fire_standard_projectile(attacker, target, damage, is_crit, main_node, character_data)
		return
	if character_data != null:
		w = PassiveSystem.apply_weapon_mods(weapon_id, w, character_data.passive_ids)
	
	var wtype := String(w.get("type", "projectile"))
	# Every ranged/cast attack gets a visible cast flash in addition to hit VFX.
	if _is_ranged_weapon_type(wtype):
		_play_vfx(main_node, "player.shot", attacker.global_position + Vector2(0, -10), Color.WHITE, 1.35)
	
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
		"whirlwind":
			_execute_whirlwind(attacker, damage, is_crit, main_node, character_data, w)
		"heavy_melee":
			_execute_heavy_strike(attacker, target, damage, is_crit, main_node, character_data, w)
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

static func _is_ranged_weapon_type(wtype: String) -> bool:
	match wtype:
		"projectile", "bomb", "chain", "pierce", "scatter", "boomerang", "beam", "dot_projectile", "slow_projectile", "cone", "delayed_strike", "ricochet", "orbital":
			return true
		_:
			return false

# === WEAPON IMPLEMENTATIONS ===

static func _fire_standard_projectile(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData) -> void:
	var proj_scene: PackedScene = load("res://scenes/Projectile.tscn")
	if proj_scene == null:
		return
	var count := 1 + maxi(0, int(round(_get_mp_add(main_node, "projectile_count_add", 0.0))))
	var dmg_mult := _get_mp_mod(main_node, "projectile_damage_mult", 1.0)
	var pierce_add := maxi(0, int(round(_get_mp_add(main_node, "projectile_pierce_add", 0.0))))
	var dir := (target.global_position - attacker.global_position).normalized()
	for i in range(count):
		var proj := proj_scene.instantiate()
		main_node.add_child(proj)
		proj.global_position = attacker.global_position
		if proj.has_method("set_visual_profile"):
			proj.set_visual_profile("bolt")
		if proj.has_method("add_pierce") and pierce_add > 0:
			proj.add_pierce(pierce_add)
		var p_dmg := maxi(1, int(round(float(damage) * dmg_mult * (1.0 if i == 0 else 0.82))))
		if proj.has_method("setup_direction") and count > 1:
			var a := dir.angle() + deg_to_rad(randf_range(-4.0, 4.0))
			proj.setup_direction(Vector2.from_angle(a), p_dmg, is_crit and i == 0, cd, attacker)
		elif proj.has_method("setup_target"):
			proj.setup_target(target, p_dmg, is_crit and i == 0, cd.passive_ids if cd else [], cd, attacker)
	_play_sfx(main_node, "player.shot", attacker.global_position)

static func _execute_melee_arc(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var arc_radius := float(w.get("arc_radius", 110))
	var arc_angle := float(w.get("arc_angle", 160))
	var falloff := float(w.get("damage_falloff", 0.8))
	var dmg_bonus := float(w.get("damage_bonus", 1.5))
	var heal_mult := float(w.get("reaper_hunger_heal_mult", 0.0))
	var kill_mult := float(w.get("reaper_hunger_kill_mult", 0.0))
	
	var base_dmg := int(float(damage) * dmg_bonus)
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
		# Hit this enemy - full damage to all in arc
		var dmg := base_dmg if hit_count == 0 else int(float(base_dmg) * falloff)
		if n2.has_method("take_damage"):
			n2.take_damage(dmg, is_crit and hit_count == 0, "reaper_slash")
		if heal_mult > 0.0 and attacker.has_method("heal"):
			attacker.heal(int(round(float(dmg) * heal_mult)))
			var hp := VfxHolyPulse.new()
			hp.setup(attacker.global_position + Vector2(0, -16), Color(0.8, 0.35, 0.45, 1.0), 10.0, 26.0, 0.18)
			main_node.add_child(hp)
			_play_sfx(main_node, "passive.reaper_hunger", attacker.global_position)
		if kill_mult > heal_mult:
			n2.set_meta("_reaper_hunger_attacker", attacker)
			n2.set_meta("_reaper_hunger_kill_heal", int(round(float(dmg) * (kill_mult - heal_mult))))
		hit_count += 1
	
	# VFX: big visible slash arc
	_spawn_melee_arc_vfx(main_node, attacker.global_position, dir, arc_radius, arc_angle)
	_play_sfx(main_node, "weapon.reaper_slash", attacker.global_position)
	
	# Screen shake for melee impact
	var shake := main_node.get_node_or_null("/root/ScreenShake")
	if shake and is_instance_valid(shake) and hit_count > 0:
		shake.shake(3.0 + float(hit_count), 0.08)

static func _spawn_melee_arc_vfx(main_node: Node2D, origin: Vector2, dir: Vector2, radius: float, angle_deg: float) -> void:
	# Create visible arc slash
	var arc := Line2D.new()
	arc.z_index = 2100
	arc.width = 8.0
	arc.default_color = Color(1.0, 0.9, 0.7, 0.9)
	arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
	arc.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	var base_angle := dir.angle()
	var half := deg_to_rad(angle_deg / 2.0)
	var points: PackedVector2Array = []
	var segments := 12
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var a := base_angle - half + t * half * 2.0
		points.append(origin + Vector2.from_angle(a) * radius)
	arc.points = points
	main_node.add_child(arc)
	
	# Fade out
	var tw := arc.create_tween()
	tw.tween_property(arc, "modulate:a", 0.0, 0.15)
	tw.tween_callback(arc.queue_free)

static func _fire_bomb(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var bomb := WP.BombProjectile.new()
	var radius := float(w.get("explosion_radius", 70)) + _get_mp_add(main_node, "bomb_radius_add", 0.0)
	radius *= _keystone_power_scale(main_node, 0.035)
	var delay_mult := maxf(0.6, _get_mp_mod(main_node, "bomb_delay_mult", 1.0))
	var speed := float(w.get("projectile_speed", 380)) / delay_mult
	var out_damage := maxi(1, int(round(float(damage) * _get_mp_mod(main_node, "bomb_damage_mult", 1.0))))
	bomb.setup(
		attacker.global_position,
		target.global_position,
		out_damage,
		is_crit,
		radius,
		float(w.get("burn_duration", 0.0)) * _get_mp_mod(main_node, "burn_duration_mult", 1.0),
		float(w.get("burn_dps_mult", 0.0)),
		speed,
		main_node,
		cd,
		attacker
	)
	main_node.add_child(bomb)
	var cluster_n := maxi(0, int(round(_get_mp_add(main_node, "bomb_cluster_count_add", 0.0))))
	if cluster_n > 0:
		var c_dmg_mult := _get_mp_mod(main_node, "bomb_cluster_damage_mult", 0.35)
		var c_rad_mult := _get_mp_mod(main_node, "bomb_cluster_radius_mult", 0.55)
		for i in range(cluster_n):
			var ang := TAU * float(i) / float(maxi(1, cluster_n))
			var off := Vector2.from_angle(ang) * 54.0
			var b2 := WP.BombProjectile.new()
			b2.setup(
				attacker.global_position,
				target.global_position + off,
				maxi(1, int(round(float(out_damage) * c_dmg_mult))),
				false,
				maxf(20.0, radius * c_rad_mult),
				float(w.get("burn_duration", 0.0)) * _get_mp_mod(main_node, "burn_duration_mult", 1.0),
				float(w.get("burn_dps_mult", 0.0)),
				speed * 0.92,
				main_node,
				cd,
				attacker
			)
			main_node.add_child(b2)
	_play_sfx(main_node, "weapon.bomb_launch", attacker.global_position)

static func _fire_chain_lightning(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var chain_count := int(w.get("chain_count", 3))
	var decay := float(w.get("chain_damage_decay", 0.75))
	var chain_range := float(w.get("chain_range", 120))
	var isolated_mult := 1.0
	var rehit_enabled := false
	var rehit_mult := 0.45
	var kill_shock_radius := 0.0
	var kill_shock_mult := 0.0
	var mp := main_node.get_node_or_null("/root/MetaProgression") if main_node != null else null
	if mp and is_instance_valid(mp):
		if mp.has_method("get_add"):
			chain_count += maxi(0, int(round(float(mp.get_add("chain_jumps_add", 0.0)))))
			decay = clampf(decay * float(mp.get_mod("chain_damage_falloff_mult", 1.0)) if mp.has_method("get_mod") else decay, 0.20, 0.99)
			chain_count += maxi(0, int(round(float(mp.get_add("mage_chain_jumps_add", 0.0)))))
			chain_range += float(mp.get_add("mage_chain_range_add", 0.0))
			kill_shock_radius = maxf(0.0, float(mp.get_add("chain_kill_shock_radius_add", 0.0)))
			kill_shock_mult = maxf(0.0, float(mp.get_add("chain_kill_shock_damage_mult", 0.0)))
			rehit_enabled = float(mp.get_add("chain_can_rehit_targets", 0.0)) >= 1.0
			rehit_mult = maxf(0.1, float(mp.get_add("chain_rehit_damage_mult", 0.45)))
		if mp.has_method("get_mod"):
			isolated_mult = float(mp.get_mod("mage_single_target_mult", 1.0))
	if cd != null and PassiveSystem.has_passive(cd.passive_ids, "chain_master"):
		var world := main_node
		if world != null:
			var pos := attacker.global_position + Vector2(0, -14)
			var fx := VfxImpactFlash.new()
			fx.setup(pos, Color(0.35, 0.85, 1.0, 1.0), 14.0, 0.12)
			world.add_child(fx)
			var fm := VfxFocusMark.new()
			fm.setup(pos, Color(0.55, 0.95, 1.0, 1.0), 16.0, 0, 0.18)
			world.add_child(fm)
			_play_sfx(main_node, "passive.chain_master", attacker.global_position)
	
	var hit_targets: Array[Node2D] = []
	var current_target := target
	var current_pos := attacker.global_position
	var current_damage := damage
	
	for i in range(chain_count):
		if current_target == null or not is_instance_valid(current_target):
			break
		
		# Deal damage
		if current_target.has_method("take_damage"):
			var dmg_i := current_damage
			if i == 0 and isolated_mult < 0.999:
				var near := _find_nearest_enemy_excluding(main_node, current_target.global_position, [current_target], chain_range)
				if near == null:
					dmg_i = maxi(1, int(round(float(dmg_i) * isolated_mult)))
			var pre_ratio := 1.0
			if current_target.has_method("get_hp_ratio"):
				pre_ratio = float(current_target.get_hp_ratio())
			current_target.take_damage(dmg_i, is_crit and i == 0, "chain_lightning")
			var post_ratio := 1.0
			if current_target.has_method("get_hp_ratio"):
				post_ratio = float(current_target.get_hp_ratio())
			if kill_shock_radius > 0.0 and kill_shock_mult > 0.0 and pre_ratio > 0.0 and post_ratio <= 0.0:
				_chain_kill_shock(main_node, current_target.global_position, dmg_i, kill_shock_radius, kill_shock_mult)
		hit_targets.append(current_target)
		
		# Lightning VFX between points
		_spawn_lightning_vfx(main_node, current_pos, current_target.global_position)
		_play_vfx(main_node, "weapon.chain_hit", current_target.global_position)
		_play_sfx(main_node, "weapon.chain_lightning", current_target.global_position)
		current_pos = current_target.global_position
		
		# Find next target
		current_damage = int(float(current_damage) * decay)
		current_target = _find_nearest_enemy_excluding(main_node, current_pos, hit_targets, chain_range)
		if current_target == null and rehit_enabled and not hit_targets.is_empty():
			var pick := hit_targets[randi() % hit_targets.size()]
			if pick != null and is_instance_valid(pick):
				current_target = pick
				current_damage = maxi(1, int(round(float(current_damage) * rehit_mult)))

static func _chain_kill_shock(main_node: Node2D, origin: Vector2, source_damage: int, radius: float, mult: float) -> void:
	if main_node == null:
		return
	var enemies := _get_enemies(main_node)
	var r2 := radius * radius
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) > r2:
			continue
		if n2.has_method("take_damage"):
			var dealt := maxi(1, int(round(float(source_damage) * mult)))
			n2.take_damage(dealt, false, "chain_kill_shock")
	_spawn_lightning_vfx(main_node, origin, origin + Vector2(radius * 0.4, 0))

static func _fire_piercing_shot(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var proj_scene: PackedScene = load("res://scenes/Projectile.tscn")
	if proj_scene == null:
		return
	var proj := proj_scene.instantiate()
	main_node.add_child(proj)
	proj.global_position = attacker.global_position
	
	var pierce := int(w.get("pierce_count", 4)) + maxi(0, int(round(_get_mp_add(main_node, "projectile_pierce_add", 0.0))))
	var out_damage := maxi(1, int(round(float(damage) * _get_mp_mod(main_node, "projectile_damage_mult", 1.0))))
	if proj.has_method("add_pierce"):
		proj.add_pierce(pierce)
	if proj.has_method("set_speed"):
		proj.set_speed(float(w.get("projectile_speed", 750)))
	if proj.has_method("set_visual_profile"):
		proj.set_visual_profile("pierce")
	if proj.has_method("setup_target"):
		proj.setup_target(target, out_damage, is_crit, cd.passive_ids if cd else [], cd, attacker)
	_play_sfx(main_node, "weapon.pierce", attacker.global_position)

static func _fire_scatter_shot(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var proj_count := int(w.get("projectile_count", 5))
	var spread := float(w.get("spread_angle", 45))
	var dmg_per := float(w.get("damage_per_proj", 0.4))
	proj_count += maxi(0, int(round(_get_mp_add(main_node, "projectile_count_add", 0.0))))
	spread *= _get_mp_mod(main_node, "projectile_spread_mult", 1.0)
	dmg_per *= _get_mp_mod(main_node, "projectile_damage_mult", 1.0)
	var pierce_add := maxi(0, int(round(_get_mp_add(main_node, "projectile_pierce_add", 0.0))))
	if cd != null and PassiveSystem.has_passive(cd.passive_ids, "scatter_specialist"):
		var dir := (target.global_position - attacker.global_position).normalized()
		var fb := VfxFlameBurst.new()
		fb.setup(attacker.global_position, Color(0.95, 0.85, 0.35, 1.0), 26.0, 10, 0.18, dir)
		main_node.add_child(fb)
		_play_sfx(main_node, "passive.scatter_specialist", attacker.global_position)
	
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
		if proj.has_method("set_visual_profile"):
			proj.set_visual_profile("scatter")
		if proj.has_method("add_pierce") and pierce_add > 0:
			proj.add_pierce(pierce_add)
		if proj.has_method("set_speed"):
			proj.set_speed(float(w.get("projectile_speed", 660)))
		if proj.has_method("setup_direction"):
			proj.setup_direction(Vector2.from_angle(angle), int(float(damage) * dmg_per), is_crit and i == proj_count / 2, cd, attacker)
		elif proj.has_method("setup_target"):
			proj.setup_target(target, int(float(damage) * dmg_per), is_crit and i == proj_count / 2, [], cd, attacker)
	
	_play_sfx(main_node, "weapon.scatter", attacker.global_position)

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
	_play_sfx(main_node, "weapon.boomerang", attacker.global_position)
	if cd != null and PassiveSystem.has_passive(cd.passive_ids, "boomerang_mastery"):
		var ms := VfxMeleeStreak.new()
		ms.setup(attacker.global_position, Vector2(1, 0), Color(0.55, 0.95, 0.90, 1.0), 36.0, 8.0, 0.10)
		main_node.add_child(ms)
		var ms2 := VfxMeleeStreak.new()
		ms2.setup(attacker.global_position, Vector2(0, 1), Color(0.35, 0.85, 0.95, 1.0), 32.0, 7.0, 0.10)
		main_node.add_child(ms2)
		_play_sfx(main_node, "passive.boomerang_mastery", attacker.global_position)

static func _fire_beam(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var beam := WP.BeamAttack.new()
	var ramp_ps := _get_mp_add(main_node, "beam_damage_ramp_per_second_add", 0.0)
	var ramp_cap := maxf(1.0, _get_mp_add(main_node, "beam_damage_ramp_cap", 1.0))
	var init_mult := _get_mp_mod(main_node, "beam_initial_damage_mult", 1.0)
	var sec_count := maxi(0, int(round(_get_mp_add(main_node, "beam_secondary_targets_add", 0.0))))
	var sec_mult := clampf(_get_mp_mod(main_node, "beam_secondary_damage_mult", 0.0), 0.0, 2.0)
	var lock_single := _get_mp_add(main_node, "beam_target_swap_resets_ramp", 0.0) >= 1.0
	var keystone_scale := _keystone_power_scale(main_node, 0.022)
	beam.setup(
		attacker,
		(target.global_position - attacker.global_position).normalized(),
		damage,
		is_crit,
		float(w.get("beam_length", 350)) * keystone_scale,
		float(w.get("beam_width", 16)),
		float(w.get("width_growth", 0.0)),
		float(w.get("duration", 0.5)) * lerpf(1.0, 1.20, keystone_scale - 1.0),
		float(w.get("tick_rate", 0.1)),
		main_node,
		cd,
		ramp_ps,
		ramp_cap,
		init_mult,
		sec_count,
		sec_mult,
		lock_single
	)
	main_node.add_child(beam)
	_play_sfx(main_node, "weapon.beam", attacker.global_position)
	if cd != null and PassiveSystem.has_passive(cd.passive_ids, "beam_focus"):
		var pos := attacker.global_position + (target.global_position - attacker.global_position).normalized() * 24.0
		var sw := VfxShockwave.new()
		sw.setup(pos, Color(1.0, 0.45, 0.55, 1.0), 10.0, 42.0, 4.0, 0.18)
		main_node.add_child(sw)
		_play_sfx(main_node, "passive.beam_focus", attacker.global_position)

static func _execute_ground_slam(attacker: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var inner_r := float(w.get("inner_radius", 55))
	var outer_r := float(w.get("outer_radius", 130))
	var inner_mult := float(w.get("inner_damage_mult", 1.4))
	var outer_mult := float(w.get("outer_damage_mult", 0.7))
	var dmg_bonus := float(w.get("damage_bonus", 1.4))
	
	var base_dmg := int(float(damage) * dmg_bonus)
	var pos := attacker.global_position
	var enemies := _get_enemies(main_node)
	var hit_count := 0
	
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		var dist := n2.global_position.distance_to(pos)
		if dist > outer_r:
			continue
		var dmg := int(float(base_dmg) * (inner_mult if dist <= inner_r else outer_mult))
		if n2.has_method("take_damage"):
			n2.take_damage(dmg, is_crit and hit_count == 0, "ground_slam")
		hit_count += 1
	
	# VFX: Create visible shockwave rings directly
	_spawn_slam_vfx(main_node, pos, inner_r, outer_r)
	_play_sfx(main_node, "weapon.slam", pos)
	
	# Screen shake
	var shake := main_node.get_node_or_null("/root/ScreenShake")
	if shake and is_instance_valid(shake) and shake.has_method("shake"):
		shake.shake(6.0, 0.15)

	# Passive: Aftershock
	if cd != null and PassiveSystem.has_passive(cd.passive_ids, "slam_aftershock"):
		var p := PassiveSystem.params_for("slam_aftershock")
		var delay := float(p.get("delay", 0.5))
		var mult := float(p.get("damage_mult", 0.5))
		var extra_dmg := int(round(float(base_dmg) * mult))
		if extra_dmg > 0 and main_node != null:
			var t := main_node.get_tree().create_timer(delay)
			t.timeout.connect(func():
				if main_node == null or not is_instance_valid(main_node):
					return
				var enemies2 := _get_enemies(main_node)
				for e2 in enemies2:
					if not is_instance_valid(e2):
						continue
					var n2 := e2 as Node2D
					if n2 == null:
						continue
					if n2.global_position.distance_to(pos) > outer_r:
						continue
					if n2.has_method("take_damage"):
						n2.take_damage(extra_dmg, false, "slam_aftershock")
				_spawn_shockwave_vfx(main_node, pos, outer_r * 0.9, Color(1.0, 0.65, 0.3, 0.9))
				var flash := VfxImpactFlash.new()
				flash.setup(pos, Color(1.0, 0.7, 0.35, 1.0), 22.0, 0.14)
				main_node.add_child(flash)
				_play_sfx(main_node, "passive.slam_aftershock", pos)
			)

static func _spawn_slam_vfx(main_node: Node2D, pos: Vector2, inner_r: float, outer_r: float) -> void:
	# Inner shockwave ring
	var inner := VfxShockwave.new()
	inner.setup(pos, Color(1.0, 0.7, 0.3, 1.0), 15.0, inner_r * 1.2, 6.0, 0.2)
	main_node.add_child(inner)
	
	# Outer shockwave ring
	var outer := VfxShockwave.new()
	outer.setup(pos, Color(0.9, 0.5, 0.2, 0.8), 20.0, outer_r * 1.1, 5.0, 0.3)
	main_node.add_child(outer)
	
	# Ground crack lines
	for i in range(8):
		var angle := TAU * float(i) / 8.0 + randf() * 0.3
		var line := _create_crack_line(pos, angle, outer_r * 0.9)
		main_node.add_child(line)
	
	# Dust particles
	for i in range(12):
		var angle := TAU * randf()
		var dist := randf_range(inner_r * 0.5, outer_r * 0.8)
		var dust_pos := pos + Vector2.from_angle(angle) * dist
		var dust := _create_dust_particle(dust_pos)
		main_node.add_child(dust)

static func _create_crack_line(origin: Vector2, angle: float, length: float) -> Line2D:
	var line := Line2D.new()
	line.z_index = 1900
	line.width = 3.0
	line.default_color = Color(0.3, 0.2, 0.1, 0.9)
	
	var points: PackedVector2Array = [origin]
	var pos := origin
	var remaining := length
	var seg_count := randi_range(3, 5)
	
	for i in range(seg_count):
		var seg_len := remaining / float(seg_count - i) * randf_range(0.7, 1.3)
		var deviation := randf_range(-0.3, 0.3)
		pos += Vector2.from_angle(angle + deviation) * seg_len
		points.append(pos)
		remaining -= seg_len
	
	line.points = points
	
	# Fade out
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.5)
	tween.tween_callback(line.queue_free)
	
	return line

static func _create_dust_particle(pos: Vector2) -> Sprite2D:
	var dust := Sprite2D.new()
	dust.global_position = pos
	dust.z_index = 2000
	
	var size := 8
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	for x in range(size):
		for y in range(size):
			var dist := Vector2(x, y).distance_to(center) / (size / 2.0)
			var alpha := maxf(0.0, 1.0 - dist) * 0.7
			img.set_pixel(x, y, Color(0.6, 0.5, 0.4, alpha))
	
	dust.texture = ImageTexture.create_from_image(img)
	dust.scale = Vector2(randf_range(1.5, 3.0), randf_range(1.5, 3.0))
	
	# Animate upward and fade
	var tween := dust.create_tween()
	tween.set_parallel(true)
	tween.tween_property(dust, "position:y", dust.position.y - randf_range(20, 40), 0.4)
	tween.tween_property(dust, "modulate:a", 0.0, 0.4)
	tween.set_parallel(false)
	tween.tween_callback(dust.queue_free)
	
	return dust

static func _fire_dot_projectile(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var proj := WP.DotProjectile.new()
	var dot_dur := float(w.get("dot_duration", 4.0)) * _get_mp_mod(main_node, "poison_duration_mult", 1.0)
	proj.setup(
		attacker.global_position,
		target,
		damage,
		is_crit,
		float(w.get("dot_damage_percent", 0.30)),
		float(w.get("poison_damage_mult", 1.0)),
		float(w.get("poison_spread_radius", 0.0)),
		dot_dur,
		float(w.get("dot_tick", 0.5)),
		float(w.get("projectile_speed", 700)),
		main_node,
		cd,
		attacker
	)
	main_node.add_child(proj)
	_play_sfx(main_node, "weapon.poison", attacker.global_position)
	_play_vfx(main_node, "weapon.poison", attacker.global_position + Vector2(0, -10))

static func _fire_slow_projectile(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var proj := WP.SlowProjectile.new()
	proj.setup(
		attacker.global_position,
		target,
		damage,
		is_crit,
		float(w.get("slow_percent", 0.40)),
		float(w.get("slow_bonus", 0.0)),
		float(w.get("shatter_radius", 0.0)),
		float(w.get("shatter_damage", 0.0)),
		float(w.get("slow_duration", 2.5)) * _get_mp_mod(main_node, "frost_slow_duration_mult", 1.0),
		float(w.get("projectile_speed", 500)),
		main_node,
		cd,
		attacker
	)
	main_node.add_child(proj)
	_play_sfx(main_node, "weapon.frost", attacker.global_position)
	_play_vfx(main_node, "weapon.frost", attacker.global_position + Vector2(0, -10))

static func _fire_cone(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var cone_angle := float(w.get("cone_angle", 60))
	var cone_range := float(w.get("cone_range", 150))
	var burn_pct := float(w.get("burn_damage_percent", 0.25))
	var burn_dur := float(w.get("burn_duration", 3.0))
	var spread_count := int(w.get("fire_spread_count", 0))
	var spread_radius := float(w.get("fire_spread_radius", 0.0))
	var damage_amp := float(w.get("fire_damage_amp", 0.0))
	
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
			var total_dmg := damage
			var burn_until: int = int(n2.get_meta("_burn_until_ms", 0))
			if damage_amp > 0.0 and burn_until > 0 and int(Time.get_ticks_msec()) <= burn_until:
				total_dmg += int(round(float(damage) * damage_amp))
			n2.take_damage(total_dmg, is_crit, "fire_cone")
		if n2.has_method("apply_burn"):
			var dps := float(damage) * burn_pct / burn_dur
			n2.apply_burn(dps, burn_dur * _get_mp_mod(main_node, "burn_duration_mult", 1.0), 0.5)
			PassiveSystem.mark_burn(n2, burn_dur)
			if spread_count > 0 and spread_radius > 0.0:
				PassiveSystem.mark_fire_spread(n2, dps, burn_dur, 0.5, spread_count)
				_play_sfx(main_node, "passive.fire_mastery", n2.global_position)
		# Per-enemy burn VFX (small flame on each enemy)
		_spawn_small_fire(main_node, n2.global_position)
	
	# Spawn proper cone particles
	_spawn_flame_cone_vfx(main_node, attacker.global_position, dir, cone_range, cone_angle)
	_play_sfx(main_node, "weapon.fire", attacker.global_position)

static func _spawn_flame_cone_vfx(main_node: Node2D, origin: Vector2, dir: Vector2, cone_range: float, cone_angle: float) -> void:
	# Create a proper cone-shaped flame effect using multiple small particles
	var base_angle := dir.angle()
	var half_cone := deg_to_rad(cone_angle / 2.0)
	var particle_count := 12
	
	for i in range(particle_count):
		var t := float(i) / float(particle_count - 1) if particle_count > 1 else 0.5
		var angle_offset := lerpf(-half_cone, half_cone, t)
		var p_angle := base_angle + angle_offset
		var particle_dir := Vector2.from_angle(p_angle)
		
		# Spawn 2-3 particles along each ray
		for j in range(3):
			var dist := cone_range * (0.3 + 0.7 * randf()) * (float(j + 1) / 3.0)
			var pos := origin + particle_dir * dist
			var particle := _create_flame_particle(main_node, pos, dist / cone_range)
			if particle:
				main_node.add_child(particle)

static func _create_flame_particle(main_node: Node2D, pos: Vector2, intensity: float) -> Node2D:
	var particle := Sprite2D.new()
	particle.global_position = pos
	particle.z_index = 2100
	
	# Create a bright, vibrant flame texture
	var size := 24
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	for x in range(size):
		for y in range(size):
			var dist := Vector2(x, y).distance_to(center) / (size / 2.0)
			var alpha := maxf(0.0, 1.0 - dist * dist) * (0.7 + intensity * 0.3)
			# Bright orange-yellow core, red edges
			var r := 1.0
			var g := lerpf(0.3, 0.9, maxf(0.0, 1.0 - dist))
			var b := lerpf(0.0, 0.3, maxf(0.0, 1.0 - dist * 2.0))
			img.set_pixel(x, y, Color(r, g, b, alpha))
	var tex := ImageTexture.create_from_image(img)
	particle.texture = tex
	particle.scale = Vector2(2.0 + randf() * 1.5, 2.0 + randf() * 1.5) * (0.6 + intensity * 0.4)
	particle.modulate = Color(1.0, 0.9, 0.7, 1.0)  # Slight warm tint
	
	# Animate fade out
	var tween := main_node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(particle, "modulate:a", 0.0, 0.35 + randf() * 0.2)
	tween.tween_property(particle, "scale", particle.scale * 1.3, 0.35)
	tween.set_parallel(false)
	tween.tween_callback(particle.queue_free)
	
	return particle

static func _spawn_small_fire(main_node: Node2D, pos: Vector2) -> void:
	var particle := Sprite2D.new()
	particle.global_position = pos + Vector2(0, -12)
	particle.z_index = 2050
	
	var img := Image.create(12, 16, false, Image.FORMAT_RGBA8)
	for x in range(12):
		for y in range(16):
			var cx := 6.0
			var cy := 12.0
			var dist := Vector2(x - cx, (y - cy) * 0.7).length() / 6.0
			var alpha := maxf(0.0, 1.0 - dist) * 0.7
			var g := lerpf(0.3, 0.8, float(16 - y) / 16.0)
			img.set_pixel(x, y, Color(1.0, g, 0.1, alpha))
	var tex := ImageTexture.create_from_image(img)
	particle.texture = tex
	particle.scale = Vector2(1.2, 1.5)
	main_node.add_child(particle)
	
	var tween := main_node.create_tween()
	tween.tween_property(particle, "modulate:a", 0.0, 0.4)
	tween.tween_callback(particle.queue_free)

static func _fire_delayed_strike(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var delay := float(w.get("delay", 0.4))
	var radius := float(w.get("strike_radius", 35))
	var count := int(w.get("strike_count", 3))
	var extra := int(w.get("extra_strikes", 0))
	var dmg_mult := float(w.get("damage_mult", 1.0))
	count += extra
	var per_dmg := int(round(float(damage) * dmg_mult / max(1, count)))

	if extra > 0:
		var fm := VfxFocusMark.new()
		fm.setup(attacker.global_position + Vector2(0, -12), Color(0.75, 0.55, 1.0, 1.0), 18.0, 0, 0.20)
		main_node.add_child(fm)
		_play_sfx(main_node, "passive.spirit_surge", attacker.global_position)
	
	for i in range(count):
		var offset := Vector2(randf_range(-40, 40), randf_range(-40, 40))
		var strike_pos := target.global_position + offset
		var strike := WP.DelayedStrike.new()
		strike.setup(strike_pos, per_dmg, is_crit and i == 0, radius, delay + float(i) * 0.15, main_node, cd, attacker)
		main_node.add_child(strike)
	
	_play_sfx(main_node, "weapon.spirit", attacker.global_position)
	_play_vfx(main_node, "weapon.spirit", attacker.global_position + Vector2(0, -12))

static func _execute_whirlwind(attacker: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var radius := float(w.get("radius", 95))
	var dmg_bonus := float(w.get("damage_bonus", 1.3))
	
	var base_dmg := int(float(damage) * dmg_bonus)
	var pos := attacker.global_position
	var enemies := _get_enemies(main_node)
	var hit_count := 0
	
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_to(pos) > radius:
			continue
		if n2.has_method("take_damage"):
			n2.take_damage(base_dmg, is_crit and hit_count == 0, "whirlwind")
		hit_count += 1
	
	# VFX: spinning slash circle
	_spawn_whirlwind_vfx(main_node, pos, radius)
	_play_sfx(main_node, "weapon.reaper_slash", pos)
	
	if hit_count > 0:
		var shake := main_node.get_node_or_null("/root/ScreenShake")
		if shake and is_instance_valid(shake):
			shake.shake(4.0 + float(hit_count) * 0.5, 0.1)

static func _spawn_whirlwind_vfx(main_node: Node2D, pos: Vector2, radius: float) -> void:
	# Create spinning slash effect
	for i in range(3):
		var arc := Line2D.new()
		arc.z_index = 2100
		arc.width = 6.0
		arc.default_color = Color(0.9, 0.95, 1.0, 0.85)
		arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
		arc.end_cap_mode = Line2D.LINE_CAP_ROUND
		
		var offset := TAU * float(i) / 3.0
		var points: PackedVector2Array = []
		for j in range(8):
			var t := float(j) / 7.0
			var a := offset + t * PI * 0.6
			var r := radius * (0.6 + t * 0.4)
			points.append(pos + Vector2.from_angle(a) * r)
		arc.points = points
		main_node.add_child(arc)
		
		var tw := arc.create_tween()
		tw.tween_property(arc, "rotation", TAU, 0.2)
		tw.parallel().tween_property(arc, "modulate:a", 0.0, 0.2)
		tw.tween_callback(arc.queue_free)

static func _execute_heavy_strike(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var cleave_count := int(w.get("cleave_count", 3))
	var stagger_dur := float(w.get("stagger_duration", 0.5))
	var dmg_bonus := float(w.get("damage_bonus", 1.8))
	
	var base_dmg := int(float(damage) * dmg_bonus)
	var dir := (target.global_position - attacker.global_position).normalized()
	var hit_count := 0
	
	# Get enemies sorted by distance in front direction
	var enemies := _get_enemies(main_node)
	var targets: Array[Node2D] = []
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null:
			continue
		var to_e := n2.global_position - attacker.global_position
		if to_e.length() > 100:
			continue
		# Must be roughly in front
		if to_e.normalized().dot(dir) < 0.3:
			continue
		targets.append(n2)
	
	# Sort by distance
	targets.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_squared_to(attacker.global_position) < b.global_position.distance_squared_to(attacker.global_position)
	)
	
	# Hit up to cleave_count
	for i in range(mini(cleave_count, targets.size())):
		var t := targets[i]
		var dmg := base_dmg if i == 0 else int(float(base_dmg) * 0.7)
		if t.has_method("take_damage"):
			t.take_damage(dmg, is_crit and i == 0, "heavy_strike")
		# Stagger effect
		if t.has_method("apply_stagger"):
			t.apply_stagger(stagger_dur)
		elif t.has_method("apply_slow"):
			t.apply_slow(0.3, stagger_dur)
		hit_count += 1
	
	# Big impact VFX
	var impact_pos := attacker.global_position + dir * 50
	_spawn_heavy_strike_vfx(main_node, impact_pos, dir)
	_play_sfx(main_node, "weapon.slam", impact_pos)
	
	var shake := main_node.get_node_or_null("/root/ScreenShake")
	if shake and is_instance_valid(shake) and hit_count > 0:
		shake.shake(6.0, 0.12)

static func _spawn_heavy_strike_vfx(main_node: Node2D, pos: Vector2, dir: Vector2) -> void:
	# Impact flash
	var flash := VfxImpactFlash.new()
	flash.setup(pos, Color(1.0, 0.8, 0.4, 1.0), 35.0, 0.15)
	main_node.add_child(flash)
	
	# Shockwave in direction
	var wave := VfxShockwave.new()
	wave.setup(pos, Color(0.9, 0.7, 0.3, 0.9), 20.0, 60.0, 5.0, 0.2)
	main_node.add_child(wave)
	
	# Slash line
	var slash := Line2D.new()
	slash.z_index = 2100
	slash.width = 12.0
	slash.default_color = Color(1.0, 0.9, 0.6, 1.0)
	slash.points = [pos - dir * 30, pos + dir * 40]
	main_node.add_child(slash)
	
	var tw := slash.create_tween()
	tw.tween_property(slash, "modulate:a", 0.0, 0.12)
	tw.tween_callback(slash.queue_free)

static func _execute_lifesteal_melee(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var lifesteal := float(w.get("lifesteal_percent", 0.30))
	var cleave_count := int(w.get("cleave_count", 3))
	var cleave_radius := float(w.get("cleave_radius", 70))
	var dmg_bonus := float(w.get("damage_bonus", 1.4))
	var overheal_mult := float(w.get("overheal_shield", 0.0))
	
	var base_dmg := int(float(damage) * dmg_bonus)
	var total_damage := 0
	var hits := 0
	
	# Hit primary target
	if target.has_method("take_damage"):
		target.take_damage(base_dmg, is_crit, "vampiric_strike")
		total_damage += base_dmg
		hits += 1
	
	# Cleave to nearby enemies
	if cleave_count > 1:
		var enemies := _get_enemies(main_node)
		for e in enemies:
			if hits >= cleave_count:
				break
			if not is_instance_valid(e) or e == target:
				continue
			var n2 := e as Node2D
			if n2 == null:
				continue
			if n2.global_position.distance_to(attacker.global_position) > cleave_radius:
				continue
			var cleave_dmg := int(float(base_dmg) * 0.7)
			if n2.has_method("take_damage"):
				n2.take_damage(cleave_dmg, false, "vampiric_strike")
				total_damage += cleave_dmg
				hits += 1
	
	# Heal attacker based on total damage
	var heal_amount := int(float(total_damage) * lifesteal)
	if heal_amount > 0:
		if overheal_mult > 0.0 and attacker.has_method("heal_with_overheal"):
			attacker.heal_with_overheal(heal_amount, overheal_mult)
		elif attacker.has_method("heal"):
			attacker.heal(heal_amount)
		# Heal VFX
		var heal_vfx := VfxHolyPulse.new()
		heal_vfx.setup(attacker.global_position, Color(0.3, 1.0, 0.4, 1.0), 10.0, 25.0, 0.2)
		main_node.add_child(heal_vfx)
	
	# VFX
	_spawn_melee_vfx(main_node, target.global_position, (target.global_position - attacker.global_position).normalized(), Color(0.9, 0.2, 0.3, 1.0))
	_play_sfx(main_node, "weapon.vampiric", target.global_position)

static func _fire_ricochet(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var ricochet := WP.RicochetProjectile.new()
	var dmg_bounce_add := maxf(0.0, _get_mp_add(main_node, "ricochet_damage_per_bounce_add", 0.0))
	var direct_mult := _get_mp_mod(main_node, "direct_projectile_damage_mult", 1.0)
	var post_mult := _get_mp_mod(main_node, "post_ricochet_projectile_damage_mult", 1.0)
	var extra_bounce := maxi(0, int(round(_get_mp_add(main_node, "ricochet_count_add", 0.0))))
	ricochet.setup(
		attacker.global_position,
		target,
		damage,
		is_crit,
		int(w.get("bounce_count", 4)) + extra_bounce,
		float(w.get("bounce_range", 150)),
		float(w.get("damage_per_bounce", 0.9)),
		main_node,
		cd,
		attacker,
		direct_mult,
		post_mult,
		dmg_bounce_add
	)
	main_node.add_child(ricochet)
	_play_sfx(main_node, "weapon.ricochet", attacker.global_position)
	_play_vfx(main_node, "weapon.ricochet", attacker.global_position + Vector2(0, -10))

static func _fire_orbital_strike(attacker: Node2D, target: Node2D, damage: int, is_crit: bool, main_node: Node2D, cd: CharacterData, w: Dictionary) -> void:
	var delay := float(w.get("delay", 1.2)) * _get_mp_mod(main_node, "orbital_delay_mult", 1.0)
	var radius := float(w.get("explosion_radius", 90)) * _keystone_power_scale(main_node, 0.03)
	var dmg_mult := float(w.get("damage_mult", 1.8)) * _get_mp_mod(main_node, "orbital_damage_mult", 1.0)
	var cluster_bonus := float(w.get("cluster_bonus", 0.0))
	var strike_pos := target.global_position
	if _get_mp_add(main_node, "orbital_targets_player_trail", 0.0) >= 1.0:
		var p := main_node.get_node_or_null("/root/Main")
		if p == null:
			p = main_node
		if p != null and is_instance_valid(p) and p.has_method("get_player_node"):
			var pn := p.get_player_node() as Node2D
			if pn != null and is_instance_valid(pn):
				strike_pos = pn.global_position
	
	var strike := WP.OrbitalStrike.new()
	strike.setup(strike_pos, int(float(damage) * dmg_mult), is_crit, radius, delay, cluster_bonus, main_node, cd, attacker)
	main_node.add_child(strike)
	_play_sfx(main_node, "player.shot", attacker.global_position)

# === HELPERS ===

static func _get_enemies(main_node: Node2D) -> Array:
	if main_node and is_instance_valid(main_node) and main_node.has_method("get_cached_enemies"):
		return main_node.get_cached_enemies()
	return main_node.get_tree().get_nodes_in_group("enemies") if main_node else []

static func _get_mp_add(main_node: Node2D, key: String, fallback: float = 0.0) -> float:
	if main_node == null:
		return fallback
	var mp := main_node.get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp) or (not mp.has_method("get_add")):
		return fallback
	return float(mp.get_add(key, fallback))

static func _get_mp_mod(main_node: Node2D, key: String, fallback: float = 1.0) -> float:
	if main_node == null:
		return fallback
	var mp := main_node.get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp) or (not mp.has_method("get_mod")):
		return fallback
	return float(mp.get_mod(key, fallback))

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
		var tier := int(round(_get_mp_add(main_node, "weapon_keystone_tier", 0.0)))
		if tier >= 4:
			match event:
				"weapon.chain_lightning", "weapon.beam":
					s.play_event("syn.arc", pos, main_node)
				"weapon.bomb_explode", "weapon.orbital_strike", "weapon.slam":
					s.play_event("syn.shock", pos, main_node)

static func _play_vfx(main_node: Node2D, event: String, pos: Vector2, tint: Color = Color.WHITE, scale: float = 1.0) -> void:
	if main_node == null:
		return
	scale *= _keystone_vfx_scale(main_node)
	var v := main_node.get_node_or_null("/root/VfxSystem")
	var ok := false
	if v and is_instance_valid(v) and v.has_method("play_event"):
		ok = bool(v.play_event(event, pos, main_node, tint, scale))
	if ok:
		return
	# Readable fallback for attacks when pack VFX are unavailable/tiny.
	if event == "player.shot":
		var flash := VfxImpactFlash.new()
		flash.setup(pos, Color(1.0, 0.92, 0.70, 1.0), 18.0 * scale, 0.11)
		main_node.add_child(flash)

static func _keystone_vfx_scale(main_node: Node2D) -> float:
	var boost := _get_mp_add(main_node, "weapon_keystone_vfx_scale_add", 0.0)
	return clampf(1.0 + boost, 1.0, 2.4)

static func _keystone_power_scale(main_node: Node2D, per_tier: float) -> float:
	var tiers := _get_mp_add(main_node, "weapon_keystone_tier", 0.0)
	return clampf(1.0 + tiers * per_tier, 1.0, 2.0)

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
