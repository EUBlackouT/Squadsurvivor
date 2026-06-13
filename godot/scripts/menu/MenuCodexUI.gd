extends Control

var _host: Control
var _built: bool = false

var _info_search: LineEdit = null
var _info_section: OptionButton = null
var _info_list: ItemList = null
var _info_details: RichTextLabel = null
var _info_hint: Label = null
var _info_entries: Array[Dictionary] = []

static func attach(host: Control) -> Control:
	var existing := host.get_node_or_null("MenuCodexUI") as Control
	if existing != null:
		return existing
	var ui: Control = load("res://scripts/menu/MenuCodexUI.gd").new()
	ui.name = "MenuCodexUI"
	ui._host = host
	host.add_child(ui)
	ui._ensure_built()
	ui.visible = false
	return ui

func prewarm() -> void:
	_ensure_built()
	visible = false

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_overlay()

func _apply_font(c: Control) -> void:
	if _host != null and _host.has_method("_apply_font"):
		_host.call("_apply_font", c)

func _play_ui(id: String) -> void:
	if _host != null and _host.has_method("_play_ui"):
		_host.call("_play_ui", id)

func _focus_deploy_button() -> void:
	if _host == null:
		return
	var btn: Button = _host.get("_deploy_btn") as Button
	if btn != null:
		btn.grab_focus()

func _sb_inset(radius: int = 12, alpha: float = 0.86) -> StyleBoxFlat:
	return UiSkin.inset_style(radius, alpha, Color(0.08, 0.06, 0.09, 0.92), Color(0.52, 0.46, 0.38, 0.45))

func open() -> void:
	_ensure_built()
	visible = true
	var shell := get_node_or_null("FullscreenShell") as UiFullscreenShell
	if shell != null:
		shell.animate_in()
	else:
		_animate_open()
	_reload_info_entries()
	if _info_search != null:
		_info_search.grab_focus()

func close() -> void:
	visible = false
	_focus_deploy_button()

func _animate_open() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, UiSkin.DUR_FAST)

func _build_overlay() -> void:
	var shell := UiFullscreenShell.build(
		"Tactical Codex",
		"Search races, passives, synergies, weapons, and live tuning.",
		UiSkin.ACCENT)
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shell)
	shell.close_btn.pressed.connect(func():
		_play_ui("ui.cancel")
		close()
	)

	var v := shell.body

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 10)
	v.add_child(filter_row)

	_info_section = OptionButton.new()
	_info_section.custom_minimum_size = Vector2(190, 34)
	_info_section.add_item("All", 0)
	_info_section.add_item("Overview", 1)
	_info_section.add_item("Stats", 2)
	_info_section.add_item("Passives", 3)
	_info_section.add_item("Synergies", 4)
	_info_section.add_item("Weapons", 5)
	_info_section.add_item("Races", 6)
	_info_section.selected = 0
	_info_section.add_theme_stylebox_override("normal", UiSkin.pixel_inset(0.92))
	_info_section.add_theme_stylebox_override("hover", UiSkin.pixel_inset(0.96))
	_info_section.add_theme_stylebox_override("focus", UiSkin.pixel_inset(0.98))
	_info_section.add_theme_color_override("font_color", UiSkin.TEXT)
	_info_section.add_theme_color_override("font_hover_color", UiSkin.TEXT)
	_info_section.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	filter_row.add_child(_info_section)

	_info_search = LineEdit.new()
	_info_search.placeholder_text = "Search (name, id, tags, description...)"
	_info_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_search.add_theme_stylebox_override("normal", UiSkin.pixel_inset(0.92))
	_info_search.add_theme_stylebox_override("focus", UiSkin.pixel_inset(0.98))
	_info_search.add_theme_color_override("font_color", UiSkin.TEXT)
	_info_search.add_theme_color_override("font_placeholder_color", UiSkin.TEXT_DIM)
	filter_row.add_child(_info_search)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	var left_frame := PanelContainer.new()
	left_frame.custom_minimum_size = Vector2(380, 420)
	left_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_frame.add_theme_stylebox_override("panel", _sb_inset(12, 0.88))
	body.add_child(left_frame)

	var left_pad := MarginContainer.new()
	left_pad.add_theme_constant_override("margin_left", 8)
	left_pad.add_theme_constant_override("margin_right", 8)
	left_pad.add_theme_constant_override("margin_top", 8)
	left_pad.add_theme_constant_override("margin_bottom", 8)
	left_frame.add_child(left_pad)

	_info_list = ItemList.new()
	_info_list.select_mode = ItemList.SELECT_SINGLE
	_info_list.allow_reselect = true
	_info_list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_info_list.add_theme_stylebox_override("selected", UiSkin.list_selected_style(UiSkin.ACCENT))
	_info_list.add_theme_stylebox_override("selected_focus", UiSkin.list_selected_style(UiSkin.ACCENT))
	_info_list.add_theme_font_size_override("font_size", 14)
	_info_list.add_theme_color_override("font_color", UiSkin.TEXT_SOFT)
	_info_list.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_info_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_pad.add_child(_info_list)

	var right_frame := PanelContainer.new()
	right_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_frame.add_theme_stylebox_override("panel", _sb_inset(12, 0.86))
	body.add_child(right_frame)

	var right_pad := MarginContainer.new()
	right_pad.add_theme_constant_override("margin_left", 10)
	right_pad.add_theme_constant_override("margin_right", 10)
	right_pad.add_theme_constant_override("margin_top", 10)
	right_pad.add_theme_constant_override("margin_bottom", 10)
	right_frame.add_child(right_pad)

	var right_v := VBoxContainer.new()
	right_v.add_theme_constant_override("separation", 8)
	right_pad.add_child(right_v)

	_info_hint = Label.new()
	_info_hint.text = "Select an entry on the left."
	_info_hint.add_theme_font_size_override("font_size", 13)
	_info_hint.add_theme_color_override("font_color", Color(0.95, 0.92, 0.80, 0.85))
	_apply_font(_info_hint)
	right_v.add_child(_info_hint)

	_info_details = RichTextLabel.new()
	_info_details.bbcode_enabled = true
	_info_details.fit_content = false
	_info_details.scroll_active = true
	_info_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_details.add_theme_font_size_override("normal_font_size", 13)
	_info_details.add_theme_color_override("default_color", Color(0.94, 0.91, 0.86, 0.96))
	_apply_font(_info_details)
	right_v.add_child(_info_details)

	_info_section.item_selected.connect(func(_idx: int):
		_update_info_list()
	)
	_info_search.text_changed.connect(func(_t: String):
		_update_info_list()
	)
	_info_list.item_selected.connect(func(idx: int):
		_render_info_entry(idx)
	)


func _load_json_dict(path: String) -> Dictionary:
	if path.is_empty() or not ResourceLoader.exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary

func _join_string_array(values: Array) -> String:
	var out: PackedStringArray = PackedStringArray()
	for v in values:
		var s := String(v).strip_edges()
		if s != "":
			out.append(s)
	return ", ".join(out)

func _reload_info_entries() -> void:
	_info_entries.clear()
	_info_entries.append({
		"section": "Overview",
		"title": "Game Loop",
		"id": "overview_game_loop",
		"text": "Draft units, combine synergies, and survive scaling enemy waves. Characters are now tuned as identity units (race + class + role + chase passives)."
	})
	_info_entries.append({
		"section": "Overview",
		"title": "Optimization Basics",
		"id": "overview_builds",
		"text": "Build around one carry and one support core. Chase units have curated signatures; higher rarity opens more passive slots and build variants."
	})
	_info_entries.append({
		"section": "Stats",
		"title": "Stat Meanings",
		"id": "stats_meanings",
		"text": "HP: survivability.\nDamage: hit strength.\nCooldown: attack interval (lower is faster).\nRange: attack distance.\nMove Speed: repositioning and kite potential."
	})
	var ub := _load_json_dict("res://data/unit_balance.json")
	if not ub.is_empty():
		var ctx := ub.get("context_stat_mult", {}) as Dictionary
		var enemy := ctx.get("enemy", {}) as Dictionary
		var recruit := ctx.get("recruit", {}) as Dictionary
		var scal := ub.get("enemy_scaling", {}) as Dictionary
		var txt := "Recruit multipliers: hp x%.2f, dmg x%.2f, move x%.2f\nEnemy multipliers: hp x%.2f, dmg x%.2f, move x%.2f\nEnemy scaling per minute: hp +%.1f%%, dmg +%.1f%%" % [
			float(recruit.get("max_hp", 1.0)), float(recruit.get("attack_damage", 1.0)), float(recruit.get("move_speed", 1.0)),
			float(enemy.get("max_hp", 1.0)), float(enemy.get("attack_damage", 1.0)), float(enemy.get("move_speed", 1.0)),
			float(scal.get("hp_per_minute_mult", 0.0)) * 100.0, float(scal.get("damage_per_minute_mult", 0.0)) * 100.0
		]
		_info_entries.append({
			"section": "Stats",
			"title": "Current Tuning Snapshot",
			"id": "stats_tuning_snapshot",
			"text": txt
		})

	var pd := _load_json_dict("res://data/passives.json")
	for p in pd.get("passives", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var d := p as Dictionary
		var tags := _join_string_array(d.get("tags", []) as Array)
		var body := String(d.get("description", ""))
		if tags != "":
			body += "\nTags: " + tags
		_info_entries.append({
			"section": "Passives",
			"title": String(d.get("name", d.get("id", ""))),
			"id": String(d.get("id", "")),
			"search": String(d.get("id", "")) + " " + tags,
			"text": body
		})

	var sd := _load_json_dict("res://data/synergies.json")
	for s in sd.get("synergies", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sy := s as Dictionary
		var tiers: Array = sy.get("tiers", []) as Array
		var lines: Array[String] = []
		for t in tiers:
			if typeof(t) != TYPE_DICTIONARY:
				continue
			var td := t as Dictionary
			var c := int(td.get("count", 0))
			var mods := td.get("mods", {}) as Dictionary
			lines.append("%d units: %s" % [c, JSON.stringify(mods)])
		_info_entries.append({
			"section": "Synergies",
			"title": String(sy.get("name", sy.get("id", ""))),
			"id": String(sy.get("id", "")),
			"search": String(sy.get("count_tag", "")),
			"text": String(sy.get("description", "")) + ("\n" + "\n".join(lines) if not lines.is_empty() else "")
		})

	var wd := _load_json_dict("res://data/weapons.json")
	for wid in wd.keys():
		var wv: Variant = wd.get(wid, {})
		if typeof(wv) != TYPE_DICTIONARY:
			continue
		var w := wv as Dictionary
		var tags2 := _join_string_array(w.get("tags", []) as Array)
		var txt2 := "%s\nType: %s" % [String(w.get("description", "")), String(w.get("type", ""))]
		if tags2 != "":
			txt2 += "\nTags: " + tags2
		_info_entries.append({
			"section": "Weapons",
			"title": String(w.get("name", String(wid))),
			"id": String(wid),
			"search": tags2,
			"text": txt2
		})

	var cr := _load_json_dict("res://data/character_registry.json")
	var races := cr.get("races", {}) as Dictionary
	for rk in races.keys():
		var rv: Variant = races.get(rk, {})
		if typeof(rv) != TYPE_DICTIONARY:
			continue
		var rd := rv as Dictionary
		_info_entries.append({
			"section": "Races",
			"title": String(rk),
			"id": String(rk).to_lower(),
			"search": _join_string_array(rd.get("passive_slots", []) as Array),
			"text": String(rd.get("description", ""))
		})

	_update_info_list()

func _info_section_name() -> String:
	if _info_section == null:
		return "All"
	return _info_section.get_item_text(_info_section.selected)

func _update_info_list() -> void:
	if _info_list == null:
		return
	_info_list.clear()
	var section := _info_section_name()
	var needle := ""
	if _info_search != null:
		needle = _info_search.text.strip_edges().to_lower()
	var count := 0
	for i in range(_info_entries.size()):
		var e := _info_entries[i]
		var sec := String(e.get("section", ""))
		if section != "All" and sec != section:
			continue
		var hay := "%s %s %s %s %s" % [
			String(e.get("title", "")),
			String(e.get("id", "")),
			String(e.get("text", "")),
			String(e.get("search", "")),
			sec
		]
		if needle != "" and hay.to_lower().find(needle) < 0:
			continue
		var label := "[%s] %s" % [sec, String(e.get("title", e.get("id", "")))]
		_info_list.add_item(label)
		_info_list.set_item_metadata(count, i)
		count += 1
	if _info_hint:
		_info_hint.text = "Results: %d" % count
	if count > 0:
		_info_list.select(0)
		_render_info_entry(0)
	else:
		if _info_details:
			_info_details.text = "No results for current filter."

func _render_info_entry(list_idx: int) -> void:
	if _info_list == null or _info_details == null:
		return
	if list_idx < 0 or list_idx >= _info_list.item_count:
		return
	var meta: Variant = _info_list.get_item_metadata(list_idx)
	if typeof(meta) != TYPE_INT:
		return
	var src_idx := int(meta)
	if src_idx < 0 or src_idx >= _info_entries.size():
		return
	var e := _info_entries[src_idx]
	var title := String(e.get("title", "Entry"))
	var sec := String(e.get("section", ""))
	var id := String(e.get("id", ""))
	var body := String(e.get("text", ""))
	_info_details.text = "[b][color=#ffe0a2]%s[/color][/b]\n[color=#b9b2aa]%s • %s[/color]\n\n%s" % [title, sec, id, body]

