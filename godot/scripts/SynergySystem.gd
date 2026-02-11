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

static func _get_synergy(syn_id: String) -> Dictionary:
	ensure_loaded()
	for s in _synergies:
		if String(s.get("id", "")) == syn_id:
			return s
	return {}

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

static func all_synergy_states() -> Array[Dictionary]:
	# Returns per-synergy state including current count and best/next tier data.
	ensure_loaded()
	var out: Array[Dictionary] = []
	for s in _synergies:
		var count_tag := String(s.get("count_tag", ""))
		if count_tag == "":
			continue
		var c: int = int(_tag_counts.get(count_tag, 0))
		var best: Dictionary = _best_tier(s.get("tiers", []), c)
		var nxt: Dictionary = _next_tier(s.get("tiers", []), c)
		out.append({
			"id": String(s.get("id", "")),
			"name": String(s.get("name", count_tag)),
			"count_tag": count_tag,
			"count": c,
			"tier_count": int(best.get("count", 0)),
			"next_tier_count": int(nxt.get("count", 0)),
			"mods": best.get("mods", {}) as Dictionary,
			"effects": best.get("effects", []) as Array,
			"next_mods": nxt.get("mods", {}) as Dictionary,
			"next_effects": nxt.get("effects", []) as Array
		})
	return out

static func synergy_states_for_cd(cd: CharacterData) -> Array[Dictionary]:
	# Synergies that this Character contributes toward (based on count_tag membership).
	ensure_loaded()
	var out: Array[Dictionary] = []
	if cd == null:
		return out
	var tags := _tags_for_cd(cd)
	for s in _synergies:
		var count_tag := String(s.get("count_tag", ""))
		if count_tag == "" or (not tags.has(count_tag)):
			continue
		var c: int = int(_tag_counts.get(count_tag, 0))
		var best: Dictionary = _best_tier(s.get("tiers", []), c)
		var nxt: Dictionary = _next_tier(s.get("tiers", []), c)
		out.append({
			"id": String(s.get("id", "")),
			"name": String(s.get("name", count_tag)),
			"count_tag": count_tag,
			"count": c,
			"tier_count": int(best.get("count", 0)),
			"next_tier_count": int(nxt.get("count", 0)),
			"mods": best.get("mods", {}) as Dictionary,
			"effects": best.get("effects", []) as Array,
			"next_mods": nxt.get("mods", {}) as Dictionary,
			"next_effects": nxt.get("effects", []) as Array
		})
	return out

static func synergy_tooltip_text(state: Dictionary) -> String:
	# Human-friendly tooltip describing current and next tier.
	var name := String(state.get("name", "Synergy"))
	var count := int(state.get("count", 0))
	var tier_n := int(state.get("tier_count", 0))
	var next_n := int(state.get("next_tier_count", 0))
	var tag := String(state.get("count_tag", ""))
	var lines: Array[String] = []
	lines.append("%s" % name)
	if tag != "":
		lines.append("Tag: %s" % tag)
	if tier_n > 0:
		lines.append("Roster: %d/%d (active)" % [count, tier_n])
	else:
		lines.append("Roster: %d/%d" % [count, max(1, next_n)])
	var mods := state.get("mods", {}) as Dictionary
	var effs: Array = state.get("effects", []) as Array
	var cur_lines := _describe_mods_and_effects(mods, effs)
	if not cur_lines.is_empty():
		lines.append("")
		lines.append("Current:")
		for l in cur_lines:
			lines.append("• " + l)

	if next_n > 0 and next_n != tier_n:
		var nmods := state.get("next_mods", {}) as Dictionary
		var neffs: Array = state.get("next_effects", []) as Array
		var nxt_lines := _describe_mods_and_effects(nmods, neffs)
		if not nxt_lines.is_empty():
			lines.append("")
			lines.append("Next (%d):" % next_n)
			for l2 in nxt_lines:
				lines.append("• " + l2)

	return "\n".join(lines)

static func synergy_tooltip_bbcode(state: Dictionary) -> String:
	# Formatted for RichTextLabel BBCode with stylized ASCII indicators.
	var name: String = String(state.get("name", "Synergy"))
	var count: int = int(state.get("count", 0))
	var tier_n: int = int(state.get("tier_count", 0))
	var next_n: int = int(state.get("next_tier_count", 0))
	var tag: String = String(state.get("count_tag", ""))

	var lines: Array[String] = []
	
	# Header with status indicator
	if tier_n > 0:
		lines.append("[b][color=#66ffaa][[ %s ]][/color][/b]" % name)
	elif next_n > 0:
		lines.append("[b][color=#ffaa66][ %s ][/color][/b]" % name)
	else:
		lines.append("[b][color=#98a6bf]( %s )[/color][/b]" % name)
	
	# Progress bar style count
	if tier_n > 0:
		lines.append("[color=#66ff88]|===| ACTIVE %d/%d[/color]" % [count, tier_n])
	elif next_n > 0:
		var filled := mini(count, next_n)
		var bar := "|"
		for i in range(next_n):
			if i < filled:
				bar += "="
			else:
				bar += "-"
		bar += "|"
		lines.append("[color=#888899]%s %d/%d[/color]" % [bar, count, next_n])
	else:
		lines.append("[color=#666677]%d units[/color]" % count)

	var mods: Dictionary = state.get("mods", {}) as Dictionary
	var effs: Array = state.get("effects", []) as Array
	var cur_lines: Array[String] = _describe_mods_and_effects(mods, effs)
	if not cur_lines.is_empty():
		lines.append("")
		if tier_n > 0:
			lines.append("[color=#66ffaa]-- Bonuses --[/color]")
		else:
			lines.append("[color=#666677]-- Locked --[/color]")
		for l in cur_lines:
			lines.append("  " + l)

	if next_n > 0 and next_n != tier_n:
		var nmods: Dictionary = state.get("next_mods", {}) as Dictionary
		var neffs: Array = state.get("next_effects", []) as Array
		var nxt_lines: Array[String] = _describe_mods_and_effects(nmods, neffs)
		if not nxt_lines.is_empty():
			lines.append("")
			lines.append("[color=#ffaa66]-- Next (%d) --[/color]" % next_n)
			for l2 in nxt_lines:
				lines.append("  " + l2)

	return "\n".join(lines)

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

static func get_active_synergies() -> Array:
	# Returns array of active synergy data for UI display
	var result: Array = []
	for a in _active:
		var tier_n := int(a.get("tier_count", 0))
		if tier_n > 0:
			result.append({
				"id": String(a.get("id", "")),
				"name": String(a.get("name", "")),
				"tier": _tier_number_from_count(a),
				"count": int(a.get("count", 0)),
				"required": tier_n,
				"mods": a.get("mods", {}),
				"effects": a.get("effects", [])
			})
	return result

static func _tier_number_from_count(state: Dictionary) -> int:
	# Calculate which tier number this is (1, 2, 3, etc)
	var count := int(state.get("count", 0))
	var id := String(state.get("id", ""))
	var syn := _get_synergy(id)
	var tiers_raw := syn.get("tiers", []) as Array
	var tier_num := 0
	for t in tiers_raw:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var td: Dictionary = t
		var n: int = int(td.get("count", 0))
		if count >= n:
			tier_num += 1
	return tier_num

static func synergy_name(syn_id: String) -> String:
	var syn := _get_synergy(syn_id)
	return String(syn.get("name", syn_id.capitalize()))

static func synergy_tooltip_text_by_id(syn_id: String, tier: int) -> String:
	# Get tooltip text for a specific synergy at a specific tier
	var syn := _get_synergy(syn_id)
	var tiers_raw := syn.get("tiers", []) as Array
	if tier < 1 or tier > tiers_raw.size():
		return ""
	var tier_data := tiers_raw[tier - 1] as Dictionary
	var mods := tier_data.get("mods", {}) as Dictionary
	var effs := tier_data.get("effects", []) as Array
	return "\n".join(_describe_mods_and_effects(mods, effs))

static func _next_tier(tiers_raw: Array, count: int) -> Dictionary:
	# Pick the lowest tier > count.
	var best: Dictionary = {}
	var best_n: int = 999999
	for t in tiers_raw:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var td: Dictionary = t
		var n: int = int(td.get("count", 0))
		if n > count and n < best_n:
			best = td
			best_n = n
	return best

static func _describe_mods_and_effects(mods: Dictionary, effects: Array) -> Array[String]:
	var out: Array[String] = []
	for k in mods.keys():
		var key := String(k)
		var v := float(mods.get(k, 1.0))
		var line := _mod_line(key, v)
		if line != "":
			out.append(line)
	for e in effects:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d := e as Dictionary
		var el := _effect_line(d)
		if el != "":
			out.append(el)
	return out

static func _mod_line(key: String, v: float) -> String:
	match key:
		"max_hp_mult":
			var pct := int(round((v - 1.0) * 100.0))
			if pct >= 0:
				return "[color=#66ff88]+%d%% Max HP[/color]" % pct
			return "[color=#ff6666]%d%% Max HP[/color]" % pct
		"attack_damage_mult":
			var pct := int(round((v - 1.0) * 100.0))
			if pct >= 0:
				return "[color=#ffaa66]+%d%% Damage[/color]" % pct
			return "[color=#ff6666]%d%% Damage[/color]" % pct
		"move_speed_mult":
			var pct := int(round((v - 1.0) * 100.0))
			if pct >= 0:
				return "[color=#66eeff]+%d%% Move Speed[/color]" % pct
			return "[color=#ff6666]%d%% Move Speed[/color]" % pct
		"attack_cooldown_mult":
			# Smaller = faster. Convert to attack speed increase.
			var inc := (1.0 / maxf(0.001, v)) - 1.0
			var pct := int(round(inc * 100.0))
			if pct >= 0:
				return "[color=#ffee66]+%d%% Attack Speed[/color]" % pct
			return "[color=#ff6666]%d%% Attack Speed[/color]" % pct
		_:
			return ""

static func _effect_line(e: Dictionary) -> String:
	var t := String(e.get("type", ""))
	match t:
		"volley_shot":
			return "[color=#88ddff]>> Volley[/color] — Every %d attacks fires a bonus shot for [color=#ffaa66]%d%%[/color] dmg" % [int(e.get("interval_attacks", 4)), int(round(float(e.get("damage_mult", 0.5)) * 100.0))]
		"pierce_bonus":
			return "[color=#88ddff]=> Pierce[/color] — Projectiles pass through [color=#ffaa66]+%d[/color] enemies" % int(e.get("extra_pierce", 1))
		"shockstep":
			return "[color=#bb88ff](( Shockwave[/color] — Every %d melee hits: [color=#ffaa66]%d%%[/color] AoE + slow" % [int(e.get("interval_hits", 3)), int(round(float(e.get("damage_mult", 0.22)) * 100.0))]
		"arc_focus":
			return "[color=#66eeff]~/ Chain[/color] — Every %d hits arcs to %d foes for [color=#ffaa66]%d%%[/color] dmg" % [int(e.get("interval_hits", 6)), int(e.get("chains", 2)), int(round(float(e.get("damage_mult", 0.30)) * 100.0))]
		"execute_protocol":
			return "[color=#ff6666]X/ Execute[/color] — Below [color=#ffaa66]%d%% HP[/color]: take [color=#ff6666]+%d%%[/color] dmg" % [int(round(float(e.get("threshold", 0.35)) * 100.0)), int(round(float(e.get("bonus_mult", 0.18)) * 100.0))]
		"ricochet_matrix":
			return "[color=#88ddff]<> Ricochet[/color] — [color=#ffaa66]%d%%[/color] chance to bounce for [color=#ffaa66]%d%%[/color] dmg" % [int(round(float(e.get("chance", 0.28)) * 100.0)), int(round(float(e.get("damage_mult", 0.55)) * 100.0))]
		"crit_arc":
			return "[color=#ffee66]!! Crit Arc[/color] — Crits: [color=#ffaa66]%d%%[/color] chance to arc [color=#ffaa66]%d%%[/color] dmg" % [int(round(float(e.get("chance", 0.35)) * 100.0)), int(round(float(e.get("damage_mult", 0.28)) * 100.0))]
		"hellfire_burn":
			return "[color=#ff8844]{{ Ignite[/color] — [color=#ffaa66]%d%%[/color] chance: [color=#ff6666]%d%%/s[/color] burn for %.1fs" % [int(round(float(e.get("chance", 0.32)) * 100.0)), int(round(float(e.get("dps_mult", 0.12)) * 100.0)), float(e.get("duration", 2.5))]
		"inferno_blast":
			return "[color=#ff4422]** Inferno[/color] — Every %d hits: [color=#ffaa66]%d%%[/color] AoE explosion" % [int(e.get("interval_hits", 7)), int(round(float(e.get("damage_mult", 0.22)) * 100.0))]
		"prismatic_surge":
			return "[color=#dd88ff]<> Prismatic[/color] — Every %d hits: random [color=#66eeff]arc[/color]/[color=#88ddff]chill[/color]/[color=#ff8844]burn[/color]" % int(e.get("interval_hits", 6))
		"pack_maul":
			return "[color=#88ff88]// Maul[/color] — Every %d melee hits: [color=#ffaa66]%d%%[/color] AoE + slow" % [int(e.get("interval_hits", 4)), int(round(float(e.get("damage_mult", 0.18)) * 100.0))]
		"bulwark_aura":
			return "[color=#66ff88](( Bulwark[/color] — Slow nearby enemies by [color=#88ddff]%d%%[/color]" % int(round((1.0 - float(e.get("slow_mult", 0.86))) * 100.0))
		"aura_heal":
			return "[color=#66ff88]++ Regen[/color] — Heal all allies [color=#66ff88]%d%% HP[/color] periodically" % int(round(float(e.get("heal_frac", 0.02)) * 100.0))
		"wisp_bolt":
			return "[color=#dd88ff]~* Wisp[/color] — Fire spirit bolt for [color=#ffaa66]%d%%[/color] dmg" % int(round(float(e.get("damage_mult", 0.35)) * 100.0))
		"sanctuary_heal":
			return "[color=#66ff88]++ Sanctuary[/color] — Heal lowest ally [color=#66ff88]%d%% HP[/color]" % int(round(float(e.get("heal_frac", 0.04)) * 100.0))
		"soul_feast":
			return "[color=#88ff88]<+ Soul Feast[/color] — On kill: heal weakest [color=#66ff88]%d%% HP[/color]" % int(round(float(e.get("heal_frac", 0.05)) * 100.0))
		"death_chill":
			return "[color=#88ddff]** Chill[/color] — On kill: slow nearby by [color=#88ddff]%d%%[/color]" % int(round((1.0 - float(e.get("slow_mult", 0.86))) * 100.0))
		"focus_fire":
			return "[color=#ffee66]:: Focus[/color] — After %d hits same target: [color=#ff6666]+%d%%[/color] dmg" % [int(e.get("stacks", 6)), int(round(float(e.get("bonus_mult", 0.35)) * 100.0))]
		"bounty":
			return "[color=#ffee66]$$ Bounty[/color] — [color=#ffaa66]%d%%[/color] on kill: [color=#ffee66]+%d[/color] Essence" % [int(round(float(e.get("chance", 0.14)) * 100.0)), int(e.get("essence", 1))]
		"tidal_surge":
			return "[color=#88ddff]~~ Tide[/color] — Every %d hits: [color=#ffaa66]%d%%[/color] AoE + slow" % [int(e.get("interval_hits", 5)), int(round(float(e.get("damage_mult", 0.25)) * 100.0))]
		"tide_mend":
			return "[color=#66ffcc]++ Brine[/color] — Periodic [color=#66ffcc]%d%% HP[/color] heal to all allies" % int(round(float(e.get("heal_frac", 0.03)) * 100.0))
		"glimmer_bolt":
			return "[color=#dd88ff]** Glimmer[/color] — [color=#ffaa66]%d%%[/color] chance to fire a slowing bolt" % int(round(float(e.get("chance", 0.35)) * 100.0))
		"aegis_blessing":
			return "[color=#66ffcc]++ Glamour[/color] — Periodic aegis to the weakest ally"
		"crystal_shard":
			return "[color=#88ddff]<> Shards[/color] — Every %d hits: %d bonus shards" % [int(e.get("interval_hits", 4)), int(e.get("extra_targets", 2))]
		"prism_guard":
			return "[color=#66ffcc]++ Prism Guard[/color] — Periodic aegis to nearby allies"
		"shadow_veil":
			return "[color=#bb88ff]// Veil[/color] — [color=#ffaa66]%d%%[/color] chance: bonus strike + slow" % int(round(float(e.get("chance", 0.35)) * 100.0))
		"shade_step":
			return "[color=#bb88ff]// Shade Step[/color] — Periodic self-aegis after striking"
		"featherstorm":
			return "[color=#88ddff]>> Storm[/color] — Every %d hits: %d feather bolts" % [int(e.get("interval_hits", 4)), int(e.get("extra_targets", 2))]
		"air_gust":
			return "[color=#88ddff]~~ Gust[/color] — Periodic wind slow around the unit"
		"web_ward":
			return "[color=#88ddff]## Web Ward[/color] — Every %d hits: web field slow" % int(e.get("interval_hits", 4))
		"venom_bite":
			return "[color=#88ff88]!! Venom[/color] — [color=#ffaa66]%d%%[/color] chance: poison DOT" % int(round(float(e.get("chance", 0.35)) * 100.0))
		"spore_cloud":
			return "[color=#88ff88]~~ Spores[/color] — Every %d hits: poison cloud" % int(e.get("interval_hits", 4))
		"verdant_mend":
			return "[color=#66ff88]++ Verdant[/color] — Periodic [color=#66ff88]%d%% HP[/color] heal to all allies" % int(round(float(e.get("heal_frac", 0.03)) * 100.0))
		"gel_slick":
			return "[color=#88ffcc]~~ Slick[/color] — Every %d hits: AoE slow + splash" % int(e.get("interval_hits", 4))
		"gel_split":
			return "[color=#88ffcc]<> Split[/color] — Every %d hits: %d gel bolts" % [int(e.get("interval_hits", 6)), int(e.get("extra_targets", 2))]
		"suppressive_fire":
			return "[color=#ffee66]:: Suppress[/color] — [color=#ffaa66]%d%%[/color] chance: slow target" % int(round(float(e.get("chance", 0.40)) * 100.0))
		"rally_ping":
			return "[color=#66ff88]++ Rally[/color] — Periodic heal to weakest ally"
		"pulse_arc":
			return "[color=#66eeff]~/ Pulse Arc[/color] — Every %d hits: arcs to %d foes" % [int(e.get("interval_hits", 5)), int(e.get("chains", 1))]
		"steel_skin":
			return "[color=#66ffcc]++ Steel Skin[/color] — Periodic self-aegis"
		"toxic_spike":
			return "[color=#88ff88]!! Spike[/color] — [color=#ffaa66]%d%%[/color] chance: toxic bleed" % int(round(float(e.get("chance", 0.35)) * 100.0))
		"mutate_surge":
			return "[color=#bb88ff]** Surge[/color] — Every %d hits: toxic shockwave" % int(e.get("interval_hits", 5))
		"gravity_well":
			return "[color=#88ddff]** Well[/color] — Every %d hits: crush clustered enemies" % int(e.get("interval_hits", 4))
		"void_bolt":
			return "[color=#bb88ff]>> Void Bolt[/color] — [color=#ffaa66]%d%%[/color] chance: extra bolt" % int(round(float(e.get("chance", 0.35)) * 100.0))
		"wyrm_breath":
			return "[color=#ff8844]{{ Breath[/color] — Every %d hits: burning cone" % int(e.get("interval_hits", 5))
		"dragon_scales":
			return "[color=#ff8844]++ Scales[/color] — Periodic self-aegis"
		"stellar_burst":
			return "[color=#ffee66]** Starlight[/color] — Every %d hits: AoE burst + heal" % int(e.get("interval_hits", 5))
		"guiding_star":
			return "[color=#ffee66]>> Star[/color] — [color=#ffaa66]%d%%[/color] chance: bolt heals allies" % int(round(float(e.get("chance", 0.40)) * 100.0))
		"blood_rite":
			return "[color=#ff6666]** Rite[/color] — Every %d hits: blood burst + self heal" % int(e.get("interval_hits", 4))
		"elemental_flux":
			return "[color=#dd88ff]<> Flux[/color] — [color=#ffaa66]%d%%[/color] chance: random element" % int(round(float(e.get("chance", 0.32)) * 100.0))
		"soul_leech":
			return "[color=#88ff88]<+ Leech[/color] — [color=#ffaa66]%d%%[/color] chance: heal on hit" % int(round(float(e.get("chance", 0.40)) * 100.0))
		"grave_nova":
			return "[color=#88ddff]** Grave Nova[/color] — Every %d hits: chill burst" % int(e.get("interval_hits", 5))
		_:
			return ""

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
			"tidal_surge":
				_effect_tidal_surge(unit, target, damage, e)
			"glimmer_bolt":
				_effect_glimmer_bolt(unit, target, damage, e)
			"crystal_shard":
				_effect_crystal_shard(unit, target, damage, e)
			"shadow_veil":
				_effect_shadow_veil(unit, target, damage, e)
			"shade_step":
				_effect_shade_step(unit, target, e)
			"featherstorm":
				_effect_featherstorm(unit, target, damage, e)
			"web_ward":
				_effect_web_ward(unit, target, damage, e)
			"venom_bite":
				_effect_venom_bite(unit, target, damage, e)
			"spore_cloud":
				_effect_spore_cloud(unit, target, damage, e)
			"gel_slick":
				_effect_gel_slick(unit, target, damage, e)
			"gel_split":
				_effect_gel_split(unit, target, damage, e)
			"suppressive_fire":
				_effect_suppressive_fire(unit, target, damage, e)
			"pulse_arc":
				_effect_pulse_arc(unit, target, damage, e)
			"toxic_spike":
				_effect_toxic_spike(unit, target, damage, e)
			"mutate_surge":
				_effect_mutate_surge(unit, target, damage, e)
			"gravity_well":
				_effect_gravity_well(unit, target, damage, e)
			"void_bolt":
				_effect_void_bolt(unit, target, damage, e)
			"wyrm_breath":
				_effect_wyrm_breath(unit, target, damage, e)
			"stellar_burst":
				_effect_stellar_burst(unit, target, damage, e)
			"guiding_star":
				_effect_guiding_star(unit, target, damage, e)
			"blood_rite":
				_effect_blood_rite(unit, target, damage, e)
			"elemental_flux":
				_effect_elemental_flux(unit, target, damage, e)
			"soul_leech":
				_effect_soul_leech(unit, target, damage, e)
			"grave_nova":
				_effect_grave_nova(unit, target, damage, e)
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
			"glimmer_bolt":
				_effect_glimmer_bolt(proj, enemy, damage, e)
			"shadow_veil":
				_effect_shadow_veil(proj, enemy, damage, e)
			"shade_step":
				_effect_shade_step(proj, enemy, e)
			"venom_bite":
				_effect_venom_bite(proj, enemy, damage, e)
			"spore_cloud":
				_effect_spore_cloud(proj, enemy, damage, e)
			"gel_slick":
				_effect_gel_slick(proj, enemy, damage, e)
			"suppressive_fire":
				_effect_suppressive_fire(proj, enemy, damage, e)
			"toxic_spike":
				_effect_toxic_spike(proj, enemy, damage, e)
			"gravity_well":
				_effect_gravity_well(proj, enemy, damage, e)
			"void_bolt":
				_effect_void_bolt(proj, enemy, damage, e)
			"wyrm_breath":
				_effect_wyrm_breath(proj, enemy, damage, e)
			"stellar_burst":
				_effect_stellar_burst(proj, enemy, damage, e)
			"guiding_star":
				_effect_guiding_star(proj, enemy, damage, e)
			"blood_rite":
				_effect_blood_rite(proj, enemy, damage, e)
			"elemental_flux":
				_effect_elemental_flux(proj, enemy, damage, e)
			"soul_leech":
				_effect_soul_leech(proj, enemy, damage, e)
			"grave_nova":
				_effect_grave_nova(proj, enemy, damage, e)
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
			"tide_mend":
				_effect_tide_mend(unit, e)
			"aegis_blessing":
				_effect_aegis_blessing(unit, e)
			"prism_guard":
				_effect_prism_guard(unit, e)
			"air_gust":
				_effect_air_gust(unit, e)
			"verdant_mend":
				_effect_verdant_mend(unit, e)
			"rally_ping":
				_effect_rally_ping(unit, e)
			"steel_skin":
				_effect_steel_skin(unit, e)
			"dragon_scales":
				_effect_dragon_scales(unit, e)
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

static func _spawn_extra_bolts(from: Node2D, origin: Vector2, radius: float, extra: int, dmg: int, tint: Color, exclude: Node2D) -> void:
	if extra <= 0:
		return
	var world := _main_world(from)
	if world == null:
		return
	var pick := _pick_near_enemy(from, origin, radius, exclude)
	var used: Array[Node2D] = []
	for _i in range(extra):
		if pick == null or used.has(pick):
			break
		used.append(pick)
		_spawn_projectile(world, origin, pick, dmg, tint)
		pick = _pick_near_enemy(from, (pick as Node2D).global_position, radius, pick)

static func _effect_tidal_surge(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	if target == null:
		return
	var interval := int(e.get("interval_hits", 5))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_tide_ctr", 0)) + 1
	from.set_meta("_syn_tide_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_tide_cd", float(e.get("cooldown", 0.12))):
		return
	var radius := float(e.get("radius", 170.0))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.25))))
	var slow_mult := float(e.get("slow_mult", 0.8))
	var dur := float(e.get("duration", 0.7))
	var origin := (target as Node2D).global_position
	var world := _main_world(from)
	if world != null:
		var nova := VfxFrostNova.new()
		nova.setup(origin, Color(0.45, 0.85, 1.0, 1.0), radius, 9, 0.22)
		_spawn_vfx(world, nova)
		_sfx(world, "syn.frost", origin, from)
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			if n2.has_method("take_damage"):
				n2.take_damage(dmg, false, "blast")
			if n2.has_method("apply_slow"):
				n2.apply_slow(slow_mult, dur)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.45, 0.85, 1.0, 1.0))

static func _effect_glimmer_bolt(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	if randf() > float(e.get("chance", 0.35)):
		return
	if not _cooldown_gate(from, "_syn_glimmer_cd", float(e.get("cooldown", 0.18))):
		return
	var radius := float(e.get("radius", 360.0))
	var pick := _pick_near_enemy(from, (target as Node2D).global_position, radius, target)
	if pick == null:
		return
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.35))))
	var world := _main_world(from)
	if world != null:
		_sfx(world, "syn.wisp", (target as Node2D).global_position, from)
	_spawn_projectile(world, (from as Node2D).global_position, pick, dmg, Color(0.85, 0.55, 1.0, 0.95))
	if pick.has_method("apply_slow"):
		pick.apply_slow(float(e.get("slow_mult", 0.85)), float(e.get("duration", 0.6)))

static func _effect_crystal_shard(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 4))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_crystal_ctr", 0)) + 1
	from.set_meta("_syn_crystal_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_crystal_cd", 0.10):
		return
	var extra := int(e.get("extra_targets", 2))
	var radius := float(e.get("radius", 240.0))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.32))))
	_spawn_extra_bolts(from, (target as Node2D).global_position, radius, extra, dmg, Color(0.75, 0.95, 1.0, 0.95), target)
	var world := _main_world(from)
	if world != null:
		_sfx(world, "syn.arc", (target as Node2D).global_position, from)

static func _effect_shadow_veil(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	if randf() > float(e.get("chance", 0.35)):
		return
	if not _cooldown_gate(from, "_syn_veil_cd", float(e.get("cooldown", 0.18))):
		return
	var bonus := int(round(float(damage) * float(e.get("bonus_mult", 0.35))))
	if bonus > 0 and target.has_method("take_damage"):
		target.take_damage(bonus, false, "phantom")
	if target.has_method("apply_slow"):
		target.apply_slow(float(e.get("slow_mult", 0.85)), float(e.get("duration", 0.6)))
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.65, 0.55, 0.95, 1.0))
	var world := _main_world(from)
	if world != null:
		_sfx(world, "syn.arc", (target as Node2D).global_position, from)

static func _effect_shade_step(from: Node2D, target: Node2D, e: Dictionary) -> void:
	if from == null or target == null:
		return
	if not _cooldown_gate(from, "_syn_shade_cd", float(e.get("cooldown", 1.8))):
		return
	if from.has_method("apply_aegis"):
		from.apply_aegis(float(e.get("duration", 0.7)), float(e.get("aegis_mult", 0.65)))
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.65, 0.55, 0.95, 1.0))

static func _effect_featherstorm(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 4))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_feather_ctr", 0)) + 1
	from.set_meta("_syn_feather_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_feather_cd", 0.10):
		return
	var extra := int(e.get("extra_targets", 2))
	var radius := float(e.get("radius", 420.0))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.28))))
	_spawn_extra_bolts(from, (from as Node2D).global_position, radius, extra, dmg, Color(0.90, 0.90, 1.0, 0.95), target)

static func _effect_web_ward(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 4))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_web_ctr", 0)) + 1
	from.set_meta("_syn_web_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_web_cd", float(e.get("cooldown", 0.12))):
		return
	var radius := float(e.get("radius", 160.0))
	var slow_mult := float(e.get("slow_mult", 0.75))
	var dur := float(e.get("duration", 0.8))
	var origin := (target as Node2D).global_position
	var world := _main_world(from)
	if world != null:
		var sw := VfxShockwave.new()
		sw.setup(origin, Color(0.70, 0.95, 0.85, 1.0), 14.0, radius, 4.0, 0.20)
		_spawn_vfx(world, sw)
		_sfx(world, "syn.frost", origin, from)
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			if n2.has_method("apply_slow"):
				n2.apply_slow(slow_mult, dur)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.70, 0.95, 0.85, 1.0))

static func _effect_venom_bite(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	if randf() > float(e.get("chance", 0.35)):
		return
	if not _cooldown_gate(from, "_syn_venom_cd", float(e.get("cooldown", 0.12))):
		return
	var dps := maxf(1.0, float(damage) * float(e.get("dps_mult", 0.18)))
	var dur := float(e.get("duration", 3.0))
	var tick := float(e.get("tick", 0.6))
	if target.has_method("apply_burn"):
		target.apply_burn(dps, dur, tick)
	elif target.has_method("apply_bleed"):
		target.apply_bleed(dps, dur, tick)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.55, 1.0, 0.65, 1.0))

static func _effect_spore_cloud(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 4))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_spore_ctr", 0)) + 1
	from.set_meta("_syn_spore_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_spore_cd", float(e.get("cooldown", 0.14))):
		return
	var radius := float(e.get("radius", 160.0))
	var dps := maxf(1.0, float(damage) * float(e.get("dps_mult", 0.18)))
	var dur := float(e.get("duration", 3.0))
	var tick := float(e.get("tick", 0.6))
	var origin := (target as Node2D).global_position
	var world := _main_world(from)
	if world != null:
		var fb := VfxFlameBurst.new()
		fb.setup(origin, Color(0.45, 1.0, 0.55, 1.0), radius * 0.30, 10, 0.20)
		_spawn_vfx(world, fb)
		_sfx(world, "syn.holy", origin, from)
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			if n2.has_method("apply_burn"):
				n2.apply_burn(dps, dur, tick)
			elif n2.has_method("apply_bleed"):
				n2.apply_bleed(dps, dur, tick)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.45, 1.0, 0.55, 1.0))

static func _effect_gel_slick(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 4))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_gel_ctr", 0)) + 1
	from.set_meta("_syn_gel_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_gel_cd", float(e.get("cooldown", 0.12))):
		return
	var radius := float(e.get("radius", 170.0))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.22))))
	var slow_mult := float(e.get("slow_mult", 0.75))
	var dur := float(e.get("duration", 0.7))
	var origin := (target as Node2D).global_position
	var world := _main_world(from)
	if world != null:
		var sw := VfxShockwave.new()
		sw.setup(origin, Color(0.70, 0.95, 0.85, 1.0), 14.0, radius, 4.0, 0.22)
		_spawn_vfx(world, sw)
		_sfx(world, "syn.frost", origin, from)
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			if n2.has_method("take_damage"):
				n2.take_damage(dmg, false, "blast")
			if n2.has_method("apply_slow"):
				n2.apply_slow(slow_mult, dur)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.70, 0.95, 0.85, 1.0))

static func _effect_gel_split(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 6))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_gel_split_ctr", 0)) + 1
	from.set_meta("_syn_gel_split_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_gel_split_cd", 0.12):
		return
	var extra := int(e.get("extra_targets", 2))
	var radius := float(e.get("radius", 240.0))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.30))))
	_spawn_extra_bolts(from, (target as Node2D).global_position, radius, extra, dmg, Color(0.70, 0.95, 0.85, 0.95), target)

static func _effect_suppressive_fire(from: Node2D, target: Node2D, _damage: int, e: Dictionary) -> void:
	if randf() > float(e.get("chance", 0.40)):
		return
	if not _cooldown_gate(from, "_syn_suppress_cd", float(e.get("cooldown", 0.10))):
		return
	if target.has_method("apply_slow"):
		target.apply_slow(float(e.get("slow_mult", 0.82)), float(e.get("duration", 0.6)))
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.85, 0.95, 1.0, 1.0))

static func _effect_pulse_arc(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 5))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_pulse_ctr", 0)) + 1
	from.set_meta("_syn_pulse_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_pulse_cd", 0.10):
		return
	var radius := float(e.get("radius", 220.0))
	var chains := int(e.get("chains", 1))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.35))))
	var origin := (target as Node2D).global_position
	var world := _main_world(from)
	var pick := _pick_near_enemy(from, origin, radius, target)
	var hit: Array[Node2D] = []
	for _i in range(chains):
		if pick == null or hit.has(pick):
			break
		hit.append(pick)
		if pick.has_method("take_damage"):
			pick.take_damage(dmg, false, "arc")
		if world != null:
			_spawn_arc(world, origin, pick.global_position, Color(0.55, 0.95, 1.0, 0.95))
			_sfx(world, "syn.arc", origin, from)
		origin = pick.global_position
		pick = _pick_near_enemy(from, origin, radius, pick)

static func _effect_toxic_spike(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	if randf() > float(e.get("chance", 0.35)):
		return
	if not _cooldown_gate(from, "_syn_toxic_cd", float(e.get("cooldown", 0.12))):
		return
	var dps := maxf(1.0, float(damage) * float(e.get("dps_mult", 0.16)))
	var dur := float(e.get("duration", 3.0))
	var tick := float(e.get("tick", 0.6))
	if target.has_method("apply_bleed"):
		target.apply_bleed(dps, dur, tick)
	elif target.has_method("apply_burn"):
		target.apply_burn(dps, dur, tick)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.55, 1.0, 0.65, 1.0))

static func _effect_mutate_surge(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 5))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_mutate_ctr", 0)) + 1
	from.set_meta("_syn_mutate_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_mutate_cd", 0.12):
		return
	var radius := float(e.get("radius", 150.0))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.28))))
	var slow_mult := float(e.get("slow_mult", 0.85))
	var dur := float(e.get("duration", 0.6))
	var origin := (target as Node2D).global_position
	var world := _main_world(from)
	if world != null:
		var sw := VfxShockwave.new()
		sw.setup(origin, Color(0.65, 1.0, 0.55, 1.0), 14.0, radius, 4.0, 0.20)
		_spawn_vfx(world, sw)
		_sfx(world, "syn.shock", origin, from)
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			if n2.has_method("take_damage"):
				n2.take_damage(dmg, false, "blast")
			if n2.has_method("apply_slow"):
				n2.apply_slow(slow_mult, dur)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.65, 1.0, 0.55, 1.0))

static func _effect_gravity_well(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 4))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_gravity_ctr", 0)) + 1
	from.set_meta("_syn_gravity_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_gravity_cd", float(e.get("cooldown", 0.14))):
		return
	var radius := float(e.get("radius", 160.0))
	var cluster := int(e.get("cluster", 3))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.28))))
	var slow_mult := float(e.get("slow_mult", 0.80))
	var dur := float(e.get("duration", 0.6))
	var origin := (target as Node2D).global_position
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	var victims: Array[Node2D] = []
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			victims.append(n2)
	if victims.size() < cluster:
		return
	var world := _main_world(from)
	if world != null:
		var sw := VfxShockwave.new()
		sw.setup(origin, Color(0.65, 0.75, 1.0, 1.0), 16.0, radius, 5.0, 0.22)
		_spawn_vfx(world, sw)
		_sfx(world, "syn.arc", origin, from)
	for v in victims:
		if v.has_method("take_damage"):
			v.take_damage(dmg, false, "blast")
		if v.has_method("apply_slow"):
			v.apply_slow(slow_mult, dur)
		if v.has_method("pulse_vfx"):
			v.pulse_vfx(Color(0.65, 0.75, 1.0, 1.0))

static func _effect_void_bolt(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	if randf() > float(e.get("chance", 0.35)):
		return
	if not _cooldown_gate(from, "_syn_void_cd", float(e.get("cooldown", 0.18))):
		return
	var radius := float(e.get("radius", 300.0))
	var pick := _pick_near_enemy(from, (target as Node2D).global_position, radius, target)
	if pick == null:
		return
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.35))))
	var world := _main_world(from)
	_spawn_projectile(world, (from as Node2D).global_position, pick, dmg, Color(0.55, 0.75, 1.0, 0.95))

static func _effect_wyrm_breath(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 5))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_wyrm_ctr", 0)) + 1
	from.set_meta("_syn_wyrm_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_wyrm_cd", float(e.get("cooldown", 0.16))):
		return
	var radius := float(e.get("radius", 150.0))
	var dps := maxf(1.0, float(damage) * float(e.get("dps_mult", 0.20)))
	var dur := float(e.get("duration", 3.0))
	var tick := float(e.get("tick", 0.5))
	var origin := (target as Node2D).global_position
	var world := _main_world(from)
	if world != null:
		var fb := VfxFlameBurst.new()
		fb.setup(origin, Color(1.0, 0.45, 0.25, 1.0), radius * 0.32, 12, 0.22)
		_spawn_vfx(world, fb)
		_sfx(world, "syn.flame", origin, from)
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			if n2.has_method("apply_burn"):
				n2.apply_burn(dps, dur, tick)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(1.0, 0.55, 0.25, 1.0))

static func _effect_stellar_burst(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 5))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_star_ctr", 0)) + 1
	from.set_meta("_syn_star_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_star_cd", float(e.get("cooldown", 0.14))):
		return
	var radius := float(e.get("radius", 160.0))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.28))))
	var heal_frac := float(e.get("heal_frac", 0.03))
	var origin := (target as Node2D).global_position
	var world := _main_world(from)
	if world != null:
		var sw := VfxShockwave.new()
		sw.setup(origin, Color(0.95, 0.85, 0.55, 1.0), 16.0, radius, 4.0, 0.20)
		_spawn_vfx(world, sw)
		_sfx(world, "syn.holy", origin, from)
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2 and n2.has_method("take_damage"):
			n2.take_damage(dmg, false, "blast")
	var squad: Array = _cached_squad(from)
	for u in squad:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2 and n2.has_method("heal") and n2.has_method("get_max_hp"):
			var mh := int(n2.get_max_hp())
			var amt := int(round(float(mh) * heal_frac))
			n2.heal(max(1, amt))

static func _effect_guiding_star(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	if randf() > float(e.get("chance", 0.40)):
		return
	if not _cooldown_gate(from, "_syn_guiding_cd", float(e.get("cooldown", 0.18))):
		return
	var radius := float(e.get("radius", 380.0))
	var pick := _pick_near_enemy(from, (target as Node2D).global_position, radius, target)
	if pick == null:
		return
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.35))))
	var heal_frac := float(e.get("heal_frac", 0.03))
	var world := _main_world(from)
	_spawn_projectile(world, (from as Node2D).global_position, pick, dmg, Color(1.0, 0.85, 0.55, 0.95))
	var squad: Array = _cached_squad(from)
	var best: Node2D = null
	var best_ratio := 2.0
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
	if world != null:
		_sfx(world, "syn.holy", (target as Node2D).global_position, from)

static func _effect_blood_rite(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 4))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_rite_ctr", 0)) + 1
	from.set_meta("_syn_rite_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_rite_cd", float(e.get("cooldown", 0.14))):
		return
	var radius := float(e.get("radius", 140.0))
	var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.30))))
	var heal_frac := float(e.get("heal_frac", 0.04))
	var origin := (target as Node2D).global_position
	var world := _main_world(from)
	if world != null:
		var sw := VfxShockwave.new()
		sw.setup(origin, Color(1.0, 0.45, 0.45, 1.0), 16.0, radius, 4.0, 0.20)
		_spawn_vfx(world, sw)
		_sfx(world, "syn.flame", origin, from)
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2 and n2.has_method("take_damage"):
			n2.take_damage(dmg, false, "blast")
	if from.has_method("heal") and from.has_method("get_max_hp"):
		var mh := int(from.get_max_hp())
		var amt := int(round(float(mh) * heal_frac))
		from.heal(max(1, amt))

static func _effect_elemental_flux(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	if randf() > float(e.get("chance", 0.32)):
		return
	if not _cooldown_gate(from, "_syn_flux_cd", float(e.get("cooldown", 0.12))):
		return
	var radius := float(e.get("radius", 220.0))
	var roll := randi() % 3
	match roll:
		0:
			var pick := _pick_near_enemy(from, (target as Node2D).global_position, radius, target)
			if pick != null:
				var dmg := int(round(float(damage) * float(e.get("damage_mult", 0.22))))
				if pick.has_method("take_damage"):
					pick.take_damage(dmg, false, "arc")
				var world := _main_world(from)
				if world != null:
					_spawn_arc(world, (target as Node2D).global_position, pick.global_position, Color(0.55, 0.95, 1.0, 0.95))
					_sfx(world, "syn.arc", (target as Node2D).global_position, from)
		1:
			if target.has_method("apply_slow"):
				target.apply_slow(float(e.get("slow_mult", 0.80)), float(e.get("slow_dur", 0.6)))
			if target.has_method("pulse_vfx"):
				target.pulse_vfx(Color(0.55, 0.85, 1.0, 1.0))
			var world2 := _main_world(from)
			if world2 != null:
				_sfx(world2, "syn.frost", (target as Node2D).global_position, from)
		_:
			var dps := maxf(1.0, float(damage) * float(e.get("burn_dps_mult", 0.14)))
			var dur := float(e.get("burn_dur", 2.4))
			if target.has_method("apply_burn"):
				target.apply_burn(dps, dur, 0.5)
			elif target.has_method("apply_bleed"):
				target.apply_bleed(dps, dur, 0.5)
			if target.has_method("pulse_vfx"):
				target.pulse_vfx(Color(1.0, 0.75, 0.25, 1.0))
			var world3 := _main_world(from)
			if world3 != null:
				_sfx(world3, "syn.flame", (target as Node2D).global_position, from)

static func _effect_soul_leech(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	if randf() > float(e.get("chance", 0.40)):
		return
	if not _cooldown_gate(from, "_syn_leech_cd", float(e.get("cooldown", 0.10))):
		return
	if not from.has_method("heal"):
		return
	var heal := int(round(float(damage) * float(e.get("heal_mult", 0.22))))
	if heal <= 0:
		return
	from.heal(heal)
	if target.has_method("pulse_vfx"):
		target.pulse_vfx(Color(0.55, 1.0, 0.65, 1.0))

static func _effect_grave_nova(from: Node2D, target: Node2D, damage: int, e: Dictionary) -> void:
	var interval := int(e.get("interval_hits", 5))
	if interval <= 0:
		return
	var c: int = int(from.get_meta("_syn_grave_ctr", 0)) + 1
	from.set_meta("_syn_grave_ctr", c)
	if c % interval != 0:
		return
	if not _cooldown_gate(from, "_syn_grave_cd", float(e.get("cooldown", 0.16))):
		return
	var radius := float(e.get("radius", 170.0))
	var slow_mult := float(e.get("slow_mult", 0.75))
	var dur := float(e.get("duration", 0.8))
	var origin := (target as Node2D).global_position
	var world := _main_world(from)
	if world != null:
		var nova := VfxFrostNova.new()
		nova.setup(origin, Color(0.55, 0.85, 1.0, 1.0), radius, 9, 0.22)
		_spawn_vfx(world, nova)
		_sfx(world, "syn.frost", origin, from)
	var enemies: Array = _cached_enemies(from)
	var r2 := radius * radius
	for en in enemies:
		if not is_instance_valid(en):
			continue
		var n2 := en as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to(origin) <= r2:
			if n2.has_method("apply_slow"):
				n2.apply_slow(slow_mult, dur)
			if n2.has_method("pulse_vfx"):
				n2.pulse_vfx(Color(0.55, 0.85, 1.0, 1.0))

static func _effect_tide_mend(unit: Node2D, e: Dictionary) -> void:
	_effect_aura_heal(unit, e)

static func _effect_aegis_blessing(unit: Node2D, e: Dictionary) -> void:
	var cd_s := float(e.get("cooldown", 2.2))
	if not _cooldown_gate(unit, "_syn_aegis_bless_cd", cd_s):
		return
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
	if best != null and best.has_method("apply_aegis"):
		best.apply_aegis(float(e.get("duration", 0.9)), float(e.get("aegis_mult", 0.70)))

static func _effect_prism_guard(unit: Node2D, e: Dictionary) -> void:
	var cd_s := float(e.get("cooldown", 2.0))
	if not _cooldown_gate(unit, "_syn_prism_guard_cd", cd_s):
		return
	var radius := float(e.get("radius", 140.0))
	var squad: Array = _cached_squad(unit)
	var r2 := radius * radius
	for u in squad:
		if not is_instance_valid(u):
			continue
		var n2 := u as Node2D
		if n2 == null:
			continue
		if n2.global_position.distance_squared_to((unit as Node2D).global_position) <= r2 and n2.has_method("apply_aegis"):
			n2.apply_aegis(float(e.get("duration", 0.9)), float(e.get("aegis_mult", 0.70)))

static func _effect_air_gust(unit: Node2D, e: Dictionary) -> void:
	var cd_s := float(e.get("cooldown", 1.8))
	if not _cooldown_gate(unit, "_syn_air_gust_cd", cd_s):
		return
	var radius := float(e.get("radius", 150.0))
	var slow_mult := float(e.get("slow_mult", 0.80))
	var dur := float(e.get("duration", 0.7))
	var world := _main_world(unit)
	if world != null:
		var nova := VfxFrostNova.new()
		nova.setup((unit as Node2D).global_position, Color(0.70, 0.90, 1.0, 1.0), radius, 8, 0.20)
		_spawn_vfx(world, nova)
		_sfx(world, "syn.frost", (unit as Node2D).global_position, unit)
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
				n2.apply_slow(slow_mult, dur)

static func _effect_verdant_mend(unit: Node2D, e: Dictionary) -> void:
	_effect_aura_heal(unit, e)

static func _effect_rally_ping(unit: Node2D, e: Dictionary) -> void:
	_effect_sanctuary_heal(unit, e)

static func _effect_steel_skin(unit: Node2D, e: Dictionary) -> void:
	var cd_s := float(e.get("cooldown", 1.9))
	if not _cooldown_gate(unit, "_syn_steel_skin_cd", cd_s):
		return
	if unit.has_method("apply_aegis"):
		unit.apply_aegis(float(e.get("duration", 0.7)), float(e.get("aegis_mult", 0.70)))

static func _effect_dragon_scales(unit: Node2D, e: Dictionary) -> void:
	_effect_steel_skin(unit, e)

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
	var v := world.get_node_or_null("/root/VfxSystem")
	if v != null and is_instance_valid(v) and v.has_method("play_event"):
		# VfxSystem uses the same event ids (syn.arc/syn.flame/etc) mapped in vfx_events.json
		v.play_event(event_id, pos, world)

static func _spawn_projectile(world: Node2D, from_pos: Vector2, to: Node2D, dmg: int, tint: Color) -> void:
	if world == null or to == null or not is_instance_valid(to):
		return
	# Use custom small bolt instead of standard projectile for synergy effects
	var bolt := _SynergyBolt.new()
	bolt.setup(from_pos, to, dmg, tint, world)
	world.add_child(bolt)

class _SynergyBolt extends Node2D:
	var _target: Node2D
	var _target_pos: Vector2
	var _damage: int
	var _speed: float = 800.0
	var _world: Node2D
	var _sprite: Sprite2D
	var _trail: Line2D
	var _trail_points: PackedVector2Array = []
	var _lifetime: float = 2.0
	
	func setup(start: Vector2, target: Node2D, dmg: int, tint: Color, world: Node2D) -> void:
		global_position = start
		_target = target
		_target_pos = target.global_position if target else start
		_damage = dmg
		_world = world
		z_index = 2000
		
		# Small glowing bolt
		_sprite = Sprite2D.new()
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		var center := Vector2(5, 5)
		for x in range(10):
			for y in range(10):
				var dist := Vector2(x, y).distance_to(center) / 5.0
				var alpha := maxf(0.0, 1.0 - dist)
				img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, alpha))
		_sprite.texture = ImageTexture.create_from_image(img)
		_sprite.scale = Vector2(1.5, 1.5)
		_sprite.modulate = Color(1.2, 1.2, 1.2, 1.0)  # Slightly overbright
		add_child(_sprite)
		
		# Short trail
		_trail = Line2D.new()
		_trail.width = 2.0
		_trail.default_color = Color(tint.r, tint.g, tint.b, 0.5)
		_trail.z_index = -1
		add_child(_trail)
	
	func _process(delta: float) -> void:
		# Auto-cleanup via lifetime
		_lifetime -= delta
		if _lifetime <= 0.0:
			queue_free()
			return
		
		if _target and is_instance_valid(_target):
			_target_pos = _target.global_position
		
		var dir := (_target_pos - global_position)
		var dist := dir.length()
		
		if dist < 12.0:
			_hit()
			return
		
		dir = dir.normalized()
		global_position += dir * _speed * delta
		rotation = dir.angle()
		
		# Simple trail behind bolt
		if _trail:
			_trail.clear_points()
			for i in range(6):
				_trail.add_point(Vector2(-i * 6, 0))
	
	func _hit() -> void:
		if _target and is_instance_valid(_target) and _target.has_method("take_damage"):
			_target.take_damage(_damage, false, "synergy")
		
		# Small impact flash
		var flash := Sprite2D.new()
		flash.global_position = global_position
		flash.z_index = 2100
		var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0.8))
		flash.texture = ImageTexture.create_from_image(img)
		flash.scale = Vector2(1.5, 1.5)
		if _world:
			_world.add_child(flash)
			var tw := flash.create_tween()
			tw.tween_property(flash, "modulate:a", 0.0, 0.1)
			tw.tween_callback(flash.queue_free)
		
		queue_free()

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
		# Wisp bolt is an arcane/magic proc — do NOT use syn.flame (burn) here, or the burn VFX will
		# incorrectly play on the squad unit.
		_sfx(world, "syn.wisp", (unit as Node2D).global_position, unit)
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
	# Race tag (if present)
	if cd.race_id != "":
		out.append("race:%s" % cd.race_id.to_lower())
	return out
