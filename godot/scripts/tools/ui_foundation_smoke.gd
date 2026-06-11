extends SceneTree

# Phase 1 design-system smoke:
# - UiModal builds its shell and emits `closed` exactly once
# - UiComponents widgets construct without errors
# - PauseMenu and SettingsMenu build on the shared foundation

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var modal := UiModal.build({"size": Vector2(400, 300), "animate": false})
	root.add_child(modal)
	_check(modal.panel != null, "modal_panel")
	_check(modal.content != null, "modal_content")
	_check(modal.backdrop != null, "modal_backdrop")

	var closed_count := [0]
	modal.closed.connect(func(): closed_count[0] += 1)
	modal.close()
	modal.close()
	_check(closed_count[0] == 1, "modal_closed_exactly_once")

	var col := VBoxContainer.new()
	root.add_child(col)
	col.add_child(UiComponents.title("Title"))
	col.add_child(UiComponents.body_label("Body"))
	col.add_child(UiComponents.hint("Hint"))
	col.add_child(UiComponents.menu_button("Primary", UiSkin.ACCENT, true))
	col.add_child(UiComponents.menu_button("Secondary", UiSkin.ACCENT_PURPLE))
	col.add_child(UiComponents.chip("Chip"))
	col.add_child(UiComponents.separator())
	var s := UiComponents.slider_row(col, "Slider", func(_v: float): pass)
	_check(s != null, "slider_row")
	s.value = 42.0
	var t := UiComponents.toggle_row(col, "Toggle", func(_on: bool): pass)
	_check(t != null, "toggle_row")

	var pm: CanvasLayer = load("res://scripts/PauseMenu.gd").new()
	root.add_child(pm)
	_check(pm.get_child_count() > 0, "pause_menu_builds")

	var sm: CanvasLayer = load("res://scripts/SettingsMenu.gd").new()
	root.add_child(sm)
	_check(sm.get_child_count() > 0, "settings_menu_builds")

	print("UI_FOUNDATION_SMOKE fails=%d" % _fails)
	quit(0 if _fails == 0 else 1)

func _check(ok: bool, label: String) -> void:
	if ok:
		print("UI_SMOKE_OK %s" % label)
	else:
		_fails += 1
		print("UI_SMOKE_FAIL %s" % label)
