extends SceneTree

# Loads core UI scripts and verifies they compile/instantiate after refactors.

const SCRIPTS: Array[String] = [
	"res://scripts/menu/CommandDeckUI.gd",
	"res://scripts/menu/MenuCodexUI.gd",
	"res://scripts/menu/ProtocolGridUI.gd",
	"res://scripts/MainMenu.gd",
	"res://scripts/Menu.gd",
	"res://scripts/run/RunHudUI.gd",
	"res://scripts/run/RecruitDraftUI.gd",
	"res://scripts/Main.gd",
	"res://scripts/PauseMenu.gd",
	"res://scripts/SettingsMenu.gd",
	"res://scripts/UiSkin.gd",
	"res://scripts/ui/UiModal.gd",
	"res://scripts/ui/UiComponents.gd",
	"res://scripts/ui/PixelUi.gd",
	"res://scripts/ui/MenuMapPreview.gd",
	"res://scripts/ui/UiFullscreenShell.gd",
]

func _init() -> void:
	var fails := 0
	for p in SCRIPTS:
		var s := load(p) as Script
		if s == null or not s.can_instantiate():
			fails += 1
			print("PARSE_SMOKE_FAIL %s" % p)
		else:
			print("PARSE_SMOKE_OK %s" % p)
	print("PARSE_SMOKE fails=%d" % fails)
	quit(0 if fails == 0 else 1)
