extends SceneTree

# Verifies the regenerated machine characters load full directional walk
# animations, with walk_west correctly flagged to mirror walk_side_right.

const CHARS: Array[String] = ["robot_elite", "ion_scout", "iron_warden"]

func _init() -> void:
	var fails := 0
	for c in CHARS:
		var south := "res://assets/characters/machines/%s/frames/walk_front/frame_000.png" % c
		var sf := PixellabUtil.walk_frames_from_south_path(south)
		if sf == null:
			fails += 1
			print("MACHINE_SMOKE_FAIL %s null_frames" % c)
			continue
		for anim in ["walk_south", "walk_north", "walk_east", "walk_west"]:
			var n := sf.get_frame_count(anim) if sf.has_animation(anim) else 0
			if n < 20:
				fails += 1
				print("MACHINE_SMOKE_FAIL %s %s frames=%d" % [c, anim, n])
			else:
				print("MACHINE_SMOKE_OK %s %s frames=%d" % [c, anim, n])
		var flip_w := bool(sf.get_meta("flip_h_for_walk_west", false))
		if flip_w:
			print("MACHINE_SMOKE_OK %s west_flips" % c)
		else:
			fails += 1
			print("MACHINE_SMOKE_FAIL %s west_does_not_flip" % c)
	print("MACHINE_FRAMES_SMOKE fails=%d" % fails)
	quit(0 if fails == 0 else 1)
