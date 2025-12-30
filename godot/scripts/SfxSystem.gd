extends Node

# Procedural SFX: generated at runtime (no external audio assets).
# Designed to be loud + distinct, with pitch variation to avoid repetition.

@export var master_gain_db: float = -3.0
@export var max_voices: int = 16
@export var default_pitch_jitter: float = 0.06
@export var loud_mode: bool = true

const SAMPLE_RATE: int = 44100

var _streams: Dictionary = {} # id -> AudioStreamWAV
var _pool: Array[AudioStreamPlayer2D] = []
var _pool_idx: int = 0

# event_id -> {stream, gain_db, pitch, jitter, min_ms_global, min_ms_emitter}
var _event_cfg: Dictionary = {}
var _last_global_ms: Dictionary = {} # event_id -> int
var _last_emitter_ms: Dictionary = {} # emitterKey|event_id -> int

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_streams()
	_build_event_cfg()
	_build_pool()

func play_2d(id: String, world_pos: Vector2, gain_db: float = 0.0, pitch: float = 1.0, pitch_jitter: float = -1.0) -> void:
	if not _streams.has(id):
		return
	if _pool.is_empty():
		return
	if pitch_jitter < 0.0:
		pitch_jitter = default_pitch_jitter

	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()

	p.global_position = world_pos
	p.stream = _streams[id] as AudioStreamWAV
	p.volume_db = master_gain_db + gain_db
	p.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()

func play_event(event_id: String, world_pos: Vector2, emitter: Object = null) -> void:
	# Event router: enforces cooldowns so SFX don't feel random/spammy.
	var now_ms: int = int(Time.get_ticks_msec())
	var cfg: Dictionary = _event_cfg.get(event_id, {}) as Dictionary

	# Back-compat: if event isn't configured, treat event_id as stream id with a small global throttle.
	if cfg.is_empty():
		if _gate_global(event_id, 90, now_ms):
			play_2d(event_id, world_pos, 0.0, 1.0)
		return

	var emitter_key := "global"
	if emitter != null and emitter is Object:
		# Use instance id if possible.
		if emitter is Node:
			emitter_key = str((emitter as Node).get_instance_id())
		else:
			emitter_key = str(emitter.get_instance_id())

	var min_g: int = int(cfg.get("min_ms_global", 0))
	var min_e: int = int(cfg.get("min_ms_emitter", 0))
	if min_g > 0 and not _gate_global(event_id, min_g, now_ms):
		return
	if min_e > 0 and not _gate_emitter(emitter_key, event_id, min_e, now_ms):
		return

	var stream_id := String(cfg.get("stream", event_id))
	var gain_db := float(cfg.get("gain_db", 0.0))
	var pitch := float(cfg.get("pitch", 1.0))
	var jitter := float(cfg.get("jitter", default_pitch_jitter))
	play_2d(stream_id, world_pos, gain_db, pitch, jitter)

func play_ui(event_id: String) -> void:
	# UI sounds play from the player's position for spatial consistency.
	var pos := Vector2.ZERO
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null and is_instance_valid(p):
		pos = p.global_position
	# Use this node as emitter to satisfy typed signature + enable per-emitter throttles.
	play_event(event_id, pos, self)

func _gate_global(event_id: String, min_ms: int, now_ms: int) -> bool:
	var last_ms: int = int(_last_global_ms.get(event_id, 0))
	if last_ms > 0 and (now_ms - last_ms) < min_ms:
		return false
	_last_global_ms[event_id] = now_ms
	return true

func _gate_emitter(emitter_key: String, event_id: String, min_ms: int, now_ms: int) -> bool:
	var key := "%s|%s" % [emitter_key, event_id]
	var last_ms: int = int(_last_emitter_ms.get(key, 0))
	if last_ms > 0 and (now_ms - last_ms) < min_ms:
		return false
	_last_emitter_ms[key] = now_ms
	return true

func _build_pool() -> void:
	_pool.clear()
	for i in range(maxi(4, max_voices)):
		var p := AudioStreamPlayer2D.new()
		p.bus = "Master"
		p.max_distance = 1200.0
		p.attenuation = 2.0
		p.panning_strength = 0.6
		add_child(p)
		_pool.append(p)

func _build_streams() -> void:
	_streams.clear()
	# Arc/zap
	_streams["arc_zap"] = _make_zap(0.11, 1200.0, 240.0, 0.25)
	# Shockwave thump
	_streams["shockwave"] = _make_thump(0.14, 90.0, 0.55)
	# Frost nova glassy crack
	_streams["frost_nova"] = _make_glass(0.16, 740.0, 0.22)
	# Flame burst whoosh + crackle
	_streams["flame_burst"] = _make_whoosh(0.16, 0.32)
	# Holy pulse chime
	_streams["holy_pulse"] = _make_chime(0.18, 520.0, 0.22)
	# Focus mark tick
	_streams["focus_tick"] = _make_tick(0.07, 980.0, 0.22)
	# Execute hit
	_streams["execute"] = _make_thump(0.10, 140.0, 0.75)
	# UI + meta
	_streams["ui_click"] = _make_tick(0.05, 840.0, 0.18)
	_streams["ui_confirm"] = _make_chime(0.16, 680.0, 0.35)
	_streams["ui_cancel"] = _make_tick(0.06, 420.0, 0.10)
	_streams["ui_reroll"] = _make_whoosh(0.14, 0.26)
	_streams["ui_open"] = _make_whoosh(0.18, 0.22)
	_streams["ui_drop"] = _make_chime(0.14, 920.0, 0.40)
	_streams["ui_victory"] = _make_chime(0.26, 520.0, 0.55)
	_streams["ui_defeat"] = _make_thump(0.18, 70.0, 0.85)
	# Combat baseline
	_streams["player_slash"] = _make_whoosh(0.10, 0.18)
	_streams["player_shot"] = _make_tick(0.05, 1120.0, 0.12)
	_streams["enemy_die"] = _make_tick(0.06, 520.0, 0.18)
	_streams["enemy_spawn_elite"] = _make_thump(0.16, 82.0, 0.65)

func _build_event_cfg() -> void:
	_event_cfg.clear()
	var loud := 3.0 if loud_mode else 0.0

	# UI
	_event_cfg["ui.click"] = {"stream": "ui_click", "gain_db": -2.0, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 40, "min_ms_emitter": 40}
	_event_cfg["ui.confirm"] = {"stream": "ui_confirm", "gain_db": 0.0, "pitch": 1.0, "jitter": 0.03, "min_ms_global": 80, "min_ms_emitter": 80}
	_event_cfg["ui.cancel"] = {"stream": "ui_cancel", "gain_db": -1.0, "pitch": 1.0, "jitter": 0.03, "min_ms_global": 80, "min_ms_emitter": 80}
	_event_cfg["ui.reroll"] = {"stream": "ui_reroll", "gain_db": 1.0 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 200, "min_ms_emitter": 200}
	_event_cfg["ui.open"] = {"stream": "ui_open", "gain_db": 1.0 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 200, "min_ms_emitter": 200}
	_event_cfg["ui.drop"] = {"stream": "ui_drop", "gain_db": 2.0 + loud, "pitch": 1.0, "jitter": 0.03, "min_ms_global": 250, "min_ms_emitter": 250}
	_event_cfg["ui.victory"] = {"stream": "ui_victory", "gain_db": 4.0 + loud, "pitch": 1.0, "jitter": 0.02, "min_ms_global": 500, "min_ms_emitter": 500}
	_event_cfg["ui.defeat"] = {"stream": "ui_defeat", "gain_db": 4.0 + loud, "pitch": 1.0, "jitter": 0.02, "min_ms_global": 500, "min_ms_emitter": 500}

	# Core combat (very frequent -> per-emitter throttle)
	_event_cfg["player.slash"] = {"stream": "player_slash", "gain_db": -1.0 + loud, "pitch": 1.0, "jitter": 0.06, "min_ms_global": 0, "min_ms_emitter": 110}
	_event_cfg["player.shot"] = {"stream": "player_shot", "gain_db": -2.0 + loud, "pitch": 1.0, "jitter": 0.08, "min_ms_global": 0, "min_ms_emitter": 90}
	_event_cfg["enemy.die"] = {"stream": "enemy_die", "gain_db": -2.0 + loud, "pitch": 1.0, "jitter": 0.08, "min_ms_global": 25, "min_ms_emitter": 0}
	_event_cfg["enemy.elite_spawn"] = {"stream": "enemy_spawn_elite", "gain_db": 2.0 + loud, "pitch": 1.0, "jitter": 0.03, "min_ms_global": 250, "min_ms_emitter": 250}

	# Synergy procs (big moments, but still throttled)
	_event_cfg["syn.arc"] = {"stream": "arc_zap", "gain_db": 0.5 + loud, "pitch": 1.0, "jitter": 0.06, "min_ms_global": 90, "min_ms_emitter": 140}
	_event_cfg["syn.shock"] = {"stream": "shockwave", "gain_db": 2.0 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 120, "min_ms_emitter": 180}
	_event_cfg["syn.frost"] = {"stream": "frost_nova", "gain_db": 2.0 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 160, "min_ms_emitter": 240}
	_event_cfg["syn.flame"] = {"stream": "flame_burst", "gain_db": 2.5 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 140, "min_ms_emitter": 220}
	_event_cfg["syn.holy"] = {"stream": "holy_pulse", "gain_db": 0.5 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 120, "min_ms_emitter": 200}
	_event_cfg["syn.focus_tick"] = {"stream": "focus_tick", "gain_db": -3.0 + loud, "pitch": 1.0, "jitter": 0.02, "min_ms_global": 40, "min_ms_emitter": 120}
	_event_cfg["syn.execute"] = {"stream": "execute", "gain_db": 2.5 + loud, "pitch": 1.0, "jitter": 0.03, "min_ms_global": 120, "min_ms_emitter": 240}

	# Enemy special actions
	_event_cfg["enemy.dash"] = {"stream": "shockwave", "gain_db": 2.5 + loud, "pitch": 1.05, "jitter": 0.03, "min_ms_global": 120, "min_ms_emitter": 350}
	_event_cfg["enemy.spit"] = {"stream": "arc_zap", "gain_db": -2.5 + loud, "pitch": 1.20, "jitter": 0.05, "min_ms_global": 40, "min_ms_emitter": 180}
	_event_cfg["enemy.explode"] = {"stream": "flame_burst", "gain_db": 4.0 + loud, "pitch": 0.92, "jitter": 0.04, "min_ms_global": 90, "min_ms_emitter": 250}
	_event_cfg["enemy.arcane"] = {"stream": "arc_zap", "gain_db": 1.2 + loud, "pitch": 1.00, "jitter": 0.05, "min_ms_global": 80, "min_ms_emitter": 260}

#
# Synth helpers
#

func _env(t: float, dur: float, a: float, d: float) -> float:
	# Simple attack/decay envelope (no sustain).
	if t < a:
		return t / maxf(0.0001, a)
	var td: float = (t - a) / maxf(0.0001, d)
	return clampf(1.0 - td, 0.0, 1.0)

func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var s := clampf(samples[i], -1.0, 1.0)
		var v := int(round(s * 32767.0))
		if v < 0:
			v += 65536
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	wav.data = bytes
	return wav

func _make_zap(dur: float, f0: float, f1: float, noise_amt: float) -> AudioStreamWAV:
	var n := int(round(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var f := lerpf(f0, f1, t / dur)
		var phase := TAU * f * t
		var s := sin(phase) * 0.7 + sin(phase * 2.02) * 0.2
		s += (rng.randf_range(-1.0, 1.0)) * noise_amt * 0.35
		s *= _env(t, dur, 0.005, dur * 0.95)
		out[i] = s * 0.9
	return _to_wav(out)

func _make_thump(dur: float, f: float, drive: float) -> AudioStreamWAV:
	var n := int(round(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var s := sin(TAU * f * t)
		# Drive (soft clip)
		s = tanh(s * (1.0 + drive * 4.0))
		s *= _env(t, dur, 0.002, dur * 0.95)
		out[i] = s * 0.95
	return _to_wav(out)

func _make_glass(dur: float, base: float, noise_amt: float) -> AudioStreamWAV:
	var n := int(round(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var f := base * (1.0 + sin(t * 28.0) * 0.07)
		var s := sin(TAU * f * t) * 0.35 + sin(TAU * f * 1.52 * t) * 0.25
		s += rng.randf_range(-1.0, 1.0) * noise_amt * 0.25
		s *= _env(t, dur, 0.003, dur * 0.95)
		out[i] = s * 0.85
	return _to_wav(out)

func _make_whoosh(dur: float, noise_amt: float) -> AudioStreamWAV:
	var n := int(round(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var sweep := lerpf(220.0, 70.0, t / dur)
		var s := sin(TAU * sweep * t) * 0.18
		s += rng.randf_range(-1.0, 1.0) * noise_amt * 0.35
		s *= _env(t, dur, 0.004, dur * 0.92)
		out[i] = s
	return _to_wav(out)

func _make_chime(dur: float, base: float, bright: float) -> AudioStreamWAV:
	var n := int(round(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var s := sin(TAU * base * t) * 0.35
		s += sin(TAU * base * 2.0 * t) * (0.18 + bright * 0.18)
		s += sin(TAU * base * 3.0 * t) * (0.06 + bright * 0.10)
		s *= _env(t, dur, 0.002, dur * 0.96)
		out[i] = s * 0.75
	return _to_wav(out)

func _make_tick(dur: float, f: float, noise_amt: float) -> AudioStreamWAV:
	var n := int(round(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var s := sin(TAU * f * t) * 0.35
		s += rng.randf_range(-1.0, 1.0) * noise_amt * 0.25
		s *= _env(t, dur, 0.001, dur * 0.60)
		out[i] = s * 0.65
	return _to_wav(out)
