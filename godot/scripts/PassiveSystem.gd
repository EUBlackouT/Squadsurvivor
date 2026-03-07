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
	var desc := String((_passives.get(id, {}) as Dictionary).get("description", ""))
	if desc == "":
		return "(No description available for '%s')" % id
	return desc

static func passive_icon(id: String) -> String:
	# Returns a stylized text icon for the passive based on its tags
	ensure_loaded()
	var p: Dictionary = _passives.get(id, {}) as Dictionary
	var tags: Array = p.get("tags", []) as Array
	
	# Map tags to icons
	if tags.has("lightning"):
		return "[ZAP]"
	elif tags.has("burn") or tags.has("dot"):
		return "[DOT]"
	elif tags.has("control") or tags.has("slow"):
		return "[CC]"
	elif tags.has("aoe"):
		return "[AOE]"
	elif tags.has("pierce") or tags.has("ranged"):
		return "[RNG]"
	elif tags.has("melee"):
		return "[MEL]"
	elif tags.has("sustain"):
		return "[HP+]"
	elif tags.has("burst") or tags.has("execute"):
		return "[DMG]"
	elif tags.has("proc"):
		return "[%]"
	elif tags.has("mobility"):
		return "[MOV]"
	elif tags.has("setup"):
		return "[SET]"
	elif tags.has("risk"):
		return "[!]"
	else:
		return "[*]"

static func passive_tooltip_bbcode(id: String) -> String:
	ensure_loaded()
	var p: Dictionary = _passives.get(id, {}) as Dictionary
	if p.is_empty():
		return "[color=#888899]Unknown passive[/color]"
	
	var name := String(p.get("name", id))
	var desc := String(p.get("description", ""))
	var tags: Array = p.get("tags", []) as Array
	var color := passive_color(id)
	var hex := "#%02x%02x%02x" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	
	var lines: Array[String] = []
	lines.append("[b][color=%s]< %s >[/color][/b]" % [hex, name])
	
	# Tag pills
	if not tags.is_empty():
		var tag_str := ""
		for t in tags:
			tag_str += "[color=#556666]|%s|[/color] " % String(t).to_upper()
		lines.append(tag_str.strip_edges())
	
	lines.append("")
	lines.append("[color=#ccccdd]%s[/color]" % desc)
	
	return "\n".join(lines)

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

static func _vfx_event(world: Node2D, event_id: String, pos: Vector2, tint: Color = Color(1, 1, 1, 1), scale_mult: float = 1.0) -> bool:
	# Try EffectBlocks flipbook events first. Returns true if something was spawned.
	if world == null:
		return false
	var v := world.get_node_or_null("/root/VfxSystem")
	if v != null and is_instance_valid(v) and v.has_method("play_event"):
		return bool(v.play_event(event_id, pos, world, tint, scale_mult))
	return false

static func _sfx_event(world: Node2D, event_id: String, pos: Vector2, emitter: Object) -> void:
	if world == null:
		return
	var s := world.get_node_or_null("/root/SfxSystem")
	if s != null and is_instance_valid(s) and s.has_method("play_event"):
		s.play_event(event_id, pos, emitter)

static func _spawn_fx(world: Node2D, fx: Node2D) -> void:
	if world == null or fx == null:
		return
	world.add_child(fx)

static func _fx_flash(world: Node2D, pos: Vector2, color: Color, radius: float, dur: float = 0.14) -> void:
	var f := VfxImpactFlash.new()
	f.setup(pos, color, radius, dur)
	_spawn_fx(world, f)

static func _fx_shock(world: Node2D, pos: Vector2, color: Color, r0: float, r1: float, width: float, dur: float) -> void:
	var sw := VfxShockwave.new()
	sw.setup(pos, color, r0, r1, width, dur)
	_spawn_fx(world, sw)

static func _fx_flame_burst(world: Node2D, pos: Vector2, color: Color, radius: float, dir: Vector2 = Vector2.ZERO) -> void:
	var fb := VfxFlameBurst.new()
	fb.setup(pos, color, radius, 10, 0.20, dir)
	_spawn_fx(world, fb)

static func _fx_frost_nova(world: Node2D, pos: Vector2, color: Color, radius: float) -> void:
	var fn := VfxFrostNova.new()
	fn.setup(pos, color, radius, 10, 0.26)
	_spawn_fx(world, fn)

static func _fx_focus(world: Node2D, pos: Vector2, color: Color, size: float) -> void:
	var fm := VfxFocusMark.new()
	fm.setup(pos, color, size, 0, 0.20)
	_spawn_fx(world, fm)

static func _fx_holy(world: Node2D, pos: Vector2, color: Color, size0: float, size1: float) -> void:
	var hp := VfxHolyPulse.new()
	hp.setup(pos, color, size0, size1, 0.22)
	_spawn_fx(world, hp)

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

static func params_for(pid: String) -> Dictionary:
	return _p(pid).get("params", {}) as Dictionary

static func has_passive(ids: PackedStringArray, pid: String) -> bool:
	for id in ids:
		if String(id) == pid:
			return true
	return false

static func apply_weapon_mods(weapon_id: String, w: Dictionary, passive_ids: PackedStringArray) -> Dictionary:
	if w.is_empty() or passive_ids.is_empty():
		return w
	var out := w.duplicate(true)
	var wtype := String(out.get("type", ""))

	if has_passive(passive_ids, "chain_master") and wtype == "chain":
		out["chain_count"] = int(out.get("chain_count", 3)) + _param_i("chain_master", "extra_chains", 2)
		var decay := float(out.get("chain_damage_decay", 0.8))
		var red := _param_f("chain_master", "decay_reduction", 0.15)
		out["chain_damage_decay"] = minf(1.0, decay + red)

	if has_passive(passive_ids, "scatter_specialist") and wtype == "scatter":
		out["projectile_count"] = int(out.get("projectile_count", 5)) + _param_i("scatter_specialist", "extra_projectiles", 2)
		var spread := float(out.get("spread_angle", 45))
		var red2 := _param_f("scatter_specialist", "spread_reduction", 0.25)
		out["spread_angle"] = maxf(6.0, spread * (1.0 - red2))

	if has_passive(passive_ids, "boomerang_mastery") and wtype == "boomerang":
		out["travel_distance"] = float(out.get("travel_distance", 200.0)) * _param_f("boomerang_mastery", "range_mult", 1.5)
		var ret := _param_f("boomerang_mastery", "return_damage_mult", 1.0)
		out["return_damage_mult"] = maxf(float(out.get("return_damage_mult", 0.6)), ret)

	if has_passive(passive_ids, "beam_focus") and wtype == "beam":
		out["duration"] = float(out.get("duration", 0.5)) * _param_f("beam_focus", "duration_mult", 1.5)
		out["width_growth"] = float(out.get("width_growth", 0.0)) + _param_f("beam_focus", "width_growth", 0.25)

	if has_passive(passive_ids, "orbital_precision") and wtype == "orbital":
		var delay := float(out.get("delay", 1.0))
		var red3 := _param_f("orbital_precision", "delay_reduction", 0.4)
		out["delay"] = maxf(0.2, delay * (1.0 - red3))
		out["cluster_bonus"] = float(out.get("cluster_bonus", 0.0)) + _param_f("orbital_precision", "cluster_bonus", 0.3)

	if has_passive(passive_ids, "bomb_expert") and wtype == "bomb":
		out["explosion_radius"] = float(out.get("explosion_radius", 70.0)) * _param_f("bomb_expert", "radius_mult", 1.3)
		out["burn_duration"] = maxf(float(out.get("burn_duration", 0.0)), _param_f("bomb_expert", "burn_duration", 2.0))
		out["burn_dps_mult"] = float(out.get("burn_dps_mult", 0.0)) + _param_f("bomb_expert", "burn_dps_mult", 0.25)

	if has_passive(passive_ids, "ricochet_master") and wtype == "ricochet":
		out["bounce_count"] = int(out.get("bounce_count", 4)) + _param_i("ricochet_master", "extra_bounces", 3)
		var p := params_for("ricochet_master")
		if bool(p.get("no_decay", false)):
			out["damage_per_bounce"] = 1.0

	if has_passive(passive_ids, "spirit_surge") and wtype == "delayed_strike":
		out["extra_strikes"] = int(out.get("extra_strikes", 0)) + _param_i("spirit_surge", "extra_strikes", 2)
		out["damage_mult"] = float(out.get("damage_mult", 1.0)) * _param_f("spirit_surge", "damage_mult", 0.65)

	if has_passive(passive_ids, "vampiric_mastery") and wtype == "lifesteal_melee":
		out["lifesteal_percent"] = float(out.get("lifesteal_percent", 0.3)) + _param_f("vampiric_mastery", "lifesteal_bonus", 0.15)
		out["overheal_shield"] = float(out.get("overheal_shield", 0.0)) + _param_f("vampiric_mastery", "overheal_shield", 0.5)

	if has_passive(passive_ids, "reaper_hunger") and wtype == "melee_arc":
		out["reaper_hunger_heal_mult"] = float(out.get("reaper_hunger_heal_mult", 0.0)) + _param_f("reaper_hunger", "heal_mult", 0.15)
		out["reaper_hunger_kill_mult"] = float(out.get("reaper_hunger_kill_mult", 0.0)) + _param_f("reaper_hunger", "kill_heal_mult", 0.3)

	if has_passive(passive_ids, "frost_mastery") and weapon_id == "frost_bolt":
		out["slow_bonus"] = float(out.get("slow_bonus", 0.0)) + _param_f("frost_mastery", "slow_bonus", 0.2)
		out["shatter_radius"] = float(out.get("shatter_radius", 0.0)) + _param_f("frost_mastery", "shatter_radius", 80.0)
		out["shatter_damage"] = float(out.get("shatter_damage", 0.0)) + _param_f("frost_mastery", "shatter_damage", 0.7)

	if has_passive(passive_ids, "poison_mastery") and weapon_id == "poison_dart":
		out["poison_damage_mult"] = float(out.get("poison_damage_mult", 1.0)) * _param_f("poison_mastery", "damage_mult", 1.3)
		out["poison_spread_radius"] = float(out.get("poison_spread_radius", 0.0)) + _param_f("poison_mastery", "spread_radius", 100.0)

	if has_passive(passive_ids, "fire_mastery") and weapon_id == "fire_wave":
		out["fire_spread_count"] = int(out.get("fire_spread_count", 0)) + _param_i("fire_mastery", "spread_count", 2)
		out["fire_spread_radius"] = float(out.get("fire_spread_radius", 0.0)) + _param_f("fire_mastery", "spread_radius", 120.0)
		out["fire_damage_amp"] = float(out.get("fire_damage_amp", 0.0)) + _param_f("fire_mastery", "damage_amp", 0.25)

	return out

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
					_cinder_brand(target, damage, ids)
			"toxic":
				_toxic_venom(target, damage, ids)
			"doomstack":
				_doomstack(unit, target, damage)
			"hailburst":
				_hailburst(unit, target, damage)
			"predator_instinct":
				_predator_instinct(target, damage)
			"chain_reaction":
				_chain_reaction_check(target, damage)
			"phantom_strike":
				_phantom_strike(unit, target, damage, is_crit)
			"venomous":
				_venomous(target, damage)
			"web_snare":
				_web_snare(unit, target)
			"spore_bloom":
				_spore_bloom(unit, target, damage)
			"gel_mitosis":
				_gel_mitosis(unit, target, damage)
			_:
				pass
	# Mage callout: Arc Surge (global, short duration). Adds a small arc proc even if the unit doesn't own arc_chain.
	var world := _main_world(unit)
	if world != null and world.has_method("is_arc_surge_active") and bool(world.is_arc_surge_active()):
		var mult := 0.22
		if world.has_method("get_arc_surge_damage_mult"):
			mult = float(world.get_arc_surge_damage_mult())
		_arc_chain(unit, target, int(round(float(damage) * mult)))
	# Fire Mastery: bonus damage to burning targets.
	if has_passive(ids, "fire_mastery"):
		_fire_mastery_bonus(target, damage)


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
				_cinder_brand(enemy, damage, passive_ids)
			"toxic":
				_toxic_venom(enemy, damage, passive_ids)
			"vampiric_bullets":
				_vampiric_bullets(_proj, damage)
			"doomstack":
				_doomstack(_proj, enemy, damage)
			"hailburst":
				_hailburst(_proj, enemy, damage)
			"predator_instinct":
				_predator_instinct(enemy, damage)
			"web_snare":
				_web_snare(_proj, enemy)
			"spore_bloom":
				_spore_bloom(_proj, enemy, damage)
			"gel_mitosis":
				_gel_mitosis(_proj, enemy, damage)
			"explosive_rounds":
				_explosive_rounds(_proj, enemy, damage)
			_:
				pass
	# Mage callout: Arc Surge also applies to projectile hits.
	var world := _main_world(_proj)
	if world != null and world.has_method("is_arc_surge_active") and bool(world.is_arc_surge_active()):
		var mult := 0.22
		if world.has_method("get_arc_surge_damage_mult"):
			mult = float(world.get_arc_surge_damage_mult())
		_arc_chain(_proj, enemy, int(round(float(damage) * mult)))
	# Fire Mastery: bonus damage to burning targets.
	if has_passive(passive_ids, "fire_mastery"):
		_fire_mastery_bonus(enemy, damage)

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
			# Extra visibility: spawn a small spark at the chained target.
			_vfx_event(world, "syn.focus_tick", n.global_position + Vector2(0, -18), Color(0.65, 0.95, 1.0, 1.0), 0.85)
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
	_vfx_event(_main_world(unit), "syn.shock", origin, Color(1.0, 0.55, 0.45, 1.0), 1.0)
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
		var world := _main_world(unit)
		if world != null:
			_vfx_event(world, "syn.holy", (unit as Node2D).global_position + Vector2(0, -18), Color(0.55, 1.0, 0.65, 1.0), 0.9)

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
	var world := _main_world(target)
	if world != null:
		_vfx_event(world, "syn.execute", (target as Node2D).global_position + Vector2(0, -18), Color(1.0, 0.85, 0.30, 1.0), 1.1)
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
	var world := _main_world(target)
	if world != null:
		_vfx_event(world, "enemy.elite_spawn", (target as Node2D).global_position + Vector2(0, -18), Color(0.82, 0.65, 1.0, 1.0), 0.75)
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
	_vfx_event(_main_world(from), "enemy.arcane", origin, Color(0.55, 0.85, 1.0, 1.0), 0.95)
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
	var world := _main_world(from)
	if world != null:
		_vfx_event(world, "hit.ranged", (target as Node2D).global_position + Vector2(0, -18), Color(0.95, 0.95, 1.0, 1.0), 0.85)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.95, 0.95, 1.0, 1.0))

static func _web_snare(from: Node2D, target: Node2D) -> void:
	if from == null or target == null or not is_instance_valid(target):
		return
	var cd := _param_f("web_snare", "cooldown", 0.35)
	if not _cooldown_gate(from, "_web_snare_ms", cd):
		return
	var mult := _param_f("web_snare", "slow_mult", 0.50)
	var dur := _param_f("web_snare", "duration", 1.0)
	if target.has_method("apply_slow"):
		target.apply_slow(mult, dur)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.88, 0.92, 1.0, 1.0))
	var world := _main_world(from)
	if world != null:
		var pos := (target as Node2D).global_position + Vector2(0, -18)
		_vfx_event(world, "passive.web_snare", pos, Color(0.88, 0.92, 1.0, 1.0), 0.95)
		_sfx_event(world, "passive.web_snare", pos, from)

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
		_vfx_event(world, "syn.arc", pick.global_position + Vector2(0, -18), Color(0.75, 0.45, 1.0, 1.0), 0.9)
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
	var world := _main_world(from)
	if world != null:
		_vfx_event(world, "syn.shock", origin, Color(0.35, 0.80, 1.0, 1.0), 0.9)
		_sfx_event(world, "syn.shock", origin, from)

static func _spore_bloom(from: Node2D, target: Node2D, damage: int) -> void:
	if from == null or target == null or not is_instance_valid(target):
		return
	var cd := _param_f("spore_bloom", "cooldown", 0.6)
	if not _cooldown_gate(from, "_spore_bloom_ms", cd):
		return
	var rad := _param_f("spore_bloom", "radius", 150.0)
	var mult := _param_f("spore_bloom", "damage_mult", 0.20)
	var dur := _param_f("spore_bloom", "duration", 3.0)
	var tick := _param_f("spore_bloom", "tick_interval", 0.6)
	var origin := (target as Node2D).global_position
	var victims := _nearby_enemies(from, origin, rad, null)
	var dps := float(damage) * mult
	if dps <= 0.0:
		return
	for v in victims:
		if v.has_method("apply_burn"):
			v.apply_burn(dps, dur, tick)
		if v.has_method("pulse_vfx"):
			v.pulse_vfx(Color(0.65, 1.0, 0.55, 1.0))
	var world := _main_world(from)
	if world != null:
		_vfx_event(world, "passive.spore_bloom", origin + Vector2(0, -12), Color(0.65, 1.0, 0.55, 1.0), 1.0)
		_sfx_event(world, "passive.spore_bloom", origin, from)

static func _gel_mitosis(from: Node2D, target: Node2D, damage: int) -> void:
	if from == null or target == null or not is_instance_valid(target):
		return
	var interval := _param_i("gel_mitosis", "interval", 4)
	var extra := _param_i("gel_mitosis", "extra_targets", 2)
	var rad := _param_f("gel_mitosis", "radius", 220.0)
	var mult := _param_f("gel_mitosis", "damage_mult", 0.45)
	var c: int = int(from.get_meta("_gel_mitosis_ctr", 0)) + 1
	from.set_meta("_gel_mitosis_ctr", c)
	if interval <= 0 or (c % interval) != 0:
		return
	var origin := (target as Node2D).global_position
	var victims := _nearby_enemies(from, origin, rad, target as Node2D)
	if victims.is_empty():
		return
	var dmg := int(round(float(damage) * mult))
	if dmg <= 0:
		return
	victims.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin)
	)
	for i in range(min(extra, victims.size())):
		_spawn_projectile(from, victims[i], dmg, Color(0.70, 0.95, 0.85, 1.0))
	var world := _main_world(from)
	if world != null:
		_vfx_event(world, "passive.gel_mitosis", origin + Vector2(0, -12), Color(0.70, 0.95, 0.85, 1.0), 0.9)
		_sfx_event(world, "passive.gel_mitosis", origin, from)

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
	var world := _main_world(target)
	if world != null:
		_vfx_event(world, "syn.frost", (target as Node2D).global_position + Vector2(0, -18), Color(0.55, 0.85, 1.0, 1.0), 0.75)
		_sfx_event(world, "syn.frost", (target as Node2D).global_position, target)

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
	var world := _main_world(target)
	if world != null:
		_vfx_event(world, "enemy.die", (target as Node2D).global_position + Vector2(0, -18), Color(1.0, 0.25, 0.35, 1.0), 0.7)
		_sfx_event(world, "hit.melee", (target as Node2D).global_position, target)

static func _cinder_brand(target: Node2D, damage: int, passive_ids: PackedStringArray) -> void:
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
	_mark_burn(target, dur)
	if has_passive(passive_ids, "fire_mastery"):
		var count := _param_i("fire_mastery", "spread_count", 2)
		_mark_fire_spread(target, dps, dur, tick, count)

static func _toxic_venom(target: Node2D, damage: int, passive_ids: PackedStringArray) -> void:
	# Applies stacking poison (uses burn system internally with green visual).
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("apply_burn"):
		return
	var mult := _param_f("toxic", "damage_mult", 0.15)
	if has_passive(passive_ids, "poison_mastery"):
		mult *= _param_f("poison_mastery", "damage_mult", 1.3)
	var dur := _param_f("toxic", "duration", 5.0)
	var tick := _param_f("toxic", "tick_interval", 0.5)
	# Stacking: each application adds more DPS (up to max_stacks)
	var max_stacks := int(_param_f("toxic", "max_stacks", 3.0))
	var current_stacks: int = int(target.get_meta("_toxic_stacks", 0))
	if current_stacks < max_stacks:
		current_stacks += 1
		target.set_meta("_toxic_stacks", current_stacks)
	var dps := float(damage) * mult * float(current_stacks)
	if dps <= 0.0:
		return
	target.apply_burn(dps, dur, tick)
	if has_passive(passive_ids, "poison_mastery"):
		_mark_poison_spread(target, dps, dur, tick, 2)
	# Green poison visual
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.35, 0.95, 0.25, 1.0))
	var world := _main_world(target)
	if world:
		_vfx_event(world, "syn.wisp", (target as Node2D).global_position + Vector2(0, -18), Color(0.35, 0.95, 0.25, 1.0), 0.6)
		_sfx_event(world, "passive.poison_mastery", (target as Node2D).global_position, target)

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
		_sfx_event(world, "passive.vampiric_mastery", su.global_position, su)
	# Heal pulse
	if world == null or (not _vfx_event(world, "syn.holy", su.global_position + Vector2(0, -18), Color(0.55, 1.0, 0.65, 1.0), 0.9)):
		var hp := VfxHolyPulse.new()
		hp.setup(su.global_position + Vector2(0, -18), Color(0.55, 1.0, 0.65, 1.0), 14.0, 38.0, 0.20)
		_spawn_vfx(su, hp)

static func _explosive_rounds(from: Node2D, target: Node2D, damage: int) -> void:
	if from == null or target == null or not is_instance_valid(target):
		return
	var rad := _param_f("explosive_rounds", "radius", 60.0)
	var mult := _param_f("explosive_rounds", "damage_mult", 0.4)
	var dmg := int(round(float(damage) * mult))
	if dmg <= 0:
		return
	var origin := (target as Node2D).global_position
	var victims := _nearby_enemies(from, origin, rad, null)
	for v in victims:
		if v.has_method("take_damage"):
			v.take_damage(dmg, false, "blast")
		if v.has_method("pulse_vfx"):
			v.pulse_vfx(Color(1.0, 0.7, 0.3, 1.0))
	var world := _main_world(from)
	if world != null:
		_fx_shock(world, origin, Color(1.0, 0.55, 0.22, 1.0), 14.0, rad * 1.05, 6.0, 0.22)
		_fx_flash(world, origin, Color(1.0, 0.75, 0.35, 1.0), 18.0 + rad * 0.25, 0.16)
		_sfx_event(world, "passive.explosive_rounds", origin, from)

static func _mark_burn(target: Node2D, duration: float) -> void:
	if target == null:
		return
	var until_ms: int = int(Time.get_ticks_msec() + int(round(duration * 1000.0)))
	target.set_meta("_burn_until_ms", until_ms)

static func mark_burn(target: Node2D, duration: float) -> void:
	_mark_burn(target, duration)

static func _fire_mastery_bonus(target: Node2D, damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var until_ms: int = int(target.get_meta("_burn_until_ms", 0))
	if until_ms <= 0 or int(Time.get_ticks_msec()) > until_ms:
		return
	var mult := _param_f("fire_mastery", "damage_amp", 0.25)
	var bonus := int(round(float(damage) * mult))
	if bonus <= 0:
		return
	if target.has_method("take_damage"):
		target.take_damage(bonus, false, "burn")
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(1.0, 0.55, 0.25, 1.0))
	var world := _main_world(target)
	if world != null:
		_fx_flash(world, (target as Node2D).global_position + Vector2(0, -12), Color(1.0, 0.55, 0.25, 1.0), 14.0, 0.12)
		_sfx_event(world, "passive.fire_mastery", (target as Node2D).global_position, target)

static func _mark_fire_spread(target: Node2D, dps: float, dur: float, tick: float, count: int) -> void:
	if target == null:
		return
	target.set_meta("_fire_spread_dps", dps)
	target.set_meta("_fire_spread_dur", dur)
	target.set_meta("_fire_spread_tick", tick)
	target.set_meta("_fire_spread_count", count)
	target.set_meta("_fire_spread_radius", _param_f("fire_mastery", "spread_radius", 120.0))
	target.set_meta("_fire_spread_until_ms", int(Time.get_ticks_msec() + int(round(dur * 1000.0))))

static func mark_fire_spread(target: Node2D, dps: float, dur: float, tick: float, count: int) -> void:
	_mark_fire_spread(target, dps, dur, tick, count)

static func _mark_poison_spread(target: Node2D, dps: float, dur: float, tick: float, count: int) -> void:
	if target == null:
		return
	target.set_meta("_poison_spread_dps", dps)
	target.set_meta("_poison_spread_dur", dur)
	target.set_meta("_poison_spread_tick", tick)
	target.set_meta("_poison_spread_count", count)
	target.set_meta("_poison_spread_radius", _param_f("poison_mastery", "spread_radius", 100.0))
	target.set_meta("_poison_spread_until_ms", int(Time.get_ticks_msec() + int(round(dur * 1000.0))))

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
	# VFX: show stack ping (EffectBlocks spark; fallback to focus mark)
	var world := _main_world(target)
	if world == null or (not _vfx_event(world, "syn.focus_tick", (target as Node2D).global_position + Vector2(0, -18), Color(0.82, 0.65, 1.0, 1.0), 0.8)):
		var fm := VfxFocusMark.new()
		fm.setup((target as Node2D).global_position + Vector2(0, -18), Color(0.82, 0.65, 1.0, 1.0), 18.0, stacks, 0.18)
		_spawn_vfx(target as Node2D, fm)
	if world != null:
		_sfx_event(world, "syn.focus_tick", (target as Node2D).global_position, target)
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
	# VFX: detonation shockwave (EffectBlocks if exported)
	if world == null or (not _vfx_event(world, "syn.shock", (target as Node2D).global_position, Color(0.82, 0.65, 1.0, 1.0), 1.1)):
		var sw := VfxShockwave.new()
		sw.setup((target as Node2D).global_position, Color(0.82, 0.65, 1.0, 1.0), 18.0, rad * 0.9, 5.0, 0.22)
		_spawn_vfx(target as Node2D, sw)
	if world != null:
		_sfx_event(world, "syn.shock", (target as Node2D).global_position, target)
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
	# VFX: frost shatter (EffectBlocks if exported)
	var world := _main_world(target)
	if world == null or (not _vfx_event(world, "syn.frost", origin + Vector2(0, -10), Color(0.55, 0.85, 1.0, 1.0), 1.05)):
		var nova := VfxFrostNova.new()
		nova.setup(origin, Color(0.55, 0.85, 1.0, 1.0), rad, 10, 0.24)
		_spawn_vfx(target as Node2D, nova)
	if world != null:
		_sfx_event(world, "syn.frost", origin, target)
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
	# VFX: highlight (EffectBlocks if exported)
	var world := _main_world(target)
	if world == null or (not _vfx_event(world, "syn.execute", (target as Node2D).global_position + Vector2(0, -18), Color(1.0, 0.85, 0.30, 1.0), 0.9)):
		var fm := VfxFocusMark.new()
		fm.setup((target as Node2D).global_position + Vector2(0, -18), Color(1.0, 0.85, 0.30, 1.0), 18.0, 0, 0.16)
		_spawn_vfx(target as Node2D, fm)
	if world != null:
		_sfx_event(world, "syn.execute", (target as Node2D).global_position, target)

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

static func _chain_reaction_check(target: Node2D, damage: int) -> void:
	# Chain Reaction triggers when target dies - we mark them for explosion.
	if target == null or not is_instance_valid(target):
		return
	var rad := _param_f("chain_reaction", "radius", 120.0)
	var mult := _param_f("chain_reaction", "damage_mult", 0.60)
	var boom_dmg := int(round(float(damage) * mult))
	target.set_meta("_chain_reaction_dmg", boom_dmg)
	target.set_meta("_chain_reaction_radius", rad)

static func trigger_chain_reaction(target: Node2D) -> void:
	# Called when target dies if they have the chain_reaction meta.
	if target == null or not is_instance_valid(target):
		return
	var boom_dmg: int = int(target.get_meta("_chain_reaction_dmg", 0))
	var rad: float = float(target.get_meta("_chain_reaction_radius", 0.0))
	if boom_dmg <= 0 or rad <= 0.0:
		return
	var origin := (target as Node2D).global_position
	var world := _main_world(target)
	if world == null:
		return
	# VFX explosion
	_vfx_event(world, "syn.shock", origin, Color(1.0, 0.55, 0.25, 1.0), 1.2)
	# Damage nearby enemies
	var victims := _nearby_enemies(target, origin, rad, target)
	for v in victims:
		if v.has_method("take_damage"):
			v.take_damage(boom_dmg, false, "blast")
		if v.has_method("pulse_vfx"):
			v.pulse_vfx(Color(1.0, 0.55, 0.25, 1.0))

static func _phantom_strike(unit: Node2D, target: Node2D, damage: int, is_crit: bool) -> void:
	if unit == null or target == null or not is_instance_valid(target):
		return
	var chance := _param_f("phantom_strike", "chance", 0.20)
	if randf() > chance:
		return
	var mult := _param_f("phantom_strike", "damage_mult", 1.0)
	var bonus_dmg := int(round(float(damage) * mult))
	if bonus_dmg <= 0:
		return
	if target.has_method("take_damage"):
		target.take_damage(bonus_dmg, is_crit, "phantom")
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.75, 0.85, 1.0, 1.0))
	var world := _main_world(unit)
	if world != null:
		_vfx_event(world, "syn.arc", (target as Node2D).global_position + Vector2(0, -18), Color(0.75, 0.85, 1.0, 1.0), 0.8)

static func _venomous(target: Node2D, damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var mult := _param_f("venomous", "damage_mult", 0.15)
	var dur := _param_f("venomous", "duration", 5.0)
	var tick := _param_f("venomous", "tick_interval", 0.5)
	var max_stacks := _param_i("venomous", "max_stacks", 3)
	var dps := float(damage) * mult
	if dps <= 0.0:
		return
	# Check current stacks
	var cur_stacks: int = int(target.get_meta("_venom_stacks", 0))
	if cur_stacks < max_stacks:
		cur_stacks += 1
		target.set_meta("_venom_stacks", cur_stacks)
	# Apply or refresh venom
	if target.has_method("apply_bleed"):
		target.apply_bleed(dps * cur_stacks, dur, tick)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.45, 0.95, 0.35, 1.0))
	var world := _main_world(target)
	if world != null:
		_vfx_event(world, "syn.wisp", (target as Node2D).global_position + Vector2(0, -18), Color(0.45, 0.95, 0.35, 1.0), 0.7)
		_sfx_event(world, "syn.wisp", (target as Node2D).global_position, target)

static func get_berserker_mods(unit: Node2D) -> Dictionary:
	# Returns stat modifiers for berserker if active (low HP = power boost).
	# Called from SquadUnit when applying stats.
	var out := {"attack_speed_mult": 1.0, "damage_mult": 1.0}
	if unit == null or not is_instance_valid(unit):
		return out
	if not unit.has_method("get_hp_ratio"):
		return out
	var hp_ratio := float(unit.get_hp_ratio())
	var threshold := _param_f("berserker", "hp_threshold", 0.50)
	if hp_ratio > threshold:
		return out
	out["attack_speed_mult"] = _param_f("berserker", "attack_speed_mult", 1.40)
	out["damage_mult"] = _param_f("berserker", "damage_mult", 1.20)
	return out

static func get_glass_cannon_mods(_unit: Node2D) -> Dictionary:
	# Glass cannon: deal +50% damage but take +25% damage.
	return {
		"damage_mult": _param_f("glass_cannon", "damage_mult", 1.50),
		"damage_taken_mult": _param_f("glass_cannon", "damage_taken_mult", 1.25)
	}

## Note: we intentionally do not spawn decal-like VFX (rings/crescents) for status effects.
