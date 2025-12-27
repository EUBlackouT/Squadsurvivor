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

func add_to_roster(cd: CharacterData) -> bool:
	if cd == null:
		return false
	# Cap roster size
	if active_roster.size() >= 6:
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


