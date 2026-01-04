extends Node

# Settings save/load + live application (audio + display).
# Saves to: user://settings.cfg

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"

var _loading: bool = false

var _master_volume: float = 1.0
var _music_volume: float = 1.0
var _sfx_volume: float = 1.0
var _fullscreen: bool = false
var _vsync_enabled: bool = true
var _screen_shake_enabled: bool = true
var _screen_shake_intensity: float = 1.0

var master_volume: float:
	get: return _master_volume
	set(value):
		_master_volume = clampf(float(value), 0.0, 1.0)
		_on_changed()

var music_volume: float:
	get: return _music_volume
	set(value):
		_music_volume = clampf(float(value), 0.0, 1.0)
		_on_changed()

var sfx_volume: float:
	get: return _sfx_volume
	set(value):
		_sfx_volume = clampf(float(value), 0.0, 1.0)
		_on_changed()

var fullscreen: bool:
	get: return _fullscreen
	set(value):
		_fullscreen = bool(value)
		_on_changed()

var vsync_enabled: bool:
	get: return _vsync_enabled
	set(value):
		_vsync_enabled = bool(value)
		_on_changed()

var screen_shake_enabled: bool:
	get: return _screen_shake_enabled
	set(value):
		_screen_shake_enabled = bool(value)
		_on_changed()

var screen_shake_intensity: float:
	get: return _screen_shake_intensity
	set(value):
		_screen_shake_intensity = clampf(float(value), 0.0, 3.0)
		_on_changed()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_settings()

func _on_changed() -> void:
	if _loading:
		return
	apply_settings()
	save_settings()

func load_settings() -> void:
	_loading = true
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		_loading = false
		# First run: keep defaults and write file once.
		save_settings()
		return

	_master_volume = clampf(float(cfg.get_value(SECTION, "master_volume", _master_volume)), 0.0, 1.0)
	_music_volume = clampf(float(cfg.get_value(SECTION, "music_volume", _music_volume)), 0.0, 1.0)
	_sfx_volume = clampf(float(cfg.get_value(SECTION, "sfx_volume", _sfx_volume)), 0.0, 1.0)
	_fullscreen = bool(cfg.get_value(SECTION, "fullscreen", _fullscreen))
	_vsync_enabled = bool(cfg.get_value(SECTION, "vsync_enabled", _vsync_enabled))
	_screen_shake_enabled = bool(cfg.get_value(SECTION, "screen_shake_enabled", _screen_shake_enabled))
	_screen_shake_intensity = clampf(float(cfg.get_value(SECTION, "screen_shake_intensity", _screen_shake_intensity)), 0.0, 3.0)
	_loading = false

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "master_volume", _master_volume)
	cfg.set_value(SECTION, "music_volume", _music_volume)
	cfg.set_value(SECTION, "sfx_volume", _sfx_volume)
	cfg.set_value(SECTION, "fullscreen", _fullscreen)
	cfg.set_value(SECTION, "vsync_enabled", _vsync_enabled)
	cfg.set_value(SECTION, "screen_shake_enabled", _screen_shake_enabled)
	cfg.set_value(SECTION, "screen_shake_intensity", _screen_shake_intensity)
	cfg.save(SAVE_PATH)

func apply_settings() -> void:
	# Audio buses
	_set_bus_volume_linear("Master", _master_volume)
	_set_bus_volume_linear("Music", _music_volume)
	_set_bus_volume_linear("SFX", _sfx_volume)

	# Display
	var mode := DisplayServer.WINDOW_MODE_WINDOWED
	if _fullscreen:
		mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(mode)

	var vs := DisplayServer.VSYNC_ENABLED if _vsync_enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vs)

func _set_bus_volume_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	# Avoid -INF when linear hits 0.
	var lin := clampf(linear, 0.0, 1.0)
	var db := linear_to_db(maxf(0.0001, lin))
	# Godot treats very low dB as effectively silent anyway.
	AudioServer.set_bus_volume_db(idx, db)





