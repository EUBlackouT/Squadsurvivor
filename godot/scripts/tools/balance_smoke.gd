extends SceneTree

func _init() -> void:
	CharacterRegistryUtil.ensure_loaded()
	UnitFactory.ensure_loaded()
	PassiveSystem.ensure_loaded()

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var map_mod: Dictionary = {}

	var starter_ids: Array[String] = ["insectoid", "ion_scout", "reef_medic"]
	for sid in starter_ids:
		var cd := CharacterRegistryUtil.build_character_data_by_id(sid, "recruit", rng, 0.0, map_mod)
		if cd == null:
			push_error("balance_smoke: missing starter id %s" % sid)
			quit(1)
			return

	var n := 120
	var hp0 := 0.0
	var dmg0 := 0.0
	var hp8 := 0.0
	var dmg8 := 0.0
	var rare_plus0 := 0
	var rare_plus8 := 0
	var rarity_roll0: Dictionary = {}
	var rarity_roll8: Dictionary = {}
	var burst0 := 0.0
	var burst8 := 0.0
	var control0 := 0.0
	var control8 := 0.0
	var sustain0 := 0.0
	var sustain8 := 0.0
	for _i in range(n):
		var a := CharacterRegistryUtil.build_random_character_data("recruit", rng, 0.0, map_mod)
		var b := CharacterRegistryUtil.build_random_character_data("recruit", rng, 8.0, map_mod)
		if a == null or b == null:
			continue
		hp0 += float(a.max_hp)
		dmg0 += float(a.attack_damage)
		hp8 += float(b.max_hp)
		dmg8 += float(b.attack_damage)
		if _rarity_rank(a.rarity_id) >= 1:
			rare_plus0 += 1
		if _rarity_rank(b.rarity_id) >= 1:
			rare_plus8 += 1
		rarity_roll0[a.rarity_id] = int(rarity_roll0.get(a.rarity_id, 0)) + 1
		rarity_roll8[b.rarity_id] = int(rarity_roll8.get(b.rarity_id, 0)) + 1
		burst0 += _path_score(a, "burst")
		burst8 += _path_score(b, "burst")
		control0 += _path_score(a, "control")
		control8 += _path_score(b, "control")
		sustain0 += _path_score(a, "sustain")
		sustain8 += _path_score(b, "sustain")

	var avg_hp0 := hp0 / maxf(1.0, float(n))
	var avg_dmg0 := dmg0 / maxf(1.0, float(n))
	var avg_hp8 := hp8 / maxf(1.0, float(n))
	var avg_dmg8 := dmg8 / maxf(1.0, float(n))

	print("BALANCE_SMOKE starter_ids=ok")
	print("BALANCE_SMOKE recruit_avg minute0 hp=%.1f dmg=%.1f rare+=%d/%d" % [avg_hp0, avg_dmg0, rare_plus0, n])
	print("BALANCE_SMOKE recruit_avg minute8 hp=%.1f dmg=%.1f rare+=%d/%d" % [avg_hp8, avg_dmg8, rare_plus8, n])
	print("BALANCE_SMOKE scaling hp_x=%.3f dmg_x=%.3f" % [avg_hp8 / maxf(1.0, avg_hp0), avg_dmg8 / maxf(1.0, avg_dmg0)])
	print("BALANCE_SMOKE rarity_roll minute0 %s" % _rarity_breakdown(rarity_roll0, n))
	print("BALANCE_SMOKE rarity_roll minute8 %s" % _rarity_breakdown(rarity_roll8, n))
	print("BALANCE_SMOKE path burst m0=%.1f m8=%.1f x=%.3f" % [burst0 / n, burst8 / n, (burst8 / n) / maxf(1.0, burst0 / n)])
	print("BALANCE_SMOKE path control m0=%.1f m8=%.1f x=%.3f" % [control0 / n, control8 / n, (control8 / n) / maxf(1.0, control0 / n)])
	print("BALANCE_SMOKE path sustain m0=%.1f m8=%.1f x=%.3f" % [sustain0 / n, sustain8 / n, (sustain8 / n) / maxf(1.0, sustain0 / n)])
	quit()

func _path_score(cd: CharacterData, path: String) -> float:
	var score := 0.0
	var hp := float(cd.max_hp)
	var dmg := float(cd.attack_damage)
	var range_v := float(cd.attack_range)
	var aps := 1.0 / maxf(0.15, float(cd.attack_cooldown))
	var speed := float(cd.move_speed)
	var crit := float(cd.crit_chance)
	# Base chassis value by path.
	match path:
		"burst":
			score += dmg * aps * 11.0 + crit * 120.0 + range_v * 0.05
		"control":
			score += dmg * aps * 8.0 + range_v * 0.07 + speed * 0.50 + hp * 0.10
		"sustain":
			score += hp * 0.34 + dmg * aps * 7.0 + speed * 0.36
	# Passive value by tags/ids.
	for pid in cd.passive_ids:
		var tags := PassiveSystem.passive_tags(String(pid))
		if path == "burst":
			if tags.has("burst") or tags.has("execute"):
				score += 24.0
			if tags.has("proc"):
				score += 15.0
			if tags.has("aoe"):
				score += 8.0
		elif path == "control":
			if tags.has("control") or tags.has("slow"):
				score += 24.0
			if tags.has("aoe"):
				score += 10.0
			if tags.has("setup"):
				score += 8.0
		else:
			if tags.has("sustain"):
				score += 24.0
			if tags.has("dot"):
				score += 10.0
			if tags.has("melee"):
				score += 6.0
		if String(pid) in ["blood_siphon", "vampiric_bullets", "vampiric_mastery"]:
			score += 16.0 if path == "sustain" else 4.0
	return score

func _rarity_breakdown(counts: Dictionary, total: int) -> String:
	var order: Array[String] = ["common", "rare", "epic", "legendary", "mythic"]
	var parts: Array[String] = []
	for rid in order:
		var c := int(counts.get(rid, 0))
		var pct := (100.0 * float(c) / maxf(1.0, float(total)))
		parts.append("%s:%d(%.1f%%)" % [rid, c, pct])
	return " ".join(parts)

func _rarity_rank(rarity_id: String) -> int:
	match rarity_id:
		"mythic":
			return 4
		"legendary":
			return 3
		"epic":
			return 2
		"rare":
			return 1
		_:
			return 0
