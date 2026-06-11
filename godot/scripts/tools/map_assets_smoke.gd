extends SceneTree
# Verifies every bg_image_path in maps.json exists and loads as a texture.

func _initialize() -> void:
	var text := FileAccess.get_file_as_string("res://data/maps.json")
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("MAP_ASSETS_SMOKE FAIL invalid maps.json")
		quit(1)
		return
	var fails := 0
	var checked := 0
	var stack: Array = [parsed]
	var paths: Dictionary = {}
	while not stack.is_empty():
		var v: Variant = stack.pop_back()
		if typeof(v) == TYPE_DICTIONARY:
			var d: Dictionary = v
			for k in d.keys():
				if String(k) == "bg_image_path":
					paths[String(d[k])] = true
				else:
					stack.append(d[k])
		elif typeof(v) == TYPE_ARRAY:
			for item in (v as Array):
				stack.append(item)
	for p in paths.keys():
		checked += 1
		var path := String(p)
		if not ResourceLoader.exists(path):
			print("MAP_ASSETS_SMOKE missing: %s" % path)
			fails += 1
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			print("MAP_ASSETS_SMOKE load_failed: %s" % path)
			fails += 1
			continue
		print("MAP_ASSETS_SMOKE ok: %s (%dx%d)" % [path, tex.get_width(), tex.get_height()])
	print("MAP_ASSETS_SMOKE checked=%d fails=%d -> %s" % [checked, fails, "OK" if fails == 0 else "FAIL"])
	quit(0 if fails == 0 else 1)
