class_name PixellabUtil
extends Node

# Runtime helpers for PixelLab character assets (registry + walk frames).
#
# Registry: res://data/pixellab_registry.json
# Assets:   res://assets/pixellab/<id>/animations/walking-8-frames/walking-8-frames/<dir>/frame_000.png
#
# Caches keep hot paths from re-loading textures every spawn.

var _loaded: bool = false
var _entries: Array[Dictionary] = []
var _walk_frames_cache: Dictionary = {} # id -> SpriteFrames
var _rotation_tex_cache: Dictionary = {} # path -> Texture2D

static func _singleton(tree: SceneTree) -> PixellabUtil:
	var n := tree.get_first_node_in_group("__pixellab_util") as PixellabUtil
	if n != null and is_instance_valid(n):
		return n
	var u := PixellabUtil.new()
	u.name = "PixellabUtil"
	u.add_to_group("__pixellab_util")
	tree.root.add_child(u)
	return u

func ensure_loaded() -> void:
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

func entry_count() -> int:
	ensure_loaded()
	return _entries.size()

func all_south_paths() -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	for e in _entries:
		out.append(String(e.get("south_path", "")))
	return out

func pick_random_south_path(rng: RandomNumberGenerator) -> String:
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

func pixellab_id_from_south_path(south_path: String) -> String:
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

func load_rotation_texture(path: String) -> Texture2D:
	if _rotation_tex_cache.has(path):
		return _rotation_tex_cache[path] as Texture2D
	if path == "" or not ResourceLoader.exists(path):
		return null
	var t := load(path) as Texture2D
	_rotation_tex_cache[path] = t
	return t

func walk_frames_from_south_path(south_path: String) -> SpriteFrames:
	ensure_loaded()
	var pid := pixellab_id_from_south_path(south_path)
	if pid == "":
		return null
	if _walk_frames_cache.has(pid):
		return _walk_frames_cache[pid] as SpriteFrames
	var frames := _build_walk_frames(pid)
	_walk_frames_cache[pid] = frames
	return frames

func _build_walk_frames(pid: String) -> SpriteFrames:
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


