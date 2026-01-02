class_name PassiveSystem
extends Node

# Data-driven passive system with lightweight VFX hooks.

static var _loaded: bool = false
static var _passives: Dictionary = {} # id -> Dictionary

const VFX_ARC_SCENE: PackedScene = preload("res://scenes/VfxArcLightning.tscn")
const PROJ_SCENE: PackedScene = preload("res://scenes/Projectile.tscn")

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path := "res://data/passives.json"
	if not ResourceLoader.exists(path):
		push_warning("PassiveSystem: missing %s" % path)
		return
	var json_text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	var arr: Array = d.get("passives", [])
	for p in arr:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = p
		var id := String(pd.get("id", ""))
		if id != "":
			_passives[id] = pd

static func passive_name(id: String) -> String:
	ensure_loaded()
	return String((_passives.get(id, {}) as Dictionary).get("name", id))

static func passive_description(id: String) -> String:
	ensure_loaded()
	return String((_passives.get(id, {}) as Dictionary).get("description", ""))

static func passive_tags(id: String) -> PackedStringArray:
	ensure_loaded()
	var arr: Array = (_passives.get(id, {}) as Dictionary).get("tags", [])
	var out := PackedStringArray()
	for t in arr:
		out.append(String(t))
	return out

static func passive_color(id: String) -> Color:
	# UI helper: color-code passive names based on tags.
	# Keep this deterministic and readable on dark backgrounds.
	var tags := passive_tags(id)
	if tags.has("lightning"):
		return Color(1.00, 0.85, 0.30, 1.0)
	if tags.has("control") or tags.has("slow"):
		return Color(0.55, 0.85, 1.00, 1.0)
	if tags.has("dot"):
		return Color(1.00, 0.30, 0.40, 1.0)
	if tags.has("burn"):
		return Color(1.00, 0.55, 0.20, 1.0)
	if tags.has("sustain"):
		return Color(0.55, 1.00, 0.65, 1.0)
	if tags.has("mobility"):
		return Color(0.70, 0.95, 0.90, 1.0)
	if tags.has("execute"):
		return Color(1.00, 0.60, 0.20, 1.0)
	if tags.has("burst"):
		return Color(1.00, 0.78, 0.32, 1.0)
	if tags.has("aoe"):
		return Color(0.82, 0.65, 1.00, 1.0)
	if tags.has("ranged"):
		return Color(0.60, 1.00, 0.80, 1.0)
	if tags.has("melee"):
		return Color(1.00, 0.55, 0.55, 1.0)
	if tags.has("setup") or tags.has("proc"):
		return Color(1.00, 0.55, 0.95, 1.0)
	return Color(0.86, 0.90, 0.96, 1.0)

static func _spawn_vfx(node: Node2D, vfx: Node2D) -> void:
	if node == null or vfx == null:
		return
	var world := _main_world(node)
	if world == null:
		return
	world.add_child(vfx)

static func extra_pierce_count(passive_ids: PackedStringArray) -> int:
	# Only one passive currently affects pierce.
	var extra: int = 0
	for id in passive_ids:
		if id == "piercing_rounds":
			extra += 1
	return extra

static func _p(pid: String) -> Dictionary:
	ensure_loaded()
	return _passives.get(pid, {}) as Dictionary

static func _param_f(pid: String, key: String, default_v: float) -> float:
	var d := _p(pid)
	var params := d.get("params", {}) as Dictionary
	return float(params.get(key, default_v))

static func _param_i(pid: String, key: String, default_v: int) -> int:
	var d := _p(pid)
	var params := d.get("params", {}) as Dictionary
	return int(params.get(key, default_v))

static func on_unit_attack(cd: CharacterData, unit: Node2D, target: Node2D, damage: int, is_crit: bool, is_melee: bool) -> void:
	if cd == null:
		return
	ensure_loaded()
	var ids := cd.passive_ids
	for pid in ids:
		match String(pid):
			"arc_chain":
				_arc_chain(unit, target, damage)
			"frost_tag":
				_frost_tag(target)
			"bleed_edge":
				if is_melee:
					_bleed_edge(target, damage)
			"echo_strike":
				_echo_strike(unit, target, damage, is_crit)
			"shockwave":
				if is_melee:
					_shockwave(unit, target, damage)
			"blood_siphon":
				if is_melee:
					_blood_siphon(unit, damage)
			"twin_shot":
				if not is_melee:
					_twin_shot(unit, target, damage)
			"scattershot":
				if not is_melee:
					_scattershot(unit, target, damage)
			"execute_mark":
				_execute_mark(target, damage)
			"hex_bomb":
				_hex_bomb_tag(target, damage)
			"time_dilation":
				_time_dilation(unit, target)
			"phase_step":
				if is_melee:
					_phase_step(unit, target)
			"stagger":
				_stagger(unit, target)
			"overload":
				_overload_proc(unit, target, damage)
			"pinpoint":
				_pinpoint_tag(target, damage)
			"vortex_tag":
				_vortex_tag(unit, target, damage)
			"cinder_brand":
				if is_melee:
					_cinder_brand(target, damage)
			"doomstack":
				_doomstack(unit, target, damage)
			"hailburst":
				_hailburst(unit, target, damage)
			"predator_instinct":
				_predator_instinct(target, damage)
			_:
				pass
	# Extra: if crit, allow certain passives to proc even for ranged via metadata on unit.
	# (No-op for now)
			_:
				pass

static func on_projectile_hit(passive_ids: PackedStringArray, _proj: Node2D, enemy: Node2D, damage: int, _is_crit: bool) -> void:
	if passive_ids.is_empty():
		return
	ensure_loaded()
	for pid in passive_ids:
		match String(pid):
			"arc_chain":
				_arc_chain(_proj, enemy, damage)
			"frost_tag":
				_frost_tag(enemy)
			"ricochet":
				_ricochet(_proj, enemy, damage)
			"execute_mark":
				_execute_mark(enemy, damage)
			"hex_bomb":
				_hex_bomb_tag(enemy, damage)
			"time_dilation":
				_time_dilation(_proj, enemy)
			"stagger":
				_stagger(_proj, enemy)
			"pinpoint":
				_pinpoint_consume(enemy, damage)
			"vortex_tag":
				_vortex_tag(_proj, enemy, damage)
			"cinder_brand":
				_cinder_brand(enemy, damage)
			"vampiric_bullets":
				_vampiric_bullets(_proj, damage)
			"doomstack":
				_doomstack(_proj, enemy, damage)
			"hailburst":
				_hailburst(_proj, enemy, damage)
			"predator_instinct":
				_predator_instinct(enemy, damage)
			_:
				pass

static func _main_world(from: Node) -> Node2D:
	if from == null:
		return null
	var main := from.get_tree().get_first_node_in_group("main") as Node2D
	return main

static func _nearby_enemies(from: Node2D, origin: Vector2, radius: float, exclude: Node2D = null) -> Array[Node2D]:
	var world := _main_world(from)
	if world == null:
		return []
	var enemies: Array = []
	if world.has_method("get_cached_enemies"):
		enemies = world.get_cached_enemies()
	else:
		enemies = world.get_tree().get_nodes_in_group("enemies")
	var out: Array[Node2D] = []
	var r2 := radius * radius
	for e_node in enemies:
		if not is_instance_valid(e_node):
			continue
		var n2 := e_node as Node2D
		if n2 == null or n2 == exclude:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			out.append(n2)
	return out

static func _spawn_projectile(from: Node2D, to: Node2D, damage: int, tint: Color) -> void:
	var world := _main_world(from)
	if world == null or PROJ_SCENE == null:
		return
	if to == null or not is_instance_valid(to):
		return
	var p := PROJ_SCENE.instantiate()
	world.add_child(p)
	(p as Node2D).global_position = from.global_position
	if p.has_method("set_vfx_color"):
		p.set_vfx_color(tint)
	if p.has_method("setup_target"):
		p.setup_target(to, damage, false, PackedStringArray())

static func _cooldown_gate(node: Node, key: String, cd_s: float) -> bool:
	# Returns true if action is allowed now; also sets the timestamp.
	if node == null:
		return false
	var now_ms: int = int(Time.get_ticks_msec())
	var last_ms: int = int(node.get_meta(key, 0))
	var cd_ms: int = int(round(cd_s * 1000.0))
	if last_ms > 0 and (now_ms - last_ms) < cd_ms:
		return false
	node.set_meta(key, now_ms)
	return true

static func _arc_chain(unit: Node2D, target: Node2D, damage: int) -> void:
	var world := _main_world(unit)
	if world == null or target == null or not is_instance_valid(target):
		return
	var enemies: Array = []
	if world.has_method("get_cached_enemies"):
		enemies = world.get_cached_enemies()
	else:
		enemies = world.get_tree().get_nodes_in_group("enemies")

	var origin := (target as Node2D).global_position
	var radius := 220.0
	var r2 := radius * radius
	var candidates: Array[Node2D] = []
	for e_node in enemies:
		if not is_instance_valid(e_node):
			continue
		var n2 := e_node as Node2D
		if n2 == null or n2 == target:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			candidates.append(n2)
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin)
	)
	var hits: int = int(min(2, candidates.size()))
	if hits <= 0:
		return
	var arc_dmg := int(round(float(damage) * 0.35))
	for i in range(hits):
		var n := candidates[i]
		if n != null and is_instance_valid(n):
			if n.has_method("take_damage"):
				n.take_damage(arc_dmg, false, "arc")
			_spawn_arc(world, origin, n.global_position, Color(0.55, 0.95, 1.0, 0.95))

static func _shockwave(unit: Node2D, target: Node2D, damage: int) -> void:
	if unit == null or target == null or not is_instance_valid(target):
		return
	var rad := _param_f("shockwave", "radius", 120.0)
	var mult := _param_f("shockwave", "damage_mult", 0.25)
	var dmg := int(round(float(damage) * mult))
	if dmg <= 0:
		return
	var origin := (target as Node2D).global_position
	var victims := _nearby_enemies(unit, origin, rad, target as Node2D)
	for v in victims:
		if v.has_method("take_damage"):
			v.take_damage(dmg, false, "blast")
		if v.has_method("pulse_vfx"):
			v.pulse_vfx(Color(1.0, 0.55, 0.45, 1.0))

static func _blood_siphon(unit: Node2D, damage: int) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var mult := _param_f("blood_siphon", "heal_mult", 0.25)
	var heal := int(round(float(damage) * mult))
	if heal <= 0:
		return
	if unit.has_method("heal"):
		unit.heal(heal)

static func _twin_shot(unit: Node2D, target: Node2D, damage: int) -> void:
	if unit == null or target == null:
		return
	var mult := _param_f("twin_shot", "damage_mult", 0.55)
	var dmg := int(round(float(damage) * mult))
	if dmg <= 0:
		return
	_spawn_projectile(unit, target, dmg, Color(0.85, 0.92, 1.0, 1.0))

static func _scattershot(unit: Node2D, target: Node2D, damage: int) -> void:
	if unit == null or target == null or not is_instance_valid(target):
		return
	var extra := _param_i("scattershot", "extra_targets", 2)
	var rad := _param_f("scattershot", "radius", 260.0)
	var mult := _param_f("scattershot", "damage_mult", 0.45)
	var dmg := int(round(float(damage) * mult))
	if dmg <= 0:
		return
	var origin := (target as Node2D).global_position
	var candidates := _nearby_enemies(unit, origin, rad, target as Node2D)
	if candidates.is_empty():
		return
	# pick up to extra closest
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin)
	)
	for i in range(min(extra, candidates.size())):
		_spawn_projectile(unit, candidates[i], dmg, Color(0.78, 0.88, 1.0, 1.0))

static func _ricochet(proj: Node2D, enemy: Node2D, damage: int) -> void:
	if proj == null or enemy == null or not is_instance_valid(enemy):
		return
	var cd := _param_f("ricochet", "cooldown", 0.15)
	if not _cooldown_gate(proj, "_ricochet_ms", cd):
		return
	var rad := _param_f("ricochet", "radius", 280.0)
	var mult := _param_f("ricochet", "damage_mult", 0.60)
	var dmg := int(round(float(damage) * mult))
	if dmg <= 0:
		return
	var origin := (enemy as Node2D).global_position
	var candidates := _nearby_enemies(proj, origin, rad, enemy as Node2D)
	if candidates.is_empty():
		return
	# nearest
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin)
	)
	_spawn_projectile(proj, candidates[0], dmg, Color(0.95, 0.95, 1.0, 1.0))

static func _execute_mark(target: Node2D, damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("get_hp_ratio"):
		return
	var th := _param_f("execute_mark", "threshold", 0.20)
	var bonus := _param_f("execute_mark", "bonus_mult", 0.35)
	var r := float(target.get_hp_ratio())
	if r > th:
		return
	var dmg := int(round(float(damage) * bonus))
	if dmg <= 0:
		return
	if target.has_method("take_damage"):
		target.take_damage(dmg, false, "execute")
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(1.0, 0.85, 0.30, 1.0))

static func _hex_bomb_tag(target: Node2D, damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var arm := _param_f("hex_bomb", "arm_seconds", 1.8)
	var rad := _param_f("hex_bomb", "radius", 150.0)
	var mult := _param_f("hex_bomb", "damage_mult", 0.60)
	var dmg := int(round(float(damage) * mult))
	if dmg <= 0:
		return
	var until_ms: int = int(Time.get_ticks_msec() + int(round(arm * 1000.0)))
	target.set_meta("_hex_bomb_until_ms", until_ms)
	target.set_meta("_hex_bomb_dmg", dmg)
	target.set_meta("_hex_bomb_radius", rad)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.75, 0.45, 1.0, 1.0))

static func _time_dilation(from: Node2D, target: Node2D) -> void:
	if from == null or target == null or not is_instance_valid(target):
		return
	var cd := _param_f("time_dilation", "cooldown", 0.35)
	if not _cooldown_gate(from, "_time_dilation_ms", cd):
		return
	var rad := _param_f("time_dilation", "radius", 170.0)
	var mult := _param_f("time_dilation", "slow_mult", 0.82)
	var dur := _param_f("time_dilation", "duration", 0.75)
	var origin := (target as Node2D).global_position
	var victims := _nearby_enemies(from, origin, rad, null)
	for v in victims:
		if v.has_method("apply_slow"):
			v.apply_slow(mult, dur)
		if v.has_method("pulse_vfx"):
			v.pulse_vfx(Color(0.55, 0.85, 1.0, 1.0))

static func _phase_step(unit: Node2D, target: Node2D) -> void:
	if unit == null or target == null or not is_instance_valid(target):
		return
	var interval := _param_i("phase_step", "interval", 4)
	var dist := _param_f("phase_step", "distance", 34.0)
	var c: int = int(unit.get_meta("_phase_ctr", 0)) + 1
	unit.set_meta("_phase_ctr", c)
	if interval <= 0 or (c % interval) != 0:
		return
	var dir := ((target as Node2D).global_position - unit.global_position).normalized()
	# blink through target
	unit.global_position = (target as Node2D).global_position + dir * dist

static func _stagger(from: Node2D, target: Node2D) -> void:
	if from == null or target == null or not is_instance_valid(target):
		return
	var cd := _param_f("stagger", "cooldown", 0.25)
	if not _cooldown_gate(from, "_stagger_ms", cd):
		return
	var mult := _param_f("stagger", "slow_mult", 0.55)
	var dur := _param_f("stagger", "duration", 0.35)
	if target.has_method("apply_slow"):
		target.apply_slow(mult, dur)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.95, 0.95, 1.0, 1.0))

static func _overload_proc(from: Node2D, target: Node2D, damage: int) -> void:
	if from == null or target == null or not is_instance_valid(target):
		return
	var interval := _param_i("overload", "interval", 5)
	var rad := _param_f("overload", "radius", 240.0)
	var mult := _param_f("overload", "damage_mult", 0.30)
	var c: int = int(from.get_meta("_overload_ctr", 0)) + 1
	from.set_meta("_overload_ctr", c)
	if interval <= 0 or (c % interval) != 0:
		return
	var origin := (target as Node2D).global_position
	var candidates := _nearby_enemies(from, origin, rad, target as Node2D)
	if candidates.is_empty():
		return
	var idx := int(Time.get_ticks_msec()) % candidates.size()
	var pick := candidates[idx]
	var dmg := int(round(float(damage) * mult))
	if pick.has_method("take_damage"):
		pick.take_damage(dmg, false, "arc")
	var world := _main_world(from)
	if world != null:
		_spawn_arc(world, origin, pick.global_position, Color(0.75, 0.45, 1.0, 0.95))

static func _pinpoint_tag(target: Node2D, damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var window := _param_f("pinpoint", "window", 1.0)
	var mult := _param_f("pinpoint", "damage_mult", 0.35)
	var until_ms: int = int(Time.get_ticks_msec() + int(round(window * 1000.0)))
	target.set_meta("_pinpoint_until_ms", until_ms)
	target.set_meta("_pinpoint_dmg", int(round(float(damage) * mult)))

static func _pinpoint_consume(target: Node2D, _damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var until_ms: int = int(target.get_meta("_pinpoint_until_ms", 0))
	if until_ms <= 0:
		return
	if int(Time.get_ticks_msec()) > until_ms:
		return
	var bonus: int = int(target.get_meta("_pinpoint_dmg", 0))
	if bonus <= 0:
		return
	# Consume once.
	target.set_meta("_pinpoint_until_ms", 0)
	if target.has_method("take_damage"):
		target.take_damage(bonus, false, "echo")
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(1.0, 0.85, 0.30, 1.0))

static func _vortex_tag(from: Node2D, target: Node2D, damage: int) -> void:
	if from == null or target == null or not is_instance_valid(target):
		return
	var cd := _param_f("vortex_tag", "cooldown", 0.5)
	if not _cooldown_gate(from, "_vortex_ms", cd):
		return
	var rad := _param_f("vortex_tag", "radius", 140.0)
	var cluster := _param_i("vortex_tag", "cluster_count", 3)
	var mult := _param_f("vortex_tag", "damage_mult", 0.22)
	var origin := (target as Node2D).global_position
	var victims := _nearby_enemies(from, origin, rad, null)
	if victims.size() < cluster:
		return
	var dmg := int(round(float(damage) * mult))
	if dmg <= 0:
		return
	for v in victims:
		if v.has_method("take_damage"):
			v.take_damage(dmg, false, "blast")
		if v.has_method("pulse_vfx"):
			v.pulse_vfx(Color(0.35, 0.80, 1.0, 1.0))

static func _frost_tag(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("apply_slow"):
		var mult := _param_f("frost_tag", "slow_mult", 0.75)
		var dur := _param_f("frost_tag", "duration", 1.5)
		target.apply_slow(mult, dur)
		# Tag for combo passives (e.g., Hailburst)
		var until_ms: int = int(Time.get_ticks_msec() + int(round(dur * 1000.0)))
		target.set_meta("_frost_until_ms", until_ms)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.55, 0.85, 1.0, 1.0))

static func _bleed_edge(target: Node2D, damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("apply_bleed"):
		var mult := _param_f("bleed_edge", "damage_mult", 0.15)
		var dur := _param_f("bleed_edge", "duration", 3.0)
		var tick := _param_f("bleed_edge", "tick_interval", 0.5)
		var dps := float(damage) * mult
		target.apply_bleed(dps, dur, tick)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(1.0, 0.25, 0.35, 1.0))

static func _cinder_brand(target: Node2D, damage: int) -> void:
	# Applies burn (DOT) on hit.
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("apply_burn"):
		return
	var mult := _param_f("cinder_brand", "damage_mult", 0.12)
	var dur := _param_f("cinder_brand", "duration", 3.2)
	var tick := _param_f("cinder_brand", "tick_interval", 0.5)
	var dps := float(damage) * mult
	if dps <= 0.0:
		return
	target.apply_burn(dps, dur, tick)
	# Tag for potential combos
	var until_ms: int = int(Time.get_ticks_msec() + int(round(dur * 1000.0)))
	target.set_meta("_burn_until_ms", until_ms)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(1.0, 0.55, 0.20, 1.0))
	# VFX: ember burst on application
	var fb := VfxFlameBurst.new()
	fb.setup((target as Node2D).global_position + Vector2(0, -22), Color(1.0, 0.55, 0.18, 1.0), 24.0, 10, 0.20, Vector2(0, -1))
	_spawn_vfx(target as Node2D, fb)

static func _vampiric_bullets(proj: Node2D, damage: int) -> void:
	# Heal shooter on projectile hit. Requires Projectile to carry source_unit.
	if proj == null:
		return
	var su: Node2D = proj.get("source_unit") as Node2D
	if su == null or not is_instance_valid(su):
		return
	if not su.has_method("heal"):
		return
	var mult := _param_f("vampiric_bullets", "heal_mult", 0.10)
	var heal := int(round(float(damage) * mult))
	if heal <= 0:
		return
	su.heal(heal)
	# VFX: leech beam + green pulse at the healer
	var world: Node2D = _main_world(proj)
	if world != null:
		var start := (proj as Node2D).global_position
		_spawn_arc(world, start, su.global_position, Color(0.55, 1.0, 0.65, 0.95))
	var hp := VfxHolyPulse.new()
	hp.setup(su.global_position + Vector2(0, -18), Color(0.55, 1.0, 0.65, 1.0), 14.0, 38.0, 0.20)
	_spawn_vfx(su, hp)

static func _doomstack(from: Node2D, target: Node2D, damage: int) -> void:
	# Stacking mark: after N hits, detonate for bonus damage + small AoE.
	if target == null or not is_instance_valid(target):
		return
	var window := _param_f("doomstack", "window", 2.0)
	var stacks_need := _param_i("doomstack", "stacks", 4)
	var mult := _param_f("doomstack", "damage_mult", 0.65)
	var rad := _param_f("doomstack", "radius", 120.0)

	var now_ms: int = int(Time.get_ticks_msec())
	var until_ms: int = int(target.get_meta("_doom_until_ms", 0))
	var stacks: int = int(target.get_meta("_doom_stacks", 0))
	if now_ms > until_ms:
		stacks = 0
	stacks += 1
	target.set_meta("_doom_stacks", stacks)
	target.set_meta("_doom_until_ms", now_ms + int(round(window * 1000.0)))
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.75, 0.45, 1.0, 1.0))
	# VFX: show stack brackets briefly
	var fm := VfxFocusMark.new()
	fm.setup((target as Node2D).global_position + Vector2(0, -18), Color(0.82, 0.65, 1.0, 1.0), 18.0, stacks, 0.18)
	_spawn_vfx(target as Node2D, fm)
	if stacks < stacks_need:
		return
	# Detonate
	target.set_meta("_doom_stacks", 0)
	target.set_meta("_doom_until_ms", 0)
	var boom := int(round(float(damage) * mult))
	if boom <= 0:
		return
	if target.has_method("take_damage"):
		target.take_damage(boom, false, "blast")
	# VFX: detonation shockwave
	var sw := VfxShockwave.new()
	sw.setup((target as Node2D).global_position, Color(0.82, 0.65, 1.0, 1.0), 18.0, rad * 0.9, 5.0, 0.22)
	_spawn_vfx(target as Node2D, sw)
	var origin := (target as Node2D).global_position
	var victims := _nearby_enemies(from if from != null else target, origin, rad, target as Node2D)
	for v in victims:
		if v.has_method("take_damage"):
			v.take_damage(int(round(float(boom) * 0.45)), false, "blast")
		if v.has_method("pulse_vfx"):
			v.pulse_vfx(Color(0.75, 0.45, 1.0, 1.0))

static func _hailburst(from: Node2D, target: Node2D, damage: int) -> void:
	# Combo: if target is Frost-tagged, consume it and shatter for AoE.
	if target == null or not is_instance_valid(target):
		return
	var until_ms: int = int(target.get_meta("_frost_until_ms", 0))
	if until_ms <= 0 or int(Time.get_ticks_msec()) > until_ms:
		return
	# Consume
	target.set_meta("_frost_until_ms", 0)
	var rad := _param_f("hailburst", "radius", 120.0)
	var mult := _param_f("hailburst", "damage_mult", 0.40)
	var boom := int(round(float(damage) * mult))
	if boom <= 0:
		return
	var origin := (target as Node2D).global_position
	var victims := _nearby_enemies(from if from != null else target, origin, rad, null)
	# VFX: frost nova on shatter
	var nova := VfxFrostNova.new()
	nova.setup(origin, Color(0.55, 0.85, 1.0, 1.0), rad, 10, 0.24)
	_spawn_vfx(target as Node2D, nova)
	for v in victims:
		if v.has_method("take_damage"):
			v.take_damage(boom, false, "blast")
		if v.has_method("pulse_vfx"):
			v.pulse_vfx(Color(0.55, 0.85, 1.0, 1.0))

static func _predator_instinct(target: Node2D, damage: int) -> void:
	# Bonus damage against healthy targets (good for opening waves).
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("get_hp_ratio"):
		return
	var th := _param_f("predator_instinct", "threshold", 0.80)
	var mult := _param_f("predator_instinct", "damage_mult", 0.20)
	var r := float(target.get_hp_ratio())
	if r < th:
		return
	var bonus := int(round(float(damage) * mult))
	if bonus <= 0:
		return
	if target.has_method("take_damage"):
		target.take_damage(bonus, false, "echo")
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(1.0, 0.85, 0.30, 1.0))
	# VFX: focus brackets
	var fm := VfxFocusMark.new()
	fm.setup((target as Node2D).global_position + Vector2(0, -18), Color(1.0, 0.85, 0.30, 1.0), 18.0, 0, 0.16)
	_spawn_vfx(target as Node2D, fm)

static func _echo_strike(unit: Node2D, target: Node2D, damage: int, _is_crit: bool) -> void:
	if unit == null or target == null:
		return
	# Use node metadata to avoid adding fields to SquadUnit.
	var c: int = int(unit.get_meta("_echo_ctr", 0))
	c += 1
	unit.set_meta("_echo_ctr", c)
	if c % 3 != 0:
		return
	if target.has_method("take_damage"):
		target.take_damage(int(round(float(damage) * 0.5)), false, "echo")
	var world := _main_world(unit)
	if world != null:
		# Avoid circular/crescent decals; use a quick arc line instead.
		_spawn_arc(world, (unit as Node2D).global_position, (target as Node2D).global_position, Color(1.0, 0.85, 0.30, 0.95))
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(1.0, 0.85, 0.30, 1.0))

static func _spawn_arc(world: Node2D, a: Vector2, b: Vector2, color: Color) -> void:
	if VFX_ARC_SCENE == null:
		return
	var v := VFX_ARC_SCENE.instantiate()
	world.add_child(v)
	if v.has_method("setup"):
		v.setup(a, b, color)

## Note: we intentionally do not spawn decal-like VFX (rings/crescents) for status effects.
