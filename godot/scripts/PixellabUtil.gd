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
	if _is_custom_character_path(south_path):
		return _custom_walk_frames_from_south_path(south_path)
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

	# Some Pixellab exports are missing certain directions (common: no east or no south).
	# We salvage walking by borrowing the closest available direction folder, and optionally
	# mirroring west<->east at runtime (via AnimatedSprite2D.flip_h).
	#
	# We encode these decisions as meta on the SpriteFrames so gameplay code can apply flip safely:
	# - flip_h_for_walk_east: bool
	# - flip_h_for_walk_west: bool
	# - src_dir_walk_*: String (e.g. "west", "south-west")
	sf.set_meta("flip_h_for_walk_east", false)
	sf.set_meta("flip_h_for_walk_west", false)

	for anim_name in dirs.keys():
		var d := String(dirs[anim_name])
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, 8.0)
		sf.set_animation_loop(anim_name, true)
		var chosen_dir := _pick_best_walk_dir(pid, base, d)
		sf.set_meta("src_dir_%s" % anim_name, chosen_dir)

		# Load frames from the chosen direction folder (if any).
		if chosen_dir != "":
			for i in range(8):
				var p := "%s/%s/frame_%03d.png" % [base, chosen_dir, i]
				if ResourceLoader.exists(p):
					var tex := load(p) as Texture2D
					if tex != null:
						sf.add_frame(anim_name, tex)

		# If we had to borrow west for east (or vice versa), flag a flip request.
		if anim_name == "walk_east" and chosen_dir == "west" and d != "west":
			sf.set_meta("flip_h_for_walk_east", true)
		if anim_name == "walk_west" and chosen_dir == "east" and d != "east":
			sf.set_meta("flip_h_for_walk_west", true)

		# If missing entirely, fallback to rotations (still non-crashing, but static).
		if sf.get_frame_count(anim_name) <= 0:
			var rot := "res://assets/pixellab/%s/rotations/%s.png" % [pid, d]
			var t := load_rotation_texture(rot)
			if t != null:
				sf.add_frame(anim_name, t)
	return sf

static func _pick_best_walk_dir(pid: String, base: String, desired_dir: String) -> String:
	# Prefer the exact desired folder.
	if _walk_dir_has_frames(base, desired_dir):
		return desired_dir

	# Fallback search order per direction. Keep this conservative: if we have any real walking
	# frames, use them rather than dropping to static rotations.
	var candidates: Array[String] = []
	match desired_dir:
		"south":
			candidates = ["south-west", "south-east", "west", "east", "north", "north-west", "north-east"]
		"north":
			candidates = ["north-west", "north-east", "west", "east", "south", "south-west", "south-east"]
		"east":
			candidates = ["south-east", "north-east", "west", "south", "north", "south-west", "north-west"]
		"west":
			candidates = ["south-west", "north-west", "east", "south", "north", "south-east", "north-east"]
		_:
			candidates = ["south", "west", "east", "north"]

	for c in candidates:
		if _walk_dir_has_frames(base, c):
			return c

	# No walking animation dirs found.
	return ""

static func _walk_dir_has_frames(base: String, dir_name: String) -> bool:
	if dir_name == "":
		return false
	# Check just frame_000 for speed.
	var p := "%s/%s/frame_000.png" % [base, dir_name]
	return ResourceLoader.exists(p)

static func _is_custom_character_path(south_path: String) -> bool:
	return south_path.find("/assets/characters/") >= 0

static func _custom_walk_frames_from_south_path(south_path: String) -> SpriteFrames:
	var root := _custom_root_from_south_path(south_path)
	if root == "":
		return null
	var cache_key := "custom:%s" % root
	if _walk_frames_cache.has(cache_key):
		return _walk_frames_cache[cache_key] as SpriteFrames
	var frames := _build_custom_walk_frames(root)
	_walk_frames_cache[cache_key] = frames
	return frames

static func _custom_root_from_south_path(south_path: String) -> String:
	var marker := "/assets/characters/"
	var idx := south_path.find(marker)
	if idx < 0:
		return ""
	var rest := south_path.substr(idx + marker.length())
	var parts := rest.split("/frames/")
	if parts.is_empty():
		return ""
	var rel := String(parts[0])
	if rel == "":
		return ""
	return "res://assets/characters/%s" % rel

static func _build_custom_walk_frames(root: String) -> SpriteFrames:
	var base := "%s/frames" % root
	var has_side := _custom_dir_has_frames(base, "walk_side")
	var has_side_right := _custom_dir_has_frames(base, "walk_side_right")
	# Ludo exports are frequently authored with side naming opposite of gameplay
	# screen direction. Prefer the swapped mapping so movement and facing match.
	var east_dir := "walk_side" if has_side else (("walk_side_right" if has_side_right else "walk_side"))
	var west_dir := "walk_side_right" if has_side_right else "walk_side"
	var sf := SpriteFrames.new()
	# If we only have one side direction, flip the opposite side.
	sf.set_meta("flip_h_for_walk_east", has_side_right and (not has_side))
	sf.set_meta("flip_h_for_walk_west", has_side and (not has_side_right))

	var dirs := {
		"walk_south": "walk_front",
		"walk_north": "walk_back",
		"walk_east": east_dir,
		"walk_west": west_dir
	}

	for anim_name in dirs.keys():
		var d := String(dirs[anim_name])
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, 12.0)
		sf.set_animation_loop(anim_name, true)
		var frames := _custom_load_frames("%s/%s" % [base, d])
		for tex in frames:
			sf.add_frame(anim_name, tex)
	return sf

static func _custom_dir_has_frames(base: String, dir_name: String) -> bool:
	var p := "%s/%s/frame_000.png" % [base, dir_name]
	return ResourceLoader.exists(p)

static func _custom_load_frames(dir_path: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	var files: Array[String] = []
	d.list_dir_begin()
	while true:
		var f := d.get_next()
		if f == "":
			break
		if d.current_is_dir():
			continue
		if not f.to_lower().ends_with(".png"):
			continue
		if not f.begins_with("frame_"):
			continue
		files.append(f)
	d.list_dir_end()
	files.sort()
	for f2 in files:
		var p := "%s/%s" % [dir_path, f2]
		var tex := load(p) as Texture2D
		if tex != null:
			out.append(tex)
	return out

static func max_frame_size(frames: SpriteFrames, anim_hint: String = "walk_south") -> Vector2:
	if frames == null:
		return Vector2.ZERO
	var max_w := 0.0
	var max_h := 0.0
	var anims := frames.get_animation_names()
	if anims.has(anim_hint):
		anims = [anim_hint]
	for a in anims:
		var anim_name := String(a)
		var count := frames.get_frame_count(anim_name)
		for i in range(count):
			var tex := frames.get_frame_texture(anim_name, i)
			if tex == null:
				continue
			var sz := tex.get_size()
			if sz.x > max_w:
				max_w = sz.x
			if sz.y > max_h:
				max_h = sz.y
	return Vector2(max_w, max_h)

static func scale_for_target_height(frames: SpriteFrames, target_height: float, min_scale: float = 0.5, max_scale: float = 0.95) -> float:
	if frames == null:
		return 1.0
	var sz := max_frame_size(frames)
	if sz.y <= 0.001:
		return 1.0
	var scale := target_height / sz.y
	return clampf(scale, min_scale, max_scale)


