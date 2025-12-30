class_name SynergySystem
extends Node

# Data-driven squad synergies (set bonuses) derived from a unit's tags.
#
# Tags are generated automatically from CharacterData:
# - class:<warrior|mage|rogue|guardian|healer|summoner>
# - origin:<undead|machine|beast|demon|elemental|human>
# - style:<melee|ranged>
# - arch:<archetype_id>
#
# Synergies are defined in: res://data/synergies.json

static var _loaded: bool = false
static var _synergies: Array[Dictionary] = []

static var _roster: Array[CharacterData] = []
static var _tag_counts: Dictionary = {} # tag -> int
static var _active: Array[Dictionary] = [] # [{name, count_tag, count, tier_count, mods, effects, applies_to_tags}]

const VFX_ARC_SCENE: PackedScene = preload("res://scenes/VfxArcLightning.tscn")
const PROJ_SCENE: PackedScene = preload("res://scenes/Projectile.tscn")

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path := "res://data/synergies.json"
	if not ResourceLoader.exists(path):
		push_warning("SynergySystem: missing %s" % path)
		return
	var json_text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SynergySystem: invalid JSON")
		return
	var d: Dictionary = parsed
	var arr: Array = d.get("synergies", [])
	_synergies.clear()
	for s in arr:
		if typeof(s) == TYPE_DICTIONARY:
			_synergies.append(s)

static func set_roster(roster: Array) -> void:
	# Accept Array[CharacterData] or Array[Variant], ignore invalid entries.
	ensure_loaded()
	_roster.clear()
	for x in roster:
		var cd := x as CharacterData
		if cd != null:
			_roster.append(cd)
	_rebuild()

static func _rebuild() -> void:
	_tag_counts.clear()
	for cd in _roster:
		for t in _tags_for_cd(cd):
			_tag_counts[t] = int(_tag_counts.get(t, 0)) + 1

	_active.clear()
	for s in _synergies:
		var count_tag := String(s.get("count_tag", ""))
		if count_tag == "":
			continue
		var c: int = int(_tag_counts.get(count_tag, 0))
		if c <= 0:
			continue
		var tier := _best_tier(s.get("tiers", []), c)
		if tier.is_empty():
			continue
		var entry := {
			"id": String(s.get("id", "")),
			"name": String(s.get("name", count_tag)),
			"count_tag": count_tag,
			"count": c,
			"tier_count": int(tier.get("count", 0)),
			"mods": tier.get("mods", {}) as Dictionary,
			"effects": tier.get("effects", []) as Array,
			"applies_to_tags": s.get("applies_to_tags", []) as Array
		}
		_active.append(entry)

static func _best_tier(tiers_raw: Array, count: int) -> Dictionary:
	# Pick the highest tier <= count.
	var best: Dictionary = {}
	var best_n: int = -1
	for t in tiers_raw:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var td: Dictionary = t
		var n: int = int(td.get("count", 0))
		if n > 0 and n <= count and n > best_n:
			best = td
			best_n = n
	return best

static func mods_for_cd(cd: CharacterData) -> Dictionary:
	# Returns multiplicative stat mods for the given unit.
	# Keys:
	# - max_hp_mult
	# - attack_damage_mult
	# - move_speed_mult
	# - attack_cooldown_mult (smaller is faster)
	var out: Dictionary = {
		"max_hp_mult": 1.0,
		"attack_damage_mult": 1.0,
		"move_speed_mult": 1.0,
		"attack_cooldown_mult": 1.0
	}
	if cd == null:
		return out
	var tags := _tags_for_cd(cd)
	for a in _active:
		var req: Array = a.get("applies_to_tags", []) as Array
		var ok := true
		for r in req:
			if not tags.has(String(r)):
				ok = false
				break
		if not ok:
			continue
		var mods := a.get("mods", {}) as Dictionary
		for k in mods.keys():
			var key := String(k)
			var v := float(mods.get(k, 1.0))
			out[key] = float(out.get(key, 1.0)) * v
	return out

static func effects_for_cd(cd: CharacterData) -> Array[Dictionary]:
	# Returns the list of effect dictionaries that apply to this unit.
	var out: Array[Dictionary] = []
	if cd == null:
		return out
	var tags := _tags_for_cd(cd)
	for a in _active:
		var req: Array = a.get("applies_to_tags", []) as Array
		var ok := true
		for r in req:
			if not tags.has(String(r)):
				ok = false
				break
		if not ok:
			continue
		var effs: Array = a.get("effects", []) as Array
		for e in effs:
			if typeof(e) == TYPE_DICTIONARY:
				out.append(e as Dictionary)
	return out

static func active_synergies() -> Array[Dictionary]:
	return _active.duplicate(true)

static func summary_text() -> String:
	# Compact, HUD-friendly summary.
	if _active.is_empty():
		return "Synergies: —"
	var parts: Array[String] = []
	for a in _active:
		var name := String(a.get("name", ""))
		var tier_n := int(a.get("tier_count", 0))
		var c := int(a.get("count", 0))
		parts.append("%s (%d/%d)" % [name, c, tier_n])
	return "Synergies: " + "  •  ".join(parts)

#
# Runtime hooks (mechanic synergies)
#

static func on_unit_attack(cd: CharacterData, unit: Node2D, target: Node2D, damage: int, is_crit: bool, is_melee: bool) -> void:
	if cd == null or unit == null or target == null:
		return
	if not is_instance_valid(unit) or not is_instance_valid(target):
		return
	var effs := effects_for_cd(cd)
	for e in effs:
		var t := String(e.get("type", ""))
		match t:
			"volley_shot":
				if not is_melee:
					_effect_volley_shot(cd, unit, target, damage, e)
			"shockstep":
				if is_melee:
					_effect_shockstep(unit, target, damage, e)
			"arc_focus":
				_effect_arc_focus(unit, target, damage, e)
			"execute_protocol":
				_effect_execute_protocol(unit, target, damage, e)
			"crit_arc":
				if is_crit:
					_effect_crit_arc(unit, target, damage, e)
			"hellfire_burn":
				_effect_hellfire_burn(unit, target, damage, e)
			"inferno_blast":
				_effect_inferno_blast(unit, target, damage, e)
			"prismatic_surge":
				_effect_prismatic_surge(unit, target, damage, e)
			"pack_maul":
				if is_melee:
					_effect_pack_maul(unit, target, damage, e)
			"focus_fire":
				_effect_focus_fire(unit, target, damage, e)
			_:
				pass

static func on_projectile_hit(cd: CharacterData, proj: Node2D, enemy: Node2D, damage: int, is_crit: bool) -> void:
	if cd == null or proj == null or enemy == null:
		return
	if not is_instance_valid(proj) or not is_instance_valid(enemy):
		return
	var effs := effects_for_cd(cd)
	for e in effs:
		var t := String(e.get("type", ""))
		match t:
			"ricochet_matrix":
				_effect_ricochet_matrix(proj, enemy, damage, e)
			"crit_arc":
				if is_crit:
					_effect_crit_arc(proj, enemy, damage, e)
			"hellfire_burn":
				_effect_hellfire_burn(proj, enemy, damage, e)
			"inferno_blast":
				_effect_inferno_blast(proj, enemy, damage, e)
			"prismatic_surge":
				_effect_prismatic_surge(proj, enemy, damage, e)
			"focus_fire":
				_effect_focus_fire(proj, enemy, damage, e)
			_:
				pass

static func tick_unit(cd: CharacterData, unit: Node2D) -> void:
	# Called from SquadUnit._physics_process (gated by cooldowns).
	if cd == null or unit == null or not is_instance_valid(unit):
		return
	var effs := effects_for_cd(cd)
	for e in effs:
		var t := String(e.get("type", ""))
		match t:
			"bulwark_aura":
				_effect_bulwark_aura(unit, e)
			"aura_heal":
				_effect_aura_heal(unit, e)
			"wisp_bolt":
				_effect_wisp_bolt(unit, e)
			"sanctuary_heal":
				_effect_sanctuary_heal(unit, e)
			_:
				pass

static func on_enemy_killed(main: Node2D, is_elite: bool, was_boss: bool) -> void:
	# Global triggers that don't need a specific killer attribution.
	if main == null or not is_instance_valid(main):
		return
	for a in _active:
		var sid := String(a.get("id", ""))
		for eff in (a.get("effects", []) as Array):
			if typeof(eff) != TYPE_DICTIONARY:
				continue
			var d := eff as Dictionary
			match String(d.get("type", "")):
				"soul_feast":
					if sid == "undying":
						_effect_soul_feast(main, is_elite, d)
				"death_chill":
					if sid == "undying":
						_effect_death_chill(main, is_elite, d)
				"bounty":
					if sid == "bannerlords":
						_effect_bounty(main, is_elite, d)
				_:
					pass

static func extra_pierce_for_cd(cd: CharacterData) -> int:
	var extra: int = 0
	for e in effects_for_cd(cd):
		if String(e.get("type", "")) == "pierce_bonus":
			extra += int(e.get("extra_pierce", 0))
	return extra

#
# New effects (Human/Demon/Elemental/Beast)
#

static func _effect_bounty(main: Node2D, is_elite: bool, e: Dictionary) -> void:
	var chance := float(e.get("chance", 0.12))
	if randf() > chance:
		return
	var base := int(e.get("essence", 1))
	var elite_bonus := int(e.get("elite_bonus", 0))
	var add := base + (elite_bonus if is_elite else 0)
	if add <= 0:
		return
	# Main owns essence economy.
	# (Main.gd defines `essence`; this is a tight integration by design.)
	main.essence = int(main.essence) + add

static func _effect_hellfire_burn(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var chance := float(e.get("chance", 0.32))
	if randf() > chance:
		return
	var cd_s := float(e.get("cooldown", 0.10))
	if not _cooldown_gate(from, "_syn_hellfire_cd", cd_s):
		return
	var dps_mult := float(e.get("dps_mult", 0.12))
	var dur := float(e.get("duration", 2.5))
	var tick := float(e.get("tick", 0.5))
	var dps := maxf(1.0, float(damage) * dps_mult)
	if target.has_method("apply_burn"):
		target.apply_burn(dps, dur, tick)
	elif target.has_method("apply_bleed"):
		# fallback
		target.apply_bleed(dps, dur, tick)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(1.0, 0.55, 0.18, 1.0))
	var world := _main_world(from)
	if world != null:
		var fb := VfxFlameBurst.new()
		fb.setup((target as Node2D).global_position, Color(1.0, 0.55, 0.18, 1.0), 26.0, 10, 0.20)
		_spawn_vfx(world, fb)
		_sfx(world, "syn.flame", (target as Node2D).global_position, from)

static func _effect_inferno_blast(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval: int = int(e.get("interval_hits", 7))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_inferno_ctr", 0)) + 1
	from.set_meta("_syn_inferno_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_inferno_cd", 0.10):
		return
	var radius := float(e.get("radius", 140.0))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.22))))
	var world := _main_world(from)
	if world != null:
		var fb := VfxFlameBurst.new()
		fb.setup((target as Node2D).global_position, Color(1.0, 0.35, 0.25, 1.0), radius * 0.30, 14, 0.22)
		_spawn_vfx(world, fb)
		_sfx(world, "syn.flame", (target as Node2D).global_position, from)
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to((target as Node2D).global_position) <= r2:
			if n2.has_method("take_damage"):
				n2.take_damage(dmg, false, "blast")
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(1.0, 0.35, 0.25, 1.0))

static func _effect_prismatic_surge(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval: int = int(e.get("interval_hits", 6))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_prism_ctr", 0)) + 1
	from.set_meta("_syn_prism_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_prism_cd", 0.12):
		return
	var radius := float(e.get("radius", 220.0))
	var roll := randi() % 3
	match roll:
		0:
			# lightning mini-arc
			var pick := _pick_near_enemy(from, (target as Node2D).global_position, radius, target)
			if pick != null:
				var world := _main_world(from)
				_spawn_arc(world, (target as Node2D).global_position, pick.global_position, Color(0.55, 0.95, 1.0, 0.95))
				_sfx(world, "syn.arc", (target as Node2D).global_position, from)
				var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.20))))
				if pick.has_method("take_damage"):
					pick.take_damage(dmg, false, "arc")
				if pick.has_method("pulse_vfx"):
					pick.pulse_vfx(Color(0.55, 0.95, 1.0, 1.0))
		1:
			# chill wave
			if target.has_method("apply_slow"):
				target.apply_slow(float(e.get("slow_mult", 0.82)), float(e.get("slow_dur", 0.7)))
			if target.has_method("pulse_vfx"):
				target.pulse_vfx(Color(0.55, 0.85, 1.0, 1.0))
			var world2 := _main_world(from)
			if world2 != null:
				var nova := VfxFrostNova.new()
				nova.setup((target as Node2D).global_position, Color(0.55, 0.85, 1.0, 1.0), 64.0, 7, 0.22)
				_spawn_vfx(world2, nova)
				_sfx(world2, "syn.frost", (target as Node2D).global_position, from)
		_:
			# burn
			var dps := maxf(1.0, float(damage) * float(e.get("burn_dps_mult", 0.10)))
			var dur := float(e.get("burn_dur", 2.2))
			if target.has_method("apply_burn"):
				target.apply_burn(dps, dur, 0.5)
			elif target.has_method("apply_bleed"):
				target.apply_bleed(dps, dur, 0.5)
			if target.has_method("pulse_vfx"):
				target.pulse_vfx(Color(1.0, 0.75, 0.25, 1.0))
			var world3 := _main_world(from)
			if world3 != null:
				var fb := VfxFlameBurst.new()
				fb.setup((target as Node2D).global_position, Color(1.0, 0.75, 0.25, 1.0), 22.0, 9, 0.18)
				_spawn_vfx(world3, fb)
				_sfx(world3, "syn.flame", (target as Node2D).global_position, from)

static func _effect_pack_maul(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval: int = int(e.get("interval_hits", 4))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_pack_ctr", 0)) + 1
	from.set_meta("_syn_pack_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_pack_cd", 0.10):
		return
	var radius := float(e.get("radius", 120.0))
	var slow_mult := float(e.get("slow_mult", 0.90))
	var slow_dur := float(e.get("slow_dur", 0.45))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.18))))
	var world := _main_world(from)
	if world != null:
		var sw := VfxShockwave.new()
		sw.setup((target as Node2D).global_position, Color(0.55, 1.0, 0.65, 1.0), 16.0, radius, 5.0, 0.20)
		_spawn_vfx(world, sw)
		_sfx(world, "syn.shock", (target as Node2D).global_position, from)
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to((target as Node2D).global_position) <= r2:
			if n2.has_method("take_damage"):
				n2.take_damage(dmg, false, "blast")
			if n2.has_method("apply_slow"):
				n2.apply_slow(slow_mult, slow_dur)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.55, 1.0, 0.65, 1.0))

static func _effect_focus_fire(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var stacks_req := int(e.get("stacks", 6))
	var window := float(e.get("window", 1.2))
	var cd_s := float(e.get("cooldown", 0.10))
	if stacks_req <= 0:
		return
	if not _cooldown_gate(from, "_syn_focus_cd", cd_s):
		return
	var now_ms: int = int(Time.get_ticks_msec())
	var world := _main_world(from)
	if world == null:
		return
	var last_target: int = int(world.get_meta("_syn_focus_tid", 0))
	var last_until: int = int(world.get_meta("_syn_focus_until", 0))
	var stacks: int = int(world.get_meta("_syn_focus_stacks", 0))
	var tid := int((target as Node).get_instance_id())
	if now_ms > last_until or last_target != tid:
		stacks = 0
	last_target = tid
	stacks += 1
	last_until = now_ms + int(round(window * 1000.0))
	world.set_meta("_syn_focus_tid", last_target)
	world.set_meta("_syn_focus_until", last_until)
	world.set_meta("_syn_focus_stacks", stacks)
	if stacks < stacks_req:
		var mark2 := VfxFocusMark.new()
		mark2.setup((target as Node2D).global_position, Color(0.92, 0.85, 0.30, 1.0), 22.0, stacks, 0.18)
		_spawn_vfx(world, mark2)
		# Only tick every 2 stacks (feels intentional, less random/noisy).
		if (stacks % 2) == 0:
			_sfx(world, "syn.focus_tick", (target as Node2D).global_position, from)
		return
	# Trigger burst and reset.
	world.set_meta("_syn_focus_stacks", 0)
	var bonus := int(round(float(damage) * float(e.get("bonus_mult", 0.35))))
	if bonus <= 0:
		return
	if target.has_method("take_damage"):
		target.take_damage(bonus, false, "execute")
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.92, 0.85, 0.30, 1.0))
	var mark := VfxFocusMark.new()
	mark.setup((target as Node2D).global_position, Color(0.92, 0.85, 0.30, 1.0), 30.0, stacks_req, 0.24)
	_spawn_vfx(world, mark)
	_sfx(world, "syn.execute", (target as Node2D).global_position, from)

#
# Effect implementations
#

static func _cooldown_gate(node: Node, key: String, cd_s: float) -> bool:
	if node == null:
		return false
	var now_ms: int = int(Time.get_ticks_msec())
	var last_ms: int = int(node.get_meta(key, 0))
	var cd_ms: int = int(round(cd_s * 1000.0))
	if last_ms > 0 and (now_ms - last_ms) < cd_ms:
		return false
	node.set_meta(key, now_ms)
	return true

static func _main_world(from: Node) -> Node2D:
	if from == null:
		return null
	return from.get_tree().get_first_node_in_group("main") as Node2D

static func _cached_enemies(from: Node) -> Array:
	var world := _main_world(from)
	if world != null and world.has_method("get_cached_enemies"):
		return world.get_cached_enemies()
	return from.get_tree().get_nodes_in_group("enemies")

static func _cached_squad(from: Node) -> Array:
	var world := _main_world(from)
	if world != null and world.has_method("get_cached_squad_units"):
		return world.get_cached_squad_units()
	return from.get_tree().get_nodes_in_group("squad_units")

static func _pick_near_enemy(from: Node2D, origin: Vector2, radius: float, exclude: Node2D) -> Node2D:
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	var best: Node2D = null
	var best_d2: float = INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n2 := e as Node2D
		if n2 == null or n2 == exclude:
			continue
		var d2 := n2.global_position.distance_squared_to(origin)
		if d2 <= r2 and d2 < best_d2:
			best_d2 = d2
			best = n2
	return best

static func _spawn_arc(world: Node2D, a: Vector2, b: Vector2, col: Color) -> void:
	if world == null or VFX_ARC_SCENE == null:
		return
	var v := VFX_ARC_SCENE.instantiate()
	world.add_child(v)
	if v.has_method("setup"):
		v.setup(a, b, col)

static func _spawn_vfx(world: Node2D, v: Node) -> void:
	if world == null or v == null:
		return
	world.add_child(v)

static func _sfx(world: Node2D, event_id: String, pos: Vector2, emitter: Object = null) -> void:
	if world == null:
		return
	var s := world.get_node_or_null("/root/SfxSystem")
	if s != null and is_instance_valid(s) and s.has_method("play_event"):
		s.play_event(event_id, pos, emitter)

static func _spawn_projectile(world: Node2D, from_pos: Vector2, to: Node2D, dmg: int, tint: Color) -> void:
	if world == null or PROJ_SCENE == null or to == null or not is_instance_valid(to):
		return
	var p := PROJ_SCENE.instantiate()
	world.add_child(p)
	(p as Node2D).global_position = from_pos
	if p.has_method("set_vfx_color"):
		p.set_vfx_color(tint)
	if p.has_method("setup_target"):
		# Signature supports optional source_cd; we omit here.
		p.setup_target(to, dmg, false, PackedStringArray())

static func _effect_volley_shot(cd: CharacterData, unit: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval: int = int(e.get("interval_attacks", 4))
	if interval <= 0:
		return
	var c: int = int(unit.get_meta("_syn_volley_ctr", 0)) + 1
	unit.set_meta("_syn_volley_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(unit, "_syn_volley_cd", 0.05):
		return
	var radius := float(e.get("radius", 420.0))
	var pick := _pick_near_enemy(unit, (target as Node2D).global_position, radius, target)
	if pick == null:
		return
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.5))))
	var world := _main_world(unit)
	_spawn_projectile(world, (unit as Node2D).global_position, pick, dmg, Color(0.70, 1.00, 0.85, 0.95))
	if pick.has_method("pulse_vfx"):
		pick.pulse_vfx(Color(0.70, 1.00, 0.85, 1.0))

static func _effect_shockstep(unit: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval: int = int(e.get("interval_hits", 3))
	if interval <= 0:
		return
	var c: int = int(unit.get_meta("_syn_shock_ctr", 0)) + 1
	unit.set_meta("_syn_shock_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(unit, "_syn_shock_cd", 0.08):
		return
	var radius := float(e.get("radius", 130.0))
	var slow_mult := float(e.get("slow_mult", 0.88))
	var duration := float(e.get("duration", 0.4))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.22))))
	var world := _main_world(unit)
	if world != null:
		var wave := VfxShockwave.new()
		wave.setup((target as Node2D).global_position, Color(0.82, 0.65, 1.0, 1.0), 18.0, radius, 5.0, 0.22)
		_spawn_vfx(world, wave)
		_sfx(world, "syn.shock", (target as Node2D).global_position, unit)
	var enemies: Array = _cached_enemies(unit)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to((target as Node2D).global_position) <= r2:
			if n2.has_method("take_damage"):
				n2.take_damage(dmg, false, "blast")
			if n2.has_method("apply_slow"):
				n2.apply_slow(slow_mult, duration)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.82, 0.65, 1.0, 1.0))

static func _effect_arc_focus(unit: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval: int = int(e.get("interval_hits", 6))
	if interval <= 0:
		return
	var c: int = int(unit.get_meta("_syn_arc_ctr", 0)) + 1
	unit.set_meta("_syn_arc_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(unit, "_syn_arc_cd", 0.12):
		return
	var radius := float(e.get("radius", 240.0))
	var chains := int(e.get("chains", 2))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.30))))
	var origin := (target as Node2D).global_position
	var enemies: Array = _cached_enemies(unit)
	var r2 := radius * radius
	var picked: int = 0
	var world := _main_world(unit)
	# One sound per proc (not per chain target).
	_sfx(world, "syn.arc", origin, unit)
	for en in enemies:
		if picked >= chains:
			break
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null or n2 == target:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			if n2.has_method("take_damage"):
				n2.take_damage(dmg, false, "arc")
			_spawn_arc(world, origin, n2.global_position, Color(0.55, 0.95, 1.0, 0.95))
			_sfx(world, "syn.arc", origin, unit)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.55, 0.95, 1.0, 1.0))
			picked += 1

static func _effect_execute_protocol(unit: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var thr := float(e.get("threshold", 0.35))
	var bonus_mult := float(e.get("bonus_mult", 0.18))
	var cd_s := float(e.get("cooldown", 0.08))
	if not _cooldown_gate(unit, "_syn_exec_cd", cd_s):
		return
	if not target.has_method("get_hp_ratio"):
		return
	var r := float(target.get_hp_ratio())
	if r > thr:
		return
	var bonus := int(round(float(damage) * bonus_mult))
	if bonus <= 0:
		return
	if target.has_method("take_damage"):
		target.take_damage(bonus, false, "execute")
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(1.0, 0.60, 0.20, 1.0))
	var world := _main_world(unit)
	if world != null:
		var mark := VfxFocusMark.new()
		mark.setup((target as Node2D).global_position, Color(1.0, 0.60, 0.20, 1.0), 22.0, 0, 0.18)
		_spawn_vfx(world, mark)
		_sfx(world, "syn.execute", (target as Node2D).global_position, unit)

static func _effect_crit_arc(unit: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var chance := float(e.get("chance", 0.35))
	if randf() > chance:
		return
	var cd_s := float(e.get("cooldown", 0.20))
	if not _cooldown_gate(unit, "_syn_crit_arc_cd", cd_s):
		return
	var radius := float(e.get("radius", 240.0))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.28))))
	var pick := _pick_near_enemy(unit as Node2D, (target as Node2D).global_position, radius, target)
	if pick == null:
		return
	var world := _main_world(unit)
	_spawn_arc(world, (target as Node2D).global_position, pick.global_position, Color(1.0, 0.85, 0.30, 0.95))
	_sfx(world, "syn.arc", (target as Node2D).global_position, unit)
	if pick.has_method("take_damage"):
		pick.take_damage(dmg, false, "arc")
	if pick.has_method("pulse_vfx"):
		pick.pulse_vfx(Color(1.0, 0.85, 0.30, 1.0))

static func _effect_ricochet_matrix(proj: Node2D, enemy: Node2D, damage: int, e: Dictionary) -> void:
	var chance := float(e.get("chance", 0.28))
	if randf() > chance:
		return
	var cd_s := float(e.get("cooldown", 0.20))
	if not _cooldown_gate(proj, "_syn_rico_cd", cd_s):
		return
	var radius := float(e.get("radius", 290.0))
	var pick := _pick_near_enemy(proj as Node2D, (enemy as Node2D).global_position, radius, enemy)
	if pick == null:
		return
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.55))))
	var world := _main_world(proj)
	_spawn_arc(world, (enemy as Node2D).global_position, pick.global_position, Color(0.70, 0.95, 0.90, 0.95))
	_spawn_projectile(world, (enemy as Node2D).global_position, pick, dmg, Color(0.70, 0.95, 0.90, 0.95))
	if world != null:
		var sw := VfxShockwave.new()
		sw.setup((enemy as Node2D).global_position, Color(0.70, 0.95, 0.90, 1.0), 14.0, 46.0, 4.0, 0.18)
		_spawn_vfx(world, sw)
		_sfx(world, "syn.arc", (enemy as Node2D).global_position, proj)

static func _effect_bulwark_aura(unit: Node2D, e: Dictionary) -> void:
	var cd_s := float(e.get("cooldown", 0.70))
	if not _cooldown_gate(unit, "_syn_bulwark_cd", cd_s):
		return
	var radius := float(e.get("radius", 95.0))
	var slow_mult := float(e.get("slow_mult", 0.86))
	var duration := float(e.get("duration", 0.55))
	var world := _main_world(unit)
	if world != null:
		var pulse := VfxHolyPulse.new()
		pulse.setup((unit as Node2D).global_position, Color(0.40, 1.0, 0.55, 1.0), 14.0, radius * 0.55, 0.20)
		_spawn_vfx(world, pulse)
		_sfx(world, "syn.holy", (unit as Node2D).global_position, unit)
	var enemies: Array = _cached_enemies(unit)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to((unit as Node2D).global_position) <= r2:
			if n2.has_method("apply_slow"):
				n2.apply_slow(slow_mult, duration)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.40, 1.0, 0.55, 1.0))

static func _effect_aura_heal(unit: Node2D, e: Dictionary) -> void:
	var cd_s := float(e.get("cooldown", 1.80))
	if not _cooldown_gate(unit, "_syn_aura_heal_cd", cd_s):
		return
	var heal_frac := float(e.get("heal_frac", 0.02))
	var world := _main_world(unit)
	if world != null:
		var pulse := VfxHolyPulse.new()
		pulse.setup((unit as Node2D).global_position, Color(0.55, 1.0, 0.65, 1.0), 16.0, 52.0, 0.22)
		_spawn_vfx(world, pulse)
		_sfx(world, "syn.holy", (unit as Node2D).global_position, unit)
	var squad: Array = _cached_squad(unit)
	for u in squad:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		if n2.has_method("heal") and n2.has_method("get_max_hp"):
			var mh := int(n2.get_max_hp())
			var amt: int = int(round(float(mh) * heal_frac))
			n2.heal(max(1, amt))
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.55, 1.0, 0.65, 1.0))

static func _effect_wisp_bolt(unit: Node2D, e: Dictionary) -> void:
	var cd_s := float(e.get("cooldown", 1.60))
	if not _cooldown_gate(unit, "_syn_wisp_cd", cd_s):
		return
	var radius := float(e.get("radius", 520.0))
	var extra := int(e.get("extra", 0))
	var enemies: Array = _cached_enemies(unit)
	if enemies.is_empty():
		return
	# pick nearest enemy to unit within radius
	var pick := _pick_near_enemy(unit as Node2D, (unit as Node2D).global_position, radius, null)
	if pick == null:
		return
	var dmg_mult := float(e.get("damage_mult", 0.35))
	var base_dmg := 10
	var cd := unit.get("character_data") as CharacterData
	if cd != null:
		base_dmg = int(cd.attack_damage)
	var dmg := int(round(float(base_dmg) * dmg_mult))
	var world := _main_world(unit)
	if world != null:
		var emb := VfxFlameBurst.new()
		emb.setup((unit as Node2D).global_position, Color(0.95, 0.35, 0.95, 1.0), 18.0, 8, 0.18)
		_spawn_vfx(world, emb)
		_sfx(world, "syn.flame", (unit as Node2D).global_position, unit)
	_spawn_projectile(world, (unit as Node2D).global_position, pick, dmg, Color(0.95, 0.35, 0.95, 0.95))
	if extra > 0:
		var pick2 := _pick_near_enemy(unit as Node2D, (pick as Node2D).global_position, radius, pick)
		if pick2 != null:
			_spawn_projectile(world, (unit as Node2D).global_position, pick2, dmg, Color(0.95, 0.35, 0.95, 0.95))

static func _effect_sanctuary_heal(unit: Node2D, e: Dictionary) -> void:
	var cd_s := float(e.get("cooldown", 2.20))
	if not _cooldown_gate(unit, "_syn_sanctuary_cd", cd_s):
		return
	var heal_frac := float(e.get("heal_frac", 0.04))
	var squad: Array = _cached_squad(unit)
	var best: Node2D = null
	var best_ratio: float = 2.0
	for u in squad:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		if n2.has_method("get_hp_ratio"):
			var r := float(n2.get_hp_ratio())
			if r < best_ratio:
				best_ratio = r
				best = n2
	if best != null and best.has_method("heal"):
		var mh := int(best.get_max_hp()) if best.has_method("get_max_hp") else 100
		var amt := int(round(float(mh) * heal_frac))
		best.heal(max(1, amt))
		if best.has_method("pulse_vfx"):
			best.pulse_vfx(Color(0.65, 0.85, 1.0, 1.0))
		var world := _main_world(unit)
		if world != null:
			var pulse := VfxHolyPulse.new()
			pulse.setup(best.global_position, Color(0.65, 0.85, 1.0, 1.0), 14.0, 46.0, 0.22)
			_spawn_vfx(world, pulse)
			_sfx(world, "syn.holy", best.global_position, unit)

static func _effect_soul_feast(main: Node2D, is_elite: bool, e: Dictionary) -> void:
	var heal_frac := float(e.get("heal_frac", 0.05))
	var elite_bonus := float(e.get("elite_bonus", 0.02))
	var squad: Array = []
	if main.has_method("get_cached_squad_units"):
		squad = main.get_cached_squad_units()
	else:
		squad = main.get_tree().get_nodes_in_group("squad_units")
	var best: Node2D = null
	var best_ratio: float = 2.0
	for u in squad:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		if n2.has_method("get_hp_ratio"):
			var r := float(n2.get_hp_ratio())
			if r < best_ratio:
				best_ratio = r
				best = n2
	if best != null and best.has_method("heal"):
		var f := heal_frac + (elite_bonus if is_elite else 0.0)
		var mh := int(best.get_max_hp()) if best.has_method("get_max_hp") else 100
		var amt := int(round(float(mh) * f))
		best.heal(max(1, amt))
		if best.has_method("pulse_vfx"):
			best.pulse_vfx(Color(0.55, 1.0, 0.65, 1.0))
		var pulse := VfxHolyPulse.new()
		pulse.setup(best.global_position, Color(0.55, 1.0, 0.65, 1.0), 14.0, 44.0, 0.22)
		_spawn_vfx(main, pulse)
		_sfx(main, "syn.holy", best.global_position, main)

static func _effect_death_chill(main: Node2D, is_elite: bool, e: Dictionary) -> void:
	# Soft crowd-control burst on kill (gated).
	var cd_s := float(e.get("cooldown", 0.35))
	if not _cooldown_gate(main, "_syn_death_chill_cd", cd_s):
		return
	var radius := float(e.get("radius", 160.0))
	var slow_mult := float(e.get("slow_mult", 0.86))
	var duration := float(e.get("duration", 0.70))
	var player := main.get_tree().get_first_node_in_group("player") as Node2D
	var origin := player.global_position if player != null else main.global_position
	var enemies: Array = []
	if main.has_method("get_cached_enemies"):
		enemies = main.get_cached_enemies()
	else:
		enemies = main.get_tree().get_nodes_in_group("enemies")
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			if n2.has_method("apply_slow"):
				n2.apply_slow(slow_mult, duration)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.55, 0.85, 1.0, 1.0))
	var nova := VfxFrostNova.new()
	nova.setup(origin, Color(0.55, 0.85, 1.0, 1.0), radius, 10, 0.26)
	_spawn_vfx(main, nova)
	_sfx(main, "syn.frost", origin, main)

static func _tags_for_cd(cd: CharacterData) -> PackedStringArray:
	var out := PackedStringArray()
	if cd == null:
		return out
	# Class tags
	match cd.class_type:
		CharacterData.Class.WARRIOR: out.append("class:warrior")
		CharacterData.Class.MAGE: out.append("class:mage")
		CharacterData.Class.ROGUE: out.append("class:rogue")
		CharacterData.Class.GUARDIAN: out.append("class:guardian")
		CharacterData.Class.HEALER: out.append("class:healer")
		CharacterData.Class.SUMMONER: out.append("class:summoner")
		_: pass
	# Origin tags
	match cd.origin:
		CharacterData.Origin.UNDEAD: out.append("origin:undead")
		CharacterData.Origin.MACHINE: out.append("origin:machine")
		CharacterData.Origin.BEAST: out.append("origin:beast")
		CharacterData.Origin.DEMON: out.append("origin:demon")
		CharacterData.Origin.ELEMENTAL: out.append("origin:elemental")
		CharacterData.Origin.HUMAN: out.append("origin:human")
		_: pass
	# Style tags
	if cd.attack_style == CharacterData.AttackStyle.MELEE:
		out.append("style:melee")
	else:
		out.append("style:ranged")
	# Archetype tag (always)
	if cd.archetype_id != "":
		out.append("arch:%s" % cd.archetype_id)
	return out


