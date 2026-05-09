class_name CharacterRegistryUtil
extends Node

# Runtime helpers for curated character assets (Ludo).
#
# Registry: res://data/character_registry.json
# Assets:   res://assets/characters/<folder>/frames/walk_front/frame_000.png

static var _loaded: bool = false
static var _entries: Array[Dictionary] = []
static var _entry_by_id: Dictionary = {}
static var _passive_catalog_loaded: bool = false
static var _known_passive_ids: Dictionary = {}

const _ORIGIN_PASSIVE: Dictionary = {
	"UNDEAD": "blood_siphon",
	"MACHINE": "overload",
	"BEAST": "bleed_edge",
	"DEMON": "cinder_brand",
	"ELEMENTAL": "arc_chain",
	"HUMAN": "pinpoint"
}

# Identity pass: give each race/class a deterministic signature package so
# characters feel collectible for "who they are", not just weapon rolls.
const _RACE_SIGNATURE_PASSIVES: Dictionary = {
	"HUMANOID": ["pinpoint", "stagger", "execute_mark"],
	"MACHINE": ["overload", "ricochet", "time_dilation"],
	"ALIEN": ["phase_step", "predator_instinct", "toxic"],
	"DEMON": ["cinder_brand", "doomstack", "chain_reaction"],
	"DRACONIC": ["cinder_brand", "shockwave", "predator_instinct"],
	"ELEMENTAL": ["arc_chain", "frost_tag", "cinder_brand"],
	"CELESTIAL": ["arc_chain", "time_dilation", "pinpoint"],
	"UNDEAD": ["blood_siphon", "bleed_edge", "hailburst"],
	"AQUATIC": ["frost_tag", "time_dilation", "vortex_tag"],
	"FAE": ["phase_step", "hex_bomb", "arc_chain"],
	"CRYSTALLINE": ["frost_tag", "hailburst", "pinpoint"],
	"SHADOWBORN": ["phase_step", "doomstack", "predator_instinct"],
	"AVIAN": ["predator_instinct", "arc_chain", "pinpoint"],
	"ARACHNID": ["web_snare", "toxic", "bleed_edge"],
	"PLANTOID": ["spore_bloom", "toxic", "vortex_tag"],
	"SLIMEKIN": ["gel_mitosis", "toxic", "time_dilation"],
	"MUTANT": ["toxic", "bleed_edge", "doomstack"]
}

const _CLASS_SIGNATURE_PASSIVES: Dictionary = {
	"WARRIOR": ["shockwave", "bleed_edge", "execute_mark"],
	"MAGE": ["arc_chain", "time_dilation", "vortex_tag"],
	"ROGUE": ["phase_step", "predator_instinct", "ricochet"],
	"GUARDIAN": ["stagger", "overload", "blood_siphon"],
	"HEALER": ["pinpoint", "frost_tag", "hailburst"],
	"SUMMONER": ["doomstack", "hex_bomb", "phantom_strike"]
}

# Hand-tuned role signatures inferred from character naming.
# This keeps the system scalable: new characters get coherent identities by naming convention.
const _ROLE_SIGNATURE_PASSIVES: Dictionary = {
	"juggernaut": ["berserker", "shockwave", "blood_siphon"],
	"colossus": ["stagger", "shockwave", "berserker"],
	"titan": ["shockwave", "stagger", "execute_mark"],
	"guardian": ["stagger", "vampiric_bullets", "frost_tag"],
	"guard": ["stagger", "execute_mark", "frost_tag"],
	"warden": ["stagger", "blood_siphon", "time_dilation"],
	"vanguard": ["stagger", "execute_mark", "shockwave"],
	"sentinel": ["pinpoint", "stagger", "arc_chain"],
	"reaver": ["bleed_edge", "predator_instinct", "doomstack"],
	"duelist": ["phase_step", "predator_instinct", "pinpoint"],
	"assassin": ["phase_step", "execute_mark", "predator_instinct"],
	"stalker": ["predator_instinct", "toxic", "phase_step"],
	"sniper": ["pinpoint", "ricochet_master", "chain_master"],
	"ranger": ["pinpoint", "scatter_specialist", "ricochet"],
	"scout": ["predator_instinct", "phase_step", "ricochet"],
	"oracle": ["arc_chain", "time_dilation", "vortex_tag"],
	"mystic": ["arc_chain", "frost_tag", "doomstack"],
	"seer": ["time_dilation", "hex_bomb", "pinpoint"],
	"caller": ["vortex_tag", "arc_chain", "doomstack"],
	"shaman": ["toxic", "spore_bloom", "arc_chain"],
	"medic": ["vampiric_bullets", "frost_tag", "pinpoint"],
	"deacon": ["frost_tag", "pinpoint", "time_dilation"],
	"alchemist": ["toxic", "poison_mastery", "explosive_rounds"],
	"necromancer": ["doomstack", "blood_siphon", "phantom_strike"],
	"warlock": ["doomstack", "hex_bomb", "arc_chain"],
	"summoner": ["phantom_strike", "doomstack", "vortex_tag"],
	"binder": ["hex_bomb", "time_dilation", "vortex_tag"],
	"slinger": ["scattershot", "ricochet", "poison_mastery"],
	"savant": ["gel_mitosis", "time_dilation", "arc_chain"],
	"marauder": ["bleed_edge", "predator_instinct", "chain_reaction"],
	"default": ["pinpoint", "execute_mark", "arc_chain"]
}

const _CHASE_PASSIVE_POOL: Array[String] = [
	"doomstack",
	"phantom_strike",
	"explosive_rounds",
	"ricochet_master",
	"spirit_surge",
	"chain_master",
	"scatter_specialist",
	"boomerang_mastery",
	"beam_focus",
	"bomb_expert",
	"orbital_precision",
	"fire_mastery",
	"frost_mastery",
	"poison_mastery",
	"reaper_hunger",
	"vampiric_mastery"
]

const _PASSIVE_CAP_BY_RARITY: Dictionary = {
	"common": 4,
	"rare": 5,
	"epic": 5,
	"legendary": 6,
	"mythic": 6
}

const _BUILD_VECTORS: Dictionary = {
	"burst": ["execute_mark", "glass_cannon", "reaper_hunger", "orbital_precision"],
	"sustain": ["blood_siphon", "vampiric_bullets", "vampiric_mastery", "time_dilation"],
	"control": ["frost_tag", "stagger", "time_dilation", "hex_bomb"],
	"mobility": ["phase_step", "predator_instinct", "ricochet", "boomerang_mastery"],
	"aoe": ["arc_chain", "chain_reaction", "scattershot", "explosive_rounds"],
	"dot": ["toxic", "bleed_edge", "poison_mastery", "fire_mastery"]
}

const _CLASS_BUILD_VECTORS: Dictionary = {
	"WARRIOR": ["burst", "sustain", "dot"],
	"MAGE": ["aoe", "control", "burst"],
	"ROGUE": ["mobility", "burst", "dot"],
	"GUARDIAN": ["sustain", "control", "aoe"],
	"HEALER": ["sustain", "control", "aoe"],
	"SUMMONER": ["aoe", "dot", "control"]
}

# Explicitly hand-tuned chase anchors for the current featured roster.
const _FEATURED_SIGNATURE_BY_ID: Dictionary = {
	"titan_juggernaut": ["berserker", "slam_aftershock"],
	"blight_necromancer": ["doomstack", "reaper_hunger"],
	"hellfire": ["fire_mastery", "chain_reaction"],
	"storm_oracle": ["arc_chain", "orbital_precision"],
	"astral_seraph": ["spirit_surge", "beam_focus"],
	"prism_guard": ["frost_mastery", "ricochet_master"],
	"dusk_reaper": ["phantom_strike", "execute_mark"],
	"vine_warden": ["spore_bloom", "vampiric_mastery"],
	"ooze_brute": ["gel_mitosis", "poison_mastery"],
	"web_marauder": ["web_snare", "predator_instinct"],
	"void_corsair": ["boomerang_mastery", "phase_step"],
	"tide_marauder": ["vortex_tag", "chain_master"]
}

const _RACE_STAT_BIAS: Dictionary = {
	# Soft stat signatures (multipliers): hp, dmg, move, range, cooldown
	"HUMANOID": {"hp": 1.05, "dmg": 1.06, "move": 1.00, "range": 1.00, "cd": 0.98},
	"MACHINE": {"hp": 1.12, "dmg": 1.04, "move": 0.93, "range": 1.00, "cd": 1.02},
	"ALIEN": {"hp": 0.94, "dmg": 1.08, "move": 1.15, "range": 1.03, "cd": 0.95},
	"DEMON": {"hp": 1.00, "dmg": 1.12, "move": 1.02, "range": 1.00, "cd": 0.96},
	"DRACONIC": {"hp": 1.10, "dmg": 1.10, "move": 0.95, "range": 0.98, "cd": 1.00},
	"ELEMENTAL": {"hp": 0.96, "dmg": 1.08, "move": 1.06, "range": 1.04, "cd": 0.96},
	"CELESTIAL": {"hp": 1.02, "dmg": 1.05, "move": 1.03, "range": 1.08, "cd": 0.94},
	"UNDEAD": {"hp": 1.10, "dmg": 0.98, "move": 0.90, "range": 1.00, "cd": 1.04},
	"AQUATIC": {"hp": 0.98, "dmg": 1.02, "move": 1.10, "range": 1.05, "cd": 0.97},
	"FAE": {"hp": 0.90, "dmg": 1.04, "move": 1.16, "range": 1.06, "cd": 0.94},
	"CRYSTALLINE": {"hp": 1.08, "dmg": 1.06, "move": 0.92, "range": 1.07, "cd": 1.00},
	"SHADOWBORN": {"hp": 0.95, "dmg": 1.10, "move": 1.12, "range": 1.00, "cd": 0.95},
	"AVIAN": {"hp": 0.92, "dmg": 1.02, "move": 1.18, "range": 1.05, "cd": 0.96},
	"ARACHNID": {"hp": 1.04, "dmg": 1.07, "move": 1.06, "range": 0.97, "cd": 0.98},
	"PLANTOID": {"hp": 1.12, "dmg": 0.98, "move": 0.88, "range": 1.06, "cd": 1.02},
	"SLIMEKIN": {"hp": 1.06, "dmg": 1.00, "move": 1.04, "range": 1.00, "cd": 1.00},
	"MUTANT": {"hp": 1.03, "dmg": 1.08, "move": 1.06, "range": 0.98, "cd": 0.99}
}

const _ROLE_STAT_BIAS: Dictionary = {
	"sniper": {"hp": 0.92, "dmg": 1.10, "move": 1.03, "range": 1.18, "cd": 0.96},
	"medic": {"hp": 1.05, "dmg": 0.94, "move": 1.05, "range": 1.05, "cd": 0.95},
	"guardian": {"hp": 1.15, "dmg": 0.97, "move": 0.90, "range": 0.95, "cd": 1.04},
	"warden": {"hp": 1.12, "dmg": 0.98, "move": 0.92, "range": 0.98, "cd": 1.02},
	"vanguard": {"hp": 1.12, "dmg": 1.00, "move": 0.93, "range": 0.97, "cd": 1.00},
	"juggernaut": {"hp": 1.18, "dmg": 1.06, "move": 0.86, "range": 0.92, "cd": 1.05},
	"colossus": {"hp": 1.20, "dmg": 1.05, "move": 0.84, "range": 0.92, "cd": 1.06},
	"assassin": {"hp": 0.90, "dmg": 1.10, "move": 1.14, "range": 1.00, "cd": 0.94},
	"duelist": {"hp": 0.95, "dmg": 1.10, "move": 1.10, "range": 1.00, "cd": 0.94},
	"stalker": {"hp": 0.96, "dmg": 1.08, "move": 1.12, "range": 1.02, "cd": 0.94},
	"oracle": {"hp": 0.94, "dmg": 1.06, "move": 1.02, "range": 1.12, "cd": 0.93},
	"seer": {"hp": 0.95, "dmg": 1.04, "move": 1.02, "range": 1.10, "cd": 0.94},
	"summoner": {"hp": 0.98, "dmg": 1.03, "move": 1.00, "range": 1.08, "cd": 0.95},
	"default": {"hp": 1.0, "dmg": 1.0, "move": 1.0, "range": 1.0, "cd": 1.0}
}

const _CLASS_STAT_BIAS: Dictionary = {
	"WARRIOR": {"hp": 1.10, "dmg": 1.06, "move": 0.96, "range": 0.94, "cd": 1.00},
	"MAGE": {"hp": 0.92, "dmg": 1.10, "move": 1.02, "range": 1.12, "cd": 0.95},
	"ROGUE": {"hp": 0.92, "dmg": 1.08, "move": 1.12, "range": 1.00, "cd": 0.94},
	"GUARDIAN": {"hp": 1.18, "dmg": 0.95, "move": 0.88, "range": 0.94, "cd": 1.05},
	"HEALER": {"hp": 0.98, "dmg": 0.90, "move": 1.04, "range": 1.08, "cd": 0.92},
	"SUMMONER": {"hp": 0.96, "dmg": 1.03, "move": 1.00, "range": 1.06, "cd": 0.95}
}

const _ORIGIN_ASPECTS_BY_RACE: Dictionary = {
	"HUMANOID": ["banner", "forge", "arcane"],
	"MACHINE": ["forge", "arcane", "storm"],
	"AQUATIC": ["abyss", "frost", "storm"],
	"FAE": ["verdant", "astral", "arcane"],
	"ELEMENTAL": ["storm", "ember", "frost"],
	"CRYSTALLINE": ["frost", "arcane", "astral"],
	"SHADOWBORN": ["umbra", "grave", "abyss"],
	"AVIAN": ["storm", "astral", "primal"],
	"ARACHNID": ["primal", "umbra", "verdant"],
	"PLANTOID": ["verdant", "frost", "astral"],
	"SLIMEKIN": ["abyss", "verdant", "primal"],
	"MUTANT": ["verdant", "primal", "grave"],
	"ALIEN": ["abyss", "arcane", "storm"],
	"DRACONIC": ["ember", "storm", "primal"],
	"CELESTIAL": ["astral", "arcane", "banner"],
	"UNDEAD": ["grave", "umbra", "abyss"]
}
const _ORIGIN_ASPECTS_DEFAULT: Array = ["banner", "forge", "arcane", "primal"]

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var reg_path := "res://data/character_registry.json"
	if not ResourceLoader.exists(reg_path):
		push_warning("CharacterRegistryUtil: missing registry at %s" % reg_path)
		return
	var json_text := FileAccess.get_file_as_string(reg_path)
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("CharacterRegistryUtil: registry JSON invalid")
		return
	var root: Dictionary = parsed
	var chars: Dictionary = root.get("characters", {})
	_entries.clear()
	_entry_by_id.clear()
	for k in chars.keys():
		var d: Dictionary = chars.get(k, {}) as Dictionary
		if d.is_empty():
			continue
		var entry: Dictionary = d.duplicate(true)
		entry["id"] = String(k)
		_entries.append(entry)
		_entry_by_id[String(k)] = entry
	_ensure_passive_catalog_loaded()

static func entry_count() -> int:
	ensure_loaded()
	return _entries.size()

static func build_random_character_data(context: String, rng: RandomNumberGenerator, elapsed_minutes: float, map_mod: Dictionary = {}) -> CharacterData:
	ensure_loaded()
	if _entries.is_empty():
		return null
	var pool := _entries_for_map(context, map_mod)
	if pool.is_empty():
		pool = _entries_with_assets(_entries)
	if pool.is_empty():
		return null
	var idx := rng.randi_range(0, pool.size() - 1)
	var entry: Dictionary = pool[idx]
	return _build_character_data_from_entry(entry, context, rng, elapsed_minutes, map_mod)

static func _entries_for_map(context: String, map_mod: Dictionary) -> Array[Dictionary]:
	if map_mod.is_empty():
		return _entries_with_assets(_entries)
	var pool: Array = []
	if context == "enemy" and map_mod.has("race_pool_enemy"):
		pool = map_mod.get("race_pool_enemy", []) as Array
	elif context == "recruit" and map_mod.has("race_pool_recruit"):
		pool = map_mod.get("race_pool_recruit", []) as Array
	elif map_mod.has("race_pool"):
		pool = map_mod.get("race_pool", []) as Array
	var blacklist: Array = map_mod.get("race_blacklist", []) as Array
	if pool.is_empty() and blacklist.is_empty():
		return _entries_with_assets(_entries)
	var out: Array[Dictionary] = []
	for entry in _entries:
		var race := String(entry.get("race", ""))
		if not pool.is_empty() and not pool.has(race):
			continue
		if not blacklist.is_empty() and blacklist.has(race):
			continue
		out.append(entry)
	return _entries_with_assets(out)

static func _entries_with_assets(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		var folder := String(entry.get("folder", ""))
		if folder == "":
			continue
		var south_path := "res://assets/characters/%s/frames/walk_front/frame_000.png" % folder
		if not ResourceLoader.exists(south_path):
			continue
		out.append(entry)
	return out

static func build_character_data_by_id(char_id: String, context: String, rng: RandomNumberGenerator, elapsed_minutes: float, map_mod: Dictionary = {}) -> CharacterData:
	ensure_loaded()
	if not _entry_by_id.has(char_id):
		return null
	var entry: Dictionary = _entry_by_id[char_id]
	return _build_character_data_from_entry(entry, context, rng, elapsed_minutes, map_mod)

static func _build_character_data_from_entry(entry: Dictionary, context: String, rng: RandomNumberGenerator, elapsed_minutes: float, map_mod: Dictionary) -> CharacterData:
	var folder := String(entry.get("folder", ""))
	if folder == "":
		return null
	var root := "res://assets/characters/%s" % folder
	var south_path := "%s/frames/walk_front/frame_000.png" % root
	if not ResourceLoader.exists(south_path):
		return null

	var base_stats: Dictionary = entry.get("base_stats", {}) as Dictionary
	var overrides: Dictionary = {}

	var rarity_id := String(entry.get("rarity_id", ""))
	if rarity_id != "":
		overrides["rarity_id"] = rarity_id
	var archetype_id := String(entry.get("archetype_id", ""))
	if archetype_id != "":
		overrides["archetype_id"] = archetype_id
	var weapon_id := String(entry.get("weapon_id", ""))
	if weapon_id != "":
		overrides["weapon_id"] = weapon_id

	var origin_str := String(entry.get("origin", ""))
	if origin_str != "":
		overrides["origin"] = _origin_from_string(origin_str)
	var class_str := String(entry.get("class_type", ""))
	if class_str != "":
		overrides["class_type"] = _class_from_string(class_str)

	var cd := UnitFactory.build_character_data(context, rng, elapsed_minutes, south_path, map_mod, base_stats, overrides)
	if cd == null:
		return null
	cd.race_id = String(entry.get("race", ""))
	cd.origin_id = _origin_aspect_for_entry(entry, cd.race_id)

	var passives := Array(cd.passive_ids)
	# Entry-specific guaranteed passives
	var required: Array = entry.get("passive_ids", []) as Array
	for pid in required:
		var s := String(pid)
		_append_passive_if_valid(passives, s)
	# Origin-based racial passive (if not already present)
	var o_name := _origin_to_name(int(cd.origin))
	var racial_id := String(entry.get("racial_passive_id", ""))
	if racial_id == "":
		racial_id = String(_ORIGIN_PASSIVE.get(o_name, ""))
	_append_passive_if_valid(passives, racial_id)
	var race_id := String(entry.get("race", ""))
	if context != "enemy":
		_apply_signature_passives(entry, passives, race_id)
		_apply_variant_passives(entry, passives, race_id, cd.rarity_id, rng)
		_apply_build_vector_passives(entry, passives, cd.rarity_id, rng)
	# Optional explicit identity overrides in registry entry:
	# "identity": {"signature_passives": [...], "chase_passive": "...", "passive_cap": 5}
	var identity := entry.get("identity", {}) as Dictionary
	var id_sigs: Array = identity.get("signature_passives", []) as Array
	for pid2 in id_sigs:
		var p2 := String(pid2)
		_append_passive_if_valid(passives, p2)
	var chase_override := String(identity.get("chase_passive", ""))
	_append_passive_if_valid(passives, chase_override)
	var cap_default := int(_PASSIVE_CAP_BY_RARITY.get(String(cd.rarity_id).to_lower(), 5))
	var passive_cap := int(identity.get("passive_cap", cap_default))
	passive_cap = clampi(passive_cap, 3, 6)
	if passives.size() > passive_cap:
		passives = passives.slice(0, passive_cap)
	cd.passive_ids = PackedStringArray(passives)
	_apply_race_stat_bias(cd, race_id)
	if context != "enemy":
		_apply_class_stat_bias(cd, String(entry.get("class_type", "")))
		_apply_role_stat_bias(cd, _role_key_for_entry(entry))
	if context != "enemy":
		_apply_signature_micro_bias(cd, String(entry.get("id", "")))
	# Optional per-entry stat override multipliers in identity block.
	if not identity.is_empty():
		_apply_identity_stat_bias(cd, identity)
	return cd

static func _origin_aspect_for_entry(entry: Dictionary, race_id: String) -> String:
	var direct := String(entry.get("origin_id", ""))
	if direct != "":
		return direct.to_lower()
	var race_key := race_id.to_upper()
	var pool: Array = _ORIGIN_ASPECTS_BY_RACE.get(race_key, _ORIGIN_ASPECTS_DEFAULT) as Array
	if pool.is_empty():
		return ""
	var id := String(entry.get("id", ""))
	var idx := _stable_index(id, pool.size())
	return String(pool[idx])

static func _stable_index(id: String, mod: int) -> int:
	if mod <= 0:
		return 0
	var h := 0
	for i in id.length():
		h = int((h * 31 + id.unicode_at(i)) % 2147483647)
	return int(h % mod)

static func _pick_signature_passive(seed_id: String, key: String, pools: Dictionary) -> String:
	var list: Array = pools.get(key.to_upper(), []) as Array
	if list.is_empty():
		return ""
	var idx := _stable_index(seed_id + "_" + key.to_lower(), list.size())
	return String(list[idx])

static func _apply_race_stat_bias(cd: CharacterData, race_id: String) -> void:
	var b: Dictionary = _RACE_STAT_BIAS.get(race_id.to_upper(), {}) as Dictionary
	if b.is_empty():
		return
	cd.max_hp = maxi(1, int(round(float(cd.max_hp) * float(b.get("hp", 1.0)))))
	cd.attack_damage = maxi(1, int(round(float(cd.attack_damage) * float(b.get("dmg", 1.0)))))
	cd.move_speed = maxf(50.0, float(cd.move_speed) * float(b.get("move", 1.0)))
	cd.attack_range = clampf(float(cd.attack_range) * float(b.get("range", 1.0)), 80.0, 760.0)
	cd.attack_cooldown = clampf(float(cd.attack_cooldown) * float(b.get("cd", 1.0)), 0.15, 2.0)

static func _apply_signature_passives(entry: Dictionary, passives: Array, race_id: String) -> void:
	var eid := String(entry.get("id", ""))
	var featured: Array = _FEATURED_SIGNATURE_BY_ID.get(eid, []) as Array
	for fp in featured:
		_append_passive_if_valid(passives, String(fp))
	var class_key := String(entry.get("class_type", ""))
	var role_key := _role_key_for_entry(entry)
	var sig_race := _pick_signature_passive(eid + "_race", race_id, _RACE_SIGNATURE_PASSIVES)
	_append_passive_if_valid(passives, sig_race)
	var sig_class := _pick_signature_passive(eid + "_class", class_key, _CLASS_SIGNATURE_PASSIVES)
	_append_passive_if_valid(passives, sig_class)
	var role_pool: Array = _ROLE_SIGNATURE_PASSIVES.get(role_key, _ROLE_SIGNATURE_PASSIVES.get("default", [])) as Array
	if not role_pool.is_empty():
		var role_idx := _stable_index(eid + "_role_" + role_key, role_pool.size())
		var sig_role := String(role_pool[role_idx])
		_append_passive_if_valid(passives, sig_role)
	# "Chase" passive: deterministic per character, high-impact identity hook.
	if not _CHASE_PASSIVE_POOL.is_empty():
		var chase_idx := _stable_index(eid + "_chase", _CHASE_PASSIVE_POOL.size())
		var chase := String(_CHASE_PASSIVE_POOL[chase_idx])
		_append_passive_if_valid(passives, chase)

static func _apply_variant_passives(entry: Dictionary, passives: Array, race_id: String, rarity_id: String, rng: RandomNumberGenerator) -> void:
	var slots := _variant_slot_count_for_rarity(rarity_id, rng)
	if slots <= 0:
		return
	var eid := String(entry.get("id", ""))
	var class_key := String(entry.get("class_type", ""))
	var role_key := _role_key_for_entry(entry)
	var candidates: Array[String] = []
	_add_pool_candidates(candidates, _ROLE_SIGNATURE_PASSIVES.get(role_key, []))
	_add_pool_candidates(candidates, _CLASS_SIGNATURE_PASSIVES.get(class_key.to_upper(), []))
	_add_pool_candidates(candidates, _RACE_SIGNATURE_PASSIVES.get(race_id.to_upper(), []))
	_add_pool_candidates(candidates, _CHASE_PASSIVE_POOL)
	# Extra flavor: deterministic "specialized" variant by entry id.
	var spec_idx := _stable_index(eid + "_variant_spec", _CHASE_PASSIVE_POOL.size())
	candidates.append(String(_CHASE_PASSIVE_POOL[spec_idx]))
	for _i in range(slots):
		var next := _pick_random_candidate(candidates, passives, rng)
		if next == "":
			break
		_append_passive_if_valid(passives, next)

static func _variant_slot_count_for_rarity(rarity_id: String, rng: RandomNumberGenerator) -> int:
	match rarity_id.to_lower():
		"rare":
			return 1 if rng.randf() < 0.60 else 0
		"epic":
			return 1
		"legendary":
			return 2
		"mythic":
			return 2
		_:
			return 0

static func _build_vector_slot_count_for_rarity(rarity_id: String, rng: RandomNumberGenerator) -> int:
	match rarity_id.to_lower():
		"epic":
			return 1 if rng.randf() < 0.55 else 0
		"legendary":
			return 1
		"mythic":
			return 2 if rng.randf() < 0.30 else 1
		_:
			return 0

static func _apply_build_vector_passives(entry: Dictionary, passives: Array, rarity_id: String, rng: RandomNumberGenerator) -> void:
	var slots := _build_vector_slot_count_for_rarity(rarity_id, rng)
	if slots <= 0:
		return
	var class_key := String(entry.get("class_type", "")).to_upper()
	var vectors: Array = _CLASS_BUILD_VECTORS.get(class_key, ["burst", "control"]) as Array
	if vectors.is_empty():
		return
	var eid := String(entry.get("id", ""))
	var first_vec_idx := _stable_index(eid + "_build_vec", vectors.size())
	for i in range(slots):
		var vec := String(vectors[(first_vec_idx + i) % vectors.size()])
		var pool: Array = _BUILD_VECTORS.get(vec, []) as Array
		if pool.is_empty():
			continue
		var pidx := _stable_index(eid + "_build_vec_" + vec + "_" + str(i), pool.size())
		_append_passive_if_valid(passives, String(pool[pidx]))

static func _add_pool_candidates(out: Array[String], pool_variant: Variant) -> void:
	if typeof(pool_variant) != TYPE_ARRAY:
		return
	var pool: Array = pool_variant as Array
	for p in pool:
		var s := String(p).strip_edges()
		if s != "" and _is_known_passive(s):
			out.append(s)

static func _pick_random_candidate(candidates: Array[String], existing: Array, rng: RandomNumberGenerator) -> String:
	if candidates.is_empty():
		return ""
	var tries: int = mini(24, candidates.size() * 2)
	for _i in range(tries):
		var idx := rng.randi_range(0, candidates.size() - 1)
		var pid := String(candidates[idx])
		if pid != "" and not existing.has(pid):
			return pid
	for pid2 in candidates:
		if not existing.has(pid2):
			return pid2
	return ""

static func _append_passive_if_valid(passives: Array, pid: String) -> void:
	var p := pid.strip_edges()
	if p == "" or passives.has(p):
		return
	if _is_known_passive(p):
		passives.append(p)

static func _is_known_passive(pid: String) -> bool:
	_ensure_passive_catalog_loaded()
	# Fail-open if catalog not available, to avoid hard-breaking runtime.
	if _known_passive_ids.is_empty():
		return true
	return _known_passive_ids.has(pid)

static func _ensure_passive_catalog_loaded() -> void:
	if _passive_catalog_loaded:
		return
	_passive_catalog_loaded = true
	_known_passive_ids.clear()
	var p := "res://data/passives.json"
	if not ResourceLoader.exists(p):
		return
	var txt := FileAccess.get_file_as_string(p)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed
	var arr: Array = root.get("passives", []) as Array
	for e in arr:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var pid := String(d.get("id", "")).strip_edges()
		if pid != "":
			_known_passive_ids[pid] = true

static func _role_key_for_entry(entry: Dictionary) -> String:
	var id := String(entry.get("id", "")).to_lower()
	var name := String(entry.get("display_name", "")).to_lower()
	var txt := id + " " + name
	# Ordered by specificity.
	var keys := [
		"juggernaut", "colossus", "guardian", "vanguard", "warden", "sentinel",
		"necromancer", "warlock", "alchemist", "summoner", "oracle", "mystic",
		"seer", "sniper", "ranger", "scout", "assassin", "duelist", "stalker",
		"savant", "slinger", "binder", "medic", "deacon", "marauder", "reaver",
		"titan", "guard"
	]
	for k in keys:
		if txt.find(k) >= 0:
			return k
	return "default"

static func _apply_role_stat_bias(cd: CharacterData, role_key: String) -> void:
	var b: Dictionary = _ROLE_STAT_BIAS.get(role_key, _ROLE_STAT_BIAS.get("default", {})) as Dictionary
	if b.is_empty():
		return
	cd.max_hp = maxi(1, int(round(float(cd.max_hp) * float(b.get("hp", 1.0)))))
	cd.attack_damage = maxi(1, int(round(float(cd.attack_damage) * float(b.get("dmg", 1.0)))))
	cd.move_speed = maxf(50.0, float(cd.move_speed) * float(b.get("move", 1.0)))
	cd.attack_range = clampf(float(cd.attack_range) * float(b.get("range", 1.0)), 80.0, 760.0)
	cd.attack_cooldown = clampf(float(cd.attack_cooldown) * float(b.get("cd", 1.0)), 0.15, 2.0)

static func _apply_class_stat_bias(cd: CharacterData, class_key: String) -> void:
	var b: Dictionary = _CLASS_STAT_BIAS.get(class_key.to_upper(), {}) as Dictionary
	if b.is_empty():
		return
	cd.max_hp = maxi(1, int(round(float(cd.max_hp) * float(b.get("hp", 1.0)))))
	cd.attack_damage = maxi(1, int(round(float(cd.attack_damage) * float(b.get("dmg", 1.0)))))
	cd.move_speed = maxf(50.0, float(cd.move_speed) * float(b.get("move", 1.0)))
	cd.attack_range = clampf(float(cd.attack_range) * float(b.get("range", 1.0)), 80.0, 760.0)
	cd.attack_cooldown = clampf(float(cd.attack_cooldown) * float(b.get("cd", 1.0)), 0.15, 2.0)

static func _unit_hash01(seed: String) -> float:
	var h := 0
	for i in seed.length():
		h = int((h * 131 + seed.unicode_at(i)) % 2147483647)
	return float(h % 10000) / 9999.0

static func _apply_signature_micro_bias(cd: CharacterData, entry_id: String) -> void:
	# Small deterministic variance so characters don't collapse to same-feel clones.
	var h0 := _unit_hash01(entry_id + "_hp")
	var h1 := _unit_hash01(entry_id + "_dmg")
	var h2 := _unit_hash01(entry_id + "_move")
	var h3 := _unit_hash01(entry_id + "_range")
	var h4 := _unit_hash01(entry_id + "_cd")
	var hp_m := lerpf(0.96, 1.08, h0)
	var dmg_m := lerpf(0.95, 1.10, h1)
	var mov_m := lerpf(0.93, 1.11, h2)
	var rng_m := lerpf(0.92, 1.10, h3)
	var cd_m := lerpf(0.92, 1.08, h4)
	cd.max_hp = maxi(1, int(round(float(cd.max_hp) * hp_m)))
	cd.attack_damage = maxi(1, int(round(float(cd.attack_damage) * dmg_m)))
	cd.move_speed = maxf(50.0, float(cd.move_speed) * mov_m)
	cd.attack_range = clampf(float(cd.attack_range) * rng_m, 80.0, 760.0)
	cd.attack_cooldown = clampf(float(cd.attack_cooldown) * cd_m, 0.15, 2.0)

static func _apply_identity_stat_bias(cd: CharacterData, identity: Dictionary) -> void:
	var sb := identity.get("stat_bias", {}) as Dictionary
	if sb.is_empty():
		return
	cd.max_hp = maxi(1, int(round(float(cd.max_hp) * float(sb.get("hp", 1.0)))))
	cd.attack_damage = maxi(1, int(round(float(cd.attack_damage) * float(sb.get("dmg", 1.0)))))
	cd.move_speed = maxf(50.0, float(cd.move_speed) * float(sb.get("move", 1.0)))
	cd.attack_range = clampf(float(cd.attack_range) * float(sb.get("range", 1.0)), 80.0, 760.0)
	cd.attack_cooldown = clampf(float(cd.attack_cooldown) * float(sb.get("cd", 1.0)), 0.15, 2.0)

static func _origin_from_string(s: String) -> int:
	match s.to_upper():
		"UNDEAD":
			return CharacterData.Origin.UNDEAD
		"MACHINE":
			return CharacterData.Origin.MACHINE
		"BEAST":
			return CharacterData.Origin.BEAST
		"DEMON":
			return CharacterData.Origin.DEMON
		"ELEMENTAL":
			return CharacterData.Origin.ELEMENTAL
		"HUMAN":
			return CharacterData.Origin.HUMAN
		_:
			return CharacterData.Origin.UNDEAD

static func _class_from_string(s: String) -> int:
	match s.to_upper():
		"MAGE":
			return CharacterData.Class.MAGE
		"ROGUE":
			return CharacterData.Class.ROGUE
		"GUARDIAN":
			return CharacterData.Class.GUARDIAN
		"HEALER":
			return CharacterData.Class.HEALER
		"SUMMONER":
			return CharacterData.Class.SUMMONER
		_:
			return CharacterData.Class.WARRIOR

static func _origin_to_name(o: int) -> String:
	match o:
		CharacterData.Origin.UNDEAD:
			return "UNDEAD"
		CharacterData.Origin.MACHINE:
			return "MACHINE"
		CharacterData.Origin.BEAST:
			return "BEAST"
		CharacterData.Origin.DEMON:
			return "DEMON"
		CharacterData.Origin.ELEMENTAL:
			return "ELEMENTAL"
		CharacterData.Origin.HUMAN:
			return "HUMAN"
		_:
			return "UNDEAD"
