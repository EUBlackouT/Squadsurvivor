class_name PixelUi
extends RefCounted

## Tactical pixel UI helpers — dark command-deck surfaces + nearest-filter portraits.
## NO wood/parchment textures. Delegates chrome to UiSkin.

static func nearest(node: CanvasItem) -> void:
	if node != null:
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

static func panel_frame(accent: Color = UiSkin.ACCENT) -> StyleBox:
	return UiSkin.pixel_panel(accent, 0.82)

static func card_frame(accent: Color, selected: bool = false) -> StyleBox:
	return UiSkin.pixel_card(accent, selected)

static func codex_frame() -> StyleBox:
	return UiSkin.pixel_panel(UiSkin.ACCENT_PURPLE, 0.86)

static func style_label(lbl: Label, size: int = 14, color: Color = UiSkin.TEXT, outline: int = 0) -> void:
	UiSkin.style_label(lbl, size, color)
	if outline > 0:
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		lbl.add_theme_constant_override("outline_size", outline)
	nearest(lbl)

static func style_button(btn: Button, primary: bool = false, accent: Color = UiSkin.ACCENT_GOLD) -> void:
	if primary:
		UiSkin.style_pixel_primary_button(btn, accent)
	else:
		UiSkin.style_pixel_secondary_button(btn, accent if accent != UiSkin.ACCENT_GOLD else UiSkin.ACCENT)
	btn.add_theme_font_size_override("font_size", 14)
	nearest(btn)

static func style_line_edit(le: LineEdit) -> void:
	le.add_theme_stylebox_override("normal", UiSkin.pixel_inset(0.92))
	le.add_theme_stylebox_override("focus", UiSkin.pixel_inset(0.98))
	le.add_theme_color_override("font_color", UiSkin.TEXT)
	le.add_theme_color_override("font_placeholder_color", UiSkin.TEXT_DIM)
	le.add_theme_font_size_override("font_size", 14)
	nearest(le)

static func style_option_button(ob: OptionButton) -> void:
	ob.add_theme_stylebox_override("normal", UiSkin.pixel_inset(0.92))
	ob.add_theme_stylebox_override("hover", UiSkin.pixel_inset(0.96))
	ob.add_theme_stylebox_override("focus", UiSkin.pixel_inset(0.98))
	ob.add_theme_stylebox_override("pressed", UiSkin.pixel_inset(1.0))
	ob.add_theme_color_override("font_color", UiSkin.TEXT)
	ob.add_theme_font_size_override("font_size", 14)
	nearest(ob)

static func chip(text: String, accent: Color = UiSkin.ACCENT, font_size: int = 11) -> PanelContainer:
	return UiComponents.chip(text, accent, font_size)

static func portrait_frame(data: Dictionary, box_size: Vector2i = Vector2i(72, 72), animate: bool = true) -> PanelContainer:
	var rarity := String(data.get("rarity_id", "common"))
	var accent := UnitFactory.rarity_color(rarity)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(box_size)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UiSkin.pixel_inset(0.94))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	frame.add_child(pad)
	var inner := maxi(32, box_size.x - 14)
	var sprite_path := String(data.get("sprite_path", ""))
	var frames := PixellabUtil.walk_frames_from_south_path(sprite_path)
	if animate and frames != null and frames.has_animation("walk_south") and frames.get_frame_count("walk_south") > 0:
		var svc := SubViewportContainer.new()
		svc.custom_minimum_size = Vector2(inner, inner)
		svc.stretch = true
		svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(svc)
		var vp := SubViewport.new()
		vp.size = Vector2i(inner, inner)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		svc.add_child(vp)
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames
		spr.animation = "walk_south"
		spr.centered = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = Vector2(inner * 0.5, inner * 0.58)
		spr.scale = Vector2.ONE * PixellabUtil.scale_for_target_height(frames, float(inner) * 0.55, 0.5, 1.2)
		spr.play()
		vp.add_child(spr)
	else:
		var tex := PixellabUtil.load_rotation_texture(sprite_path)
		if tex == null:
			var pid := String(data.get("pixellab_id", ""))
			if pid != "":
				tex = PixellabUtil.load_rotation_texture("res://assets/pixellab/%s/rotations/south.png" % pid)
		if tex != null:
			var svc2 := SubViewportContainer.new()
			svc2.custom_minimum_size = Vector2(inner, inner)
			svc2.stretch = true
			svc2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			pad.add_child(svc2)
			var vp2 := SubViewport.new()
			vp2.size = Vector2i(inner, inner)
			vp2.transparent_bg = true
			vp2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			vp2.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
			svc2.add_child(vp2)
			var spr2 := Sprite2D.new()
			spr2.texture = tex
			spr2.centered = true
			spr2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr2.position = Vector2(inner * 0.5, inner * 0.58)
			var target_h := float(inner) * 0.55
			spr2.scale = Vector2.ONE * PixellabUtil.scale_texture_to_height(tex, target_h, 0.5, 1.2)
			vp2.add_child(spr2)
	return frame

static func modal_shell(title: String, subtitle: String = "", accent: Color = UiSkin.ACCENT) -> Dictionary:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.04, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 28
	panel.offset_top = 22
	panel.offset_right = -28
	panel.offset_bottom = -22
	panel.add_theme_stylebox_override("panel", UiSkin.pixel_panel(accent, 0.78))
	root.add_child(panel)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", UiSkin.SPACE_LG)
	outer.add_theme_constant_override("margin_right", UiSkin.SPACE_LG)
	outer.add_theme_constant_override("margin_top", UiSkin.SPACE_MD)
	outer.add_theme_constant_override("margin_bottom", UiSkin.SPACE_MD)
	panel.add_child(outer)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	outer.add_child(root_v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiSkin.SPACE_MD)
	root_v.add_child(header)

	var head_v := VBoxContainer.new()
	head_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_v.add_theme_constant_override("separation", 2)
	header.add_child(head_v)

	var title_l := Label.new()
	title_l.text = title.to_upper()
	style_label(title_l, UiSkin.FONT_H2, UiSkin.TEXT)
	head_v.add_child(title_l)

	if subtitle != "":
		var sub := Label.new()
		sub.text = subtitle
		style_label(sub, UiSkin.FONT_XS, accent)
		head_v.add_child(sub)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(44, 44)
	style_button(close_btn, false, UiSkin.ACCENT_RED)
	header.add_child(close_btn)

	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UiSkin.SPACE_SM)
	root_v.add_child(body)

	return {"root": root, "body": body, "close_btn": close_btn, "panel": panel}

static func animate_modal_in(shell: Dictionary) -> void:
	var panel: Control = shell.get("panel")
	var root: Control = shell.get("root")
	if root == null:
		return
	root.modulate.a = 0.0
	if panel != null:
		panel.scale = Vector2(0.98, 0.98)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, UiSkin.DUR_MED)
	if panel != null:
		tw.tween_property(panel, "scale", Vector2.ONE, UiSkin.DUR_MED) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
