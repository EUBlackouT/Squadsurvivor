class_name PixellabUtil
extends Node

# Runtime helpers for PixelLab character assets (registry + walk frames).
#
# Registry: res://data/pixellab_registry.json
# Assets:   res://assets/pixellab/<id>/animations/walking-8-frames/walking-8-frames/<dir>/frame_000.png
#
# Caches keep hot paths from re-loading textures every spawn.

static var _loaded: bool = false
static var _entries: Array[Dictionary] = []
static var _walk_frames_cache: Dictionary = {} # id -> SpriteFrames
static var _rotation_tex_cache: Dictionary = {} # path -> Texture2D

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var reg_path := "res://data/pixellab_registry.json"
	if not ResourceLoader.exists(reg_path):
		push_warning("PixellabUtil: missing registry at %s" % reg_path)
		return
	var json_text := FileAccess.get_file_as_string(reg_path)
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PixellabUtil: registry JSON invalid")
		return
	var d: Dictionary = parsed
	var raw: Array = d.get("entries", [])
	_entries.clear()
	for e in raw:
		if typeof(e) == TYPE_DICTIONARY:
			_entries.append(e)

static func entry_count() -> int:
	ensure_loaded()
	return _entries.size()

static func all_south_paths() -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	for e in _entries:
		out.append(String(e.get("south_path", "")))
	return out

static func pick_random_south_path(rng: RandomNumberGenerator) -> String:
	ensure_loaded()
	if _entries.is_empty():
		return ""
	# Weighted pick (default weight=1)
	var total: int = 0
	for e in _entries:
		total += int(e.get("weight", 1))
	var roll := rng.randi_range(1, max(1, total))
	var acc: int = 0
	for e in _entries:
		acc += int(e.get("weight", 1))
		if roll <= acc:
			return String(e.get("south_path", ""))
	return String(_entries[0].get("south_path", ""))

static func entry_from_south_path(south_path: String) -> Dictionary:
	ensure_loaded()
	for e in _entries:
		if String(e.get("south_path", "")) == south_path:
			return e
	return {}

static func entry_from_id(pid: String) -> Dictionary:
	ensure_loaded()
	for e in _entries:
		if String(e.get("id", "")) == pid:
			return e
	return {}

static func origin_hint_from_south_path(south_path: String) -> int:
	# Best-effort mapping based on optional registry metadata.
	# If your registry entries include "origin": "<undead|machine|beast|demon|elemental|human>", we will use it.
	var e := entry_from_south_path(south_path)
	var o := String(e.get("origin", ""))
	if o == "":
		# Also allow tags array like ["undead", "demon"]
		var tags: Array = e.get("tags", [])
		for t in tags:
			var s := String(t).to_lower()
			if s in ["undead", "machine", "beast", "demon", "elemental", "human"]:
				o = s
				break
	match o.to_lower():
		"undead":
			return CharacterData.Origin.UNDEAD
		"machine":
			return CharacterData.Origin.MACHINE
		"beast":
			return CharacterData.Origin.BEAST
		"demon":
			return CharacterData.Origin.DEMON
		"elemental":
			return CharacterData.Origin.ELEMENTAL
		"human":
			return CharacterData.Origin.HUMAN
		_:
			return -1

static func pixellab_id_from_south_path(south_path: String) -> String:
	# Expected: res://assets/pixellab/<id>/rotations/south.png
	var parts := south_path.split("/", false)
	var idx := parts.find("pixellab")
	if idx >= 0 and idx + 1 < parts.size():
		return parts[idx + 1]
	# fallback: try uuid-ish segment
	for p in parts:
		if p.length() >= 30 and p.count("-") >= 3:
			return p
	return ""

static func load_rotation_texture(path: String) -> Texture2D:
	if _rotation_tex_cache.has(path):
		return _rotation_tex_cache[path] as Texture2D
	if path == "" or not ResourceLoader.exists(path):
		return null
	var t := load(path) as Texture2D
	_rotation_tex_cache[path] = t
	return t

static func walk_frames_from_south_path(south_path: String) -> SpriteFrames:
	ensure_loaded()
	var pid := pixellab_id_from_south_path(south_path)
	if pid == "":
		return null
	if _walk_frames_cache.has(pid):
		return _walk_frames_cache[pid] as SpriteFrames
	var frames := _build_walk_frames(pid)
	_walk_frames_cache[pid] = frames
	return frames

static func _build_walk_frames(pid: String) -> SpriteFrames:
	var base := "res://assets/pixellab/%s/animations/walking-8-frames/walking-8-frames" % pid
	var dirs := {
		"walk_south": "south",
		"walk_north": "north",
		"walk_east": "east",
		"walk_west": "west"
	}
	var sf := SpriteFrames.new()
	for anim_name in dirs.keys():
		var d := String(dirs[anim_name])
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, 8.0)
		sf.set_animation_loop(anim_name, true)
		for i in range(8):
			var p := "%s/%s/frame_%03d.png" % [base, d, i]
			if ResourceLoader.exists(p):
				var tex := load(p) as Texture2D
				if tex != null:
					sf.add_frame(anim_name, tex)
		# If missing, fallback to rotations (still non-crashing)
		if sf.get_frame_count(anim_name) <= 0:
			var rot := "res://assets/pixellab/%s/rotations/%s.png" % [pid, d]
			var t := load_rotation_texture(rot)
			if t != null:
				sf.add_frame(anim_name, t)
	return sf


