extends Node

# Runtime VFX routing:
# - Uses exported 2D flipbooks (PNG sequences) generated from EffectBlocks PixelRenderer.
# - Falls back to "do nothing" if an effect isn't exported yet (game still works).
#
# Export convention expected by this system:
#   res://assets/vfx/effectblocks/<effect_key>/<effect_key>_0000.png
#   res://assets/vfx/effectblocks/<effect_key>/<effect_key>_0001.png
#   ...
#
# You can export using: res://PolyBlocks/PixelRenderer/PixelRenderer.tscn

const CFG_PATH := "res://data/vfx_events.json"

var _loaded: bool = false
var _export_root: String = "res://assets/vfx/effectblocks"
var _default_fps: int = 12
var _events: Dictionary = {} # event_id -> {effect_key, fps?, scale?, offset?, tint?, z?}

var _cache_frames: Dictionary = {} # effect_key -> Array[Texture2D]
var _cache_fps: Dictionary = {} # effect_key -> int

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_loaded()

func clear_cache() -> void:
	_cache_frames.clear()
	_cache_fps.clear()

func get_frames_for_key(effect_key: String) -> Array[Texture2D]:
	ensure_loaded()
	return _get_frames(effect_key)

func get_event_cfg(event_id: String) -> Dictionary:
	ensure_loaded()
	return _events.get(event_id, {}) as Dictionary

func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not ResourceLoader.exists(CFG_PATH):
		return
	var txt := FileAccess.get_file_as_string(CFG_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	_export_root = String(d.get("export_root", _export_root))
	_default_fps = int(d.get("default_fps", _default_fps))
	_events = (d.get("events", {}) as Dictionary)

func play_event(event_id: String, pos: Vector2, parent: Node = null, tint: Color = Color(1, 1, 1, 1), scale_mult: float = 1.0) -> bool:
	# Returns true if something was spawned.
	ensure_loaded()
	if event_id == "" or _events.is_empty():
		return false
	if not _events.has(event_id):
		return false

	var ed: Dictionary = _events.get(event_id, {}) as Dictionary
	var effect_key := String(ed.get("effect_key", ""))
	if effect_key == "":
		return false

	var frames := _get_frames(effect_key)
	if frames.is_empty():
		return false

	var fps := int(ed.get("fps", _default_fps))
	_cache_fps[effect_key] = fps

	var scale_cfg := float(ed.get("scale", 1.0))
	var z_cfg := int(ed.get("z", 2000))
	var off: Variant = ed.get("offset", null)
	var offset := Vector2.ZERO
	if typeof(off) == TYPE_ARRAY:
		var a := off as Array
		if a.size() >= 2:
			offset = Vector2(float(a[0]), float(a[1]))
	var tint_cfg: Variant = ed.get("tint", null)
	if typeof(tint_cfg) == TYPE_STRING:
		var c := Color.html(String(tint_cfg))
		tint = tint * c

	var root := parent
	if root == null:
		root = get_tree().get_first_node_in_group("main")
	if root == null or not is_instance_valid(root):
		return false

	var v := VfxFlipbook2D.new()
	root.add_child(v)
	v.global_position = pos + offset
	v.z_index = z_cfg
	v.setup(frames, float(fps), false, tint, scale_mult * scale_cfg)
	return true

func _get_frames(effect_key: String) -> Array[Texture2D]:
	# IMPORTANT: if we previously cached "no frames", re-scan.
	# This allows exporting new flipbooks while the editor/game is open.
	if _cache_frames.has(effect_key):
		var cached := _cache_frames[effect_key] as Array[Texture2D]
		if cached != null and (not cached.is_empty()):
			return cached
	var frames: Array[Texture2D] = []

	var dir_path := "%s/%s" % [_export_root, effect_key]
	var d := DirAccess.open(dir_path)
	if d == null:
		_cache_frames[effect_key] = frames
		return frames

	var want_prefix := effect_key + "_"
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
		if not f.begins_with(want_prefix):
			continue
		files.append(f)
	d.list_dir_end()

	files.sort()
	for f2 in files:
		var p := "%s/%s" % [dir_path, f2]
		var tex := load(p) as Texture2D
		if tex != null:
			frames.append(tex)

	# Guardrail: if export produced fully-transparent frames (common when capture camera isn't current),
	# treat as "not available" so gameplay falls back to old VFX instead of invisible projectiles.
	if not frames.is_empty():
		var img := frames[0].get_image() if frames[0] != null else null
		if img == null or img.get_used_rect().size.x <= 0 or img.get_used_rect().size.y <= 0:
			frames.clear()

	_cache_frames[effect_key] = frames
	return frames


