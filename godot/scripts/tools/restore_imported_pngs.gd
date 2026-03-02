extends SceneTree

# Restores missing PNG/WEBP sources from Godot .import metadata by decoding the
# cached .ctex files. This is useful when only *.png.import or *.webp.import
# files remain.

const ROOT := "res://assets/characters"

func _initialize() -> void:
	var restored := 0
	var skipped := 0
	var import_files: Array[String] = _scan_import_files(ROOT)
	for import_path in import_files:
		var cfg := ConfigFile.new()
		var err: int = cfg.load(import_path)
		if err != OK:
			skipped += 1
			continue
		var source_file: String = String(cfg.get_value("deps", "source_file", ""))
		if source_file == "":
			skipped += 1
			continue
		var source_abs := ProjectSettings.globalize_path(source_file)
		if FileAccess.file_exists(source_abs):
			skipped += 1
			continue
		var remap_path: String = String(cfg.get_value("remap", "path", ""))
		if remap_path == "":
			skipped += 1
			continue
		var tex: Texture2D = null
		if ResourceLoader.exists(remap_path):
			tex = load(remap_path) as Texture2D
		else:
			var abs := ProjectSettings.globalize_path(remap_path)
			if FileAccess.file_exists(abs):
				tex = load(abs) as Texture2D
		if tex == null:
			skipped += 1
			continue
		var img := tex.get_image()
		if img == null:
			skipped += 1
			continue
		_ensure_dir_for_file(source_file)
		var save_err := _save_image(img, source_file)
		if save_err == OK:
			restored += 1
		else:
			skipped += 1
	print("restore_imported_pngs: restored=%d skipped=%d" % [restored, skipped])
	quit()

func _scan_import_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [root]
	while stack.size() > 0:
		var dir_path: String = stack.pop_back()
		var d: DirAccess = DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		while true:
			var f: String = d.get_next()
			if f == "":
				break
			if d.current_is_dir():
				if f.begins_with("."):
					continue
				stack.append("%s/%s" % [dir_path, f])
				continue
			if f.ends_with(".png.import") or f.ends_with(".webp.import"):
				out.append("%s/%s" % [dir_path, f])
		d.list_dir_end()
	return out

func _save_image(img: Image, source_file: String) -> int:
	if source_file.ends_with(".webp"):
		return img.save_webp(source_file)
	return img.save_png(source_file)

func _ensure_dir_for_file(path: String) -> void:
	var dir := path.get_base_dir()
	if dir == "":
		return
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
