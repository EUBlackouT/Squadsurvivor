extends Node

# Persistent meta progression (hard goals).
# Saved to: user://meta.json

const SAVE_PATH := "user://meta.json"
const DEBUG_BACKUP_PATH := "user://meta_debug_backup.json"
const SAVE_VERSION := 1
const MAP_TIER_FALLBACK_BY_ID := {
	"graveyard": 1,
	"church": 1,
	"library": 2,
	"foundry": 3,
	"cathedral": 4
}

@export var max_squad_slots_cap: int = 8
@export var max_roster_cap: int = 18

# Meta currency (earned from runs)
var sigils: int = 0

# Starts at 3. Increases via unlocks.
var squad_slots: int = 3

# Hard curve: intentionally grindy.
const SLOT_COSTS: Array[int] = [500, 1500, 4000, 9000, 17000] # for slots 4..8

# Last run summary for UI (menu + end screen)
var last_run: Dictionary = {}

# Map progression gates (unlocked map ids).
var map_unlocks: PackedStringArray = PackedStringArray(["graveyard"])

# Meta skill tree (global Protocol Grid)
var meta_nodes_owned: PackedStringArray = PackedStringArray(["core_0"])
var _tree_cache: Dictionary = {}
var _mods_cache: Dictionary = {}
var _mods_dirty: bool = true

const KEYSTONE_POWER_SPIKES := {
	"storm_closed_circuit": {"chain_jumps_add": 2.0, "chain_rehit_damage_mult": 1.35, "weapon_keystone_nova_hits_add": 2.0},
	"bomb_delayed_catastrophe": {"bomb_damage_mult": 1.35, "bomb_radius_add": 26.0, "weapon_keystone_vfx_scale_add": 0.16},
	"beam_surgical_continuity": {"beam_damage_ramp_per_second_add": 0.20, "beam_damage_ramp_cap": 1.18, "weapon_keystone_vfx_scale_add": 0.12},
	"orbital_judgment_delay": {"orbital_damage_mult": 1.45, "orbital_delay_mult": 0.84, "weapon_keystone_vfx_scale_add": 0.22},
	"butcher_protocol": {"execute_blast_damage_mult": 1.35, "execute_blast_radius_add": 90.0, "weapon_keystone_nova_damage_mult_add": 0.18},
	"rico_violence_geometry": {"post_ricochet_projectile_damage_mult": 1.22, "ricochet_count_add": 1.0, "weapon_keystone_nova_hits_add": 1.0},
	"pierce_execution_line": {"projectile_pierce_add": 1.0, "execute_threshold_add": 0.02, "weapon_keystone_nova_radius_add": 30.0},
	"scatter_shotgun_saint": {"projectile_count_add": 2.0, "projectile_damage_mult": 1.18, "weapon_keystone_vfx_scale_add": 0.10},
	"proj_converging_fire": {"projectile_damage_mult": 1.20, "projectile_pierce_add": 1.0, "weapon_keystone_nova_damage_mult_add": 0.10}
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_save()

func _load_tree() -> void:
	if not _tree_cache.is_empty():
		return
	var path := "res://data/meta_tree.json"
	if not ResourceLoader.exists(path):
		_tree_cache = {}
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_tree_cache = {}
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_tree_cache = {}
		return
	_tree_cache = parsed as Dictionary

func tree_data() -> Dictionary:
	_load_tree()
	return _tree_cache

func _find_node_by_id(id: String) -> Dictionary:
	_load_tree()
	if id == "":
		return {}
	var nodes: Array = _tree_cache.get("nodes", [])
	for n in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var d := n as Dictionary
		if String(d.get("id", "")) == id:
			return d
	return {}

func _node_map_tier_req(node: Dictionary) -> int:
	if node.has("map_tier_req"):
		return maxi(1, int(node.get("map_tier_req", 1)))
	var cost := int(node.get("cost", 0))
	var tags: Array = node.get("tags", []) as Array
	var is_keystone := false
	for t in tags:
		if String(t) == "keystone":
			is_keystone = true
			break
	if is_keystone:
		if cost >= 4600:
			return 4
		if cost >= 3300:
			return 3
		return 2
	if cost >= 4200:
		return 3
	if cost >= 2800:
		return 2
	return 1

func get_map_tier(map_id: String) -> int:
	var mid := map_id.strip_edges().to_lower()
	if mid == "":
		return 1
	var rc := get_node_or_null("/root/RunConfig")
	if rc != null and is_instance_valid(rc) and rc.has_method("get_map"):
		var md: Dictionary = rc.get_map(mid) as Dictionary
		if not md.is_empty():
			var mt := int(md.get("tier", 0))
			if mt > 0:
				return mt
	if MAP_TIER_FALLBACK_BY_ID.has(mid):
		return int(MAP_TIER_FALLBACK_BY_ID[mid])
	return 1

func get_highest_unlocked_map_tier() -> int:
	var highest := 1
	if map_unlocks.is_empty():
		return highest
	for mid in map_unlocks:
		highest = maxi(highest, get_map_tier(String(mid)))
	return highest

func get_node_unlock_requirements(id: String) -> Dictionary:
	var node := _find_node_by_id(id)
	if node.is_empty():
		return {}
	var req_tier := _node_map_tier_req(node)
	var cur_tier := get_highest_unlocked_map_tier()
	return {
		"required_map_tier": req_tier,
		"current_map_tier": cur_tier,
		"map_tier_blocked": cur_tier < req_tier
	}

func owns_node(id: String) -> bool:
	return meta_nodes_owned.has(id)

func can_buy_node(id: String) -> bool:
	_load_tree()
	if id == "" or owns_node(id):
		return false
	var node := _find_node_by_id(id)
	if node.is_empty():
		return false
	var cost := int(node.get("cost", 0))
	if sigils < cost:
		return false
	var req_tier := _node_map_tier_req(node)
	var cur_tier := get_highest_unlocked_map_tier()
	if cur_tier < req_tier:
		return false
	var prereq: Array = node.get("prereq", [])
	for p in prereq:
		if not owns_node(String(p)):
			return false
	return true

func buy_node(id: String) -> bool:
	if not can_buy_node(id):
		return false
	var nodes: Array = _tree_cache.get("nodes", [])
	for n in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var d := n as Dictionary
		if String(d.get("id", "")) != id:
			continue
		var cost := int(d.get("cost", 0))
		if sigils < cost:
			return false
		sigils -= cost
		meta_nodes_owned.append(id)
		_mods_dirty = true
		save()
		return true
	return false

func refund_node(id: String) -> bool:
	# Simple refund: only allow if nothing depends on it.
	if id == "core_0":
		return false
	if not owns_node(id):
		return false
	_load_tree()
	var nodes: Array = _tree_cache.get("nodes", [])
	# Block refund if any owned node lists this as prereq.
	for n in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var d := n as Dictionary
		var nid := String(d.get("id", ""))
		if not owns_node(nid):
			continue
		var prereq: Array = d.get("prereq", [])
		for p in prereq:
			if String(p) == id:
				return false
	# Refund cost fully (tunable later).
	for n2 in nodes:
		if typeof(n2) != TYPE_DICTIONARY:
			continue
		var d2 := n2 as Dictionary
		if String(d2.get("id", "")) == id:
			sigils += int(d2.get("cost", 0))
			break
	meta_nodes_owned.remove_at(meta_nodes_owned.find(id))
	_mods_dirty = true
	save()
	return true

func mods() -> Dictionary:
	if _mods_dirty:
		_rebuild_mods()
	return _mods_cache

func get_mod(key: String, default_value: float = 1.0) -> float:
	var m := mods()
	if not m.has(key):
		return default_value
	return float(m.get(key, default_value))

func get_add(key: String, default_value: float = 0.0) -> float:
	var m := mods()
	if not m.has(key):
		return default_value
	return float(m.get(key, default_value))

func _rebuild_mods() -> void:
	_load_tree()
	_mods_cache = {}
	var nodes: Array = _tree_cache.get("nodes", [])
	var owned_keystones := PackedStringArray()
	for n in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var d := n as Dictionary
		var id := String(d.get("id", ""))
		if not owns_node(id):
			continue
		var tags: Array = d.get("tags", []) as Array
		if tags.has("keystone"):
			owned_keystones.append(id)
		var mods_d: Dictionary = d.get("mods", {}) as Dictionary
		for k in mods_d.keys():
			var key := String(k)
			# Convention:
			# - keys ending with _mult multiply (default 1.0)
			# - others add (default 0.0) (e.g. lockout seconds)
			if key.ends_with("_mult"):
				var cur := float(_mods_cache.get(key, 1.0))
				var v_mult: float = float(mods_d.get(k, 1.0))
				_mods_cache[key] = cur * v_mult
			else:
				var cur2 := float(_mods_cache.get(key, 0.0))
				var v_add: float = float(mods_d.get(k, 0.0))
				_mods_cache[key] = cur2 + v_add
	_apply_keystone_power_curve(owned_keystones)
	_mods_dirty = false

func _add_mod(key: String, amount: float) -> void:
	_mods_cache[key] = float(_mods_cache.get(key, 0.0)) + amount

func _mul_mod(key: String, mult: float) -> void:
	_mods_cache[key] = float(_mods_cache.get(key, 1.0)) * mult

func _apply_keystone_power_curve(owned_keystones: PackedStringArray) -> void:
	var kc := owned_keystones.size()
	if kc <= 0:
		return
	# Baseline power curve: each keystone should feel like a direct power stride,
	# not only an occasional proc spike.
	_mul_mod("squad_damage_mult", pow(1.045, kc))
	_mul_mod("squad_attack_speed_mult", pow(1.020, kc))
	_mul_mod("projectile_damage_mult", pow(1.032, kc))
	_mul_mod("bomb_damage_mult", pow(1.026, kc))
	_mul_mod("orbital_damage_mult", pow(1.030, kc))
	_mul_mod("beam_initial_damage_mult", pow(1.026, kc))
	_mul_mod("post_ricochet_projectile_damage_mult", pow(1.020, kc))
	_add_mod("weapon_keystone_tier", float(kc))
	_add_mod("weapon_keystone_vfx_scale_add", minf(1.25, 0.08 * float(kc)))
	_add_mod("weapon_keystone_nova_damage_mult_add", minf(1.10, 0.07 * float(kc)))
	_add_mod("weapon_keystone_nova_radius_add", 24.0 + 7.0 * float(kc))
	_add_mod("weapon_keystone_nova_hits_add", minf(10.0, 2.0 + floorf(float(kc) * 0.5)))
	_add_mod("weapon_keystone_nova_interval_sub", minf(6.0, floorf(float(kc) * 0.45)))

	# Keystone identity spikes: major archetype keystones unlock bigger
	# "Vampire Survivors" style milestones.
	for kid in owned_keystones:
		var spike := KEYSTONE_POWER_SPIKES.get(String(kid), {}) as Dictionary
		if spike.is_empty():
			continue
		for k in spike.keys():
			var key := String(k)
			var v := float(spike.get(key, 0.0))
			if key.ends_with("_mult"):
				_mul_mod(key, v)
			else:
				_add_mod(key, v)

func get_squad_slots() -> int:
	var base := clampi(squad_slots, 3, max_squad_slots_cap)
	# Add starting squad bonus from Protocol Grid
	var bonus := int(get_add("starting_squad_add", 0.0))
	return clampi(base + bonus, 3, max_squad_slots_cap)

func get_roster_cap() -> int:
	# Let players prep more than active squad.
	# Starts 6, grows by +2 per slot unlock: 3->6, 4->8, 5->10, 6->12, 7->14, 8->16.
	var slots: int = get_squad_slots()
	var extra: int = maxi(0, (slots - 3)) * 2
	var cap: int = 6 + extra
	return clampi(cap, 6, max_roster_cap)

func get_next_slot_cost() -> int:
	var cur := get_squad_slots()
	if cur >= max_squad_slots_cap:
		return -1
	var idx := cur - 3 # slot4->1st cost
	if idx < 0 or idx >= SLOT_COSTS.size():
		return -1
	return int(SLOT_COSTS[idx])

func can_unlock_next_slot() -> bool:
	var cost := get_next_slot_cost()
	return cost > 0 and sigils >= cost

func unlock_next_slot() -> bool:
	var cur := get_squad_slots()
	if cur >= max_squad_slots_cap:
		return false
	var cost := get_next_slot_cost()
	if cost <= 0 or sigils < cost:
		return false
	sigils -= cost
	squad_slots = cur + 1
	save()
	return true

func add_sigils(amount: int) -> void:
	if amount <= 0:
		return
	sigils += amount
	save()

# Wrapper methods for Protocol Grid UI
func get_sigils() -> int:
	return sigils

func spend_sigils(amount: int) -> bool:
	if amount <= 0 or sigils < amount:
		return false
	sigils -= amount
	save()
	return true

func get_unlocked_upgrades() -> Array:
	return Array(meta_nodes_owned)

func unlock_upgrade(id: String) -> void:
	if not meta_nodes_owned.has(id):
		meta_nodes_owned.append(id)
		_mods_dirty = true
		save()

func set_last_run(summary: Dictionary) -> void:
	last_run = summary
	save()

func is_map_unlocked(map_id: String) -> bool:
	if map_id == "":
		return false
	if map_unlocks.is_empty():
		map_unlocks = PackedStringArray(["graveyard"])
	return map_unlocks.has(map_id)

func unlock_map(map_id: String) -> void:
	if map_id == "":
		return
	if map_unlocks.is_empty():
		map_unlocks = PackedStringArray(["graveyard"])
	if not map_unlocks.has(map_id):
		map_unlocks.append(map_id)
		save()

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		sigils = 0
		squad_slots = 3
		last_run = {}
		meta_nodes_owned = PackedStringArray(["core_0"])
		map_unlocks = PackedStringArray(["graveyard"])
		_mods_dirty = true
		save()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	sigils = int(d.get("sigils", 0))
	squad_slots = int(d.get("squad_slots", 3))
	last_run = d.get("last_run", {}) as Dictionary
	var mu: Array = d.get("map_unlocks", ["graveyard"])
	var mu_out := PackedStringArray()
	for e in mu:
		mu_out.append(String(e))
	if not mu_out.has("graveyard"):
		mu_out.append("graveyard")
	map_unlocks = mu_out
	var owned: Array = d.get("meta_nodes_owned", [])
	var out := PackedStringArray()
	for e in owned:
		out.append(String(e))
	if not out.has("core_0"):
		out.append("core_0")
	meta_nodes_owned = out
	_sanitize_debug_profile()
	_mods_dirty = true

func _sanitize_debug_profile() -> void:
	# Guardrail: if a debug/test profile leaked into normal play, reset to natural progression.
	# Thresholds are intentionally very high to avoid touching legitimate saves.
	var suspicious_sigils := sigils >= 5_000_000
	var suspicious_nodes := meta_nodes_owned.size() >= 120
	if not (suspicious_sigils or suspicious_nodes):
		return
	# Best-effort backup for recovery if this was intentional.
	var backup := {
		"version": SAVE_VERSION,
		"sigils": sigils,
		"squad_slots": squad_slots,
		"last_run": last_run,
		"map_unlocks": Array(map_unlocks),
		"meta_nodes_owned": Array(meta_nodes_owned)
	}
	var fb := FileAccess.open(DEBUG_BACKUP_PATH, FileAccess.WRITE)
	if fb != null:
		fb.store_string(JSON.stringify(backup))
		fb.close()
	sigils = 0
	squad_slots = 3
	last_run = {}
	map_unlocks = PackedStringArray(["graveyard"])
	meta_nodes_owned = PackedStringArray(["core_0"])
	_mods_dirty = true
	save()
	print("META_SANITY_RESET applied=true backup=%s" % DEBUG_BACKUP_PATH)

func save() -> void:
	var root := {
		"version": SAVE_VERSION,
		"sigils": sigils,
		"squad_slots": squad_slots,
		"last_run": last_run,
		"map_unlocks": Array(map_unlocks),
		"meta_nodes_owned": Array(meta_nodes_owned)
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("MetaProgression: failed to open save for write")
		return
	f.store_string(JSON.stringify(root))
