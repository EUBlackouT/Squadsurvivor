extends Control

var _host: Control
var _built: bool = false

const PROTOCOL_GRID_BG_PATH: String = "res://assets/ui/revamp/protocol_grid_bg_v2.webp"
const PROTOCOL_GRID_FRAME_PATH: String = "res://assets/ui/revamp/protocol_grid_frame_v2.webp"
const PROTOCOL_NODE_RING_PATH: String = "res://assets/ui/revamp/protocol_node_ring_v2.webp"
const PROTOCOL_USE_FRAME_OVERLAY: bool = false
const PROTOCOL_USE_TEXTURE_BG: bool = false
const PROTOCOL_ICON_DIR: String = "res://assets/ui/revamp/protocol_icons/"
const PROTOCOL_ICON_BY_FAMILY := {
	"core": "fam_core_v2.webp",
	"vitality": "fam_vitality_v2.webp",
	"offense": "fam_offense_v2.webp",
	"focus": "fam_focus_v2.webp",
	"rally": "fam_command_v2.webp",
	"squad": "fam_command_v2.webp",
	"dash": "fam_mobility_v2.webp",
	"mobility": "fam_mobility_v2.webp",
	"overclock": "fam_overclock_v2.webp",
	"misc": "fam_offense_v2.webp"
}
const PROTOCOL_KEYSTONE_ICON_BY_ID := {
	"starting_unit": "key_starting_unit_v3.webp",
	"focus_keystone": "key_focus_keystone_v3.webp",
	"rally_keystone": "key_rally_keystone_v3.webp",
	"dash_keystone": "key_dash_keystone_v3.webp",
	"squad_keystone": "key_squad_keystone_v3.webp",
	"oc_keystone": "key_oc_keystone_v3.webp",
	"oc_discharge": "key_oc_discharge_v3.webp",
	"starting_unit_2": "key_starting_unit_2_v3.webp",
	"dash_strider": "key_dash_strider_v3.webp",
	"bulwark_keystone": "key_bulwark_keystone_v3.webp",
	"tempo_keystone": "key_tempo_keystone_v3.webp",
	"sniper_grid": "key_marksman_v2.webp",
	"glass_core": "key_glass_v2.webp",
	"blood_circuit": "key_sustain_v2.webp",
	"oc_storm_keystone": "key_oc_storm_keystone_v3.webp",
	"execution_net": "key_execution_net_v3.webp",
	"point_blank_oath": "key_point_blank_oath_v3.webp",
	"conductor_oath": "key_conductor_oath_v3.webp",
	"phalanx_protocol": "key_phalanx_protocol_v3.webp",
	"headhunter_grid": "key_headhunter_grid_v3.webp",
	"fusion_overload": "key_fusion_v2.webp",
	"war_doctrine": "key_war_doctrine_v3.webp",
	"mindforge_oath": "key_mindforge_v2.webp",
	"reaper_clause": "key_reaper_clause_v3.webp",
	"eldritch_drive": "key_eldritch_v2.webp",
	"reaper_momentum": "key_momentum_v2.webp",
	"butcher_protocol": "key_butcher_v2.webp",
	"mirror_aegis": "key_mirror_v2.webp",
	"last_stand_kernel": "key_laststand_v2.webp",
	"feedback_loop": "key_feedback_v2.webp",
	"singularity_drive": "key_singularity_v2.webp",
	"bloodforge_oath": "key_bloodforge_v2.webp",
	"capacitor_lord": "key_capacitor_v2.webp"
}

var _protocol_nodes: Array[Dictionary] = []
var _protocol_node_by_id: Dictionary = {}
var _protocol_edges: Array[Dictionary] = []
var _protocol_upgrades_runtime: Array[Dictionary] = []
var _protocol_selected_id: String = ""
var _protocol_sel_title: Label = null
var _protocol_sel_desc: Label = null
var _protocol_sel_cost: Label = null
var _protocol_buy_btn: Button = null
var _protocol_sigils_lbl: Label = null
var _protocol_sel_effects: RichTextLabel = null
var _protocol_graph_view: Control = null
var _protocol_graph_root: Control = null
var _protocol_dragging: bool = false
var _protocol_drag_candidate: bool = false
var _protocol_drag_start: Vector2 = Vector2.ZERO
var _protocol_drag_last: Vector2 = Vector2.ZERO
var _protocol_pan: Vector2 = Vector2.ZERO
var _protocol_zoom: float = 1.0
var _protocol_hover_id: String = ""
var _protocol_icon_cache: Dictionary = {}
var _protocol_node_ring_tex: Texture2D = null
var _protocol_medallion_cache: Dictionary = {}
var _protocol_node_shell_cache: Dictionary = {}
var _protocol_icon_mask_mat: ShaderMaterial = null
var _protocol_search: LineEdit = null
var _protocol_search_query: String = ""

static func attach(host: Control) -> Control:
	var existing := host.get_node_or_null("ProtocolGridUI") as Control
	if existing != null:
		return existing
	var ui: Control = load("res://scripts/menu/ProtocolGridUI.gd").new()
	ui.name = "ProtocolGridUI"
	ui._host = host
	host.add_child(ui)
	ui._ensure_built()
	return ui

func prewarm() -> void:
	_ensure_built()
	if _protocol_upgrades_runtime.is_empty():
		_protocol_upgrades_runtime = _protocol_data()

func _apply_font(c: Control) -> void:
	if _host != null and _host.has_method("_apply_font"):
		_host.call("_apply_font", c)

func _play_ui(id: String) -> void:
	if _host != null and _host.has_method("_play_ui"):
		_host.call("_play_ui", id)

func _make_menu_button(text: String, is_primary: bool, accent: Color = UiSkin.ACCENT) -> Button:
	return _host.call("_make_menu_button", text, is_primary, accent) as Button

func _refresh_host_sigils() -> void:
	if _host != null and _host.has_method("_refresh_sigils"):
		_host.call("_refresh_sigils")

func _focus_deploy_button() -> void:
	if _host == null:
		return
	var btn: Button = _host.get("_deploy_btn") as Button
	if btn != null:
		btn.grab_focus()

func _load_tex(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _sb_inset(radius: int = 12, alpha: float = 0.86) -> StyleBoxFlat:
	return UiSkin.inset_style(radius, alpha, Color(0.08, 0.06, 0.09, 0.92), Color(0.52, 0.46, 0.38, 0.45))

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_overlay()

func _build_overlay() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.02, 0.04, 0.88)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.name = "PanelContainer"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var vp_h := get_viewport_rect().size.y
	var outer_margin := 18.0
	if vp_h <= 800.0:
		outer_margin = 12.0
	if vp_h <= 740.0:
		outer_margin = 8.0
	panel.offset_left = outer_margin
	panel.offset_top = outer_margin
	panel.offset_right = -outer_margin
	panel.offset_bottom = -outer_margin
	panel.add_theme_stylebox_override("panel", UiSkin.pixel_panel(UiSkin.ACCENT_PURPLE, 0.78))
	add_child(panel)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 8 if vp_h <= 760.0 else 12)
	pad.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "PROTOCOL GRID"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", UiSkin.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_font(title)
	header.add_child(title)

	_protocol_sigils_lbl = Label.new()
	_protocol_sigils_lbl.name = "SigilsLabel"
	_protocol_sigils_lbl.text = "★ 0"
	_protocol_sigils_lbl.add_theme_font_size_override("font_size", 12)
	_protocol_sigils_lbl.add_theme_color_override("font_color", UiSkin.ACCENT_GOLD)
	_apply_font(_protocol_sigils_lbl)
	header.add_child(_protocol_sigils_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(44, 44)
	UiSkin.style_secondary_button(close_btn, UiSkin.ACCENT_RED)
	close_btn.pressed.connect(func():
		_play_ui("ui.cancel")
		close()
	)
	header.add_child(close_btn)

	var sub := Label.new()
	sub.text = "Drag: Left Mouse  •  Zoom: Mouse Wheel  •  Keystone nodes reshape your run."
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.67, 0.78, 0.94, 0.98))
	_apply_font(sub)
	vbox.add_child(sub)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	vbox.add_child(search_row)

	var search_lbl := Label.new()
	search_lbl.text = "Search"
	search_lbl.add_theme_font_size_override("font_size", 13)
	search_lbl.add_theme_color_override("font_color", Color(0.76, 0.86, 0.99, 0.94))
	_apply_font(search_lbl)
	search_row.add_child(search_lbl)

	_protocol_search = LineEdit.new()
	_protocol_search.placeholder_text = "node, effect, element, weapon..."
	_protocol_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_protocol_search.text_changed.connect(func(t: String):
		_protocol_search_query = t.strip_edges().to_lower()
		_update_protocol_grid()
	)
	_protocol_search.text_submitted.connect(func(_t: String):
		_focus_first_protocol_search_match()
	)
	search_row.add_child(_protocol_search)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	var graph_frame := PanelContainer.new()
	# Important: never force a fixed graph height; this caused bottom clipping on 720p windows.
	graph_frame.custom_minimum_size = Vector2.ZERO
	graph_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_frame.add_theme_stylebox_override("panel", _sb_inset(14, 0.88))
	body.add_child(graph_frame)

	var graph_bg := TextureRect.new()
	graph_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	graph_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	graph_bg.stretch_mode = TextureRect.STRETCH_SCALE
	graph_bg.texture = _load_tex(PROTOCOL_GRID_BG_PATH) if PROTOCOL_USE_TEXTURE_BG else null
	graph_bg.modulate = Color(1.0, 1.0, 1.0, 0.22 if PROTOCOL_USE_TEXTURE_BG else 0.0)
	graph_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph_frame.add_child(graph_bg)

	var graph_tint := ColorRect.new()
	graph_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	graph_tint.color = Color(0.03, 0.06, 0.11, 0.86)
	graph_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph_frame.add_child(graph_tint)

	var graph_vignette := ColorRect.new()
	graph_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	graph_vignette.color = Color(0.03, 0.04, 0.08, 0.22)
	graph_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph_frame.add_child(graph_vignette)

	if PROTOCOL_USE_FRAME_OVERLAY and ResourceLoader.exists(PROTOCOL_GRID_FRAME_PATH):
		var frame_tex := load(PROTOCOL_GRID_FRAME_PATH) as Texture2D
		if frame_tex != null:
			var frame_ov := TextureRect.new()
			frame_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
			frame_ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			frame_ov.stretch_mode = TextureRect.STRETCH_SCALE
			frame_ov.texture = frame_tex
			frame_ov.modulate = Color(1.0, 1.0, 1.0, 0.82)
			frame_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame_ov.z_index = 6
			graph_frame.add_child(frame_ov)

	_protocol_graph_view = Control.new()
	_protocol_graph_view.name = "GraphView"
	_protocol_graph_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_protocol_graph_view.clip_contents = true
	_protocol_graph_view.mouse_filter = Control.MOUSE_FILTER_STOP
	graph_frame.add_child(_protocol_graph_view)

	_protocol_graph_root = Control.new()
	_protocol_graph_root.name = "GraphRoot"
	_protocol_graph_root.custom_minimum_size = Vector2(6200, 4600)
	_protocol_graph_view.add_child(_protocol_graph_root)
	_protocol_zoom = 1.0
	_protocol_pan = Vector2.ZERO

	if PROTOCOL_USE_FRAME_OVERLAY and ResourceLoader.exists(PROTOCOL_GRID_FRAME_PATH):
		var frame_top_tex := load(PROTOCOL_GRID_FRAME_PATH) as Texture2D
		if frame_top_tex != null:
			var frame_top := TextureRect.new()
			frame_top.set_anchors_preset(Control.PRESET_FULL_RECT)
			frame_top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			frame_top.stretch_mode = TextureRect.STRETCH_SCALE
			frame_top.texture = frame_top_tex
			frame_top.modulate = Color(1.0, 1.0, 1.0, 0.68)
			frame_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
			graph_frame.add_child(frame_top)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(220, 0)
	side.size_flags_horizontal = Control.SIZE_SHRINK_END
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_stylebox_override("panel", _sb_inset(12, 0.96))
	body.add_child(side)

	var side_pad := MarginContainer.new()
	side_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	side_pad.add_theme_constant_override("margin_left", 10)
	side_pad.add_theme_constant_override("margin_right", 10)
	side_pad.add_theme_constant_override("margin_top", 10)
	side_pad.add_theme_constant_override("margin_bottom", 10)
	side.add_child(side_pad)

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	side_pad.add_child(sv)

	_protocol_sel_title = Label.new()
	_protocol_sel_title.text = "Select a node"
	_protocol_sel_title.add_theme_font_size_override("font_size", 12)
	_protocol_sel_title.add_theme_color_override("font_color", UiSkin.TEXT)
	_apply_font(_protocol_sel_title)
	sv.add_child(_protocol_sel_title)

	_protocol_sel_desc = Label.new()
	_protocol_sel_desc.text = "Travel nodes are small. Keystone nodes are large build changers."
	_protocol_sel_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_protocol_sel_desc.add_theme_font_size_override("font_size", 13)
	_protocol_sel_desc.add_theme_color_override("font_color", UiSkin.TEXT_SOFT)
	_apply_font(_protocol_sel_desc)
	sv.add_child(_protocol_sel_desc)

	_protocol_sel_cost = Label.new()
	_protocol_sel_cost.add_theme_font_size_override("font_size", 16)
	_protocol_sel_cost.add_theme_color_override("font_color", UiSkin.ACCENT_GOLD)
	_apply_font(_protocol_sel_cost)
	sv.add_child(_protocol_sel_cost)

	_protocol_sel_effects = RichTextLabel.new()
	_protocol_sel_effects.bbcode_enabled = true
	_protocol_sel_effects.scroll_active = false
	_protocol_sel_effects.fit_content = true
	_protocol_sel_effects.add_theme_font_size_override("normal_font_size", 12)
	_protocol_sel_effects.add_theme_color_override("default_color", Color(0.80, 0.90, 1.0, 0.95))
	sv.add_child(_protocol_sel_effects)

	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.scroll_active = false
	legend.fit_content = true
	legend.text = "[color=#66ff99]● Owned[/color]  [color=#aee1ff]● Available[/color]  [color=#55657a]● Locked[/color]  [color=#ffd36b]⬢ Keystone[/color]"
	legend.add_theme_font_size_override("normal_font_size", 12)
	legend.add_theme_color_override("default_color", Color(0.74, 0.84, 0.95, 0.9))
	sv.add_child(legend)

	sv.add_spacer(true)

	_protocol_buy_btn = _make_menu_button("Unlock Node", true)
	_protocol_buy_btn.custom_minimum_size = Vector2(0, 48)
	_protocol_buy_btn.pressed.connect(func():
		if _protocol_selected_id == "":
			_play_ui("ui.error")
			return
		_unlock_protocol_node(_protocol_selected_id)
	)
	sv.add_child(_protocol_buy_btn)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var back_btn := _make_menu_button("← Back", false)
	back_btn.custom_minimum_size = Vector2(180, 44)
	back_btn.pressed.connect(func():
		_play_ui("ui.cancel")
		close()
	)
	btn_row.add_child(back_btn)

	var fit_btn := _make_menu_button("Fit Web", false)
	fit_btn.custom_minimum_size = Vector2(160, 44)
	fit_btn.pressed.connect(func():
		_play_ui("ui.click")
		_protocol_fit_to_tree()
	)
	btn_row.add_child(fit_btn)

	_build_protocol_graph()
	_update_protocol_grid()
	call_deferred("_protocol_fit_to_tree")

func open() -> void:
	_ensure_built()
	visible = true
	_animate_open()
	_update_protocol_grid()

func _animate_open() -> void:
	var panel := get_node_or_null("PanelContainer") as Control
	modulate.a = 0.0
	if panel != null:
		panel.scale = Vector2(0.98, 0.98)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, UiSkin.DUR_MED)
	if panel != null:
		tw.tween_property(panel, "scale", Vector2.ONE, UiSkin.DUR_MED) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _build_protocol_graph() -> void:
	if _protocol_graph_root == null or not is_instance_valid(_protocol_graph_root):
		return
	for c in _protocol_graph_root.get_children():
		c.queue_free()
	_protocol_nodes.clear()
	_protocol_edges.clear()
	_protocol_node_by_id.clear()
	_protocol_upgrades_runtime = _protocol_data()
	for upgrade in _protocol_upgrades_runtime:
		var node := _create_protocol_node(upgrade)
		_protocol_graph_root.add_child(node["panel"])
		_protocol_nodes.append(node)
		_protocol_node_by_id[node["id"]] = node
	_draw_protocol_lines(_protocol_graph_root)
	_layout_protocol_tree(_protocol_graph_root)

func _create_protocol_node(upgrade: Dictionary) -> Dictionary:
	var graph_pos: Vector2 = upgrade.get("graph_pos", Vector2.ZERO) as Vector2
	var node_color := _protocol_node_accent_color(upgrade, String(upgrade.get("id", "")))
	var is_keystone := bool(upgrade.get("is_keystone", false))
	var is_major := bool(upgrade.get("is_major", false))

	var node_size := Vector2(56, 56)
	if is_major:
		node_size = Vector2(90, 90)
	if is_keystone:
		node_size = Vector2(132, 132)

	var panel := PanelContainer.new()
	panel.name = String(upgrade.get("id", "node"))
	panel.custom_minimum_size = node_size
	panel.position = graph_pos - node_size * 0.5
	panel.z_index = 4

	var shell := TextureRect.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shell.texture = _protocol_node_shell_texture(int(node_size.x), node_color, is_keystone, is_major)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(shell)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	sb.border_color = Color(0.0, 0.0, 0.0, 0.0)
	var radius := int(node_size.y * 0.5)
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	sb.border_width_bottom = 0
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.0)
	sb.shadow_size = 0
	panel.add_theme_stylebox_override("panel", sb)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var vcenter := VBoxContainer.new()
	vcenter.alignment = BoxContainer.ALIGNMENT_CENTER
	vcenter.add_theme_constant_override("separation", 2)
	center.add_child(vcenter)

	var icon_tex := _protocol_icon_texture_for_id(String(upgrade.get("id", "")), is_keystone)
	if icon_tex != null:
		var icon_size := 22.0 if not is_major else 30.0
		if is_keystone:
			icon_size = 44.0
		var icon_stack := Control.new()
		icon_stack.custom_minimum_size = Vector2(icon_size + 8.0, icon_size + 8.0)
		icon_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vcenter.add_child(icon_stack)

		var med := TextureRect.new()
		med.set_anchors_preset(Control.PRESET_FULL_RECT)
		med.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		med.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		med.texture = _protocol_medallion_texture(int(round(icon_size + 8.0)), node_color, is_keystone)
		med.modulate = Color(1.0, 1.0, 1.0, 0.95)
		med.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_stack.add_child(med)

		var icon_rect := TextureRect.new()
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.offset_left = 3.0
		icon_rect.offset_top = 3.0
		icon_rect.offset_right = -3.0
		icon_rect.offset_bottom = -3.0
		icon_rect.texture = icon_tex
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.modulate = Color(1.0, 1.0, 1.0, 0.98)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _protocol_icon_mask_mat == null:
			var sh := Shader.new()
			sh.code = "shader_type canvas_item;\nvoid fragment(){\n\tvec2 uv = UV * 2.0 - 1.0;\n\tfloat r = length(uv);\n\tfloat circle = smoothstep(1.03, 0.82, r);\n\tvec4 t = texture(TEXTURE, UV);\n\tfloat lum = dot(t.rgb, vec3(0.299, 0.587, 0.114));\n\tfloat sat = max(max(t.r, t.g), t.b) - min(min(t.r, t.g), t.b);\n\tfloat ink = max(lum, sat * 1.35);\n\tfloat symbol = smoothstep(0.14, 0.52, ink);\n\tfloat alpha = max(t.a, symbol) * circle;\n\tvec3 col = mix(vec3(0.08, 0.11, 0.16), clamp(t.rgb * 1.24, vec3(0.0), vec3(1.0)), symbol);\n\tfloat rim = smoothstep(0.94, 0.70, r) * 0.14;\n\tCOLOR = vec4(col + rim, alpha);\n}\n"
			_protocol_icon_mask_mat = ShaderMaterial.new()
			_protocol_icon_mask_mat.shader = sh
		icon_rect.material = _protocol_icon_mask_mat
		icon_stack.add_child(icon_rect)
	else:
		var icon_lbl := Label.new()
		icon_lbl.text = String(upgrade.get("icon", "N"))
		icon_lbl.add_theme_font_size_override("font_size", 14 if not is_major else 18)
		if is_keystone:
			icon_lbl.add_theme_font_size_override("font_size", 22)
		icon_lbl.add_theme_color_override("font_color", node_color)
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_apply_font(icon_lbl)
		vcenter.add_child(icon_lbl)

	var mini := Label.new()
	mini.text = _protocol_short_name(String(upgrade.get("name", "")))
	mini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mini.add_theme_font_size_override("font_size", 8 if not is_keystone else 9)
	mini.add_theme_color_override("font_color", Color(0.84, 0.92, 1.0, 0.90))
	_apply_font(mini)
	if is_keystone or is_major:
		vcenter.add_child(mini)

	var btn_overlay := Button.new()
	btn_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_overlay.flat = true
	btn_overlay.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_child(btn_overlay)

	var upgrade_id := String(upgrade.get("id", ""))
	panel.tooltip_text = "%s\n%s\nCost: ★ %d" % [
		String(upgrade.get("name", upgrade_id)),
		String(upgrade.get("desc", "")),
		int(upgrade.get("cost", 0))
	]
	btn_overlay.pressed.connect(func():
		_protocol_selected_id = upgrade_id
		_update_protocol_grid()
		var tw := panel.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "scale", Vector2(1.16, 1.16), 0.06)
		tw.tween_property(panel, "scale", Vector2(1.10, 1.10), 0.08)
	)
	btn_overlay.mouse_entered.connect(func():
		_protocol_hover_id = upgrade_id
		_on_protocol_node_hovered(upgrade_id, true)
		_update_protocol_grid()
	)
	btn_overlay.mouse_exited.connect(func():
		if _protocol_hover_id == upgrade_id:
			_protocol_hover_id = ""
		_on_protocol_node_hovered(upgrade_id, false)
		_update_protocol_grid()
	)

	return {
		"id": upgrade_id,
		"panel": panel,
		"color": node_color,
		"upgrade": upgrade,
		"is_keystone": is_keystone,
		"is_major": is_major
	}

func _draw_protocol_lines(container: Control) -> void:
	for ch in container.get_children():
		if ch is Line2D:
			ch.queue_free()
		elif ch is Control and String(ch.name).begins_with("EdgeDot_"):
			ch.queue_free()
	_protocol_edges.clear()
	for node in _protocol_nodes:
		var upgrade: Dictionary = node.get("upgrade", {})
		var prereqs: Array = upgrade.get("prereq", [])
		var panel: Control = node.get("panel")
		if panel == null:
			continue
		var to_pos := panel.position + panel.size * 0.5
		for prereq_id in prereqs:
			var from: Dictionary = _protocol_node_by_id.get(String(prereq_id), {}) as Dictionary
			var from_panel: Control = from.get("panel", null) as Control
			if from_panel == null:
				continue
			var from_pos := from_panel.position + from_panel.size * 0.5
			var fam_col := _protocol_node_accent_color(upgrade, String(node.get("id", "")))
			var line := Line2D.new()
			line.width = 3.2
			line.default_color = Color(fam_col.r, fam_col.g, fam_col.b, 0.68)
			line.antialiased = true
			line.points = [from_pos, to_pos]
			line.z_index = 3
			var under := Line2D.new()
			under.width = 8.2
			under.default_color = Color(fam_col.r * 0.45, fam_col.g * 0.45, fam_col.b * 0.45, 0.22)
			under.antialiased = true
			under.points = [from_pos, to_pos]
			under.z_index = 2
			container.add_child(under)
			container.add_child(line)
			var from_id := String(prereq_id)
			var to_id := String(node.get("id", ""))
			var bridge := _protocol_is_visual_bridge_edge(from_id, to_id)
			_protocol_edges.append({"from": from_id, "to": to_id, "line": line, "under": under, "family_color": fam_col, "bridge": bridge})

func _update_protocol_grid() -> void:
	var mp := get_node_or_null("/root/MetaProgression")
	var sigils := 0
	var unlocked: Array = []
	if mp and is_instance_valid(mp):
		if mp.has_method("get_sigils"):
			sigils = int(mp.get_sigils())
		if mp.has_method("get_unlocked_upgrades"):
			unlocked = mp.get_unlocked_upgrades()

	if _protocol_sigils_lbl != null and is_instance_valid(_protocol_sigils_lbl):
		_protocol_sigils_lbl.text = "★ %d" % sigils

	var detail_id := _protocol_selected_id if _protocol_hover_id == "" else _protocol_hover_id
	var trace_ids := _protocol_trace_ids(detail_id)

	for node in _protocol_nodes:
		var id := String(node.get("id", ""))
		var panel: PanelContainer = node.get("panel", null) as PanelContainer
		var upgrade: Dictionary = node.get("upgrade", {})
		if panel == null:
			continue
		var matches_search := _protocol_node_matches_search(upgrade)

		var is_unlocked := id in unlocked
		var prereqs: Array = upgrade.get("prereq", [])
		var prereqs_met := true
		for prereq_id in prereqs:
			if not String(prereq_id) in unlocked:
				prereqs_met = false
				break

		var cost := int(upgrade.get("cost", 0))
		var can_afford := sigils >= cost
		if is_unlocked:
			panel.self_modulate = Color(0.90, 1.0, 0.94, 1.0)
		elif prereqs_met and can_afford:
			panel.self_modulate = Color(0.98, 1.0, 1.0, 1.0)
		elif prereqs_met:
			panel.self_modulate = Color(0.84, 0.90, 0.98, 0.95)
		else:
			panel.self_modulate = Color(0.58, 0.64, 0.74, 0.82)
		if _protocol_search_query != "" and not matches_search:
			panel.self_modulate = Color(panel.self_modulate.r * 0.56, panel.self_modulate.g * 0.56, panel.self_modulate.b * 0.58, 0.26)
		panel.modulate = Color(1, 1, 1, 1)
		panel.scale = Vector2(1.10, 1.10) if id == _protocol_selected_id else (Vector2(1.06, 1.06) if trace_ids.has(id) else Vector2.ONE)
		if trace_ids.has(id) and not is_unlocked:
			panel.self_modulate = Color(
				minf(1.0, panel.self_modulate.r + 0.10),
				minf(1.0, panel.self_modulate.g + 0.10),
				minf(1.0, panel.self_modulate.b + 0.10),
				panel.self_modulate.a
			)

	for e in _protocol_edges:
		var line := e.get("line", null) as Line2D
		var under := e.get("under", null) as Line2D
		if line == null:
			continue
		var from_id := String(e.get("from", ""))
		var to_id := String(e.get("to", ""))
		var bridge := bool(e.get("bridge", false))
		var edge_visible := true
		if _protocol_search_query != "":
			var from_u := _protocol_find_upgrade(from_id)
			var to_u := _protocol_find_upgrade(to_id)
			edge_visible = _protocol_node_matches_search(from_u) or _protocol_node_matches_search(to_u)
		var from_owned := from_id in unlocked
		var to_owned := to_id in unlocked
		var to_available := from_owned and (not to_owned)
		var fam_col := e.get("family_color", Color(0.57, 0.85, 1.0, 1.0)) as Color
		if trace_ids.has(from_id) and trace_ids.has(to_id):
			line.default_color = Color(1.0, 0.92, 0.58, 0.95)
			line.width = 4.8
			if under != null:
				under.default_color = Color(1.0, 0.82, 0.38, 0.30)
				under.width = 10.2
		elif from_owned and to_owned:
			line.default_color = Color(0.55, 1.0, 0.70, 0.84)
			line.width = 4.0
			if under != null:
				under.default_color = Color(0.35, 0.95, 0.55, 0.22)
				under.width = 8.8
		elif to_available:
			line.default_color = Color(fam_col.r, fam_col.g, fam_col.b, 0.78)
			line.width = 3.6
			if under != null:
				under.default_color = Color(fam_col.r * 0.45, fam_col.g * 0.45, fam_col.b * 0.45, 0.18)
				under.width = 8.0
		else:
			line.default_color = Color(fam_col.r * 0.75, fam_col.g * 0.75, fam_col.b * 0.75, 0.42)
			line.width = 3.0
			if under != null:
				under.default_color = Color(fam_col.r * 0.35, fam_col.g * 0.35, fam_col.b * 0.35, 0.12)
				under.width = 7.2
		var trace_edge := trace_ids.has(from_id) and trace_ids.has(to_id)
		if bridge and (not trace_edge):
			# Bridge links stay visible, but remain visually secondary.
			line.default_color = Color(line.default_color.r, line.default_color.g, line.default_color.b, line.default_color.a * 0.40)
			line.width = maxf(1.2, line.width * 0.64)
			if under != null:
				under.default_color = Color(under.default_color.r, under.default_color.g, under.default_color.b, under.default_color.a * 0.18)
				under.width = maxf(1.8, under.width * 0.54)
				under.visible = edge_visible
			line.visible = edge_visible
		else:
			line.visible = edge_visible
			if under != null:
				under.visible = edge_visible
		if not edge_visible:
			line.default_color = Color(line.default_color.r, line.default_color.g, line.default_color.b, line.default_color.a * 0.18)
			line.width = maxf(1.2, line.width * 0.62)
			if under != null:
				under.default_color = Color(under.default_color.r, under.default_color.g, under.default_color.b, under.default_color.a * 0.12)
				under.width = maxf(2.0, under.width * 0.62)

	if _protocol_sel_title != null and _protocol_sel_desc != null and _protocol_sel_cost != null:
		var nd := _protocol_find_upgrade(detail_id)
		if nd.is_empty():
			_protocol_sel_title.text = "Select a node"
			_protocol_sel_desc.text = "Choose a path node to plan your build."
			_protocol_sel_cost.text = ""
			if _protocol_sel_effects:
				_protocol_sel_effects.text = ""
			if _protocol_buy_btn:
				_protocol_buy_btn.disabled = true
		else:
			_protocol_sel_title.text = String(nd.get("name", detail_id))
			var detail_desc := String(nd.get("desc", ""))
			var cst := int(nd.get("cost", 0))
			var owned := detail_id in unlocked
			var req_tier := 1
			var cur_tier := 1
			var tier_blocked := false
			if mp != null and is_instance_valid(mp) and mp.has_method("get_node_unlock_requirements"):
				var req: Dictionary = mp.get_node_unlock_requirements(detail_id) as Dictionary
				if not req.is_empty():
					req_tier = int(req.get("required_map_tier", 1))
					cur_tier = int(req.get("current_map_tier", 1))
					tier_blocked = bool(req.get("map_tier_blocked", false))
			if tier_blocked:
				detail_desc += "\n\n[Tier Gate] Requires map tier %d (current: %d)." % [req_tier, cur_tier]
			_protocol_sel_desc.text = detail_desc
			if owned:
				_protocol_sel_cost.text = "Owned"
			elif tier_blocked:
				_protocol_sel_cost.text = "Locked: Map Tier %d required" % req_tier
			else:
				_protocol_sel_cost.text = "Cost: ★ %d" % cst
			if _protocol_sel_effects:
				_protocol_sel_effects.text = _protocol_effects_bbcode(nd)
			if _protocol_buy_btn:
				var can_buy := false
				if mp != null and is_instance_valid(mp) and mp.has_method("can_buy_node"):
					can_buy = bool(mp.can_buy_node(detail_id))
				_protocol_buy_btn.disabled = owned or (not can_buy)
func _unlock_protocol_node(upgrade_id: String) -> void:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp):
		return
	if not mp.has_method("buy_node"):
		_play_ui("ui.error")
		return
	if not bool(mp.buy_node(upgrade_id)):
		_play_ui("ui.error")
		return
	_play_ui("ui.levelup")
	_update_protocol_grid()

func _protocol_find_upgrade(id: String) -> Dictionary:
	for u in _protocol_upgrades_runtime:
		if String(u.get("id", "")) == id:
			return u
	return {}

func _on_protocol_node_hovered(upgrade_id: String, hovered: bool) -> void:
	for node in _protocol_nodes:
		if String(node.get("id", "")) != upgrade_id:
			continue
		var panel: Control = node.get("panel", null) as Control
		if panel == null:
			break
		var target_scale := Vector2(1.08, 1.08) if String(node.get("id", "")) == _protocol_selected_id else Vector2.ONE
		if hovered:
			target_scale = Vector2(1.12, 1.12)
		var t := panel.create_tween()
		t.tween_property(panel, "scale", target_scale, 0.10)
		break

func close() -> void:
	visible = false
	_protocol_drag_candidate = false
	_protocol_dragging = false
	_protocol_hover_id = ""
	_protocol_search_query = ""
	if _protocol_search != null and is_instance_valid(_protocol_search):
		_protocol_search.clear()
	_focus_deploy_button()
	_refresh_host_sigils()

func _layout_protocol_tree(root: Control) -> void:
	if root == null or not is_instance_valid(root):
		return
	if _protocol_nodes.is_empty():
		return
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for n in _protocol_nodes:
		var panel := n.get("panel", null) as Control
		if panel == null:
			continue
		var center := panel.position + panel.size * 0.5
		minp.x = minf(minp.x, center.x)
		minp.y = minf(minp.y, center.y)
		maxp.x = maxf(maxp.x, center.x)
		maxp.y = maxf(maxp.y, center.y)
	var padding := Vector2(420, 360)
	root.custom_minimum_size = Vector2(
		maxf(2200.0, (maxp.x - minp.x) + padding.x * 2.0),
		maxf(1600.0, (maxp.y - minp.y) + padding.y * 2.0)
	)
	var shift := Vector2(padding.x - minp.x, padding.y - minp.y)
	for n2 in _protocol_nodes:
		var panel2 := n2.get("panel", null) as Control
		if panel2 == null:
			continue
		panel2.position += shift
	_draw_protocol_lines(root)
	_clamp_protocol_pan()
	_apply_protocol_pan()

func _focus_protocol_graph() -> void:
	if _protocol_graph_view == null or not is_instance_valid(_protocol_graph_view):
		return
	if _protocol_graph_root == null or not is_instance_valid(_protocol_graph_root):
		return
	var target := Vector2(_protocol_graph_root.custom_minimum_size.x * 0.5, _protocol_graph_root.custom_minimum_size.y * 0.5)
	var mp := get_node_or_null("/root/MetaProgression")
	var unlocked: Array = []
	if mp and is_instance_valid(mp) and mp.has_method("get_unlocked_upgrades"):
		unlocked = mp.get_unlocked_upgrades()
	for n in _protocol_nodes:
		var id := String(n.get("id", ""))
		if id in unlocked:
			var panel := n.get("panel", null) as Control
			if panel != null:
				target = panel.position + panel.size * 0.5
				if _protocol_selected_id == "":
					_protocol_selected_id = id
				break
	var viewport_size := _protocol_graph_view.size
	_protocol_pan = viewport_size * 0.5 - target * _protocol_zoom
	_clamp_protocol_pan()
	_apply_protocol_pan()
	_update_protocol_grid()

func _focus_protocol_node(id: String) -> void:
	if _protocol_graph_view == null or not is_instance_valid(_protocol_graph_view):
		return
	var nd := _protocol_node_by_id.get(id, {}) as Dictionary
	var panel := nd.get("panel", null) as Control
	if panel == null:
		return
	var target := panel.position + panel.size * 0.5
	var viewport_size := _protocol_graph_view.size
	_protocol_pan = viewport_size * 0.5 - target * _protocol_zoom
	_clamp_protocol_pan()
	_apply_protocol_pan()

func _protocol_fit_to_tree() -> void:
	if _protocol_graph_view == null or not is_instance_valid(_protocol_graph_view):
		return
	if _protocol_graph_root == null or not is_instance_valid(_protocol_graph_root):
		return
	var view_size := _protocol_graph_view.size
	var root_size := _protocol_graph_root.custom_minimum_size
	if root_size.x <= 1.0 or root_size.y <= 1.0:
		return
	var pad := Vector2(42.0, 42.0)
	var zx := (view_size.x - pad.x) / root_size.x
	var zy := (view_size.y - pad.y) / root_size.y
	_protocol_zoom = clampf(minf(zx, zy), 0.06, 2.40)
	var center := root_size * 0.5
	_protocol_pan = view_size * 0.5 - center * _protocol_zoom
	_clamp_protocol_pan()
	_apply_protocol_pan()

func _protocol_data() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp) or (not mp.has_method("tree_data")):
		return out
	var tree: Dictionary = mp.tree_data()
	var nodes: Array = tree.get("nodes", []) as Array
	var filtered: Array[Dictionary] = []
	for n in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var d := n as Dictionary
		var id := String(d.get("id", ""))
		if id == "":
			continue
		var pos_arr := d.get("pos", [0, 0]) as Array
		var px := float(pos_arr[0]) if pos_arr.size() > 0 else 0.0
		var py := float(pos_arr[1]) if pos_arr.size() > 1 else 0.0
		d["__pos_v2"] = Vector2(px, py)
		filtered.append(d)
	if filtered.is_empty():
		return out

	var graph_size := Vector2(22000, 16800)
	var center := graph_size * 0.5
	var node_by_id: Dictionary = {}
	for d in filtered:
		node_by_id[String(d.get("id", ""))] = d
	var depth_cache: Dictionary = {}
	var per_depth_groups: Dictionary = {}
	var sorted_nodes: Array[Dictionary] = filtered.duplicate()
	sorted_nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var aid := String(a.get("id", ""))
		var bid := String(b.get("id", ""))
		var da := _protocol_node_depth(aid, node_by_id, depth_cache)
		var db := _protocol_node_depth(bid, node_by_id, depth_cache)
		if da != db:
			return da < db
		return aid < bid
	)
	var placed: Dictionary = {}
	for d2 in sorted_nodes:
		var id2 := String(d2.get("id", ""))
		var depth := _protocol_node_depth(id2, node_by_id, depth_cache)
		var family := _protocol_family_key(id2)
		var cluster := String(d2.get("cluster", ""))
		var key := "%s|%d|%s" % [family, depth, cluster]
		if not per_depth_groups.has(key):
			per_depth_groups[key] = []
		(per_depth_groups[key] as Array).append(d2)

	for gk in per_depth_groups.keys():
		var group := per_depth_groups[gk] as Array
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa: Vector2 = a.get("__pos_v2", Vector2.ZERO) as Vector2
			var pb: Vector2 = b.get("__pos_v2", Vector2.ZERO) as Vector2
			if absf(pa.y - pb.y) > 0.01:
				return pa.y < pb.y
			return pa.x < pb.x
		)

	for d2 in sorted_nodes:
		var id2 := String(d2.get("id", ""))
		var depth := _protocol_node_depth(id2, node_by_id, depth_cache)
		var family := _protocol_family_key(id2)
		var cluster := String(d2.get("cluster", ""))
		var key := "%s|%d|%s" % [family, depth, cluster]
		var group2 := per_depth_groups.get(key, []) as Array
		var idx := maxi(0, group2.find(d2))
		var lane_count := maxi(1, group2.size())
		var lane := float(idx) - float(lane_count - 1) * 0.5
		var base_angle := _protocol_family_angle(family) + _protocol_cluster_angle_offset(cluster)
		var radial := Vector2.from_angle(base_angle)
		var tangent := Vector2(-radial.y, radial.x)
		var radius := 320.0 + float(depth) * 640.0
		if _protocol_is_keystone(d2):
			radius += 160.0
		elif _protocol_is_major(d2):
			radius += 90.0
		var pos_v: Vector2 = d2.get("__pos_v2", Vector2.ZERO) as Vector2
		var norm_lane := clampf((pos_v.x * 0.00072) + (pos_v.y * 0.00062), -1.0, 1.0)
		var gp := center + radial * radius + tangent * (lane * 360.0 + norm_lane * 130.0)
		var prereq_raw := d2.get("prereq", []) as Array
		var prereq: Array[String] = []
		for p in prereq_raw:
			var ps := String(p)
			if ps != "":
				prereq.append(ps)
		if not prereq.is_empty():
			var centroid := Vector2.ZERO
			var ncount := 0
			for pid in prereq:
				if placed.has(pid):
					centroid += placed[pid] as Vector2
					ncount += 1
			if ncount > 0:
				centroid /= float(ncount)
				# Keep structured sector identity, but pull toward parent neighborhood
				# to reduce long edge crossings and "random web" diagonals.
				gp = gp.lerp(centroid + radial * 380.0, 0.18)
		if id2 == "core_0":
			gp = center
		placed[id2] = gp
		var name2 := String(d2.get("name", id2))
		var desc2 := String(d2.get("desc", ""))
		var cost2 := int(d2.get("cost", 0))
		out.append({
			"id": id2,
			"name": name2,
			"desc": desc2,
			"cost": cost2,
			"icon": _protocol_icon_for_node(d2),
			"color": _protocol_color_for_node(d2),
			"is_keystone": _protocol_is_keystone(d2),
			"is_major": _protocol_is_major(d2),
			"prereq": prereq,
			"graph_pos": gp,
			"cluster": String(d2.get("cluster", "")),
			"search": _protocol_node_search_blob(d2)
		})

	# Separation pass: prevent tight visual clumps while preserving radial structure.
	for _iter in range(0, 12):
		for i in range(out.size()):
			var a := out[i] as Dictionary
			var id_a := String(a.get("id", ""))
			if id_a == "" or id_a == "core_0":
				continue
			var pa: Vector2 = a.get("graph_pos", Vector2.ZERO) as Vector2
			var push := Vector2.ZERO
			for j in range(out.size()):
				if i == j:
					continue
				var b := out[j] as Dictionary
				var pb: Vector2 = b.get("graph_pos", Vector2.ZERO) as Vector2
				var delta := pa - pb
				var dist := delta.length()
				var min_sep := 220.0
				if bool(a.get("is_keystone", false)) or bool(b.get("is_keystone", false)):
					min_sep = 300.0
				elif bool(a.get("is_major", false)) or bool(b.get("is_major", false)):
					min_sep = 260.0
				if dist > 0.01 and dist < min_sep:
					push += delta.normalized() * (min_sep - dist)
			if push.length_squared() <= 0.01:
				continue
			var radial_delta := pa - center
			if radial_delta.length_squared() <= 0.01:
				continue
			var radial_dir := radial_delta.normalized()
			var tangent := Vector2(-radial_dir.y, radial_dir.x)
			var tangential_push := tangent * push.dot(tangent) * 0.30
			var radial_push := radial_dir * clampf(push.dot(radial_dir) * 0.06, -20.0, 20.0)
			pa += tangential_push + radial_push
			var depth_a := _protocol_node_depth(id_a, node_by_id, depth_cache)
			var ideal_radius := 320.0 + float(depth_a) * 640.0
			if bool(a.get("is_keystone", false)):
				ideal_radius += 160.0
			elif bool(a.get("is_major", false)):
				ideal_radius += 90.0
			var r_now := (pa - center).length()
			if r_now > 0.01:
				var r_blend := lerpf(r_now, ideal_radius, 0.10)
				pa = center + (pa - center).normalized() * r_blend
			a["graph_pos"] = pa
			out[i] = a
	return out

func _protocol_family_angle(family: String) -> float:
	match family:
		"core": return -PI * 0.5
		"vitality": return -PI * 0.80
		"offense": return -PI * 0.18
		"focus": return PI * 0.06
		"rally": return PI * 0.42
		"squad": return PI * 0.78
		"dash": return PI * 1.06
		"overclock": return PI * 1.42
		"mobility": return PI * 1.66
		_: return -PI * 0.34

func _protocol_cluster_angle_offset(cluster: String) -> float:
	match cluster:
		"storm": return -0.10
		"fire": return 0.08
		"frost": return 0.20
		"poison": return 0.34
		"projectile": return -0.06
		"scatter": return -0.20
		"ricochet": return -0.30
		"pierce": return -0.42
		"bomb": return 0.00
		"beam": return 0.26
		"orbital": return 0.44
		"hybrid": return 0.14
		_: return 0.0

func _protocol_is_visual_bridge_edge(from_id: String, to_id: String) -> bool:
	if from_id == "" or to_id == "":
		return false
	if to_id.find("bridge_") >= 0 or to_id.find("doctrine_link_") >= 0:
		return true
	if to_id.find("hybrid_") >= 0:
		return true
	var ff := _protocol_family_key(from_id)
	var tf := _protocol_family_key(to_id)
	return ff != tf

func _protocol_node_search_blob(node: Dictionary) -> String:
	var bits: Array[String] = []
	bits.append(String(node.get("id", "")))
	bits.append(String(node.get("name", "")))
	bits.append(String(node.get("desc", "")))
	bits.append(String(node.get("cluster", "")))
	for t in node.get("tags", []) as Array:
		bits.append(String(t))
	var mods := node.get("mods", {}) as Dictionary
	for k in mods.keys():
		bits.append(String(k))
	return " ".join(bits).to_lower()

func _protocol_node_matches_search(upgrade: Dictionary) -> bool:
	if _protocol_search_query == "":
		return true
	if upgrade.is_empty():
		return false
	return String(upgrade.get("search", "")).find(_protocol_search_query) >= 0

func _focus_first_protocol_search_match() -> void:
	if _protocol_search_query == "":
		return
	for u in _protocol_upgrades_runtime:
		if not _protocol_node_matches_search(u):
			continue
		var id := String(u.get("id", ""))
		if id == "":
			continue
		_protocol_selected_id = id
		_focus_protocol_node(id)
		_update_protocol_grid()
		return

func _apply_protocol_pan() -> void:
	if _protocol_graph_root == null or not is_instance_valid(_protocol_graph_root):
		return
	_protocol_graph_root.scale = Vector2.ONE * _protocol_zoom
	_protocol_graph_root.position = _protocol_pan

func _clamp_protocol_pan() -> void:
	if _protocol_graph_view == null or not is_instance_valid(_protocol_graph_view):
		return
	if _protocol_graph_root == null or not is_instance_valid(_protocol_graph_root):
		return
	var view_size := _protocol_graph_view.size
	var root_size := _protocol_graph_root.custom_minimum_size * _protocol_zoom
	if root_size.x <= view_size.x:
		_protocol_pan.x = (view_size.x - root_size.x) * 0.5
	else:
		var over_x := 220.0
		var min_x := view_size.x - root_size.x - over_x
		var max_x := over_x
		_protocol_pan.x = clampf(_protocol_pan.x, min_x, max_x)
	if root_size.y <= view_size.y:
		_protocol_pan.y = (view_size.y - root_size.y) * 0.5
	else:
		var over_y := 180.0
		var min_y := view_size.y - root_size.y - over_y
		var max_y := over_y
		_protocol_pan.y = clampf(_protocol_pan.y, min_y, max_y)

func _set_protocol_zoom(new_zoom: float, screen_pos: Vector2) -> void:
	if _protocol_graph_view == null or not is_instance_valid(_protocol_graph_view):
		return
	var graph_rect := _protocol_graph_view.get_global_rect()
	var local := screen_pos - graph_rect.position
	var before := (local - _protocol_pan) / maxf(0.001, _protocol_zoom)
	_protocol_zoom = clampf(new_zoom, 0.06, 2.40)
	_protocol_pan = local - before * _protocol_zoom
	_clamp_protocol_pan()
	_apply_protocol_pan()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _protocol_graph_view == null or not is_instance_valid(_protocol_graph_view):
		return
	var graph_rect := _protocol_graph_view.get_global_rect()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and graph_rect.has_point(mb.position):
				_protocol_drag_candidate = true
				_protocol_dragging = false
				_protocol_drag_start = mb.position
				_protocol_drag_last = mb.position
			elif not mb.pressed:
				if _protocol_dragging:
					get_viewport().set_input_as_handled()
				_protocol_drag_candidate = false
				_protocol_dragging = false
		elif (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and graph_rect.has_point(mb.position):
			var step := 1.14 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / 1.14)
			_set_protocol_zoom(_protocol_zoom * step, mb.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _protocol_drag_candidate:
			var moved := mm.position.distance_to(_protocol_drag_start)
			if moved > 8.0:
				_protocol_dragging = true
			if _protocol_dragging:
				_protocol_pan += mm.relative
				_clamp_protocol_pan()
				_apply_protocol_pan()
				_protocol_drag_last = mm.position
				get_viewport().set_input_as_handled()

func _protocol_icon_for_node(node: Dictionary) -> String:
	var tags := node.get("tags", []) as Array
	for t in tags:
		if String(t) == "keystone":
			return "KEY"
	var id := String(node.get("id", ""))
	if id.find("hp_") >= 0:
		return "HP"
	if id.find("dmg_") >= 0:
		return "DMG"
	if id.find("armor_") >= 0 or id.find("bulwark") >= 0:
		return "ARM"
	if id.find("speed") >= 0 or id.find("dash") >= 0:
		return "SPD"
	if id.find("tempo") >= 0:
		return "AS"
	if id.find("crit") >= 0:
		return "CRT"
	if id.find("ballistics") >= 0 or id.find("sniper") >= 0:
		return "RNG"
	if id.find("essence") >= 0:
		return "ESS"
	if id.find("recycle") >= 0 or id.find("blood_circuit") >= 0:
		return "HEAL"
	if id.find("focus") >= 0:
		return "FOC"
	if id.find("predator") >= 0 or id.find("execution") >= 0:
		return "HNT"
	if id.find("aether") >= 0 or id.find("mindforge") >= 0:
		return "MND"
	if id.find("surge") >= 0 or id.find("conductor") >= 0:
		return "SRG"
	if id.find("rally") >= 0:
		return "RLY"
	if id.find("bridge") >= 0:
		return "LNK"
	if id.find("squad") >= 0:
		return "SQD"
	if id.find("anchor") >= 0 or id.find("phalanx") >= 0:
		return "ANK"
	if id.find("brawler") >= 0 or id.find("point_blank") >= 0:
		return "CLS"
	if id.find("crit_weave") >= 0 or id.find("headhunter") >= 0:
		return "CRX"
	if id.find("oc_") >= 0 or id.find("overclock") >= 0:
		return "ARC"
	return "MOD"

func _protocol_color_for_node(node: Dictionary) -> String:
	var tags := node.get("tags", []) as Array
	for t in tags:
		if String(t) == "keystone":
			return "#ffd36b"
	var id := String(node.get("id", ""))
	if id.find("hp_") >= 0:
		return "#ff6464"
	if id.find("dmg_") >= 0:
		return "#ff9850"
	if id.find("speed") >= 0 or id.find("dash") >= 0:
		return "#66ff9a"
	if id.find("crit") >= 0:
		return "#ffe066"
	if id.find("essence") >= 0:
		return "#66d2ff"
	if id.find("focus") >= 0:
		return "#9a8cff"
	if id.find("predator") >= 0 or id.find("execution") >= 0:
		return "#b69bff"
	if id.find("aether") >= 0 or id.find("mindforge") >= 0:
		return "#6ed1ff"
	if id.find("static_drive") >= 0 or id.find("eldritch_drive") >= 0:
		return "#9f86ff"
	if id.find("surge") >= 0 or id.find("conductor") >= 0:
		return "#7bb7ff"
	if id.find("rally") >= 0:
		return "#5ec6ff"
	if id.find("bridge") >= 0:
		return "#7ec7d8"
	if id.find("squad") >= 0:
		return "#7dffcb"
	if id.find("anchor") >= 0 or id.find("phalanx") >= 0:
		return "#69d8a0"
	if id.find("brawler") >= 0 or id.find("point_blank") >= 0:
		return "#ff8f6c"
	if id.find("crit_weave") >= 0 or id.find("headhunter") >= 0:
		return "#ffa76d"
	if id.find("oc_") >= 0 or id.find("overclock") >= 0:
		return "#c288ff"
	return "#9eb8ff"

func _protocol_is_keystone(node: Dictionary) -> bool:
	var tags := node.get("tags", []) as Array
	for t in tags:
		if String(t) == "keystone":
			return true
	return false

func _protocol_family_key(id: String) -> String:
	if id == "core_0":
		return "core"
	if id.begins_with("storm_") or id.find("closed_circuit") >= 0:
		return "overclock"
	if id.begins_with("fire_") or id.find("ash_economy") >= 0:
		return "offense"
	if id.begins_with("frost_") or id.find("stillness_tax") >= 0:
		return "focus"
	if id.begins_with("poison_") or id.find("terminal_dose") >= 0:
		return "rally"
	if id.begins_with("proj_"):
		return "offense"
	if id.begins_with("scatter_"):
		return "offense"
	if id.begins_with("rico_") or id.begins_with("pierce_"):
		return "focus"
	if id.begins_with("bomb_"):
		return "offense"
	if id.begins_with("beam_"):
		return "focus"
	if id.begins_with("orbital_"):
		return "focus"
	if id.begins_with("hybrid_"):
		return "squad"
	if id.begins_with("hp_") or id.begins_with("crit_"):
		return "vitality"
	if id.begins_with("armor_") or id.find("bulwark") >= 0:
		return "vitality"
	if id.begins_with("dmg_") or id.begins_with("essence_") or id.begins_with("draft_") or id.begins_with("starting_"):
		return "offense"
	if id.begins_with("tempo_") or id.find("glass_core") >= 0:
		return "offense"
	if id.begins_with("ballistics_") or id.find("sniper_grid") >= 0:
		return "focus"
	if id.begins_with("recycle_") or id.find("blood_circuit") >= 0:
		return "rally"
	if id.begins_with("tactician_") or id.find("war_doctrine") >= 0:
		return "rally"
	if id.begins_with("focus_"):
		return "focus"
	if id.begins_with("rally_"):
		return "rally"
	if id.begins_with("squad_"):
		return "squad"
	if id.begins_with("dash_"):
		return "dash"
	if id.begins_with("oc_"):
		return "overclock"
	if id.begins_with("speed_"):
		return "mobility"
	if id.begins_with("surge_") or id.find("conductor") >= 0:
		return "overclock"
	if id.begins_with("fusion_") or id.find("fusion_overload") >= 0:
		return "overclock"
	if id.begins_with("aether_") or id.find("mindforge") >= 0:
		return "overclock"
	if id.begins_with("static_drive_") or id.find("eldritch_drive") >= 0:
		return "overclock"
	if id.begins_with("execution_") or id.find("reaper_clause") >= 0:
		return "offense"
	if id.begins_with("execution_blast_") or id.find("butcher_protocol") >= 0:
		return "offense"
	if id.begins_with("momentum_") or id.find("reaper_momentum") >= 0:
		return "offense"
	if id.begins_with("anchor_") or id.find("phalanx") >= 0:
		return "squad"
	if id.begins_with("crit_weave_") or id.find("headhunter") >= 0:
		return "offense"
	if id.begins_with("aether_feedback_") or id.find("mirror_aegis") >= 0:
		return "overclock"
	if id.begins_with("overfeed_") or id.find("feedback_loop") >= 0 or id.find("capacitor_lord") >= 0:
		return "overclock"
	if id.begins_with("laststand_") or id.find("bloodforge_oath") >= 0:
		return "rally"
	if id.begins_with("doctrine_link_") or id.find("singularity_drive") >= 0:
		return "squad"
	return "misc"

func _protocol_node_depth(id: String, node_by_id: Dictionary, cache: Dictionary) -> int:
	if cache.has(id):
		return int(cache[id])
	if id == "core_0":
		cache[id] = 0
		return 0
	var node := node_by_id.get(id, {}) as Dictionary
	var prereq := node.get("prereq", []) as Array
	if prereq.is_empty():
		cache[id] = 1
		return 1
	var best := 0
	for p in prereq:
		var pid := String(p)
		if pid == "":
			continue
		best = maxi(best, _protocol_node_depth(pid, node_by_id, cache))
	cache[id] = best + 1
	return best + 1

func _protocol_is_major(node: Dictionary) -> bool:
	if _protocol_is_keystone(node):
		return false
	var tags := node.get("tags", []) as Array
	for t in tags:
		if String(t) == "notable" or String(t) == "major":
			return true
	var cost := int(node.get("cost", 0))
	var prereq := node.get("prereq", []) as Array
	return cost >= 450 or prereq.size() >= 2

func _protocol_short_name(name_txt: String) -> String:
	if name_txt.is_empty():
		return ""
	var parts := name_txt.split(" ", false)
	var out := ""
	for p in parts:
		if p.is_empty():
			continue
		out += p.substr(0, 1).to_upper()
		if out.length() >= 3:
			break
	if out.is_empty():
		out = name_txt.substr(0, mini(3, name_txt.length())).to_upper()
	return out

func _protocol_effects_bbcode(node: Dictionary) -> String:
	var mp := get_node_or_null("/root/MetaProgression")
	if mp == null or not is_instance_valid(mp) or (not mp.has_method("tree_data")):
		return ""
	var td: Dictionary = mp.tree_data()
	var nodes: Array = td.get("nodes", []) as Array
	var target_id := String(node.get("id", ""))
	for n in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var d := n as Dictionary
		if String(d.get("id", "")) != target_id:
			continue
		var mods := d.get("mods", {}) as Dictionary
		if mods.is_empty():
			return "[color=#7f93aa]No direct stat changes[/color]"
		var lines: Array[String] = []
		for k in mods.keys():
			var key := String(k)
			var val := float(mods.get(k, 0.0))
			if key.ends_with("_mult"):
				var pct := (val - 1.0) * 100.0
				var sign := "+" if pct >= 0.0 else ""
				lines.append("• %s: %s%d%%" % [_protocol_label_for_mod(key), sign, int(round(pct))])
			else:
				var sign2 := "+" if val >= 0.0 else ""
				lines.append("• %s: %s%s" % [_protocol_label_for_mod(key), sign2, str(snappedf(val, 0.01))])
		return "[b]Node Effects[/b]\n%s" % "\n".join(lines)
	return ""

func _protocol_label_for_mod(key: String) -> String:
	match key:
		"squad_hp_mult": return "Squad HP"
		"squad_damage_mult": return "Squad Damage"
		"squad_speed_mult": return "Squad Speed"
		"squad_crit_add": return "Crit Chance"
		"essence_mult": return "Essence Gain"
		"draft_rarity_boost": return "Draft Rarity Bias"
		"starting_squad_add": return "Starting Squad Size"
		"focus_duration_mult": return "Focus Duration"
		"focus_lockout_s": return "Focus Swap Lockout"
		"rally_duration_mult": return "Rally Duration"
		"rally_speed_mult": return "Rally Speed"
		"rally_follow_mult": return "Rally Follow Aggression"
		"dash_cooldown_mult": return "Dash Cooldown"
		"dash_distance_mult": return "Dash Distance"
		"dash_follow_mult": return "Dash Cohesion"
		"overclock_unlocked": return "Unlock Overclock"
		"overclock_attack_speed_mult": return "Overclock Attack Speed"
		"overclock_move_speed_mult": return "Overclock Move Speed"
		"overclock_damage_mult": return "Overclock Damage"
		"overclock_focus_bias_mult": return "Overclock Focus Bias"
		"overclock_cooldown_mult": return "Overclock Cooldown"
		"overclock_duration_mult": return "Overclock Duration"
		"overclock_burst_damage_add": return "Overclock Burst Damage"
		"overclock_burst_radius_add": return "Overclock Burst Radius"
		"squad_attack_speed_mult": return "Squad Attack Speed"
		"squad_range_mult": return "Ranged Attack Range"
		"squad_damage_taken_mult": return "Damage Taken"
		"on_kill_heal_add": return "Heal on Kill"
		"overclock_chain_chance_add": return "Overclock Chain Chance"
		"overclock_chain_jumps_add": return "Overclock Chain Jumps"
		"overclock_chain_damage_mult": return "Overclock Chain Damage"
		"overclock_chain_radius_add": return "Overclock Chain Radius"
		"ranged_to_melee_add": return "Convert Ranged to Melee"
		"ranged_transfer_melee_mult": return "Ranged Buff Transfer to Melee"
		"focus_mark_damage_mult": return "Focus Mark Damage"
		"damage_taken_as_essence_add": return "Damage Taken As Essence"
		"execute_threshold_add": return "Execute Threshold"
		"overclock_always_on_add": return "Overclock Always On"
		"kill_chain_window_add": return "Kill Chain Window"
		"kill_chain_haste_per_stack_add": return "Kill Chain Haste per Stack"
		"kill_chain_max_stacks_add": return "Kill Chain Max Stacks"
		"overclock_extend_on_kill_add": return "Overclock Extend on Kill"
		"execute_blast_radius_add": return "Execute Blast Radius"
		"execute_blast_damage_mult": return "Execute Blast Damage"
		"execute_blast_mark_threshold_add": return "Execute Blast Mark Threshold"
		"essence_guard_reflect_ratio_add": return "Essence Guard Reflect Ratio"
		"essence_guard_reflect_radius_add": return "Essence Guard Reflect Radius"
		"guardian_intercept_ratio_add": return "Guardian Intercept Ratio"
		"non_guardian_hp_mult": return "Non-Guardian HP"
		"slowed_execute_threshold_add": return "Execute Threshold vs Slowed"
		"unslowed_enemy_damage_taken_mult": return "Damage vs Unslowed Enemies"
		"crit_execute_vuln_add": return "Crit Apply Execute Vulnerability"
		"noncrit_damage_mult": return "Non-Crit Damage"
		"point_blank_max_bonus_add": return "Point-Blank Max Bonus"
		"point_blank_far_penalty_add": return "Point-Blank Far Penalty"
		"farshot_max_bonus_add": return "Farshot Max Bonus"
		"farshot_near_penalty_add": return "Farshot Near Penalty"
		"near_enemy_damage_taken_mult": return "Damage Taken Near Enemies"
		"near_enemy_threat_radius_add": return "Near Enemy Threat Radius"
		"mage_chain_jumps_add": return "Mage Chain Jumps"
		"mage_chain_range_add": return "Mage Chain Range"
		"mage_single_target_mult": return "Mage Chain Isolated Damage"
		"chain_jumps_add": return "Chain Jumps"
		"chain_damage_falloff_mult": return "Chain Falloff"
		"chain_kill_shock_radius_add": return "Chain Kill Shock Radius"
		"chain_kill_shock_damage_mult": return "Chain Kill Shock Damage"
		"chain_can_rehit_targets": return "Chain Can Rehit Targets"
		"chain_rehit_damage_mult": return "Chain Rehit Damage"
		"burning_enemy_execute_threshold_add": return "Execute Threshold vs Burning"
		"burn_duration_mult": return "Burn Duration"
		"slowed_enemy_damage_mult": return "Slowed Enemy Contact Damage"
		"slow_initial_strength_mult": return "Initial Slow Strength"
		"slow_stacks_to_freeze_enabled": return "Slow Stacks Freeze"
		"freeze_after_slow_duration": return "Freeze After Slow Duration"
		"projectile_count_add": return "Projectile Count"
		"projectile_damage_mult": return "Projectile Damage"
		"projectile_pierce_add": return "Projectile Pierce"
		"projectile_spread_mult": return "Projectile Spread"
		"bomb_radius_add": return "Bomb Radius"
		"bomb_delay_mult": return "Bomb Delay"
		"bomb_damage_mult": return "Bomb Damage"
		"poison_duration_mult": return "Poison Duration"
		"frost_slow_duration_mult": return "Frost Slow Duration"
		"orbital_damage_mult": return "Orbital Damage"
		"orbital_delay_mult": return "Orbital Delay"
		"ricochet_damage_per_bounce_add": return "Ricochet Damage per Bounce"
		"direct_projectile_damage_mult": return "Direct Projectile Damage"
		"post_ricochet_projectile_damage_mult": return "Post-Ricochet Projectile Damage"
		"ricochet_count_add": return "Ricochet Count"
		"pierce_damage_per_enemy_hit_add": return "Pierce Damage per Enemy Hit"
		"piercing_hits_can_execute": return "Piercing Hits Can Execute"
		"bomb_cluster_count_add": return "Bomb Cluster Count"
		"bomb_cluster_damage_mult": return "Bomb Cluster Damage"
		"bomb_cluster_radius_mult": return "Bomb Cluster Radius"
		"beam_damage_ramp_per_second_add": return "Beam Damage Ramp per Second"
		"beam_damage_ramp_cap": return "Beam Damage Ramp Cap"
		"beam_initial_damage_mult": return "Beam Initial Damage"
		"beam_secondary_targets_add": return "Beam Secondary Targets"
		"beam_secondary_damage_mult": return "Beam Secondary Damage"
		"beam_target_swap_resets_ramp": return "Beam Target Swap Resets Ramp"
		"orbital_targets_player_trail": return "Orbital Targets Squad Trail"
		"berserk_threshold_add": return "Last-Stand HP Threshold"
		"berserk_damage_mult": return "Last-Stand Damage"
		"berserk_attack_speed_mult": return "Last-Stand Attack Speed"
		"berserk_damage_taken_mult": return "Last-Stand Damage Taken"
		_: return key

func _protocol_trace_ids(from_id: String) -> Dictionary:
	var out: Dictionary = {}
	if from_id == "":
		return out
	var stack: Array[String] = [from_id]
	while not stack.is_empty():
		var cur: String = String(stack.pop_back())
		if out.has(cur):
			continue
		out[cur] = true
		var nd := _protocol_node_by_id.get(cur, {}) as Dictionary
		var up := nd.get("upgrade", {}) as Dictionary
		var prereq := up.get("prereq", []) as Array
		for p in prereq:
			var pid := String(p)
			if pid != "" and not out.has(pid):
				stack.append(pid)
	return out

func _protocol_node_accent_color(node: Dictionary, id: String) -> Color:
	var cluster := String(node.get("cluster", ""))
	if cluster != "":
		return _protocol_cluster_color(cluster)
	return _protocol_family_color(id)

func _protocol_cluster_color(cluster: String) -> Color:
	match cluster:
		"storm": return Color(0.50, 0.82, 1.0, 1.0)
		"fire": return Color(1.0, 0.57, 0.32, 1.0)
		"frost": return Color(0.62, 0.90, 1.0, 1.0)
		"poison": return Color(0.54, 1.0, 0.60, 1.0)
		"projectile": return Color(1.0, 0.84, 0.56, 1.0)
		"scatter": return Color(1.0, 0.72, 0.45, 1.0)
		"ricochet": return Color(1.0, 0.78, 0.54, 1.0)
		"pierce": return Color(1.0, 0.90, 0.68, 1.0)
		"bomb": return Color(1.0, 0.54, 0.28, 1.0)
		"beam": return Color(0.90, 0.68, 1.0, 1.0)
		"orbital": return Color(1.0, 0.70, 0.38, 1.0)
		"hybrid": return Color(0.66, 0.96, 0.92, 1.0)
		_: return Color(0.62, 0.74, 0.92, 1.0)

func _protocol_family_color(id: String) -> Color:
	var f := _protocol_family_key(id)
	match f:
		"vitality": return Color(1.0, 0.47, 0.47, 1.0)
		"offense": return Color(1.0, 0.65, 0.35, 1.0)
		"focus": return Color(0.72, 0.62, 1.0, 1.0)
		"rally": return Color(0.37, 0.78, 1.0, 1.0)
		"squad": return Color(0.49, 1.0, 0.80, 1.0)
		"dash": return Color(0.40, 1.0, 0.60, 1.0)
		"overclock": return Color(0.76, 0.56, 1.0, 1.0)
		"mobility": return Color(0.56, 0.96, 0.84, 1.0)
		"core": return Color(0.82, 0.88, 1.0, 1.0)
		_: return Color(0.62, 0.74, 0.92, 1.0)

func _protocol_icon_texture_for_id(id: String, is_keystone: bool = false) -> Texture2D:
	var file := ""
	if is_keystone and PROTOCOL_KEYSTONE_ICON_BY_ID.has(id):
		file = String(PROTOCOL_KEYSTONE_ICON_BY_ID[id])
	if file == "":
		var family := _protocol_family_key(id)
		file = String(PROTOCOL_ICON_BY_FAMILY.get(family, "fam_offense_v2.webp"))
	var path := PROTOCOL_ICON_DIR + file
	if _protocol_icon_cache.has(path):
		return _protocol_icon_cache[path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_protocol_icon_cache[path] = tex
	return tex

func _protocol_medallion_texture(size_px: int, accent: Color, keystone: bool) -> Texture2D:
	var size := maxi(20, size_px)
	var key := "%d|%.3f|%.3f|%.3f|%s" % [size, accent.r, accent.g, accent.b, "k" if keystone else "n"]
	if _protocol_medallion_cache.has(key):
		return _protocol_medallion_cache[key] as Texture2D
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(float(size) * 0.5, float(size) * 0.5)
	var outer := float(size) * 0.48
	var inner := float(size) * 0.34
	var core := float(size) * 0.26
	var ring_col := Color(accent.r, accent.g, accent.b, 0.95 if keystone else 0.86)
	var rim_col := Color(0.95, 0.98, 1.0, 0.88 if keystone else 0.72)
	var core_col := Color(0.06, 0.09, 0.14, 0.98)
	for y in range(size):
		for x in range(size):
			var d := Vector2(float(x), float(y)).distance_to(c)
			if d <= outer and d >= inner:
				var t := clampf((d - inner) / maxf(1.0, outer - inner), 0.0, 1.0)
				img.set_pixel(x, y, ring_col.lerp(rim_col, t))
			elif d < inner and d >= core:
				img.set_pixel(x, y, Color(0.14, 0.18, 0.25, 0.92))
			elif d < core:
				var t2 := clampf(d / maxf(1.0, core), 0.0, 1.0)
				img.set_pixel(x, y, core_col.lerp(Color(0.13, 0.17, 0.25, 0.98), t2))
	var tex := ImageTexture.create_from_image(img)
	_protocol_medallion_cache[key] = tex
	return tex

func _protocol_node_shell_texture(size_px: int, accent: Color, keystone: bool, major: bool) -> Texture2D:
	var size := maxi(28, size_px)
	var key := "%d|%.3f|%.3f|%.3f|%s|%s" % [size, accent.r, accent.g, accent.b, "k" if keystone else "n", "m" if major else "s"]
	if _protocol_node_shell_cache.has(key):
		return _protocol_node_shell_cache[key] as Texture2D
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(float(size) * 0.5, float(size) * 0.5)
	var glow := float(size) * 0.50
	var shell_outer := float(size) * 0.43
	var shell_inner := float(size) * 0.29
	var core := float(size) * 0.23
	var halo_a := 0.34 if not keystone else 0.46
	var ring_boost := 1.0
	if major:
		ring_boost = 1.08
	if keystone:
		ring_boost = 1.18
	for y in range(size):
		for x in range(size):
			var p := Vector2(float(x), float(y))
			var d := p.distance_to(c)
			var col := Color(0, 0, 0, 0)
			if d <= glow:
				var h := 1.0 - clampf(d / maxf(1.0, glow), 0.0, 1.0)
				col = Color(accent.r, accent.g, accent.b, pow(h, 2.7) * halo_a)
			if d <= shell_outer and d >= shell_inner:
				var t := clampf((d - shell_inner) / maxf(1.0, shell_outer - shell_inner), 0.0, 1.0)
				var ring_col := Color(
					minf(1.0, accent.r * (0.76 + 0.34 * ring_boost)),
					minf(1.0, accent.g * (0.76 + 0.34 * ring_boost)),
					minf(1.0, accent.b * (0.76 + 0.34 * ring_boost)),
					0.76 + 0.20 * (1.0 - t)
				)
				col = col.blend(ring_col)
			if d < shell_inner and d >= core:
				var t_mid := clampf((d - core) / maxf(1.0, shell_inner - core), 0.0, 1.0)
				col = col.blend(Color(0.14, 0.18, 0.27, 0.88 - t_mid * 0.18))
			if d < core:
				var t_core := clampf(d / maxf(1.0, core), 0.0, 1.0)
				col = col.blend(Color(0.05, 0.08, 0.14, 0.94).lerp(Color(0.14, 0.20, 0.30, 0.82), t_core))
			# Small specular highlight to make nodes look tactile/clickable.
			var hvec := p - (c + Vector2(-float(size) * 0.09, -float(size) * 0.12))
			var hdist := hvec.length()
			var hs := 1.0 - clampf(hdist / maxf(1.0, float(size) * 0.24), 0.0, 1.0)
			if hs > 0.0 and d < shell_outer:
				col = col.blend(Color(0.95, 0.99, 1.0, hs * 0.13))
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_protocol_node_shell_cache[key] = tex
	return tex
