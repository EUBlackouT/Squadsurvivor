extends Node

# Persistent meta progression (hard goals).
# Saved to: user://meta.json

const SAVE_PATH := "user://meta.json"
const SAVE_VERSION := 1

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

# Meta skill tree (global Protocol Grid)
var meta_nodes_owned: PackedStringArray = PackedStringArray(["core_0"])
var _tree_cache: Dictionary = {}
var _mods_cache: Dictionary = {}
var _mods_dirty: bool = true

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

func owns_node(id: String) -> bool:
	return meta_nodes_owned.has(id)

func can_buy_node(id: String) -> bool:
	_load_tree()
	if id == "" or owns_node(id):
		return false
	var nodes: Array = _tree_cache.get("nodes", [])
	var node: Dictionary = {}
	for n in nodes:
		if typeof(n) == TYPE_DICTIONARY and String((n as Dictionary).get("id", "")) == id:
			node = n as Dictionary
			break
	if node.is_empty():
		return false
	var cost := int(node.get("cost", 0))
	if sigils < cost:
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
	for n in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var d := n as Dictionary
		var id := String(d.get("id", ""))
		if not owns_node(id):
			continue
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
	_mods_dirty = false

func get_squad_slots() -> int:
	return clampi(squad_slots, 3, max_squad_slots_cap)

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

func set_last_run(summary: Dictionary) -> void:
	last_run = summary
	save()

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		sigils = 0
		squad_slots = 3
		last_run = {}
		meta_nodes_owned = PackedStringArray(["core_0"])
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
	var owned: Array = d.get("meta_nodes_owned", [])
	var out := PackedStringArray()
	for e in owned:
		out.append(String(e))
	if not out.has("core_0"):
		out.append("core_0")
	meta_nodes_owned = out
	_mods_dirty = true

func save() -> void:
	var root := {
		"version": SAVE_VERSION,
		"sigils": sigils,
		"squad_slots": squad_slots,
		"last_run": last_run,
		"meta_nodes_owned": Array(meta_nodes_owned)
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("MetaProgression: failed to open save for write")
		return
	f.store_string(JSON.stringify(root))
