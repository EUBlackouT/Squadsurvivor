extends Node

# Minimal cross-scene run configuration.
# Keeps the selected map + loads map tuning from JSON (data-driven).

var selected_map_id: String = "graveyard"

var _loaded: bool = false
var _maps_by_id: Dictionary = {}

const MAPS_PATH: String = "res://data/maps.json"
const SAVE_PATH: String = "user://run_config.json"

func _ready() -> void:
	ensure_loaded()
	_load_save()

func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	if not ResourceLoader.exists(MAPS_PATH):
		push_warning("RunConfig: missing %s" % MAPS_PATH)
		return

	var json_text := FileAccess.get_file_as_string(MAPS_PATH)
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("RunConfig: invalid JSON in %s" % MAPS_PATH)
		return

	var root := parsed as Dictionary
	var arr: Array = root.get("maps", [])
	for m in arr:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = m
		var id := String(d.get("id", ""))
		if id == "":
			continue
		_maps_by_id[id] = d

func get_map_ids() -> Array[String]:
	ensure_loaded()
	var ids: Array[String] = []
	for k in _maps_by_id.keys():
		ids.append(String(k))
	ids.sort()
	return ids

func get_map(map_id: String) -> Dictionary:
	ensure_loaded()
	if _maps_by_id.has(map_id):
		return _maps_by_id[map_id] as Dictionary
	# Fallback to first available map
	for k in _maps_by_id.keys():
		return _maps_by_id[k] as Dictionary
	return {}

func get_selected_map() -> Dictionary:
	return get_map(selected_map_id)

func set_selected_map_id(map_id: String) -> void:
	ensure_loaded()
	if _maps_by_id.has(map_id):
		selected_map_id = map_id
		_save()

func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d := parsed as Dictionary
	var mid := String(d.get("selected_map_id", selected_map_id))
	if _maps_by_id.has(mid):
		selected_map_id = mid

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"selected_map_id": selected_map_id}))
	f.close()



