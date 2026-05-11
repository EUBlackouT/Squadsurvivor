extends SceneTree

const STARTER_IDS: Array[String] = ["insectoid", "ion_scout", "reef_medic"]
const PATHS: Array[String] = ["starter_only", "burst", "control", "sustain"]

func _init() -> void:
	CharacterRegistryUtil.ensure_loaded()
	UnitFactory.ensure_loaded()
	PassiveSystem.ensure_loaded()

	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var map_mod: Dictionary = {}

	for p in PATHS:
		var result := _run_path_smoke(p, rng, map_mod)
		print("PATH_SMOKE %s %s" % [p, result])
	quit()

func _run_path_smoke(path: String, rng: RandomNumberGenerator, map_mod: Dictionary) -> String:
	var roster: Array[CharacterData] = []
	for sid in STARTER_IDS:
		var cd := CharacterRegistryUtil.build_character_data_by_id(sid, "recruit", rng, 0.0, map_mod)
		if cd == null:
			return "error=missing_starter:%s" % sid
		_apply_starter_nerf(cd)
		roster.append(cd)

	var fail_minute := -1.0
	var weak_streak := 0
	var minute := 0.0
	var next_draft_at := 1.0
	while minute <= 10.0:
		if path != "starter_only" and minute >= next_draft_at:
			next_draft_at += 1.0
			if roster.size() < 10:
				var pick := _pick_best_recruit(path, rng, minute, map_mod)
				if pick != null:
					roster.append(pick)

		var squad_p := _squad_power(roster, path)
		var enemy_p := _enemy_pressure(rng, minute, map_mod)
		var ratio := squad_p / maxf(1.0, enemy_p)
		if minute >= 1.0 and ratio < 0.72:
			weak_streak += 1
			if weak_streak >= 6:
				fail_minute = minute
				break
		else:
			weak_streak = 0
		minute += 0.33

	if fail_minute > 0.0:
		return "failed_at=%.1f roster=%d" % [fail_minute, roster.size()]
	return "clears_10m roster=%d" % roster.size()

func _pick_best_recruit(path: String, rng: RandomNumberGenerator, minute: float, map_mod: Dictionary) -> CharacterData:
	var best: CharacterData = null
	var best_score := -1e18
	for _i in range(10):
		var cd := CharacterRegistryUtil.build_random_character_data("recruit", rng, minute + 7.0, map_mod)
		if cd == null:
			continue
		var sc := _unit_path_score(cd, path)
		if sc > best_score:
			best_score = sc
			best = cd
	return best

func _squad_power(roster: Array[CharacterData], path: String) -> float:
	if roster.is_empty():
		return 0.0
	var total := 0.0
	for cd in roster:
		total += _unit_path_score(cd, path)
	var size_mult := 0.90 + minf(0.55, float(roster.size()) * 0.055)
	var build_mult := 1.0
	if path != "starter_only":
		# Represents level-ups/upgrades that compound during an active run.
		build_mult = 1.0 + minf(0.75, maxf(0.0, float(roster.size() - 3)) * 0.09)
	return total * size_mult * build_mult

func _unit_path_score(cd: CharacterData, path: String) -> float:
	var hp := float(cd.max_hp)
	var dmg := float(cd.attack_damage)
	var range_v := float(cd.attack_range)
	var aps := 1.0 / maxf(0.15, float(cd.attack_cooldown))
	var speed := float(cd.move_speed)
	var crit := float(cd.crit_chance)
	var crit_m := float(cd.crit_mult)
	var crit_factor := 1.0 + crit * maxf(0.0, crit_m - 1.0)
	var dps := dmg * aps * crit_factor
	var score := 0.0
	match path:
		"burst":
			score += dps * 15.0 + range_v * 0.07 + speed * 0.35 + hp * 0.07
		"control":
			score += dps * 11.0 + range_v * 0.10 + speed * 0.55 + hp * 0.10
		"sustain":
			score += dps * 10.0 + hp * 0.30 + speed * 0.40 + range_v * 0.04
		_:
			score += dps * 10.5 + hp * 0.20 + speed * 0.35 + range_v * 0.06

	for pid in cd.passive_ids:
		var tags := PassiveSystem.passive_tags(String(pid))
		match path:
			"burst":
				if tags.has("burst") or tags.has("execute"):
					score += 30.0
				if tags.has("proc"):
					score += 16.0
				if tags.has("aoe"):
					score += 8.0
			"control":
				if tags.has("control") or tags.has("slow"):
					score += 28.0
				if tags.has("setup"):
					score += 10.0
				if tags.has("aoe"):
					score += 8.0
			"sustain":
				if tags.has("sustain"):
					score += 30.0
				if tags.has("dot"):
					score += 12.0
				if tags.has("melee"):
					score += 7.0
			_:
				if tags.has("aoe") or tags.has("burst") or tags.has("sustain"):
					score += 8.0
		if String(pid) in ["blood_siphon", "vampiric_bullets", "vampiric_mastery"]:
			score += 18.0 if path == "sustain" else 4.0
	return score

func _enemy_pressure(rng: RandomNumberGenerator, minute: float, map_mod: Dictionary) -> float:
	var r := clampf(minute / maxf(0.001, 10.5 * float(map_mod.get("difficulty_ramp_minutes_mult", 1.0))), 0.0, 1.0)
	var curved := pow(r, maxf(0.1, 2.1 * float(map_mod.get("ramp_curve_power_mult", 1.0))))
	var spawn_a := 1.95 * float(map_mod.get("spawn_interval_start_mult", 1.0))
	var spawn_b := 0.58 * float(map_mod.get("spawn_interval_end_mult", 1.0))
	var spawn_interval := lerpf(spawn_a, spawn_b, curved) * float(map_mod.get("spawn_interval_mult", 1.0))
	var max_a := 20.0 * float(map_mod.get("max_enemies_start_mult", 1.0))
	var max_b := 154.0 * float(map_mod.get("max_enemies_end_mult", 1.0))
	var max_enemies := lerpf(max_a, max_b, curved) * float(map_mod.get("max_enemies_mult", 1.0))

	var enemy_avg := 0.0
	for _i in range(24):
		var e := CharacterRegistryUtil.build_random_character_data("enemy", rng, minute, map_mod)
		if e == null:
			continue
		var ep := _unit_path_score(e, "starter_only")
		enemy_avg += ep
	enemy_avg /= 24.0

	var on_screen := max_enemies * 0.42
	var pressure := enemy_avg * on_screen
	pressure += enemy_avg * (3.5 / maxf(0.20, spawn_interval))
	return pressure

func _apply_starter_nerf(cd: CharacterData) -> void:
	cd.max_hp = maxi(1, int(round(float(cd.max_hp) * 0.74)))
	cd.attack_damage = maxi(1, int(round(float(cd.attack_damage) * 0.60)))
	cd.attack_range = maxf(110.0, cd.attack_range * 0.82)
	cd.attack_cooldown = maxf(0.45, cd.attack_cooldown * 1.24)
	cd.move_speed = maxf(78.0, cd.move_speed * 0.90)
	cd.crit_chance = minf(cd.crit_chance, 0.03)
	if cd.passive_ids.size() > 1:
		cd.passive_ids = PackedStringArray([String(cd.passive_ids[0])])
