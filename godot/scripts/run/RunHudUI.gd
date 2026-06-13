extends CanvasLayer
class_name RunHudUI

var _host: Node
var _passive_overlay: PanelContainer = null
var _squad_strip_sig: String = ""
var _hud_label_cache: Dictionary = {}
var _dbg_cd: float = 0.0
var _dbg_text: String = ""

static func attach(host: Node) -> CanvasLayer:
	if host.has_node("HUD"):
		return host.get_node("HUD") as CanvasLayer
	var hud: CanvasLayer = load("res://scripts/run/RunHudUI.gd").new()
	hud.name = "HUD"
	hud.layer = 10
	hud.set("_host", host)
	host.add_child(hud)
	hud.call("_build")
	return hud

static func _class_name(c: int) -> String:
	match c:
		CharacterData.Class.WARRIOR: return "Warrior"
		CharacterData.Class.MAGE: return "Mage"
		CharacterData.Class.ROGUE: return "Rogue"
		CharacterData.Class.GUARDIAN: return "Guardian"
		CharacterData.Class.HEALER: return "Healer"
		CharacterData.Class.SUMMONER: return "Summoner"
		_: return "Unknown"

func sync_passive_overlay_hotkey() -> void:
	if _passive_overlay == null:
		return
	var blocked: bool = bool(_host._game_over) or bool(_host._victory) or _host.get_tree().paused \
		or _host.has_node("RecruitDraftUI") or _host.has_node("PauseMenu")
	var wants_overlay: bool = (not blocked) and Input.is_key_pressed(KEY_TAB)
	if wants_overlay and not _passive_overlay.visible:
		show_passive_overlay()
	elif (not wants_overlay) and _passive_overlay.visible:
		hide_passive_overlay()

func _build() -> void:
	# Tiny autosave indicator (top-right)
	var autosave_lbl := Label.new()
	autosave_lbl.name = "AutosaveLabel"
	autosave_lbl.text = "Autosaving…"
	autosave_lbl.visible = false
	autosave_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	autosave_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	autosave_lbl.offset_left = -170
	autosave_lbl.offset_right = -18
	autosave_lbl.offset_top = 16
	autosave_lbl.offset_bottom = 36
	autosave_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	autosave_lbl.add_theme_font_size_override("font_size", 12)
	autosave_lbl.add_theme_color_override("font_color", Color(0.78, 0.92, 1.0, 0.92))
	add_child(autosave_lbl)

	# Minimal modern HUD: slim top-center status stack, nothing boxy in the corners.
	var top_stack := VBoxContainer.new()
	top_stack.name = "TopStack"
	top_stack.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_stack.offset_left = -320
	top_stack.offset_right = 320
	top_stack.offset_top = 10
	top_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_stack.add_theme_constant_override("separation", 4)
	top_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_stack)

	var pill_center := HBoxContainer.new()
	pill_center.alignment = BoxContainer.ALIGNMENT_CENTER
	pill_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_stack.add_child(pill_center)

	var timer_chip := _make_hud_chip("RunTimerLabel", "0:00   ✧ 0", UiSkin.ACCENT_GOLD, 14)
	pill_center.add_child(timer_chip)

	var objective_lbl := Label.new()
	objective_lbl.name = "ObjectiveLabel"
	objective_lbl.text = ""
	objective_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_lbl.add_theme_font_size_override("font_size", 12)
	objective_lbl.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
	objective_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	objective_lbl.add_theme_constant_override("outline_size", 3)
	objective_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_stack.add_child(objective_lbl)

	var boss_center := HBoxContainer.new()
	boss_center.alignment = BoxContainer.ALIGNMENT_CENTER
	boss_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_stack.add_child(boss_center)
	var boss_chip := _make_hud_chip("BossLabel", "", UiSkin.ACCENT_RED, 13)
	boss_chip.visible = false
	boss_center.add_child(boss_chip)

	# Active sets: quiet line above the squad strip (bottom-left).
	var syn_lbl := Label.new()
	syn_lbl.name = "SynergyLabel"
	syn_lbl.text = ""
	syn_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	syn_lbl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	syn_lbl.offset_left = 12
	syn_lbl.offset_bottom = -66
	syn_lbl.add_theme_font_size_override("font_size", 12)
	syn_lbl.add_theme_color_override("font_color", UiSkin.ACCENT_PURPLE)
	syn_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	syn_lbl.add_theme_constant_override("outline_size", 3)
	syn_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(syn_lbl)

	# Debug-only readouts (bottom-right, hidden unless debug HUD is on).
	var dbg_stack := VBoxContainer.new()
	dbg_stack.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dbg_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dbg_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dbg_stack.offset_right = -12
	dbg_stack.offset_bottom = -12
	dbg_stack.add_theme_constant_override("separation", 2)
	dbg_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dbg_stack)
	for dbg_name in ["CommandLabel", "DebugLabel", "PerfLabel"]:
		var dl := Label.new()
		dl.name = dbg_name
		dl.text = ""
		dl.visible = false
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dl.add_theme_font_size_override("font_size", 11)
		dl.add_theme_color_override("font_color", UiSkin.TEXT_DIM)
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dbg_stack.add_child(dl)

	# Squad health strip (bottom-left): one race-colored chip per member.
	var strip := HBoxContainer.new()
	strip.name = "SquadStrip"
	strip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	strip.grow_horizontal = Control.GROW_DIRECTION_END
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.offset_left = 12
	strip.offset_bottom = -12
	strip.add_theme_constant_override("separation", UiSkin.SPACE_XS)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)

	# Passive overlay panel (shown when holding TAB)
	_create_passive_overlay()

func _update_squad_strip() -> void:
	var strip := get_node_or_null("SquadStrip") as HBoxContainer
	if strip == null:
		return

	var sig := ""
	for u in _host.live_squad_units:
		if is_instance_valid(u):
			sig += str(u.get_instance_id()) + ","
	if sig != _squad_strip_sig:
		_squad_strip_sig = sig
		for c in strip.get_children():
			c.queue_free()
		for u in _host.live_squad_units:
			if not is_instance_valid(u):
				continue
			var cd := (u as Node).get("character_data") as CharacterData
			if cd == null:
				continue
			var rcol := UiSkin.race_color(String(cd.race_id))
			var chip := PanelContainer.new()
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_theme_stylebox_override("panel", UiSkin.chip_style(rcol))
			chip.set_meta("unit_id", u.get_instance_id())
			strip.add_child(chip)

			var vb := VBoxContainer.new()
			vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_theme_constant_override("separation", 3)
			chip.add_child(vb)

			var nm := Label.new()
			nm.text = cd.archetype_id.capitalize()
			nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			UiSkin.style_label(nm, UiSkin.FONT_XS, rcol)
			vb.add_child(nm)

			var bar := ProgressBar.new()
			bar.name = "HpBar"
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(86, 6)
			bar.max_value = 1.0
			bar.value = 1.0
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bg_sb := StyleBoxFlat.new()
			bg_sb.bg_color = Color(0.05, 0.08, 0.12, 0.85)
			bg_sb.set_corner_radius_all(3)
			bar.add_theme_stylebox_override("background", bg_sb)
			var fill_sb := StyleBoxFlat.new()
			fill_sb.bg_color = rcol
			fill_sb.set_corner_radius_all(3)
			bar.add_theme_stylebox_override("fill", fill_sb)
			vb.add_child(bar)

	# Refresh HP values on existing chips.
	var by_id: Dictionary = {}
	for u2 in _host.live_squad_units:
		if is_instance_valid(u2):
			by_id[u2.get_instance_id()] = u2
	for chip2 in strip.get_children():
		var uid: int = int((chip2 as Node).get_meta("unit_id", 0))
		if not by_id.has(uid):
			continue
		var unit: Node = by_id[uid]
		var bar2 := (chip2 as Node).find_child("HpBar", true, false) as ProgressBar
		if bar2 == null or not unit.has_method("get_hp_ratio"):
			continue
		var r := float(unit.call("get_hp_ratio"))
		bar2.value = r
		# Low-HP flash so endangered members read at a glance.
		(chip2 as CanvasItem).modulate = Color(1, 1, 1, 1) if r > 0.35 else Color(1.0, 0.55, 0.55, 1.0)
	strip.visible = not _host.live_squad_units.is_empty()

func _create_passive_overlay() -> void:
	_passive_overlay = PanelContainer.new()
	_passive_overlay.name = "PassiveOverlay"
	_passive_overlay.visible = false
	_passive_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block mouse input
	_passive_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_passive_overlay.offset_left = -380
	_passive_overlay.offset_right = 380
	_passive_overlay.offset_top = -280
	_passive_overlay.offset_bottom = 280
	_passive_overlay.add_theme_stylebox_override("panel", UiSkin.glowing_panel_style(UiSkin.ACCENT))
	add_child(_passive_overlay)
	
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"  # Name it so we can find it!
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_passive_overlay.add_child(scroll)
	
	var content := VBoxContainer.new()
	content.name = "PassiveContent"
	content.add_theme_constant_override("separation", 16)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(content)
	
	var title := Label.new()
	title.name = "Title"
	title.text = "══════ SQUAD PASSIVES ══════"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	
	var hint := Label.new()
	hint.text = "Release TAB to close"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.75, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)
	
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	content.add_child(spacer)

func show_passive_overlay() -> void:
	if _passive_overlay == null:
		return
	if _host._game_over or _host._victory:
		return
	_update_passive_overlay()
	_passive_overlay.visible = true

func hide_passive_overlay() -> void:
	if _passive_overlay == null:
		return
	_passive_overlay.visible = false

func _update_passive_overlay() -> void:
	if _passive_overlay == null:
		return
	var content := _passive_overlay.get_node_or_null("ScrollContainer/PassiveContent") as VBoxContainer
	if content == null:
		push_warning("PassiveOverlay: content node not found")
		return
	
	# Clear old unit sections (keep title, hint, and spacer = first 3 children)
	for i in range(content.get_child_count() - 1, 2, -1):
		content.get_child(i).queue_free()
	
	# Check if we have squad units
	var valid_units: Array = []
	for unit in _host.live_squad_units:
		if is_instance_valid(unit):
			var cd: CharacterData = (unit as Node).get("character_data") as CharacterData
			if cd != null:
				valid_units.append({"unit": unit, "cd": cd})
	
	if valid_units.size() == 0:
		var empty_msg := Label.new()
		empty_msg.text = "No squad units with passives found"
		empty_msg.add_theme_font_size_override("font_size", 14)
		empty_msg.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72, 0.8))
		empty_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(empty_msg)
		return
	
	# Build UI for each unit
	for data in valid_units:
		var cd: CharacterData = data["cd"]
		
		# Unit card container with styled background
		var card := PanelContainer.new()
		var rarity_col := UnitFactory.rarity_color(cd.rarity_id)
		var card_sb := UiSkin.card_style(rarity_col, false)
		card_sb.content_margin_left = 12
		card_sb.content_margin_right = 12
		card_sb.content_margin_top = 10
		card_sb.content_margin_bottom = 10
		card.add_theme_stylebox_override("panel", card_sb)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(card)
		
		var unit_section := VBoxContainer.new()
		unit_section.add_theme_constant_override("separation", 8)
		unit_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(unit_section)
		
		# Unit header
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 10)
		unit_section.add_child(header)
		
		var name_lbl := Label.new()
		var stars := " ★".repeat(cd.tier) if cd.tier > 1 else ""
		name_lbl.text = "%s %s%s" % [UnitFactory.rarity_name(cd.rarity_id).to_upper(), cd.archetype_id.capitalize(), stars]
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", rarity_col)
		header.add_child(name_lbl)
		
		header.add_spacer(true)
		
		var style_lbl := Label.new()
		var overlay_weapon := WeaponSystem.weapon_name(cd.weapon_id) if cd.weapon_id != "" else ("Melee" if cd.attack_style == CharacterData.AttackStyle.MELEE else "Ranged")
		var style_icon := "⚔" if cd.attack_style == CharacterData.AttackStyle.MELEE else "🏹"
		style_lbl.text = "%s %s" % [style_icon, overlay_weapon]
		style_lbl.add_theme_font_size_override("font_size", 12)
		style_lbl.add_theme_color_override("font_color", Color(0.70, 0.85, 1.0, 0.85))
		header.add_child(style_lbl)
		
		# Divider
		var divider := HSeparator.new()
		divider.add_theme_stylebox_override("separator", StyleBoxLine.new())
		divider.add_theme_constant_override("separation", 4)
		unit_section.add_child(divider)
		
		# Passives
		if cd.passive_ids.size() > 0:
			for pid in cd.passive_ids:
				var pass_row := VBoxContainer.new()
				pass_row.add_theme_constant_override("separation", 2)
				unit_section.add_child(pass_row)
				
				var pc := PassiveSystem.passive_color(pid)
				
				# Passive name row with icon
				var name_row := HBoxContainer.new()
				name_row.add_theme_constant_override("separation", 8)
				pass_row.add_child(name_row)
				
				var icon_lbl := Label.new()
				icon_lbl.text = PassiveSystem.passive_icon(pid)
				icon_lbl.add_theme_font_size_override("font_size", 14)
				icon_lbl.add_theme_color_override("font_color", pc)
				name_row.add_child(icon_lbl)
				
				var name_l := Label.new()
				name_l.text = PassiveSystem.passive_name(pid)
				name_l.add_theme_font_size_override("font_size", 14)
				name_l.add_theme_color_override("font_color", Color(pc.r * 1.1, pc.g * 1.1, pc.b * 1.1, 1.0))
				name_row.add_child(name_l)
				
				# Description on its own line
				var desc_l := Label.new()
				desc_l.text = "    " + PassiveSystem.passive_description(pid)
				desc_l.add_theme_font_size_override("font_size", 12)
				desc_l.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86, 0.9))
				desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				desc_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				pass_row.add_child(desc_l)
		else:
			var no_pass := Label.new()
			no_pass.text = "— No passives —"
			no_pass.add_theme_font_size_override("font_size", 12)
			no_pass.add_theme_color_override("font_color", Color(0.50, 0.55, 0.62, 0.7))
			no_pass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			unit_section.add_child(no_pass)
		
		# Show weapon info
		if cd.weapon_id != "" and cd.weapon_id != "standard_bolt":
			var weapon_row := HBoxContainer.new()
			weapon_row.add_theme_constant_override("separation", 8)
			unit_section.add_child(weapon_row)
			
			var weapon_icon := Label.new()
			weapon_icon.text = WeaponSystem.weapon_icon(cd.weapon_id)
			weapon_icon.add_theme_font_size_override("font_size", 14)
			weapon_icon.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5, 1.0))
			weapon_row.add_child(weapon_icon)
			
			var weapon_name := Label.new()
			weapon_name.text = WeaponSystem.weapon_name(cd.weapon_id)
			weapon_name.add_theme_font_size_override("font_size", 13)
			weapon_name.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6, 0.95))
			weapon_row.add_child(weapon_name)
			
			var weapon_desc := Label.new()
			weapon_desc.text = " - " + WeaponSystem.weapon_description(cd.weapon_id)
			weapon_desc.add_theme_font_size_override("font_size", 11)
			weapon_desc.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 0.8))
			weapon_row.add_child(weapon_desc)
	
	# === SYNERGIES SECTION ===
	_add_synergies_to_overlay(content)

func _add_synergies_to_overlay(content: VBoxContainer) -> void:
	# Get active synergies from SynergySystem
	var active := SynergySystem.get_active_synergies()
	if active.is_empty():
		return
	
	# Synergy header
	var syn_header := Label.new()
	syn_header.text = "══════ ACTIVE SYNERGIES ══════"
	syn_header.add_theme_font_size_override("font_size", 18)
	syn_header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45, 1.0))
	syn_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(syn_header)
	
	var syn_spacer := Control.new()
	syn_spacer.custom_minimum_size = Vector2(0, 8)
	content.add_child(syn_spacer)
	
	# Display each active synergy
	for syn_data in active:
		var syn_id: String = String(syn_data.get("id", ""))
		var tier: int = int(syn_data.get("tier", 0))
		var count: int = int(syn_data.get("count", 0))
		var required: int = int(syn_data.get("required", 0))
		
		if syn_id == "" or tier <= 0:
			continue
		
		# Synergy card
		var syn_card := PanelContainer.new()
		var syn_col := _synergy_tier_color(tier)
		var syn_sb := UiSkin.card_style(syn_col, false)
		syn_sb.content_margin_left = 12
		syn_sb.content_margin_right = 12
		syn_sb.content_margin_top = 8
		syn_sb.content_margin_bottom = 8
		syn_card.add_theme_stylebox_override("panel", syn_sb)
		syn_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(syn_card)
		
		var syn_vbox := VBoxContainer.new()
		syn_vbox.add_theme_constant_override("separation", 4)
		syn_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		syn_card.add_child(syn_vbox)
		
		# Synergy name and tier
		var syn_name_row := HBoxContainer.new()
		syn_name_row.add_theme_constant_override("separation", 10)
		syn_vbox.add_child(syn_name_row)
		
		var syn_name := Label.new()
		syn_name.text = SynergySystem.synergy_name(syn_id)
		syn_name.add_theme_font_size_override("font_size", 15)
		syn_name.add_theme_color_override("font_color", _synergy_tier_color(tier))
		syn_name_row.add_child(syn_name)
		
		var tier_lbl := Label.new()
		tier_lbl.text = "★".repeat(tier)
		tier_lbl.add_theme_font_size_override("font_size", 13)
		tier_lbl.add_theme_color_override("font_color", _synergy_tier_color(tier))
		syn_name_row.add_child(tier_lbl)
		
		syn_name_row.add_spacer(true)
		
		var count_lbl := Label.new()
		count_lbl.text = "(%d/%d)" % [count, required]
		count_lbl.add_theme_font_size_override("font_size", 12)
		count_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 0.8))
		syn_name_row.add_child(count_lbl)
		
		# Synergy effects description - use RichTextLabel for BBCode support
		var effects := SynergySystem.synergy_tooltip_text_by_id(syn_id, tier)
		if effects != "":
			var effect_lbl := RichTextLabel.new()
			effect_lbl.bbcode_enabled = true
			effect_lbl.fit_content = true
			effect_lbl.scroll_active = false
			effect_lbl.text = effects
			effect_lbl.add_theme_font_size_override("normal_font_size", 12)
			effect_lbl.add_theme_color_override("default_color", Color(0.75, 0.80, 0.85, 0.9))
			effect_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			effect_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			syn_vbox.add_child(effect_lbl)

func _synergy_tier_color(tier: int) -> Color:
	match tier:
		1: return Color(0.75, 0.85, 0.65, 1.0)  # Bronze/green
		2: return Color(0.65, 0.80, 1.0, 1.0)   # Silver/blue
		3: return Color(1.0, 0.85, 0.45, 1.0)   # Gold
		4: return Color(1.0, 0.55, 0.85, 1.0)   # Diamond/pink
		_: return Color(0.8, 0.8, 0.8, 1.0)

func _hud_label(label_name: String) -> Label:
	# Labels live inside chip panels; resolve recursively and cache.
	var cached: Variant = _hud_label_cache.get(label_name)
	if cached is Label and is_instance_valid(cached):
		return cached as Label
	var hud := self
	if hud == null:
		return null
	var l := hud.find_child(label_name, true, false) as Label
	if l != null:
		_hud_label_cache[label_name] = l
	return l

func refresh() -> void:
	_update_squad_strip()

	var t := _hud_label("RunTimerLabel")
	if t:
		var secs := int(round(((Time.get_ticks_msec() / 1000.0) - _host.run_start_time)))
		var mm := int(secs / 60)
		var ss := int(secs % 60)
		t.text = "%d:%02d    ✧ %d" % [mm, ss, _host.essence]
		if t.get_parent() is CanvasItem:
			(t.get_parent() as CanvasItem).visible = true

	var b := _hud_label("BossLabel")
	if b:
		if _host._boss_node and is_instance_valid(_host._boss_node) and _host._boss_node.has_method("get_hp_ratio"):
			var r := float(_host._boss_node.get_hp_ratio())
			var ticks := int(round(clampf(r, 0.0, 1.0) * 20.0))
			b.text = "☠ %s%s %d%%" % ["▰".repeat(ticks), "▱".repeat(20 - ticks), int(round(r * 100.0))]
			if b.get_parent() is CanvasItem:
				(b.get_parent() as CanvasItem).visible = true
		else:
			b.text = ""
			if b.get_parent() is CanvasItem:
				(b.get_parent() as CanvasItem).visible = false

	var o := _hud_label("ObjectiveLabel")
	if o:
		var now_s := int(round(((Time.get_ticks_msec() / 1000.0) - _host.run_start_time)))
		var now_m := float(now_s) / 60.0
		var txt := ""
		if _host.enable_bosses and _host._boss_fight_active:
			if _host._boss_deadline_s > 0.0:
				var left := maxi(0, int(round(_host._boss_deadline_s - float(Time.get_ticks_msec()) / 1000.0)))
				txt = "Objective: Slay the boss before %d:%02d." % [int(left / 60), int(left % 60)]
			else:
				txt = "Objective: Slay the boss."
		elif _host.enable_bosses and _host._multi_boss_schedule_enabled and _host._boss_wave_index < _host._boss_wave_times.size():
			var next_boss_m := float(_host._boss_wave_times[_host._boss_wave_index])
			var left2s := maxi(0, int(round((next_boss_m - now_m) * 60.0)))
			txt = "Objective: Prepare for boss wave %d (%d:%02d)." % [_host._boss_wave_index + 1, int(left2s / 60), int(left2s % 60)]
		elif _host.enable_bosses and (not _host._boss_spawned):
			var left2 := maxi(0.0, _host.run_timer_max_minutes - now_m)
			var left2s2 := int(round(left2 * 60.0))
			txt = "Objective: Hold out until boss (%d:%02d)." % [int(left2s2 / 60), int(left2s2 % 60)]
		else:
			var left3 := maxi(0.0, _host.run_timer_max_minutes - now_m)
			var left3s := int(round(left3 * 60.0))
			txt = "Objective: Survive the run (%d:%02d)." % [int(left3s / 60), int(left3s % 60)]
		if _host._objective_event_index < _host._objective_events.size():
			var next_m := float(_host._objective_events[_host._objective_event_index])
			var dt_s := maxi(0, int(round((next_m - now_m) * 60.0)))
			txt += "  Next surge in %d:%02d." % [int(dt_s / 60), int(dt_s % 60)]
		o.text = txt

	var s := _hud_label("SynergyLabel")
	if s:
		s.text = SynergySystem.summary_text()
		# Always show when sets are active; the player should feel their build.
		s.visible = _host.debug_hud_enabled or not SynergySystem.get_active_synergies().is_empty()

	var cmd := _hud_label("CommandLabel")
	if cmd:
		var focus_txt := "Focus: —"
		var ft: Node2D = _host.get_focus_target()
		if ft != null:
			focus_txt = "Focus: %.1fs" % maxf(0.0, _host._focus_until_s)
		var rally_txt := "Rally: —"
		if _host._rally_until_s > 0.0:
			rally_txt = "Rally: %.1fs" % maxf(0.0, _host._rally_until_s)
		var dash_txt := "Dash: —"
		var player := _host.get_tree().get_first_node_in_group("player")
		if player and is_instance_valid(player) and (player as Node).has_method("get_dash_cd_left"):
			var dcl := float((player as Node).get_dash_cd_left())
			dash_txt = "Dash: READY" if dcl <= 0.0 else ("Dash: %.1fs" % dcl)
		var oc_txt := ""
		if _host._overclock_unlocked():
			oc_txt = "   Overclock(Q): READY" if _host._overclock_cd_s <= 0.0 else ("   Overclock(Q): %.1fs" % _host._overclock_cd_s)
		var callout_txt := "Callout(F): READY" if _host._callout_cd_s <= 0.0 else ("Callout(F): %.1fs" % _host._callout_cd_s)
		var active_txt := ""
		if _host._callout_until_s > 0.0 and _host._callout_class >= 0:
			active_txt = "   Active: %s %.1fs" % [_class_name(_host._callout_class), _host._callout_until_s]
		cmd.text = "Commands: LMB Focus • RMB Rally • Shift Dash%s   |   %s   %s   %s   %s%s" % [oc_txt, focus_txt, rally_txt, dash_txt, callout_txt, active_txt]
		cmd.visible = _host.debug_hud_enabled

	# Debug: count collision shapes / particles to confirm source of circles.
	var dbg := _hud_label("DebugLabel")
	if dbg:
		if not _host.debug_hud_enabled:
			dbg.text = ""
			dbg.visible = false
		else:
			_dbg_cd -= get_process_delta_time()
			if _dbg_cd <= 0.0:
				_dbg_cd = 0.6
				var info := _collect_debug_counts(_host)
				_dbg_text = "DBG CollisionShape2D:%d  CircleShape2D:%d  Particles:%d" % [
					int(info.get("cshape2d", 0)),
					int(info.get("circle2d", 0)),
					int(info.get("particles2d", 0))
				]
				var proj_count: int = _host.get_tree().get_nodes_in_group("projectiles").size()
				_dbg_text += "  Projectiles:%d%s" % [proj_count, " (HIDDEN)" if _host._hide_projectiles else ""]
				var samples_v: Variant = info.get("circle_paths", PackedStringArray())
				var samples: PackedStringArray = samples_v if samples_v is PackedStringArray else PackedStringArray()
				if samples.size() > 0:
					_dbg_text += "\nCircles: " + ", ".join(samples)
				var details_v: Variant = info.get("circle_details", PackedStringArray())
				var details: PackedStringArray = details_v if details_v is PackedStringArray else PackedStringArray()
				if details.size() > 0:
					_dbg_text += "\nCircleSrc: " + " || ".join(details)
			dbg.text = _dbg_text
			dbg.visible = true

	var perf := _hud_label("PerfLabel")
	if perf:
		if not _host.debug_perf_overlay_enabled:
			perf.text = ""
			perf.visible = false
		else:
			perf.text = _host._perf_text
			perf.visible = true

func _make_hud_chip(label_name: String, text: String, accent: Color, font_size: int = 12) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match label_name:
		"RunTimerLabel":
			chip.custom_minimum_size.x = 170
		"BossLabel":
			chip.custom_minimum_size.x = 320
		_:
			chip.custom_minimum_size.x = 120
	var sb := UiSkin.chip_style(accent if accent != null else UiSkin.ACCENT)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.name = label_name
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.clip_text = true
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", UiSkin.TEXT_SOFT)
	chip.add_child(lbl)
	return chip

func _collect_debug_counts(root: Node) -> Dictionary:
	var cshape2d: int = 0
	var circle2d: int = 0
	var particles2d: int = 0
	var circle_paths := PackedStringArray()
	var circle_details := PackedStringArray()

	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back() as Node
		if n is CollisionShape2D:
			cshape2d += 1
			var cs := n as CollisionShape2D
			var sh := cs.shape
			if sh is CircleShape2D:
				circle2d += 1
				if circle_paths.size() < 6:
					circle_paths.append(String(cs.get_path()))
					var parent := cs.get_parent()
					var ppath: String = "<no-parent>"
					var ptype: String = "<no-parent>"
					var scr_path: String = "<no-script>"
					if parent != null:
						ppath = String(parent.get_path())
						ptype = parent.get_class()
						var scr: Script = parent.get_script() as Script
						if scr != null:
							scr_path = String(scr.resource_path)
					circle_details.append("%s | %s | %s" % [ppath, ptype, scr_path])
		elif n is GPUParticles2D or n is CPUParticles2D:
			particles2d += 1
		for ch in n.get_children():
			if ch is Node:
				stack.append(ch)

	return {
		"cshape2d": cshape2d,
		"circle2d": circle2d,
		"particles2d": particles2d,
		"circle_paths": circle_paths,
		"circle_details": circle_details
	}

