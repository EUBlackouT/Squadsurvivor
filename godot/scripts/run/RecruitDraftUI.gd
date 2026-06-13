extends CanvasLayer
class_name RecruitDraftUI

const _MenuMapPreview := preload("res://scripts/ui/MenuMapPreview.gd")
const _PixelUi := preload("res://scripts/ui/PixelUi.gd")

var _host: Node

func _elapsed_minutes() -> float:
	return float(_host.call("_elapsed_minutes"))

static func present(host: Node) -> void:
	if host.has_node("RecruitDraftUI"):
		return
	var ui: CanvasLayer = load("res://scripts/run/RecruitDraftUI.gd").new()
	ui.name = "RecruitDraftUI"
	ui.layer = 100
	ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	ui._host = host
	host.add_child(ui)
	ui._build()

func _build() -> void:
	var map_preview = _MenuMapPreview.new()
	map_preview.name = "MapPreview"
	map_preview.pan_speed = 0.9
	map_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	var rc := _host.get_node_or_null("/root/RunConfig")
	if rc != null and is_instance_valid(rc):
		if rc.has_method("ensure_loaded"):
			rc.ensure_loaded()
		var map_id := String(rc.selected_map_id) if "selected_map_id" in rc else "church"
		var m: Dictionary = rc.get_map(map_id) if rc.has_method("get_map") else {}
		var tex := _MenuMapPreview.load_map_texture(map_id, m)
		if tex != null:
			map_preview.set_preview_texture(tex)
	add_child(map_preview)

	var top_scrim := _draft_scrim(0.82, 0.0)
	top_scrim.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_scrim.offset_bottom = 220
	add_child(top_scrim)

	var bottom_scrim := _draft_scrim(0.0, 0.94)
	bottom_scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_scrim.offset_top = -280
	add_child(bottom_scrim)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.02, 0.03, 0.58)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	backdrop.modulate.a = 0.0
	var bd_tw := backdrop.create_tween()
	bd_tw.tween_property(backdrop, "modulate:a", 1.0, UiSkin.DUR_MED)

	var screen := PanelContainer.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.offset_left = 48
	screen.offset_right = -48
	screen.offset_top = 20
	screen.offset_bottom = -20
	screen.add_theme_stylebox_override("panel", UiSkin.pixel_panel(UiSkin.ACCENT_GOLD, 0.72))
	screen.modulate.a = 0.0
	screen.scale = Vector2(0.98, 0.98)
	add_child(screen)

	var screen_tw := screen.create_tween()
	screen_tw.set_parallel(true)
	screen_tw.tween_property(screen, "modulate:a", 1.0, UiSkin.DUR_MED)
	screen_tw.tween_property(screen, "scale", Vector2.ONE, UiSkin.DUR_MED) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var screen_pad := MarginContainer.new()
	screen_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_pad.add_theme_constant_override("margin_left", UiSkin.SPACE_XL)
	screen_pad.add_theme_constant_override("margin_right", UiSkin.SPACE_XL)
	screen_pad.add_theme_constant_override("margin_top", UiSkin.SPACE_LG)
	screen_pad.add_theme_constant_override("margin_bottom", UiSkin.SPACE_LG)
	screen.add_child(screen_pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiSkin.SPACE_MD)
	screen_pad.add_child(vbox)

	# Header: title left, _host.essence right.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiSkin.SPACE_MD)
	vbox.add_child(head)

	var head_v := VBoxContainer.new()
	head_v.add_theme_constant_override("separation", 0)
	head.add_child(head_v)

	var title := Label.new()
	title.text = "REINFORCEMENTS INBOUND"
	UiSkin.style_label(title, UiSkin.FONT_H1, UiSkin.TEXT)
	head_v.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "SELECT ONE OPERATIVE  ·  KEYS 1 / 2 / 3 TO COMMIT"
	UiSkin.style_label(subtitle, UiSkin.FONT_XS, UiSkin.ACCENT)
	head_v.add_child(subtitle)

	head.add_spacer(true)

	var info_panel := PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", UiSkin.chip_style(UiSkin.ACCENT_GOLD))
	head.add_child(info_panel)
	var info := Label.new()
	info.name = "InfoLabel"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "✧ %d ESSENCE" % _host.essence
	UiSkin.style_label(info, UiSkin.FONT_LEAD, UiSkin.ACCENT_GOLD)
	info_panel.add_child(info)

	# Candidate row fills the screen.
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UiSkin.SPACE_LG)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)

	# Footer: reroll left, skip right.
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	vbox.add_child(btns)

	var reroll_btn := Button.new()
	reroll_btn.text = "↻ REROLL ALL  (%d✧)" % _host.reroll_cost_essence
	reroll_btn.add_theme_font_size_override("font_size", 16)
	reroll_btn.custom_minimum_size = Vector2(240, 48)
	btns.add_child(reroll_btn)
	UiSkin.style_secondary_button(reroll_btn, UiSkin.ACCENT_GOLD)
	UiSkin.add_hover_scale(reroll_btn, 1.02)

	reroll_btn.pressed.connect(func():
		if _host.essence < _host.reroll_cost_essence:
			return
		var s := _host.get_node_or_null("/root/SfxSystem")
		if s and s.has_method("play_ui"):
			s.play_ui("ui.reroll")
		_host.essence -= _host.reroll_cost_essence
		for c in hbox.get_children():
			c.queue_free()
		_populate_recruit_cards(hbox, false)
		info.text = "✧ %d ESSENCE" % _host.essence
	)

	_populate_recruit_cards(hbox, _host._force_rift_next_draft)
	_host._force_rift_next_draft = false

	btns.add_spacer(true)

	var close_btn := Button.new()
	close_btn.text = "SKIP — DECIDE LATER"
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.custom_minimum_size = Vector2(240, 48)
	UiSkin.style_secondary_button(close_btn, UiSkin.ACCENT_RED)
	UiSkin.add_hover_scale(close_btn, 1.02)
	close_btn.pressed.connect(func():
		var s := _host.get_node_or_null("/root/SfxSystem")
		if s and is_instance_valid(s) and s.has_method("play_ui"):
			s.play_ui("ui.pause_close")
		_close()
	)
	btns.add_child(close_btn)

func _populate_recruit_cards(hbox: HBoxContainer, is_rift: bool) -> void:
	var options: Array[CharacterData] = []
	var now_m: float = _elapsed_minutes()
	var max_rarity_rank := _max_recruit_rarity_rank_for_map()

	# Option 1-2: trophies from recent kills
	_host._recent_trophy_pool.shuffle()
	for t in _host._recent_trophy_pool:
		if options.size() >= 2:
			break
		var tc := t as CharacterData
		if tc == null:
			continue
		if _rarity_rank(tc.rarity_id) > max_rarity_rank:
			continue
		options.append(tc)

	# Option 3: random recruit roll; bias upward so each draft has a "worth checking" card.
	var cd := _roll_recruit_for_current_map(now_m + (5.0 if is_rift else 2.0), 24)
	if cd != null:
		options.append(cd)

	# Ensure 3 cards
	var fill_tries := 0
	while options.size() < 3 and fill_tries < 24:
		fill_tries += 1
		var cd2 := _roll_recruit_for_current_map(now_m + 1.5, 14)
		if cd2 != null:
			options.append(cd2)
	# Hard fallback: duplicate existing valid options so the UI always renders 3 cards.
	while options.size() < 3 and not options.is_empty():
		options.append(options[options.size() - 1])
	if options.is_empty():
		# As a last resort, abort draft gracefully instead of showing broken cards.
		_close()
		return
	# Mid-run quality floor: guarantee at least one rare+ candidate.
	if now_m >= 4.0:
		var has_rare_plus := false
		for c in options:
			if _rarity_rank(c.rarity_id) >= 1:
				has_rare_plus = true
				break
		if not has_rare_plus:
			for _i in range(14):
				var boosted := _roll_recruit_for_current_map(now_m + 8.0, 20)
				if boosted != null and _rarity_rank(boosted.rarity_id) >= 1:
					options[options.size() - 1] = boosted
					break

	var card_i := 0
	for c in options:
		var card := _create_character_card(c)
		hbox.add_child(card)
		# Number-key shortcuts: 1/2/3 commits instantly.
		var rb := card.get_meta("recruit_btn", null) as Button
		if rb != null and card_i < 3:
			var sc := Shortcut.new()
			var ev := InputEventKey.new()
			ev.keycode = (KEY_1 + card_i) as Key
			sc.events = [ev]
			rb.shortcut = sc
		# Staggered pop entrance so each candidate lands with its own beat.
		# (Scale, not position: the HBox owns child positions.)
		card.modulate.a = 0.0
		card.scale = Vector2(0.94, 0.94)
		var tw := card.create_tween()
		tw.tween_interval(0.06 + 0.08 * float(card_i))
		tw.set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, UiSkin.DUR_MED)
		tw.tween_property(card, "scale", Vector2.ONE, UiSkin.DUR_MED) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		card_i += 1

func _rarity_rank(rarity_id: String) -> int:
	match rarity_id:
		"mythic":
			return 4
		"legendary":
			return 3
		"epic":
			return 2
		"rare":
			return 1
		_:
			return 0

func _map_tier() -> int:
	return maxi(1, int(_host._map_mod.get("tier", 1)))

func _max_recruit_rarity_rank_for_map() -> int:
	var tier := _map_tier()
	if tier <= 1:
		return 1 # up to rare on easiest maps
	if tier == 2:
		return 2 # up to epic
	if tier == 3:
		return 3 # up to legendary
	return 4 # mythic allowed on top tier

func _roll_recruit_for_current_map(effective_minutes: float, tries: int = 16) -> CharacterData:
	var max_rank := _max_recruit_rarity_rank_for_map()
	for _i in range(maxi(1, tries)):
		var c := CharacterRegistryUtil.build_random_character_data("recruit", _host.rng, effective_minutes, _host._map_mod)
		if c == null:
			continue
		var rr := _rarity_rank(c.rarity_id)
		if rr <= max_rank:
			return c
	# Fallback if rolls keep missing the cap.
	return null

func _draft_class_name(class_type: int) -> String:
	match class_type:
		CharacterData.Class.WARRIOR:
			return "WARRIOR"
		CharacterData.Class.MAGE:
			return "MAGE"
		CharacterData.Class.ROGUE:
			return "ROGUE"
		CharacterData.Class.GUARDIAN:
			return "GUARDIAN"
		CharacterData.Class.HEALER:
			return "HEALER"
		CharacterData.Class.SUMMONER:
			return "SUMMONER"
		_:
			return "UNKNOWN"

func _draft_origin_name(origin: int) -> String:
	match origin:
		CharacterData.Origin.UNDEAD:
			return "UNDEAD"
		CharacterData.Origin.MACHINE:
			return "MACHINE"
		CharacterData.Origin.BEAST:
			return "BEAST"
		CharacterData.Origin.DEMON:
			return "DEMON"
		CharacterData.Origin.ELEMENTAL:
			return "ELEMENTAL"
		CharacterData.Origin.HUMAN:
			return "HUMAN"
		_:
			return "UNKNOWN"

func _create_character_card(cd: CharacterData) -> Control:
	# Tall, portrait-dominant candidate panel; fills its share of the screen.
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 420)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var rarity_col := UnitFactory.rarity_color(cd.rarity_id)
	# Epic+ cards glow at rest so big pulls feel special before you even read them.
	var rare_glow := _rarity_rank(cd.rarity_id) >= 2
	card.add_theme_stylebox_override("panel", _PixelUi.card_frame(rarity_col, rare_glow))
	UiSkin.add_hover_glow(card, rarity_col)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 14)
	card.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pad.add_child(v)

	# Rarity banner: full-width colored strip so the pull quality reads at a glance.
	var banner := PanelContainer.new()
	var banner_sb := StyleBoxFlat.new()
	banner_sb.bg_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.16)
	banner_sb.border_width_bottom = 2
	banner_sb.border_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.65)
	banner_sb.corner_radius_top_left = UiSkin.RADIUS_SM
	banner_sb.corner_radius_top_right = UiSkin.RADIUS_SM
	banner_sb.content_margin_left = 10
	banner_sb.content_margin_right = 10
	banner_sb.content_margin_top = 5
	banner_sb.content_margin_bottom = 5
	banner.add_theme_stylebox_override("panel", banner_sb)
	v.add_child(banner)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	banner.add_child(header)

	var rarity_lbl := Label.new()
	rarity_lbl.text = UnitFactory.rarity_name(cd.rarity_id).to_upper()
	UiSkin.style_label(rarity_lbl, UiSkin.FONT_BODY, rarity_col)
	header.add_child(rarity_lbl)

	# NEW vs UPGRADE badge: the player should instantly know what picking does.
	var cm_badge := _host.get_node_or_null("/root/CollectionManager")
	if cm_badge != null and is_instance_valid(cm_badge) and cm_badge.has_method("find_dupe_by_appearance"):
		var badge := Label.new()
		if int(cm_badge.find_dupe_by_appearance(cd)) < 0:
			badge.text = "★ NEW"
			UiSkin.style_label(badge, UiSkin.FONT_XS, UiSkin.ACCENT_GOLD)
		else:
			badge.text = "▲ UPGRADE"
			UiSkin.style_label(badge, UiSkin.FONT_XS, UiSkin.ACCENT_GREEN)
		header.add_child(badge)

	header.add_spacer(true)

	var arch := Label.new()
	arch.text = cd.archetype_id.to_upper()
	UiSkin.style_label(arch, UiSkin.FONT_BODY, UiSkin.TEXT)
	header.add_child(arch)

	# Identity as color-coded chips instead of one cramped text line.
	var ident_row := HFlowContainer.new()
	ident_row.alignment = FlowContainer.ALIGNMENT_CENTER
	ident_row.add_theme_constant_override("h_separation", 6)
	ident_row.add_theme_constant_override("v_separation", 4)
	v.add_child(ident_row)

	var race_name := String(cd.race_id).to_upper()
	if race_name == "":
		race_name = _draft_origin_name(cd.origin)
	var origin_name := String(cd.origin_id).to_upper()
	if origin_name == "":
		origin_name = _draft_origin_name(cd.origin)
	ident_row.add_child(UiComponents.chip(race_name.capitalize(), UiSkin.race_color(race_name), UiSkin.FONT_XS))
	ident_row.add_child(UiComponents.chip(origin_name.capitalize(), UiSkin.ACCENT, UiSkin.FONT_XS))
	ident_row.add_child(UiComponents.chip(_draft_class_name(cd.class_type).capitalize(), UiSkin.ACCENT_PURPLE, UiSkin.FONT_XS))

	# Set progress: show which squad sets this recruit advances (race sets first).
	var syn_states := SynergySystem.synergy_states_for_cd(cd)
	if not syn_states.is_empty():
		syn_states.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ar := String(a.get("count_tag", "")).begins_with("race:")
			var br := String(b.get("count_tag", "")).begins_with("race:")
			if ar != br:
				return ar
			return int(a.get("count", 0)) > int(b.get("count", 0))
		)
		var syn_lines: Array[String] = []
		for st in syn_states:
			if syn_lines.size() >= 2:
				break
			var syn_nm := String(st.get("name", ""))
			var syn_c := int(st.get("count", 0))
			var next_n := int(st.get("next_tier_count", 0))
			var tier_n := int(st.get("tier_count", 0))
			if next_n > 0 and syn_c + 1 >= next_n:
				syn_lines.append("[color=#ffd973]⬆ %s set %d/%d — COMPLETES[/color]" % [syn_nm, syn_c + 1, next_n])
			elif next_n > 0:
				syn_lines.append("[color=#9eb0c4]%s set %d/%d[/color]" % [syn_nm, syn_c + 1, next_n])
			elif tier_n > 0:
				syn_lines.append("[color=#9eb0c4]%s set maxed[/color]" % syn_nm)
		if not syn_lines.is_empty():
			var syn_rt := RichTextLabel.new()
			syn_rt.bbcode_enabled = true
			syn_rt.fit_content = true
			syn_rt.scroll_active = false
			syn_rt.mouse_filter = Control.MOUSE_FILTER_PASS
			syn_rt.add_theme_font_size_override("normal_font_size", UiSkin.FONT_XS)
			syn_rt.text = "[center]%s[/center]" % "\n".join(syn_lines)
			syn_rt.tooltip_text = "Squad sets grant bonuses at 2 and 4 members.\nCounts compare against your current squad; field this recruit from the Collection before your next deploy."
			v.add_child(syn_rt)

	# Portrait: dominant, animated, on a rarity-tinted stage.
	var portrait_frame := PanelContainer.new()
	var stage_sb := StyleBoxFlat.new()
	stage_sb.bg_color = Color(0.03, 0.045, 0.08, 0.92)
	stage_sb.border_width_bottom = 2
	stage_sb.border_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.35)
	stage_sb.corner_radius_top_left = UiSkin.RADIUS_SM
	stage_sb.corner_radius_top_right = UiSkin.RADIUS_SM
	stage_sb.corner_radius_bottom_left = UiSkin.RADIUS_SM
	stage_sb.corner_radius_bottom_right = UiSkin.RADIUS_SM
	portrait_frame.add_theme_stylebox_override("panel", stage_sb)
	portrait_frame.custom_minimum_size = Vector2(0, 170)
	portrait_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(portrait_frame)

	var portrait_pad := MarginContainer.new()
	portrait_pad.add_theme_constant_override("margin_left", 6)
	portrait_pad.add_theme_constant_override("margin_right", 6)
	portrait_pad.add_theme_constant_override("margin_top", 6)
	portrait_pad.add_theme_constant_override("margin_bottom", 6)
	portrait_frame.add_child(portrait_pad)

	# Animated portrait using a SubViewport so we can render AnimatedSprite2D inside UI.
	var frames := PixellabUtil.walk_frames_from_south_path(cd.sprite_path)
	if frames != null and frames.has_animation("walk_south") and frames.get_frame_count("walk_south") > 0:
		var svc := SubViewportContainer.new()
		svc.custom_minimum_size = Vector2(120, 140)
		svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		svc.stretch = true
		svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		svc.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		portrait_pad.add_child(svc)

		var vp := SubViewport.new()
		vp.size = Vector2i(190, 170)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		svc.add_child(vp)

		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames
		spr.animation = "walk_south"
		spr.play()
		spr.centered = true
		spr.position = Vector2(vp.size.x * 0.5, vp.size.y * 0.5 + 14.0)
		var scale := PixellabUtil.scale_for_target_height(frames, 118.0, 0.40, 1.40)
		spr.scale = Vector2.ONE * scale
		spr.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		vp.add_child(spr)
	else:
		# Fallback to static south portrait if frames missing.
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(120, 140)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex := PixellabUtil.load_rotation_texture(cd.sprite_path)
		if tex == null and cd.pixellab_id != "":
			tex = PixellabUtil.load_rotation_texture("res://assets/pixellab/%s/rotations/south.png" % cd.pixellab_id)
		portrait.texture = tex
		portrait_pad.add_child(portrait)

	var style_label := Label.new()
	var draft_weapon_name := WeaponSystem.weapon_name(cd.weapon_id) if cd.weapon_id != "" else ("MELEE" if cd.attack_style == CharacterData.AttackStyle.MELEE else "RANGED")
	style_label.text = "⚔ %s" % draft_weapon_name
	style_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiSkin.style_label(style_label, UiSkin.FONT_SM, Color(0.78, 0.88, 1.0, 0.90))
	v.add_child(style_label)

	# Stats as mini bars: value + relative strength at a glance.
	var stat_defs: Array = [
		["HP", "%d" % cd.max_hp, clampf(float(cd.max_hp) / 400.0, 0.04, 1.0), Color(0.55, 0.92, 0.62)],
		["DMG", "%d" % cd.attack_damage, clampf(float(cd.attack_damage) / 40.0, 0.04, 1.0), Color(1.0, 0.62, 0.52)],
		["SPD", "%.2fs" % cd.attack_cooldown, clampf(1.0 - (cd.attack_cooldown - 0.4) / 1.6, 0.04, 1.0), Color(0.55, 0.85, 0.95)],
		["RNG", "%d" % int(cd.attack_range), clampf(float(cd.attack_range) / 620.0, 0.04, 1.0), Color(0.88, 0.80, 0.55)],
	]
	for sd in stat_defs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var nm_lbl := Label.new()
		nm_lbl.text = String(sd[0])
		nm_lbl.custom_minimum_size.x = 42
		UiSkin.style_label(nm_lbl, UiSkin.FONT_XS, UiSkin.TEXT_DIM)
		row.add_child(nm_lbl)
		var bar_bg := PanelContainer.new()
		var bg_sb := StyleBoxFlat.new()
		bg_sb.bg_color = Color(1, 1, 1, 0.06)
		bg_sb.corner_radius_top_left = 3
		bg_sb.corner_radius_top_right = 3
		bg_sb.corner_radius_bottom_left = 3
		bg_sb.corner_radius_bottom_right = 3
		bar_bg.add_theme_stylebox_override("panel", bg_sb)
		bar_bg.custom_minimum_size = Vector2(0, 8)
		bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar_bg)
		var fill := ColorRect.new()
		var sc := sd[3] as Color
		fill.color = Color(sc.r, sc.g, sc.b, 0.85)
		fill.custom_minimum_size = Vector2(0, 8)
		fill.size_flags_horizontal = Control.SIZE_FILL
		fill.size_flags_stretch_ratio = float(sd[2])
		var spacer_fill := Control.new()
		spacer_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer_fill.size_flags_stretch_ratio = maxf(0.001, 1.0 - float(sd[2]))
		var bar_h := HBoxContainer.new()
		bar_h.add_theme_constant_override("separation", 0)
		bar_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_bg.add_child(bar_h)
		fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_h.add_child(fill)
		bar_h.add_child(spacer_fill)
		var val_lbl := Label.new()
		val_lbl.text = String(sd[1])
		val_lbl.custom_minimum_size.x = 52
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UiSkin.style_label(val_lbl, UiSkin.FONT_XS, sc)
		row.add_child(val_lbl)

	# Passives as compact chips (tooltip shows full description).
	var pass_title := Label.new()
	pass_title.text = "PASSIVES"
	pass_title.add_theme_font_size_override("font_size", 12)
	pass_title.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 0.85))
	v.add_child(pass_title)

	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	v.add_child(chips)

	var shown := 0
	for pid in cd.passive_ids:
		if shown >= 3:
			break
		var chip := PanelContainer.new()
		var pc := PassiveSystem.passive_color(pid)
		var csb := UiSkin.chip_style(pc)
		chip.add_theme_stylebox_override("panel", csb)
		chip.tooltip_text = "%s\n%s" % [PassiveSystem.passive_name(pid), PassiveSystem.passive_description(pid)]
		chips.add_child(chip)

		var mp := MarginContainer.new()
		mp.add_theme_constant_override("margin_left", 8)
		mp.add_theme_constant_override("margin_right", 8)
		mp.add_theme_constant_override("margin_top", 4)
		mp.add_theme_constant_override("margin_bottom", 4)
		chip.add_child(mp)
		var tl := Label.new()
		tl.text = PassiveSystem.passive_name(pid)
		tl.add_theme_font_size_override("font_size", 12)
		tl.add_theme_color_override("font_color", Color(pc.r, pc.g, pc.b, 0.95))
		mp.add_child(tl)
		shown += 1

	if cd.passive_ids.size() > shown:
		var more := Label.new()
		more.text = "+%d" % (cd.passive_ids.size() - shown)
		more.add_theme_font_size_override("font_size", 12)
		more.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 0.75))
		chips.add_child(more)

	v.add_spacer(true)

	# Primary action dominates; utilities sit beneath it.
	var unlock := Button.new()
	unlock.text = "RECRUIT"
	unlock.custom_minimum_size = Vector2(0, 52)
	unlock.add_theme_font_size_override("font_size", 19)
	UiSkin.style_primary_button(unlock, rarity_col)
	v.add_child(unlock)
	unlock.pressed.connect(func(): _select_character(cd))
	card.set_meta("recruit_btn", unlock)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	v.add_child(btn_row)

	# Banish: replace just this card for 1 _host.essence (cheaper, surgical reroll).
	var banish := Button.new()
	banish.text = "↻ BANISH %d✧" % _host.banish_cost_essence
	banish.tooltip_text = "Banish: replace only this card (%d Essence)" % _host.banish_cost_essence
	banish.custom_minimum_size = Vector2(0, 38)
	banish.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banish.add_theme_font_size_override("font_size", 13)
	UiSkin.style_secondary_button(banish, UiSkin.ACCENT_GOLD)
	btn_row.add_child(banish)
	banish.pressed.connect(func(): _banish_draft_card(card))

	var details := Button.new()
	details.text = "DETAILS"
	details.custom_minimum_size = Vector2(0, 38)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_font_size_override("font_size", 13)
	btn_row.add_child(details)
	UiSkin.style_secondary_button(details)
	details.pressed.connect(func(): _show_character_details(cd))

	return card

func _banish_draft_card(card: Control) -> void:
	var s := _host.get_node_or_null("/root/SfxSystem")
	if _host.essence < _host.banish_cost_essence:
		if s and s.has_method("play_ui"):
			s.play_ui("ui.error")
		return
	var replacement := _roll_recruit_for_current_map(_elapsed_minutes() + 2.0, 24)
	if replacement == null:
		return
	_host.essence -= _host.banish_cost_essence
	if s and s.has_method("play_ui"):
		s.play_ui("ui.reroll")

	var parent := card.get_parent()
	var idx := card.get_index()
	var new_card := _create_character_card(replacement)
	parent.add_child(new_card)
	parent.move_child(new_card, idx)
	card.queue_free()
	new_card.modulate.a = 0.0
	var tw := new_card.create_tween()
	tw.tween_property(new_card, "modulate:a", 1.0, UiSkin.DUR_MED)

	var info := find_child("InfoLabel", true, false) as Label
	if info != null:
		info.text = "✧ %d ESSENCE" % _host.essence

func _show_character_details(cd: CharacterData) -> void:
	if has_node("CharacterDetails"):
		get_node("CharacterDetails").queue_free()
	var layer := CanvasLayer.new()
	layer.name = "CharacterDetails"
	layer.layer = 110
	layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(layer)

	var rarity_col := UnitFactory.rarity_color(cd.rarity_id)

	# Dim behind the sheet; clicking it closes (consistent with other modals).
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UiSkin.BACKDROP_DIM.r, UiSkin.BACKDROP_DIM.g, UiSkin.BACKDROP_DIM.b, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			layer.queue_free()
	)
	layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -360
	panel.offset_top = -240
	panel.offset_right = 360
	panel.offset_bottom = 240
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(panel)
	panel.add_theme_stylebox_override("panel", UiSkin.glowing_panel_style(rarity_col))

	# Standard pop entrance.
	panel.pivot_offset = Vector2(360, 240)
	panel.scale = Vector2(0.94, 0.94)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, UiSkin.DUR_FAST)
	tw.tween_property(panel, "scale", Vector2.ONE, UiSkin.DUR_MED) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", UiSkin.SPACE_LG)
	pad.add_theme_constant_override("margin_right", UiSkin.SPACE_LG)
	pad.add_theme_constant_override("margin_top", UiSkin.SPACE_LG)
	pad.add_theme_constant_override("margin_bottom", UiSkin.SPACE_LG)
	panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiSkin.SPACE_MD)
	pad.add_child(v)

	var t := Label.new()
	t.text = cd.archetype_id.capitalize()
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiSkin.style_label(t, 26, UiSkin.TEXT)
	v.add_child(t)

	var rarity_line := Label.new()
	rarity_line.text = "%s  •  %s" % [UnitFactory.rarity_name(cd.rarity_id).to_upper(), String(cd.race_id).capitalize()]
	rarity_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiSkin.style_label(rarity_line, UiSkin.FONT_BODY, rarity_col)
	v.add_child(rarity_line)

	var weapon_name := WeaponSystem.weapon_name(cd.weapon_id) if cd.weapon_id != "" else ("MELEE" if cd.attack_style == CharacterData.AttackStyle.MELEE else "RANGED")
	var b := Label.new()
	b.text = "⚔ %s\nHP %d  DMG %d  CD %.2f  RNG %d\nCrit %.0f%%  x%.2f" % [
		weapon_name,
		cd.max_hp, cd.attack_damage, cd.attack_cooldown, int(cd.attack_range),
		cd.crit_chance * 100.0, cd.crit_mult
	]
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiSkin.style_label(b, UiSkin.FONT_BODY, UiSkin.TEXT_SOFT)
	v.add_child(b)

	var p := Label.new()
	var lines: Array[String] = []
	for pid in cd.passive_ids:
		lines.append("• %s\n  %s" % [PassiveSystem.passive_name(pid), PassiveSystem.passive_description(pid)])
	p.text = "Passives:\n%s" % "\n".join(lines)
	p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiSkin.style_label(p, UiSkin.FONT_SM, UiSkin.TEXT_SOFT)
	v.add_child(p)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, UiSkin.BUTTON_HEIGHT)
	UiSkin.style_secondary_button(close)
	close.pressed.connect(func(): layer.queue_free())
	v.add_child(close)

func _select_character(cd: CharacterData) -> void:
	# Unlock into persistent collection (NOT directly into squad).
	var cm := _host.get_node_or_null("/root/CollectionManager")
	if cm and is_instance_valid(cm):
		var s := _host.get_node_or_null("/root/SfxSystem")
		var rarity := UnitFactory.rarity_name(cd.rarity_id)
		var col := UnitFactory.rarity_color(cd.rarity_id)
		
		# First try to unlock as new character
		if cm.has_method("unlock_character"):
			var ok: bool = bool(cm.unlock_character(cd))
			if ok:
				# New character unlocked!
				if s and s.has_method("play_ui"):
					s.play_ui("ui.pick")
				if _host.toast_layer != null:
					_host.toast_layer.show_toast("Unlocked: %s • %s" % [rarity, cd.archetype_id], col)
				# Offer immediate deployment (swap or free slot) for this run.
				show_swap_prompt(cd)
				return
		
		# If not new, try to merge as duplicate (upgrade existing character!)
		if cm.has_method("merge_duplicate"):
			var result: Dictionary = cm.merge_duplicate(cd)
			if result.get("success", false):
				# Dupe merged - upgrade!
				if s and s.has_method("play_ui"):
					s.play_ui("ui.levelup")  # Special sound for upgrade
				if _host.toast_layer != null:
					var bonus_text: String = result.get("bonus_text", "")
					_host.toast_layer.show_toast("UPGRADED!\n%s" % bonus_text, Color(1.0, 0.85, 0.25, 1.0))
				# Screen shake for the upgrade feel
				var ss := _host.get_node_or_null("/root/ScreenShake")
				if ss and is_instance_valid(ss) and ss.has_method("shake"):
					ss.shake(5.0, 0.15)
				_close()
				return
		
		# Fallback: exact duplicate with no merge possible
		if s and s.has_method("play_ui"):
			s.play_ui("ui.cancel")
		if _host.toast_layer != null:
			_host.toast_layer.show_toast("Already maxed: %s" % cd.archetype_id, Color(0.7, 0.8, 0.9, 1.0))
	_close()

func show_swap_prompt(cd: CharacterData) -> void:
	# After unlocking, let the player field the recruit right now:
	# free slot -> deploy directly; full squad -> swap out a member for this run.
	var player := _host.get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not player.has_method("replace_squad_unit"):
		_close()
		return

	var squad: Array = []
	if "squad_units" in player:
		for u in (player.get("squad_units") as Array):
			if is_instance_valid(u):
				squad.append(u)

	var cap := 6
	var mp := _host.get_node_or_null("/root/MetaProgression")
	if mp and is_instance_valid(mp) and mp.has_method("get_squad_slots"):
		cap = int(mp.get_squad_slots())
	var has_free_slot := squad.size() < cap

	if has_node("SwapPrompt"):
		get_node("SwapPrompt").queue_free()
	var layer := CanvasLayer.new()
	layer.name = "SwapPrompt"
	layer.layer = 112
	layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UiSkin.BACKDROP_DIM.r, UiSkin.BACKDROP_DIM.g, UiSkin.BACKDROP_DIM.b, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var rarity_col := UnitFactory.rarity_color(cd.rarity_id)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var rows := squad.size() + (1 if has_free_slot else 0)
	var half := Vector2(280.0, clampf(110.0 + 22.0 * float(rows), 150.0, 330.0))
	panel.offset_left = -half.x
	panel.offset_right = half.x
	panel.offset_top = -half.y
	panel.offset_bottom = half.y
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UiSkin.glowing_panel_style(rarity_col))
	layer.add_child(panel)

	panel.pivot_offset = half
	panel.scale = Vector2(0.94, 0.94)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, UiSkin.DUR_FAST)
	tw.tween_property(panel, "scale", Vector2.ONE, UiSkin.DUR_MED) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", UiSkin.SPACE_LG)
	pad.add_theme_constant_override("margin_right", UiSkin.SPACE_LG)
	pad.add_theme_constant_override("margin_top", UiSkin.SPACE_LG)
	pad.add_theme_constant_override("margin_bottom", UiSkin.SPACE_LG)
	panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	pad.add_child(v)

	var title := Label.new()
	title.text = "Deploy %s now?" % cd.archetype_id.capitalize()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiSkin.style_label(title, UiSkin.FONT_H3, rarity_col)
	v.add_child(title)

	var sub := Label.new()
	sub.text = "It's saved to your Collection either way."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiSkin.style_label(sub, UiSkin.FONT_XS, UiSkin.TEXT_DIM)
	v.add_child(sub)

	var tiers_before := _capture_set_tiers()

	if has_free_slot:
		var deploy := Button.new()
		deploy.text = "Deploy Now (free slot)"
		deploy.custom_minimum_size = Vector2(0, UiSkin.BUTTON_HEIGHT)
		UiSkin.style_primary_button(deploy, rarity_col)
		deploy.pressed.connect(func():
			if player.has_method("add_squad_unit"):
				player.add_squad_unit(cd)
			if _host.toast_layer != null:
				_host.toast_layer.show_toast("Deployed: %s" % cd.archetype_id, rarity_col)
			_announce_new_set_tiers(tiers_before, cd)
			layer.queue_free()
			_close()
		)
		v.add_child(deploy)

	if not squad.is_empty():
		var swap_hint := Label.new()
		swap_hint.text = "— or swap out a squad member —"
		swap_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiSkin.style_label(swap_hint, UiSkin.FONT_XS, UiSkin.TEXT_DIM)
		v.add_child(swap_hint)

	for u in squad:
		var ucd := (u as Node).get("character_data") as CharacterData
		if ucd == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiSkin.SPACE_SM)
		v.add_child(row)

		var nm := Label.new()
		var hp_pct := 100
		if (u as Node).has_method("get_hp_ratio"):
			hp_pct = int(round(float((u as Node).call("get_hp_ratio")) * 100.0))
		nm.text = "%s  •  %s  •  %d%% HP" % [ucd.archetype_id.capitalize(), String(ucd.race_id).capitalize(), hp_pct]
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiSkin.style_label(nm, UiSkin.FONT_SM, UiSkin.race_color(String(ucd.race_id)))
		row.add_child(nm)

		var swap_btn := Button.new()
		swap_btn.text = "Swap"
		swap_btn.custom_minimum_size = Vector2(86, 32)
		UiSkin.style_secondary_button(swap_btn, UiSkin.ACCENT_GOLD)
		var swap_target: Node2D = u
		swap_btn.pressed.connect(func():
			var out_name := ucd.archetype_id.capitalize()
			if bool(player.call("replace_squad_unit", swap_target, cd)):
				var s2 := _host.get_node_or_null("/root/SfxSystem")
				if s2 and is_instance_valid(s2) and s2.has_method("play_ui"):
					s2.play_ui("ui.pick")
				if _host.toast_layer != null:
					_host.toast_layer.show_toast("Deployed: %s  (benched %s)" % [cd.archetype_id.capitalize(), out_name], rarity_col)
				_announce_new_set_tiers(tiers_before, cd)
			layer.queue_free()
			_close()
		)
		row.add_child(swap_btn)

	var keep := Button.new()
	keep.text = "Save for Later"
	keep.custom_minimum_size = Vector2(0, UiSkin.BUTTON_HEIGHT)
	UiSkin.style_secondary_button(keep)
	keep.pressed.connect(func():
		layer.queue_free()
		_close()
	)
	v.add_child(keep)

func _capture_set_tiers() -> Dictionary:
	var out: Dictionary = {}
	for a in SynergySystem.get_active_synergies():
		out[String(a.get("id", ""))] = int(a.get("tier", 0))
	return out

func _announce_new_set_tiers(before: Dictionary, _cd: CharacterData) -> void:
	# Celebrate any set tier that activated/upgraded due to the squad change.
	for a in SynergySystem.get_active_synergies():
		var id := String(a.get("id", ""))
		var tier := int(a.get("tier", 0))
		if tier > int(before.get(id, 0)):
			if _host.toast_layer != null:
				_host.toast_layer.show_toast("SET ACTIVE: %s ★%d" % [String(a.get("name", "")), tier], UiSkin.ACCENT_GOLD)
			var s := _host.get_node_or_null("/root/SfxSystem")
			if s and is_instance_valid(s) and s.has_method("play_ui"):
				s.play_ui("ui.levelup")

func _close() -> void:
	queue_free()
	_host.get_tree().paused = false

func _draft_scrim(from_a: float, to_a: float) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, from_a), Color(0, 0, 0, to_a)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr