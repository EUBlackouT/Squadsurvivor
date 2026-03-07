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
var _events: Dictionary = {} # event_id -> {effect_key?, scene_3d?, fps?, scale?, offset?, tint?, z?, loop?, duration_s?, viewport_size?, ortho_size?, cam_pos?, cam_target?, cam_up?, force_emit?, pixel_material?, pixel_target_px?}

var _cache_frames: Dictionary = {} # effect_key -> Array[Texture2D]
var _cache_fps: Dictionary = {} # effect_key -> int
var _cache_scene3d: Dictionary = {} # path -> PackedScene

# Debugging helpers (opt-in; avoids spamming normal play).
var debug_toasts_enabled: bool = false
var _debug_last_ms: Dictionary = {} # event_id -> int
var _warned_missing_third_party: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_loaded()
	_warn_if_missing_third_party_assets()

func _warn_if_missing_third_party_assets() -> void:
	# These are intentionally not tracked in git (.gitignore). If they disappear (e.g. after a clean),
	# we want a loud signal instead of "VFX silently missing".
	if _warned_missing_third_party:
		return
	_warned_missing_third_party = true

	var missing: Array[String] = []

	# 3D pack (used by some scene_3d VFX like syn.holy).
	if not ResourceLoader.exists("res://PolyBlocks/PixelRenderer/PixelRenderer.tscn"):
		missing.append("res://PolyBlocks/ (third-party pack folder missing)")

	# Exported flipbooks (used by effect_key VFX).
	var export_dir_ok := (DirAccess.open(_export_root) != null)
	if not export_dir_ok:
		missing.append(_export_root + " (exported flipbooks folder missing)")

	if missing.is_empty():
		return

	var msg := "Missing local third-party VFX assets:\n- " + "\n- ".join(missing) + "\n\nThese folders are intentionally not committed to git; re-copy/re-extract them locally."
	push_warning(msg)

	# Try to surface it in-game if we can find the ToastLayer.
	var main_node: Node = get_tree().get_first_node_in_group("main") as Node
	if main_node != null and is_instance_valid(main_node):
		var tl_obj: Variant = main_node.get("toast_layer")
		var tl: ToastLayer = tl_obj as ToastLayer
		if tl != null and is_instance_valid(tl):
			tl.show_toast("Missing local VFX assets (see console warning)", Color(1.0, 0.5, 0.4, 1.0))

func set_debug_toasts_enabled(enabled: bool) -> void:
	debug_toasts_enabled = enabled

func clear_cache() -> void:
	_cache_frames.clear()
	_cache_fps.clear()
	_cache_scene3d.clear()

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
		push_warning("VfxSystem: missing config at %s" % CFG_PATH)
		return
	var txt := FileAccess.get_file_as_string(CFG_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		# If vfx_events.json is invalid (e.g., contains comments), everything will silently fall back.
		push_warning("VfxSystem: failed to parse %s (expected JSON object). First chars: %s" % [CFG_PATH, txt.substr(0, 120)])
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
	# Debug: show which configured source we actually use (helps catch "wrong label" confusion).
	# Rate-limited and disabled by default.
	if debug_toasts_enabled and (event_id == "syn.holy" or event_id == "syn.flame"):
		var now_ms: int = int(Time.get_ticks_msec())
		var last_ms: int = int(_debug_last_ms.get(event_id, 0))
		if last_ms == 0 or (now_ms - last_ms) > 250:
			_debug_last_ms[event_id] = now_ms
			var main_node: Node = get_tree().get_first_node_in_group("main") as Node
			if main_node != null and is_instance_valid(main_node):
				var tl_obj: Variant = main_node.get("toast_layer")
				var tl: ToastLayer = tl_obj as ToastLayer
				if tl != null and is_instance_valid(tl):
					var src: String = ""
					var scene_path: String = String(ed.get("scene_3d", ""))
					if scene_path != "":
						src = "scene_3d: " + scene_path
					else:
						src = "effect_key: " + String(ed.get("effect_key", ""))
					tl.show_toast("VFX " + event_id + " → " + src, Color(0.65, 0.85, 1.0, 1.0))

	# If configured with a 3D scene, render it live via SubViewport -> Sprite2D (no baking).
	var scene3d_path := String(ed.get("scene_3d", ""))
	if scene3d_path != "":
		var root3 := parent
		if root3 == null:
			root3 = get_tree().get_first_node_in_group("main")
		if root3 == null or not is_instance_valid(root3):
			return false

		var ps := _load_scene3d(scene3d_path)
		if ps == null:
			return false

		var v3 := VfxViewport3D2D.new()
		(root3 as Node).add_child(v3)

		var z_cfg := int(ed.get("z", 2000))
		var scale_cfg := float(ed.get("scale", 1.0))
		var off: Variant = ed.get("offset", null)
		var offset := Vector2.ZERO
		if typeof(off) == TYPE_ARRAY:
			var a := off as Array
			if a.size() >= 2:
				offset = Vector2(float(a[0]), float(a[1]))
		v3.global_position = pos + offset
		v3.z_index = z_cfg
		v3.scale = Vector2.ONE * (scale_mult * scale_cfg)

		var vp_size := int(ed.get("viewport_size", 256))
		var ortho := float(ed.get("ortho_size", 4.0))
		var dur := float(ed.get("duration_s", 1.0))
		var loop_cfg := bool(ed.get("loop", false))
		var force_emit := bool(ed.get("force_emit", true))
		var pixel_target_px := int(ed.get("pixel_target_px", vp_size))
		var pixel_mat_path := String(ed.get("pixel_material", ""))
		var pixel_mat: ShaderMaterial = null
		if pixel_mat_path != "" and ResourceLoader.exists(pixel_mat_path):
			pixel_mat = load(pixel_mat_path) as ShaderMaterial
		var pixel_params := (ed.get("pixel_params", {}) as Dictionary)

		var cam_pos := Vector3(0, 8, 0)
		var cam_target := Vector3.ZERO
		var cam_up := Vector3.UP
		var cp_v: Variant = ed.get("cam_pos", null)
		var ct_v: Variant = ed.get("cam_target", null)
		var cu_v: Variant = ed.get("cam_up", null)
		if typeof(cp_v) == TYPE_ARRAY and (cp_v as Array).size() >= 3:
			var a3 := cp_v as Array
			cam_pos = Vector3(float(a3[0]), float(a3[1]), float(a3[2]))
		if typeof(ct_v) == TYPE_ARRAY and (ct_v as Array).size() >= 3:
			var b3 := ct_v as Array
			cam_target = Vector3(float(b3[0]), float(b3[1]), float(b3[2]))
		if typeof(cu_v) == TYPE_ARRAY and (cu_v as Array).size() >= 3:
			var c3 := cu_v as Array
			cam_up = Vector3(float(c3[0]), float(c3[1]), float(c3[2]))

		var hide_names := PackedStringArray()
		var hn_v: Variant = ed.get("hide_nodes", null)
		if typeof(hn_v) == TYPE_ARRAY:
			for it in (hn_v as Array):
				hide_names.append(String(it))

		# Apply tint at the 2D level for readability (doesn't change the underlying 3D asset).
		var tint_cfg: Variant = ed.get("tint", null)
		if typeof(tint_cfg) == TYPE_STRING:
			tint = tint * Color.html(String(tint_cfg))

		v3.setup(ps, vp_size, ortho, cam_pos, cam_target, cam_up, 1.0, dur, loop_cfg, force_emit, pixel_mat, pixel_target_px, hide_names, pixel_params)
		# Sprite2D is child of VfxViewport3D2D, so we modulate the whole node for tint.
		v3.modulate = tint
		return true
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
	var loop_cfg := bool(ed.get("loop", false))
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
	v.setup(frames, float(fps), loop_cfg, tint, scale_mult * scale_cfg)
	return true

func _load_scene3d(scene_path: String) -> PackedScene:
	if _cache_scene3d.has(scene_path):
		return _cache_scene3d[scene_path] as PackedScene
	if not ResourceLoader.exists(scene_path):
		_cache_scene3d[scene_path] = null
		return null
	var ps := load(scene_path) as PackedScene
	_cache_scene3d[scene_path] = ps
	return ps

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
		var lf := f.to_lower()
		var is_png := lf.ends_with(".png")
		var is_png_import := lf.ends_with(".png.import")
		if not is_png and not is_png_import:
			continue
		if not f.begins_with(want_prefix):
			continue
		files.append(f)
	d.list_dir_end()

	files.sort()
	for f2 in files:
		var tex: Texture2D = null
		var p := "%s/%s" % [dir_path, f2]
		if f2.to_lower().ends_with(".png"):
			tex = load(p) as Texture2D
		elif f2.to_lower().ends_with(".png.import"):
			tex = _load_texture_from_import_file(p)
		if tex != null:
			frames.append(tex)

	# Guardrail: if export produced fully-transparent frames (common when capture camera isn't current),
	# treat as "not available" so gameplay falls back to old VFX instead of invisible projectiles.
	if not frames.is_empty():
		# IMPORTANT: many effects start with an empty frame. Only reject the flipbook if *all* sampled
		# frames look empty (fully transparent / zero used rect).
		var any_visible := false
		var sample_n := mini(frames.size(), 6) # keep it cheap
		for i in range(sample_n):
			var tex_i := frames[i]
			if tex_i == null:
				continue
			var img := tex_i.get_image()
			if img == null:
				continue
			var r := img.get_used_rect()
			if r.size.x > 0 and r.size.y > 0:
				any_visible = true
				break
		if not any_visible:
			frames.clear()

	_cache_frames[effect_key] = frames
	return frames

func _load_texture_from_import_file(import_path: String) -> Texture2D:
	# Support repos where source PNGs are absent but .png.import + .ctex exist.
	# Example line in .import:
	# path="res://.godot/imported/fireballs_0000.png-<hash>.ctex"
	var txt := FileAccess.get_file_as_string(import_path)
	if txt.is_empty():
		return null
	var remap_path := ""
	for line in txt.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("path="):
			remap_path = s.substr(5)
			break
	if remap_path == "":
		return null
	remap_path = remap_path.strip_edges()
	if remap_path.begins_with("\"") and remap_path.ends_with("\"") and remap_path.length() >= 2:
		remap_path = remap_path.substr(1, remap_path.length() - 2)
	if remap_path == "" or not ResourceLoader.exists(remap_path):
		return null
	return load(remap_path) as Texture2D
