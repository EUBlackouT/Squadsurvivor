class_name CharacterRegistryUtil
extends Node

# Runtime helpers for curated character assets (Ludo).
#
# Registry: res://data/character_registry.json
# Assets:   res://assets/characters/<folder>/frames/walk_front/frame_000.png

static var _loaded: bool = false
static var _entries: Array[Dictionary] = []
static var _entry_by_id: Dictionary = {}

const _ORIGIN_PASSIVE: Dictionary = {
	"UNDEAD": "blood_siphon",
	"MACHINE": "overload",
	"BEAST": "bleed_edge",
	"DEMON": "cinder_brand",
	"ELEMENTAL": "arc_chain",
	"HUMAN": "pinpoint"
}

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

	var passives := Array(cd.passive_ids)
	# Entry-specific guaranteed passives
	var required: Array = entry.get("passive_ids", []) as Array
	for pid in required:
		var s := String(pid)
		if s != "" and not passives.has(s):
			passives.append(s)
	# Origin-based racial passive (if not already present)
	var o_name := _origin_to_name(int(cd.origin))
	var racial_id := String(entry.get("racial_passive_id", ""))
	if racial_id == "":
		racial_id = String(_ORIGIN_PASSIVE.get(o_name, ""))
	if racial_id != "" and not passives.has(racial_id):
		passives.append(racial_id)
	cd.passive_ids = PackedStringArray(passives)
	return cd

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
