extends Control

@onready var start_btn: Button = get_node_or_null("Root/Right/StartRun") as Button
@onready var roster_box: VBoxContainer = get_node_or_null("Root/Right/RosterBox") as VBoxContainer
@onready var collection_box: VBoxContainer = get_node_or_null("Root/Left/CollectionBox") as VBoxContainer
@onready var map_select: OptionButton = get_node_or_null("Root/Right/MapSelect") as OptionButton

var _selected_unlock: Dictionary = {}
var _toast: ToastLayer = null

func _ready() -> void:
	# Force load save
	var cm := get_node_or_null("/root/CollectionManager")
	if cm and is_instance_valid(cm) and cm.has_method("load_save"):
		cm.load_save()

	_toast = ToastLayer.new()
	add_child(_toast)
	_refresh()

	_setup_map_select()

	if start_btn:
		start_btn.pressed.connect(_on_start_run)

func _setup_map_select() -> void:
	if map_select == null:
		return
	var rc := get_node_or_null("/root/RunConfig")
	if rc == null or not is_instance_valid(rc):
		return
	if rc.has_method("ensure_loaded"):
		rc.ensure_loaded()

	map_select.clear()

	var ids: Array[String] = []
	if rc.has_method("get_map_ids"):
		ids = rc.get_map_ids()
	for i in range(ids.size()):
		var m: Dictionary = rc.get_map(ids[i]) if rc.has_method("get_map") else {}
		var name := String(m.get("name", ids[i]))
		map_select.add_item(name, i)
		map_select.set_item_metadata(i, ids[i])

	# Select current
	var cur := String(rc.selected_map_id) if "selected_map_id" in rc else "graveyard"
	for i in range(map_select.item_count):
		if String(map_select.get_item_metadata(i)) == cur:
			map_select.select(i)
			break

	map_select.item_selected.connect(func(idx: int):
		var id := String(map_select.get_item_metadata(idx))
		if rc.has_method("set_selected_map_id"):
			rc.set_selected_map_id(id)
		var m2: Dictionary = rc.get_map(id) if rc.has_method("get_map") else {}
		if _toast:
			_toast.show_toast("Selected: %s — %s" % [String(m2.get("name", id)), String(m2.get("tagline", ""))], Color(0.65, 0.85, 1.0, 1.0))
	)

func _refresh() -> void:
	_refresh_collection()
	_refresh_roster()

func _refresh_collection() -> void:
	if collection_box == null:
		return
	for c in collection_box.get_children():
		c.queue_free()

	var cm := Engine.get_singleton("CollectionManager") if Engine.has_singleton("CollectionManager") else null
	if cm == null:
		cm = get_node_or_null("/root/CollectionManager")
	if cm == null:
		return
	var unlocked: Array = cm.unlocked
	if unlocked.is_empty():
		var l := Label.new()
		l.text = "No unlocked characters yet.\n(Play a run, unlock trophies in the draft.)"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		collection_box.add_child(l)
		return

	for e in unlocked:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var data: Dictionary = d.get("data", {}) as Dictionary
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		collection_box.add_child(row)

		var name := Label.new()
		var rarity := String(data.get("rarity_id", "common"))
		var arch := String(data.get("archetype_id", "bruiser"))
		name.text = "%s • %s" % [UnitFactory.rarity_name(rarity), arch]
		name.add_theme_color_override("font_color", UnitFactory.rarity_color(rarity))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)

		var details := Button.new()
		details.text = "Details"
		row.add_child(details)
		details.pressed.connect(func():
			_show_details(data)
		)

		var add := Button.new()
		add.text = "Add"
		row.add_child(add)
		add.pressed.connect(func():
			_add_unlock_to_roster(data)
		)

func _refresh_roster() -> void:
	if roster_box == null:
		return
	for c in roster_box.get_children():
		c.queue_free()

	var cm := Engine.get_singleton("CollectionManager") if Engine.has_singleton("CollectionManager") else null
	if cm == null:
		cm = get_node_or_null("/root/CollectionManager")
	if cm == null:
		return

	var roster: Array = cm.active_roster
	for i in range(6):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		roster_box.add_child(row)

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i < roster.size() and typeof(roster[i]) == TYPE_DICTIONARY:
			var d: Dictionary = roster[i]
			var rarity := String(d.get("rarity_id", "common"))
			var arch := String(d.get("archetype_id", "bruiser"))
			label.text = "%d) %s • %s" % [i + 1, UnitFactory.rarity_name(rarity), arch]
		else:
			label.text = "%d) (empty)" % [i + 1]
		row.add_child(label)

		if i < roster.size():
			var remove := Button.new()
			remove.text = "Remove"
			row.add_child(remove)
			remove.pressed.connect(func():
				cm.remove_from_roster(i)
				_refresh()
			)

func _add_unlock_to_roster(data: Dictionary) -> void:
	var cm := Engine.get_singleton("CollectionManager") if Engine.has_singleton("CollectionManager") else null
	if cm == null:
		cm = get_node_or_null("/root/CollectionManager")
	if cm == null:
		return
	if cm.active_roster.size() >= 6:
		if _toast:
			_toast.show_toast("Roster full (max 6). Remove someone first.", Color(1.0, 0.55, 0.45, 1.0))
		return
	var cd := cm._dict_to_cd(data) if cm.has_method("_dict_to_cd") else null
	if cd == null:
		return
	cm.add_to_roster(cd)
	if _toast:
		var rarity := String(data.get("rarity_id", "common"))
		var arch := String(data.get("archetype_id", "bruiser"))
		_toast.show_toast("Added to roster: %s • %s" % [UnitFactory.rarity_name(rarity), arch], UnitFactory.rarity_color(rarity))
	_refresh()

func _on_start_run() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _show_details(data: Dictionary) -> void:
	# Simple modal (reuses draft-style content but lightweight).
	if has_node("DetailsModal"):
		get_node("DetailsModal").queue_free()
	var layer := CanvasLayer.new()
	layer.name = "DetailsModal"
	layer.layer = 170
	add_child(layer)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.72)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -360
	panel.offset_top = -240
	panel.offset_right = 360
	panel.offset_bottom = 240
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(panel)

	var rarity := String(data.get("rarity_id", "common"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.95)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = UnitFactory.rarity_color(rarity)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	panel.add_theme_stylebox_override("panel", sb)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pad.add_child(v)

	var arch := String(data.get("archetype_id", "bruiser"))
	var style := "MELEE" if int(data.get("attack_style", 1)) == 0 else "RANGED"

	var t := Label.new()
	t.text = "%s • %s • %s" % [UnitFactory.rarity_name(rarity), arch, style]
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", UnitFactory.rarity_color(rarity))
	v.add_child(t)

	var stats := Label.new()
	stats.text = "HP %d  DMG %d  CD %.2f  RNG %d\nCrit %.0f%%  x%.2f" % [
		int(data.get("max_hp", 100)),
		int(data.get("attack_damage", 10)),
		float(data.get("attack_cooldown", 1.0)),
		int(float(data.get("attack_range", 300.0))),
		float(data.get("crit_chance", 0.0)) * 100.0,
		float(data.get("crit_mult", 1.5))
	]
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(stats)

	var p := Label.new()
	var lines: Array[String] = []
	var pids: Array = data.get("passive_ids", [])
	for pid in pids:
		lines.append("• %s\n  %s" % [PassiveSystem.passive_name(String(pid)), PassiveSystem.passive_description(String(pid))])
	p.text = "Passives:\n%s" % "\n".join(lines)
	p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(p)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): layer.queue_free())
	v.add_child(close)


