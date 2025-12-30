class_name UnitFactory
extends Node

# Builds CharacterData from balance tables and a chosen PixelLab south path.
# Uses static caches so callers can use UnitFactory.* without instancing nodes.

static var _loaded: bool = false
static var _balance: Dictionary = {}

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path := "res://data/unit_balance.json"
	if not ResourceLoader.exists(path):
		push_warning("UnitFactory: missing %s" % path)
		return
	var json_text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("UnitFactory: invalid JSON")
		return
	_balance = parsed as Dictionary

static func build_character_data(context: String, rng: RandomNumberGenerator, elapsed_minutes: float, south_path: String, map_mod: Dictionary = {}) -> CharacterData:
	ensure_loaded()
	var cd := CharacterData.new()
	cd.sprite_path = south_path

	# Try derive Pixellab id from path.
	cd.pixellab_id = _pixellab_id_from_south_path(south_path)

	var rarity_id := roll_rarity_id(context, rng, elapsed_minutes, map_mod)
	var archetype_id := roll_archetype_id(context, rng)
	cd.rarity_id = rarity_id
	cd.archetype_id = archetype_id

	var arch := _get_archetype(archetype_id)
	var base := (arch.get("base", {}) as Dictionary)

	var hp := float(base.get("max_hp", 100))
	var dmg := float(base.get("attack_damage", 10))
	var ran := float(base.get("attack_range", 300.0))
	var cdv := float(base.get("attack_cooldown", 1.0))
	var ms := float(base.get("move_speed", 120.0))
	var crit_c := float(base.get("crit_chance", 0.0))
	var crit_m := float(base.get("crit_mult", 1.5))

	# Context multipliers (enemy vs recruit)
	var ctx_mult := (_balance.get("context_stat_mult", {}) as Dictionary).get(context, {}) as Dictionary
	hp *= float(ctx_mult.get("max_hp", 1.0))
	dmg *= float(ctx_mult.get("attack_damage", 1.0))
	ms *= float(ctx_mult.get("move_speed", 1.0))

	# Map multipliers (baseline difficulty & pacing lives here)
	if context == "enemy":
		hp *= float(map_mod.get("enemy_hp_mult", 1.0))
		dmg *= float(map_mod.get("enemy_damage_mult", 1.0))
		ms *= float(map_mod.get("enemy_speed_mult", 1.0))

	# Apply rarity multipliers
	var rarity := _get_rarity(rarity_id)
	var mult := (rarity.get("stat_mult", {}) as Dictionary)
	hp *= float(mult.get("max_hp", 1.0))
	dmg *= float(mult.get("attack_damage", 1.0))
	ms *= float(mult.get("move_speed", 1.0))
	crit_c += float(mult.get("crit_chance_add", 0.0))

	# Apply time scaling for enemies
	if context == "enemy":
		var scaling := (_balance.get("enemy_scaling", {}) as Dictionary)
		var hp_mult := 1.0 + float(scaling.get("hp_per_minute_mult", 0.0)) * elapsed_minutes
		var dmg_mult := 1.0 + float(scaling.get("damage_per_minute_mult", 0.0)) * elapsed_minutes
		hp *= hp_mult
		dmg *= dmg_mult
	elif context == "recruit":
		# Draft scaling should NOT make Map 1 the main power farm.
		# So: per-map caps from maps.json control how spicy drafts can get.
		var scale_mins := float(map_mod.get("recruit_scale_minutes", 12.0))
		var t := clampf(elapsed_minutes / maxf(0.1, scale_mins), 0.0, 1.0)
		var curved := pow(t, 1.20)
		var hp_bonus_max := float(map_mod.get("recruit_hp_bonus_max", 0.10))
		var dmg_bonus_max := float(map_mod.get("recruit_dmg_bonus_max", 0.18))
		hp *= 1.0 + hp_bonus_max * curved
		dmg *= 1.0 + dmg_bonus_max * curved

	cd.max_hp = int(round(hp))
	cd.attack_damage = int(round(dmg))
	cd.attack_range = ran
	cd.attack_cooldown = maxf(0.15, cdv)
	cd.move_speed = ms
	cd.crit_chance = clampf(crit_c, 0.0, 0.75)
	cd.crit_mult = maxf(1.1, crit_m)

	_apply_attack_style_random(cd, rng)
	_roll_passives(cd, rng, context, elapsed_minutes)

	# Best-effort class hint mapping
	var hint := String(arch.get("class_hint", "WARRIOR"))
	cd.class_type = _class_from_hint(hint)
	# Origin is the "faction/species" tag used for synergies.
	# Best-effort: if the PixelLab registry entry includes origin metadata, respect it; otherwise fallback to random.
	var o_hint := PixellabUtil.origin_hint_from_south_path(south_path)
	if o_hint >= 0:
		cd.origin = o_hint
	else:
		cd.origin = rng.randi() % 6
	return cd

static func rarity_name(rarity_id: String) -> String:
	ensure_loaded()
	var r := _get_rarity(rarity_id)
	return String(r.get("name", rarity_id))

static func rarity_color(rarity_id: String) -> Color:
	match rarity_id:
		"legendary":
			return Color(1.0, 0.80, 0.28)
		"epic":
			return Color(0.75, 0.45, 1.0)
		"rare":
			return Color(0.35, 0.80, 1.0)
		_:
			return Color(0.78, 0.82, 0.88)

static func roll_rarity_id(context: String, rng: RandomNumberGenerator, elapsed_minutes: float, map_mod: Dictionary = {}) -> String:
	ensure_loaded()
	var rarities: Array = _balance.get("rarities", [])
	if rarities.is_empty():
		return "common"
	# Build weights with a tiny time bias (helps variety later).
	var eff_minutes := elapsed_minutes
	if context == "recruit":
		eff_minutes += float(map_mod.get("recruit_rarity_bias_minutes", 0.0))
	var weights: Array[int] = []
	var ids: Array[String] = []
	for r in rarities:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var rd: Dictionary = r
		var id := String(rd.get("id", "common"))
		var w0 := int((rd.get("weight", {}) as Dictionary).get(context, 1))
		var bonus := 0
		if context == "recruit":
			if id == "rare":
				bonus = int(floor(eff_minutes * 0.4))
			elif id == "epic":
				bonus = int(floor(eff_minutes * 0.2))
			elif id == "legendary":
				bonus = int(floor(eff_minutes * 0.08))
		weights.append(max(1, w0 + bonus))
		ids.append(id)
	return _weighted_pick(ids, weights, rng)

static func roll_archetype_id(_context: String, rng: RandomNumberGenerator) -> String:
	ensure_loaded()
	var archs: Array = _balance.get("archetypes", [])
	if archs.is_empty():
		return "bruiser"
	var idx := rng.randi_range(0, archs.size() - 1)
	var d := archs[idx] as Dictionary
	return String(d.get("id", "bruiser"))

static func _weighted_pick(ids: Array[String], weights: Array[int], rng: RandomNumberGenerator) -> String:
	var total: int = 0
	for w in weights:
		total += w
	var roll := rng.randi_range(1, max(1, total))
	var acc: int = 0
	for i in range(ids.size()):
		acc += weights[i]
		if roll <= acc:
			return ids[i]
	return ids[0]

static func _get_rarity(rarity_id: String) -> Dictionary:
	ensure_loaded()
	var rarities: Array = _balance.get("rarities", [])
	for r in rarities:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = r
		if String(d.get("id", "")) == rarity_id:
			return d
	return {"id": "common", "name": "Common", "stat_mult": {"max_hp": 1.0, "attack_damage": 1.0}}

static func _get_archetype(archetype_id: String) -> Dictionary:
	ensure_loaded()
	var archs: Array = _balance.get("archetypes", [])
	for a in archs:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = a
		if String(d.get("id", "")) == archetype_id:
			return d
	return {"id": "bruiser", "class_hint": "WARRIOR", "base": {"max_hp": 100, "attack_damage": 10}}

static func _class_from_hint(hint: String) -> CharacterData.Class:
	match hint:
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

static func _apply_attack_style_random(cd: CharacterData, rng: RandomNumberGenerator) -> void:
	# Randomly roll melee vs ranged, with tradeoffs.
	var melee := rng.randf() < 0.38
	if melee:
		cd.attack_style = CharacterData.AttackStyle.MELEE
		cd.attack_range = clampf(cd.attack_range * 0.55, 80.0, 220.0)
		cd.attack_damage = int(round(float(cd.attack_damage) * 1.22))
		cd.attack_cooldown = maxf(0.25, cd.attack_cooldown * 0.90)
		cd.max_hp = int(round(float(cd.max_hp) * 1.12))
	else:
		cd.attack_style = CharacterData.AttackStyle.RANGED
		cd.attack_range = clampf(cd.attack_range * 1.05, 240.0, 680.0)
		cd.attack_damage = int(round(float(cd.attack_damage) * 1.0))

static func _roll_passives(cd: CharacterData, rng: RandomNumberGenerator, _context: String, _elapsed_minutes: float) -> void:
	ensure_loaded()
	var pools := _balance.get("passive_pools", {}) as Dictionary
	var pool := pools.get(cd.rarity_id, []) as Array
	if pool.is_empty():
		cd.passive_ids = PackedStringArray()
		return

	# Rarity-driven passive count (with RNG high-rolls).
	# This is a key part of the compulsion loop: commons are simple, legendaries feel stacked.
	var want: int = _roll_passive_count(cd.rarity_id, rng)
	if want <= 0:
		cd.passive_ids = PackedStringArray()
		return

	var chosen: Array[String] = []
	var attempts: int = 0
	while chosen.size() < want and attempts < 80:
		attempts += 1
		var id := String(pool[rng.randi_range(0, pool.size() - 1)])
		if chosen.has(id):
			continue
		chosen.append(id)
	cd.passive_ids = PackedStringArray(chosen)

static func _pixellab_id_from_south_path(south_path: String) -> String:
	var parts := south_path.split("/", false)
	var idx := parts.find("pixellab")
	if idx >= 0 and idx + 1 < parts.size():
		return parts[idx + 1]
	return ""

static func _roll_passive_count(rarity_id: String, rng: RandomNumberGenerator) -> int:
	# Weighted counts per rarity. Tuned so early units don't feel overloaded.
	# Common: usually 1, sometimes 2
	# Rare: usually 2, sometimes 3
	# Epic: usually 3, sometimes 4
	# Legendary: usually 4, sometimes 5
	var roll := rng.randf()
	match rarity_id:
		"legendary":
			return 5 if roll < 0.18 else 4
		"epic":
			if roll < 0.10:
				return 4
			return 3
		"rare":
			if roll < 0.15:
				return 3
			return 2
		_:
			if roll < 0.22:
				return 2
			return 1


