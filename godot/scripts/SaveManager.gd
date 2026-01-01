extends Node

# Run save + meta save (wrapper around existing autoloads).
#
# Run save: user://run_save.json
# Meta save (sigils/unlocks): user://meta_save.json

const RUN_SAVE_PATH := "user://run_save.json"
const META_SAVE_PATH := "user://meta_save.json"
const SAVE_VERSION := 1

var resume_next_run: bool = false
var _cached_run: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func request_resume() -> bool:
	var d := load_run()
	if d.is_empty():
		resume_next_run = false
		_cached_run = {}
		return false
	resume_next_run = true
	_cached_run = d
	return true

func pop_cached_run() -> Dictionary:
	var d := _cached_run
	_cached_run = {}
	resume_next_run = false
	return d

func save_run(main_node: Node) -> void:
	var main := main_node
	if main == null or not is_instance_valid(main):
		main = get_tree().get_first_node_in_group("main")
	if main == null or not is_instance_valid(main):
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	var player_pos := Vector2.ZERO
	if player != null and is_instance_valid(player):
		player_pos = player.global_position

	var elapsed_s: float = 0.0
	if "run_start_time" in main:
		var now_s := float(Time.get_ticks_msec()) / 1000.0
		elapsed_s = maxf(0.0, now_s - float(main.get("run_start_time")))

	var essence: int = int(main.get("essence") if "essence" in main else 0)
	var kills: int = int(main.get("_run_kills") if "_run_kills" in main else 0)
	var boss_spawned: bool = bool(main.get("_boss_spawned") if "_boss_spawned" in main else false)

	# Map/seed metadata (helps debugging and future restore fidelity)
	var map_id := ""
	var rc := get_node_or_null("/root/RunConfig")
	if rc != null and is_instance_valid(rc) and ("selected_map_id" in rc):
		map_id = String(rc.get("selected_map_id"))
	var map_name := ""
	if "_map_mod" in main:
		var mm: Dictionary = main.get("_map_mod") as Dictionary
		map_name = String(mm.get("name", ""))
	var seed: int = int(main.get("random_seed") if "random_seed" in main else 0)

	var squad_arr: Array = []
	if player != null and is_instance_valid(player) and "squad_units" in player:
		var squad_nodes: Array = player.get("squad_units")
		for u in squad_nodes:
			if not is_instance_valid(u):
				continue
			var cd := (u as Node).get("character_data") as CharacterData
			if cd != null:
				squad_arr.append(_cd_to_dict(cd))

	var root := {
		"version": SAVE_VERSION,
		"map_id": map_id,
		"map_name": map_name,
		"random_seed": seed,
		"player_pos": [player_pos.x, player_pos.y],
		"elapsed_s": elapsed_s,
		"essence": essence,
		"kills": kills,
		"boss_spawned": boss_spawned,
		"squad": squad_arr
	}

	var f := FileAccess.open(RUN_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: failed to open run save for write")
		return
	f.store_string(JSON.stringify(root))

func load_run() -> Dictionary:
	if not FileAccess.file_exists(RUN_SAVE_PATH):
		return {}
	var f := FileAccess.open(RUN_SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}

	var root: Dictionary = parsed
	var out: Dictionary = {}
	out["raw"] = root
	out["version"] = int(root.get("version", 0))
	out["map_id"] = String(root.get("map_id", ""))
	out["map_name"] = String(root.get("map_name", ""))
	out["random_seed"] = int(root.get("random_seed", 0))

	var p: Vector2 = Vector2.ZERO
	var parr: Array = root.get("player_pos", [])
	if parr.size() >= 2:
		p = Vector2(float(parr[0]), float(parr[1]))
	out["player_pos"] = p

	out["elapsed_s"] = float(root.get("elapsed_s", 0.0))
	out["essence"] = int(root.get("essence", 0))
	out["kills"] = int(root.get("kills", 0))
	out["boss_spawned"] = bool(root.get("boss_spawned", false))

	var squad: Array[CharacterData] = []
	var sarr: Array = root.get("squad", [])
	for e in sarr:
		if typeof(e) == TYPE_DICTIONARY:
			squad.append(_dict_to_cd(e as Dictionary))
	out["squad"] = squad

	return out

func has_saved_run() -> bool:
	return FileAccess.file_exists(RUN_SAVE_PATH)

func delete_run_save() -> void:
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(RUN_SAVE_PATH)

func save_meta() -> void:
	var mp := get_node_or_null("/root/MetaProgression")
	var cm := get_node_or_null("/root/CollectionManager")
	var root := {
		"version": SAVE_VERSION,
		"meta": {
			"sigils": int(mp.sigils) if (mp != null and is_instance_valid(mp) and "sigils" in mp) else 0,
			"squad_slots": int(mp.squad_slots) if (mp != null and is_instance_valid(mp) and "squad_slots" in mp) else 3,
			"last_run": mp.last_run if (mp != null and is_instance_valid(mp) and "last_run" in mp) else {}
		},
		"collection": {
			"unlocked": cm.unlocked if (cm != null and is_instance_valid(cm) and "unlocked" in cm) else [],
			"active_roster": cm.active_roster if (cm != null and is_instance_valid(cm) and "active_roster" in cm) else []
		}
	}

	var f := FileAccess.open(META_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: failed to open meta save for write")
		return
	f.store_string(JSON.stringify(root))

func load_meta() -> void:
	if not FileAccess.file_exists(META_SAVE_PATH):
		return
	var f := FileAccess.open(META_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed
	var meta: Dictionary = root.get("meta", {}) as Dictionary
	var coll: Dictionary = root.get("collection", {}) as Dictionary

	var mp := get_node_or_null("/root/MetaProgression")
	if mp != null and is_instance_valid(mp):
		if "sigils" in mp:
			mp.sigils = int(meta.get("sigils", int(mp.sigils)))
		if "squad_slots" in mp:
			mp.squad_slots = int(meta.get("squad_slots", int(mp.squad_slots)))
		if "last_run" in mp:
			mp.last_run = meta.get("last_run", mp.last_run) as Dictionary
		if mp.has_method("save"):
			mp.save()

	var cm := get_node_or_null("/root/CollectionManager")
	if cm != null and is_instance_valid(cm):
		if "unlocked" in cm:
			cm.unlocked = coll.get("unlocked", cm.unlocked) as Array
		if "active_roster" in cm:
			cm.active_roster = coll.get("active_roster", cm.active_roster) as Array
		if cm.has_method("save"):
			cm.save()

func _cd_to_dict(cd: CharacterData) -> Dictionary:
	# Keep in sync with CollectionManager serialization.
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


