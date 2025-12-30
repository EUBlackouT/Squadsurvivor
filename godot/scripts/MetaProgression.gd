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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_save()

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

func save() -> void:
	var root := {
		"version": SAVE_VERSION,
		"sigils": sigils,
		"squad_slots": squad_slots,
		"last_run": last_run
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("MetaProgression: failed to open save for write")
		return
	f.store_string(JSON.stringify(root))
