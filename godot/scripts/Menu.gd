extends Control

@onready var start_btn: Button = get_node_or_null("Root/Right/StartRun") as Button
@onready var resume_btn: Button = get_node_or_null("Root/Right/ResumeRun") as Button
@onready var settings_btn: Button = get_node_or_null("Root/Right/SettingsBtn") as Button
@onready var back_btn: Button = get_node_or_null("Root/Right/BackBtn") as Button
@onready var roster_box: VBoxContainer = get_node_or_null("Root/Right/RosterBox") as VBoxContainer
@onready var collection_box: VBoxContainer = get_node_or_null("Root/Left/CollectionBox") as VBoxContainer
@onready var map_select: OptionButton = get_node_or_null("Root/Right/MapSelect") as OptionButton

var _selected_unlock: Dictionary = {}
var _toast: ToastLayer = null
var _meta_card: PanelContainer = null
var _meta_prog: ProgressBar = null
var _meta_label_top: Label = null
var _meta_label_bottom: Label = null
var _meta_btn: Button = null
var _last_run_label: RichTextLabel = null

func _ready() -> void:
	# Force load save
	var cm := get_node_or_null("/root/CollectionManager")
	if cm and is_instance_valid(cm) and cm.has_method("load_save"):
		cm.load_save()

	_toast = ToastLayer.new()
	add_child(_toast)
	_refresh()

	_setup_map_select()
	_setup_meta_ui()

	# Menu music
	var mm := get_node_or_null("/root/MusicManager")
	if mm and is_instance_valid(mm) and mm.has_method("play"):
		mm.play("menu", 0.35)

	if start_btn:
		start_btn.pressed.connect(func():
			var s := get_node_or_null("/root/SfxSystem")
			if s and s.has_method("play_ui"):
				s.play_ui("ui.confirm")
			_on_start_run()
		)

	if settings_btn:
		settings_btn.pressed.connect(func():
			var s := get_node_or_null("/root/SfxSystem")
			if s and s.has_method("play_ui"):
				s.play_ui("ui.click")
			_open_settings()
		)

	if back_btn:
		back_btn.pressed.connect(func():
			var s := get_node_or_null("/root/SfxSystem")
			if s and s.has_method("play_ui"):
				s.play_ui("ui.cancel")
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		)

	var sv := get_node_or_null("/root/SaveManager")
	if sv and is_instance_valid(sv) and sv.has_method("load_meta"):
		# Optional: if meta_save.json exists, treat it as a higher-priority snapshot.
		sv.load_meta()

	# Resume run (if available)
	if resume_btn:
		var has := false
		if sv and is_instance_valid(sv) and sv.has_method("has_saved_run"):
			has = bool(sv.has_saved_run())
		resume_btn.visible = has
		if has:
			resume_btn.pressed.connect(func():
				var s := get_node_or_null("/root/SfxSystem")
				if s and s.has_method("play_ui"):
					s.play_ui("ui.resume_load")
				if sv and is_instance_valid(sv) and sv.has_method("request_resume"):
					if bool(sv.request_resume()):
						_on_start_run()
			)

func _meta_cap() -> int:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_roster_cap"):
		return int(mp.get_roster_cap())
	return 6

func _open_settings() -> void:
	if has_node("SettingsMenu"):
		return
	var sm := preload("res://scripts/SettingsMenu.gd").new()
	sm.name = "SettingsMenu"
	add_child(sm)

func _setup_meta_ui() -> void:
	var right := get_node_or_null("Root/Right/RightPad/RightVBox") as VBoxContainer
	if right == null:
		return
	# Meta card
	_meta_card = PanelContainer.new()
	_meta_card.name = "MetaCard"
	_meta_card.custom_minimum_size = Vector2(0, 210)
	right.add_child(_meta_card)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.10, 0.95)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.4, 0.8, 1.0, 0.18)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 14
	_meta_card.add_theme_stylebox_override("panel", sb)

	var neon := ShaderMaterial.new()
	neon.shader = preload("res://shaders/ui_neon_frame.gdshader")
	neon.set_shader_parameter("base_color", Color(0.07, 0.08, 0.10, 0.95))
	neon.set_shader_parameter("glow_color", Color(0.4, 0.8, 1.0, 0.5))
	neon.set_shader_parameter("glow_width", 0.02)
	neon.set_shader_parameter("pulse_speed", 1.1)
	_meta_card.material = neon

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	_meta_card.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pad.add_child(v)

	var title := Label.new()
	title.text = "Meta Progress"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
	v.add_child(title)

	_meta_label_top = Label.new()
	_meta_label_top.add_theme_font_size_override("font_size", 14)
	_meta_label_top.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96, 0.95))
	_meta_label_top.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_meta_label_top)

	_meta_prog = ProgressBar.new()
	_meta_prog.custom_minimum_size = Vector2(0, 18)
	_meta_prog.min_value = 0
	_meta_prog.max_value = 100
	v.add_child(_meta_prog)

	_meta_label_bottom = Label.new()
	_meta_label_bottom.add_theme_font_size_override("font_size", 13)
	_meta_label_bottom.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 0.95))
	_meta_label_bottom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_meta_label_bottom)

	_meta_btn = Button.new()
	_meta_btn.name = "UnlockSlotBtn"
	_meta_btn.custom_minimum_size = Vector2(0, 44)
	_meta_btn.add_theme_font_size_override("font_size", 16)
	v.add_child(_meta_btn)

	_last_run_label = RichTextLabel.new()
	_last_run_label.bbcode_enabled = true
	_last_run_label.scroll_active = false
	_last_run_label.fit_content = true
	_last_run_label.add_theme_font_size_override("normal_font_size", 12)
	_last_run_label.add_theme_color_override("default_color", Color(0.78, 0.82, 0.88, 0.95))
	v.add_child(_last_run_label)

	_meta_btn.pressed.connect(func():
		var mp := get_node_or_null("/root/MetaProgression")
		if mp == null or not is_instance_valid(mp):
			return
		if mp.has_method("unlock_next_slot") and bool(mp.unlock_next_slot()):
			if _toast:
				_toast.show_toast("Unlocked +1 Squad Slot!", Color(0.55, 1.0, 0.65, 1.0))
			var s := get_node_or_null("/root/SfxSystem")
			if s and s.has_method("play_ui"):
				s.play_ui("ui.confirm")
		else:
			var s2 := get_node_or_null("/root/SfxSystem")
			if s2 and s2.has_method("play_ui"):
				s2.play_ui("ui.cancel")
		_refresh()
	)

	_refresh_meta_ui()

func _refresh_meta_ui() -> void:
	var mp := get_node_or_null("/root/MetaProgression")
	if _meta_label_top == null:
		return
	if mp == null or not is_instance_valid(mp):
		_meta_label_top.text = ""
		if _meta_btn: _meta_btn.visible = false
		if _meta_prog: _meta_prog.visible = false
		return
	var slots := int(mp.get_squad_slots()) if mp.has_method("get_squad_slots") else 3
	var roster_cap := int(mp.get_roster_cap()) if mp.has_method("get_roster_cap") else 6
	var sig := int(mp.sigils) if "sigils" in mp else 0
	var cost := int(mp.get_next_slot_cost()) if mp.has_method("get_next_slot_cost") else -1
	_meta_label_top.text = "Sigils: %d    Squad Slots: %d    Roster Cap: %d" % [sig, slots, roster_cap]

	# Progress to next slot
	if _meta_prog:
		if cost > 0:
			_meta_prog.visible = true
			_meta_prog.min_value = 0
			_meta_prog.max_value = cost
			_meta_prog.value = clampi(sig, 0, cost)
		else:
			_meta_prog.visible = false

	if _meta_label_bottom:
		if cost > 0:
			_meta_label_bottom.text = "Next slot: %d → %d   Cost: %d sigils" % [slots, slots + 1, cost]
		else:
			_meta_label_bottom.text = "Max squad slots reached."

	if _meta_btn:
		_meta_btn.disabled = (cost <= 0) or (sig < cost)
		_meta_btn.text = ("Unlock Squad Slot (%d)" % cost) if cost > 0 else "Max Squad Slots"

	# Last run summary
	if _last_run_label:
		var lr: Dictionary = mp.last_run if "last_run" in mp else {}
		if lr.is_empty():
			_last_run_label.text = "[b]Last Run:[/b] —"
		else:
			var map_name := String(lr.get("map_name", ""))
			var win := bool(lr.get("victory", false))
			var mm := int(lr.get("minutes", 0))
			var kills := int(lr.get("kills", 0))
			var elites := int(lr.get("elite_kills", 0))
			var drafts := int(lr.get("drafts", 0))
			var earned := int(lr.get("sigils_earned", 0))
			var status := "[color=#55ff99]VICTORY[/color]" if win else "[color=#ff6666]DEFEAT[/color]"
			_last_run_label.text = "[b]Last Run:[/b] %s  %s\n[b]Time:[/b] %dm   [b]Kills:[/b] %d (elites %d)   [b]Drafts:[/b] %d\n[b]Sigils earned:[/b] %d" % [map_name, status, mm, kills, elites, drafts, earned]

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
		var s := get_node_or_null("/root/SfxSystem")
		if s and s.has_method("play_ui"):
			s.play_ui("ui.click")
		if rc.has_method("set_selected_map_id"):
			rc.set_selected_map_id(id)
		var m2: Dictionary = rc.get_map(id) if rc.has_method("get_map") else {}
		if _toast:
			_toast.show_toast("Selected: %s — %s" % [String(m2.get("name", id)), String(m2.get("tagline", ""))], Color(0.65, 0.85, 1.0, 1.0))
	)

func _refresh() -> void:
	_refresh_collection()
	_refresh_roster()
	_refresh_meta_ui()

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
	var cap := _meta_cap()
	for i in range(cap):
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
	var cap := _meta_cap()
	if cm.active_roster.size() >= cap:
		if _toast:
			_toast.show_toast("Roster full (max %d). Remove someone first." % cap, Color(1.0, 0.55, 0.45, 1.0))
		return
	var cd: CharacterData = (cm._dict_to_cd(data) as CharacterData) if cm.has_method("_dict_to_cd") else null
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


