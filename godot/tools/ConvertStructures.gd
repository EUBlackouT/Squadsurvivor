@tool
extends EditorScript

const IN_DIR := "res://assets/_incoming"
const OUT_DIR := "res://assets/structures"
const FRAME_SIZE := Vector2i(256, 256) # width, height of each output frame
const TARGET_FRAMES := 8
const INNER_PADDING := 3 # pixels from bottom/edges to avoid bleeding

func _run() -> void:
	# Run this from the Script Editor: File → Run
	var in_da := DirAccess.open(IN_DIR)
	if in_da == null:
		push_error("ConvertStructures: Missing folder " + IN_DIR + " (create it and drop your PNG strips inside).")
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var processed := []
	in_da.list_dir_begin()
	while true:
		var name := in_da.get_next()
		if name == "":
			break
		if in_da.current_is_dir():
			continue
		if not name.to_lower().ends_with(".png"):
			continue
		var in_path := IN_DIR + "/" + name
		var out_name := name.get_basename() + "_sheet.png"
		var out_path := OUT_DIR + "/" + out_name
		if _convert_strip(in_path, out_path):
			processed.append(out_name)
	in_da.list_dir_end()

	if processed.is_empty():
		printerr("ConvertStructures: No PNGs converted. Ensure your source strips are in " + IN_DIR)
	else:
		print("ConvertStructures: Converted -> ", processed)
		# Trigger reimport for immediate availability in the editor
		for f in processed:
			var p := OUT_DIR + "/" + f
			if ResourceLoader.exists(p):
				ResourceLoader.load(p)


func _convert_strip(in_path: String, out_path: String) -> bool:
	var img := Image.new()
	var err := img.load(in_path)
	if err != OK:
		push_error("ConvertStructures: Failed to load " + in_path)
		return false
	img.convert(Image.FORMAT_RGBA8)

	var w := img.get_width()
	var h := img.get_height()
	if h <= 0 or w <= 0:
		push_error("ConvertStructures: Invalid source size for " + in_path)
		return false

	# Detect frame count in a single horizontal row among common candidates.
	var candidates := [8, 6, 4, 1]
	var frames := 1
	for c in candidates:
		if w % c == 0:
			frames = c
			break
	var src_frame_w := int(w / frames)
	var src_frame_h := h

	# Remove background to alpha using sampled background color (top-left corner band).
	var bg := _sample_bg(img)
	_colorkey_to_alpha(img, bg, 0.10) # 10% distance tolerance in RGB space

	# Compute per-frame bounds and bottom-center for alignment.
	var bounds := []
	var bottom_centers := []
	for i in range(frames):
		var rect := Rect2i(i * src_frame_w, 0, src_frame_w, src_frame_h)
		var b := _alpha_bounds(img, rect)
		bounds.append(b)
		bottom_centers.append(_bottom_center_x(img, rect, b))

	# Use median bottom-center across frames as the global pivot X.
	var pivot_x := _median(bottom_centers)

	# Build output strip (1 × TARGET_FRAMES), each frame FRAME_SIZE.
	var out_w := FRAME_SIZE.x * TARGET_FRAMES
	var out_h := FRAME_SIZE.y
	var out := Image.create(out_w, out_h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))

	# Map source frames to TARGET_FRAMES (pad/duplicate if needed).
	var map_idx := []
	if frames == TARGET_FRAMES:
		for i in range(TARGET_FRAMES):
			map_idx.append(i)
	elif frames == 6:
		map_idx = [0, 1, 1, 2, 3, 4, 5, 5] # gentle duplication near ends
	elif frames == 4:
		map_idx = [0, 0, 1, 1, 2, 2, 3, 3]
	else:
		for i in range(TARGET_FRAMES):
			map_idx.append(0)

	for i in range(TARGET_FRAMES):
		var si := map_idx[i]
		var srect := Rect2i(si * src_frame_w, 0, src_frame_w, src_frame_h)
		var brect : Rect2i = bounds[si]
		var sub := img.get_region(brect)

		var bottom_center_src := _bottom_center_x(img, srect, brect)
		var center_within_bounds := bottom_center_src - brect.position.x
		var dst_x := int(round((i * FRAME_SIZE.x) + FRAME_SIZE.x * 0.5 - center_within_bounds))
		var dst_y := out_h - INNER_PADDING - brect.size.y

		# Clamp draw position to stay fully inside the frame (with padding).
		dst_x = clamp(dst_x, i * FRAME_SIZE.x + INNER_PADDING, (i + 1) * FRAME_SIZE.x - INNER_PADDING - brect.size.x)
		dst_y = clamp(dst_y, INNER_PADDING, out_h - INNER_PADDING - brect.size.y)

		out.blit_rect(sub, Rect2i(Vector2i.ZERO, brect.size), Vector2i(dst_x, dst_y))

	var save_err := out.save_png(out_path)
	if save_err != OK:
		push_error("ConvertStructures: Failed to save " + out_path)
		return false
	return true


func _sample_bg(img: Image) -> Color:
	# Average a small band in the top-left corner to estimate background color.
	var w := img.get_width()
	var h := img.get_height()
	var sx := clamp(w / 20, 1, 16)
	var sy := clamp(h / 20, 1, 16)
	var acc := Vector3.ZERO
	var cnt := 0.0
	for y in range(sy):
		for x in range(sx):
			var c := img.get_pixel(x, y)
			acc += Vector3(c.r, c.g, c.b)
			cnt += 1.0
	if cnt <= 0.0:
		return Color(0, 0, 0, 1)
	acc /= cnt
	return Color(acc.x, acc.y, acc.z, 1.0)


func _colorkey_to_alpha(img: Image, key: Color, tol: float) -> void:
	# Convert pixels close to 'key' color to fully transparent.
	# tol ∈ [0,1], as Euclidean distance in RGB.
	img.lock()
	var w := img.get_width()
	var h := img.get_height()
	var tol2 := tol * tol
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			var dr := c.r - key.r
			var dg := c.g - key.g
			var db := c.b - key.b
			var d2 := dr * dr + dg * dg + db * db
			if d2 <= tol2:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
	img.unlock()


func _alpha_bounds(img: Image, rect: Rect2i) -> Rect2i:
	# Tight bounding box of non-transparent pixels inside 'rect'.
	img.lock()
	var x0 := 1_000_000
	var y0 := 1_000_000
	var x1 := -1
	var y1 := -1
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var a := img.get_pixel(x, y).a
			if a > 0.01:
				if x < x0: x0 = x
				if y < y0: y0 = y
				if x > x1: x1 = x
				if y > y1: y1 = y
	img.unlock()
	if x1 < x0 or y1 < y0:
		return Rect2i(rect.position, rect.size) # fallback: full cell
	return Rect2i(Vector2i(x0, y0), Vector2i(x1 - x0 + 1, y1 - y0 + 1))


func _bottom_center_x(img: Image, cell: Rect2i, bounds: Rect2i) -> int:
	# Find bottom-center X by scanning the bottom 20% of the bounds for opaque pixels.
	img.lock()
	var y_start := bounds.position.y + int(bounds.size.y * 0.8)
	var y_end := bounds.position.y + bounds.size.y - 1
	var x_min := 1_000_000
	var x_max := -1
	for y in range(y_start, y_end + 1):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			if img.get_pixel(x, y).a > 0.01:
				if x < x_min: x_min = x
				if x > x_max: x_max = x
	img.unlock()
	if x_max < x_min:
		# fallback: geometric center of the bounds
		return bounds.position.x + int(bounds.size.x * 0.5)
	return int(round((x_min + x_max) * 0.5))


func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var a := values.duplicate()
	a.sort()
	var n := a.size()
	if (n % 2) == 1:
		return float(a[n / 2])
	return 0.5 * (float(a[n / 2 - 1]) + float(a[n / 2]))


