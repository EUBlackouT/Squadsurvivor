extends Node

# Persistent unlock collection + active roster.
# Saved at: user://collection.json

const SAVE_PATH := "user://collection.json"
const SAVE_VERSION := 1

var unlocked: Array[Dictionary] = [] # each: { "id": String, "data": Dictionary }
var active_roster: Array[Dictionary] = [] # each: saved CharacterData dict

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_save()

func _make_unlock_id(cd: CharacterData) -> String:
	# Unique per "variant" so builds can exist.
	var pid := cd.pixellab_id if cd.pixellab_id != "" else cd.sprite_path
	var pass_str := ",".join(cd.passive_ids)
	return "%s|%s|%s|%s|%s" % [
		pid,
		cd.rarity_id,
		cd.archetype_id,
		str(int(cd.attack_style)),
		pass_str
	]

func _cd_to_dict(cd: CharacterData) -> Dictionary:
	return {
		"sprite_path": cd.sprite_path,
		"pixellab_id": cd.pixellab_id,
		"rarity_id": cd.rarity_id,
		"archetype_id": cd.archetype_id,
		"origin": int(cd.origin),
		"class_type": int(cd.class_type),
		"tier": int(cd.tier),
		"attack_style": int(cd.attack_style),
		"weapon_id": cd.weapon_id,
		"passive_ids": Array(cd.passive_ids),
		"crit_chance": float(cd.crit_chance),
		"crit_mult": float(cd.crit_mult),
		"max_hp": int(cd.max_hp),
		"attack_damage": int(cd.attack_damage),
		"attack_range": float(cd.attack_range),
		"attack_cooldown": float(cd.attack_cooldown),
		"move_speed": float(cd.move_speed)
	}

func _dict_to_cd(d: Dictionary) -> CharacterData:
	var cd := CharacterData.new()
	cd.sprite_path = String(d.get("sprite_path", ""))
	cd.pixellab_id = String(d.get("pixellab_id", ""))
	cd.rarity_id = String(d.get("rarity_id", "common"))
	cd.archetype_id = String(d.get("archetype_id", "bruiser"))
	cd.origin = int(d.get("origin", 0))
	cd.class_type = int(d.get("class_type", 0))
	cd.tier = int(d.get("tier", 1))
	cd.attack_style = int(d.get("attack_style", 1))
	cd.weapon_id = String(d.get("weapon_id", "standard_bolt"))
	var arr: Array = d.get("passive_ids", [])
	var pids := PackedStringArray()
	for a in arr:
		pids.append(String(a))
	cd.passive_ids = pids
	cd.crit_chance = float(d.get("crit_chance", 0.0))
	cd.crit_mult = float(d.get("crit_mult", 1.5))
	cd.max_hp = int(d.get("max_hp", 100))
	cd.attack_damage = int(d.get("attack_damage", 10))
	cd.attack_range = float(d.get("attack_range", 300.0))
	cd.attack_cooldown = float(d.get("attack_cooldown", 1.0))
	cd.move_speed = float(d.get("move_speed", 120.0))
	return cd

func unlock_character(cd: CharacterData) -> bool:
	if cd == null:
		return false
	var uid := _make_unlock_id(cd)
	for e in unlocked:
		if String(e.get("id", "")) == uid:
			return false
	unlocked.append({"id": uid, "data": _cd_to_dict(cd)})
	save()
	return true

# Dupe system: find existing character with same appearance (pixellab_id)
func find_dupe_by_appearance(cd: CharacterData) -> int:
	if cd == null:
		return -1
	var target_id := cd.pixellab_id if cd.pixellab_id != "" else cd.sprite_path
	if target_id == "":
		return -1
	for i in range(unlocked.size()):
		var data: Dictionary = unlocked[i].get("data", {})
		var existing_id := String(data.get("pixellab_id", ""))
		if existing_id == "":
			existing_id = String(data.get("sprite_path", ""))
		if existing_id == target_id:
			return i
	return -1

# Merge duplicate character to upgrade an existing one
# Returns: { "success": bool, "upgraded_cd": CharacterData, "bonus_text": String }
func merge_duplicate(cd: CharacterData) -> Dictionary:
	if cd == null:
		return {"success": false, "upgraded_cd": null, "bonus_text": ""}
	
	var dupe_idx := find_dupe_by_appearance(cd)
	if dupe_idx < 0:
		return {"success": false, "upgraded_cd": null, "bonus_text": ""}
	
	# Get existing character data
	var existing_data: Dictionary = unlocked[dupe_idx].get("data", {})
	var existing_cd := _dict_to_cd(existing_data)
	
	# Upgrade bonuses per merge (stacks!)
	var current_tier: int = int(existing_data.get("tier", 1))
	var new_tier: int = mini(current_tier + 1, 5)  # Max tier 5 (★★★★★)
	
	# Per-tier bonuses (compound!)
	var hp_bonus := 0.12  # +12% HP per merge
	var dmg_bonus := 0.10  # +10% damage per merge
	var crit_bonus := 0.02  # +2% crit chance per merge
	
	existing_cd.tier = new_tier
	existing_cd.max_hp = int(round(float(existing_cd.max_hp) * (1.0 + hp_bonus)))
	existing_cd.attack_damage = int(round(float(existing_cd.attack_damage) * (1.0 + dmg_bonus)))
	existing_cd.crit_chance = clampf(existing_cd.crit_chance + crit_bonus, 0.0, 0.50)
	
	# Chance to inherit a passive from the dupe (if they have different ones)
	var inherited_passive := ""
	for pid in cd.passive_ids:
		if not existing_cd.passive_ids.has(pid):
			# 50% chance to inherit this passive
			if randf() < 0.50:
				var new_passives := Array(existing_cd.passive_ids)
				new_passives.append(pid)
				existing_cd.passive_ids = PackedStringArray(new_passives)
				inherited_passive = pid
				break
	
	# Update the stored character
	unlocked[dupe_idx]["data"] = _cd_to_dict(existing_cd)
	unlocked[dupe_idx]["id"] = _make_unlock_id(existing_cd)
	
	# Also update in active roster if present
	_update_roster_character(existing_cd)
	
	save()
	
	# Build bonus description
	var stars := "★".repeat(new_tier)
	var bonus_text := "%s\n+12%% HP, +10%% DMG, +2%% Crit" % stars
	if inherited_passive != "":
		bonus_text += "\n+NEW: %s" % PassiveSystem.passive_name(inherited_passive)
	
	return {"success": true, "upgraded_cd": existing_cd, "bonus_text": bonus_text}

func _update_roster_character(cd: CharacterData) -> void:
	# Find and update this character in active roster
	var target_id := cd.pixellab_id if cd.pixellab_id != "" else cd.sprite_path
	for i in range(active_roster.size()):
		var data: Dictionary = active_roster[i]
		var roster_id := String(data.get("pixellab_id", ""))
		if roster_id == "":
			roster_id = String(data.get("sprite_path", ""))
		if roster_id == target_id:
			active_roster[i] = _cd_to_dict(cd)
			break

func add_to_roster(cd: CharacterData) -> bool:
	if cd == null:
		return false
	# Cap roster size
	var cap := 6
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_roster_cap"):
		cap = int(mp.get_roster_cap())
	if active_roster.size() >= cap:
		return false
	active_roster.append(_cd_to_dict(cd))
	save()
	return true

func remove_from_roster(index: int) -> void:
	if index < 0 or index >= active_roster.size():
		return
	active_roster.remove_at(index)
	save()

func clear_roster() -> void:
	active_roster.clear()
	save()

func get_active_roster_character_data() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for d in active_roster:
		if typeof(d) == TYPE_DICTIONARY:
			out.append(_dict_to_cd(d))
	return out

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		# Seed starter unlocks (so Menu isn't empty on first run)
		unlocked = []
		active_roster = []
		# Deterministic starter pack so new installs feel consistent.
		PixellabUtil.ensure_loaded()
		UnitFactory.ensure_loaded()
		var rng := RandomNumberGenerator.new()
		rng.seed = 1337
		var starters: Array[CharacterData] = []
		var tries: int = 0
		while starters.size() < 3 and tries < 50:
			tries += 1
			var south := PixellabUtil.pick_random_south_path(rng)
			var cd := UnitFactory.build_character_data("recruit", rng, 0.0, south)
			# Avoid duplicates by unlock_id
			var uid := _make_unlock_id(cd)
			var dup := false
			for s in starters:
				if _make_unlock_id(s) == uid:
					dup = true
					break
			if dup:
				continue
			starters.append(cd)
		for cd2 in starters:
			unlocked.append({"id": _make_unlock_id(cd2), "data": _cd_to_dict(cd2)})
			active_roster.append(_cd_to_dict(cd2))
		save()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed
	unlocked = []
	var uarr: Array = root.get("unlocked", [])
	for e in uarr:
		if typeof(e) == TYPE_DICTIONARY:
			unlocked.append(e)
	active_roster = []
	var rarr: Array = root.get("active_roster", [])
	for e2 in rarr:
		if typeof(e2) == TYPE_DICTIONARY:
			active_roster.append(e2)

func save() -> void:
	var root := {
		"version": SAVE_VERSION,
		"unlocked": unlocked,
		"active_roster": active_roster
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("CollectionManager: failed to open save for write")
		return
	f.store_string(JSON.stringify(root))

# Re-roll weapons for all existing characters (dev/testing)
func reroll_all_weapons() -> int:
	WeaponSystem.ensure_loaded()
	var all_weapons: Array = WeaponSystem.all_weapon_ids()
	if all_weapons.is_empty():
		return 0
	
	var count := 0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	# Re-roll unlocked characters
	for i in range(unlocked.size()):
		var data: Dictionary = unlocked[i].get("data", {})
		var old_weapon := String(data.get("weapon_id", "standard_bolt"))
		# Pick a new weapon (different from current)
		var new_weapon := old_weapon
		var tries := 0
		while new_weapon == old_weapon and tries < 10:
			new_weapon = all_weapons[rng.randi() % all_weapons.size()]
			tries += 1
		data["weapon_id"] = new_weapon
		# Update attack_style based on weapon tags
		var tags := WeaponSystem.weapon_tags(new_weapon)
		if tags.has("melee"):
			data["attack_style"] = 0
			data["attack_range"] = 80.0
		else:
			data["attack_style"] = 1
			data["attack_range"] = 350.0
		unlocked[i]["data"] = data
		count += 1
	
	# Re-roll active roster
	for i in range(active_roster.size()):
		var data: Dictionary = active_roster[i]
		var old_weapon := String(data.get("weapon_id", "standard_bolt"))
		var new_weapon := old_weapon
		var tries := 0
		while new_weapon == old_weapon and tries < 10:
			new_weapon = all_weapons[rng.randi() % all_weapons.size()]
			tries += 1
		data["weapon_id"] = new_weapon
		var tags := WeaponSystem.weapon_tags(new_weapon)
		if tags.has("melee"):
			data["attack_style"] = 0
			data["attack_range"] = 80.0
		else:
			data["attack_style"] = 1
			data["attack_range"] = 350.0
		active_roster[i] = data
	
	save()
	print("CollectionManager: Re-rolled weapons for %d characters" % count)
	# Print what weapons were assigned
	for i in range(mini(5, active_roster.size())):
		var data: Dictionary = active_roster[i]
		print("  Character %d: %s" % [i, data.get("weapon_id", "UNKNOWN")])
	return count
