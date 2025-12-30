class_name EnemyFactory
extends Node

# Rolls enemy archetype + elite affixes from data tables.

static var _loaded: bool = false
static var _archs: Array[Dictionary] = []
static var _affixes: Array[Dictionary] = []

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path := "res://data/enemy_archetypes.json"
	if not ResourceLoader.exists(path):
		push_warning("EnemyFactory: missing %s" % path)
		return
	var json_text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("EnemyFactory: invalid JSON")
		return
	var d: Dictionary = parsed
	_archs.clear()
	for a in (d.get("archetypes", []) as Array):
		if typeof(a) == TYPE_DICTIONARY:
			_archs.append(a as Dictionary)
	_affixes.clear()
	for af in (d.get("elite_affixes", []) as Array):
		if typeof(af) == TYPE_DICTIONARY:
			_affixes.append(af as Dictionary)

static func roll_enemy_ai_id(rng: RandomNumberGenerator, elapsed_minutes: float) -> String:
	ensure_loaded()
	if _archs.is_empty():
		return "brute"
	var phase := _phase(elapsed_minutes)
	var ids: Array[String] = []
	var weights: Array[int] = []
	for a in _archs:
		var id := String(a.get("id", "brute"))
		var w := _arch_weight(a, phase)
		if w <= 0:
			continue
		ids.append(id)
		weights.append(w)
	if ids.is_empty():
		return "brute"
	return _weighted_pick(ids, weights, rng)

static func archetype_mods(ai_id: String) -> Dictionary:
	ensure_loaded()
	for a in _archs:
		if String(a.get("id", "")) == ai_id:
			return (a.get("mods", {}) as Dictionary)
	return {"hp_mult": 1.0, "dmg_mult": 1.0, "speed_mult": 1.0, "scale": 1.0}

static func roll_elite_affixes(rng: RandomNumberGenerator, elapsed_minutes: float, max_count: int = 2) -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	if _affixes.is_empty() or max_count <= 0:
		return out

	# More affixes later.
	var phase := _phase(elapsed_minutes)
	var target := 1 if phase == "early" else (2 if phase == "mid" else 2)
	target = min(max_count, target)

	var picks: Array[String] = []
	var weights: Array[int] = []
	for a in _affixes:
		picks.append(String(a.get("id", "")))
		weights.append(int(a.get("weight", 1)))

	while out.size() < target and picks.size() > 0:
		var id := _weighted_pick(picks, weights, rng)
		if id == "" or out.has(id):
			# remove to avoid infinite loops
			var idx := picks.find(id)
			if idx >= 0:
				picks.remove_at(idx)
				weights.remove_at(idx)
			continue
		out.append(id)
		# remove so affixes are unique
		var i := picks.find(id)
		if i >= 0:
			picks.remove_at(i)
			weights.remove_at(i)
	return out

static func _phase(elapsed_minutes: float) -> String:
	if elapsed_minutes < 3.5:
		return "early"
	if elapsed_minutes < 8.0:
		return "mid"
	return "late"

static func _arch_weight(a: Dictionary, phase: String) -> int:
	var w := a.get("weights", {}) as Dictionary
	return int(w.get(phase, 1))

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


