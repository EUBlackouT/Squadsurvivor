extends Node

# Music crossfader with **procedural fallback**.
# If you later add real files under res://assets/audio/*.mp3, they will override the synth.

const TRACKS := {
	"menu": "res://assets/audio/menu.mp3",
	"combat": "res://assets/audio/combat.mp3",
	"victory": "res://assets/audio/victory.mp3",
	"defeat": "res://assets/audio/defeat.mp3"
}

const SAMPLE_RATE: int = 22050

var _a: AudioStreamPlayer = null
var _b: AudioStreamPlayer = null
var _active_is_a: bool = true
var _current_track_id: String = ""

var _proc_streams: Dictionary = {} # track_id -> AudioStream

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_a = AudioStreamPlayer.new()
	_b = AudioStreamPlayer.new()
	_a.bus = _pick_bus()
	_b.bus = _pick_bus()
	_a.volume_db = -80.0
	_b.volume_db = -80.0
	add_child(_a)
	add_child(_b)
	_build_procedural_streams()

func play(track_id: String, crossfade_duration: float = 1.0) -> void:
	if track_id == _current_track_id:
		return
	var stream := _resolve_stream(track_id)
	if stream == null:
		push_warning("MusicManager: unknown track_id '%s' (no file, no synth)" % track_id)
		return

	var from := _a if _active_is_a else _b
	var to := _b if _active_is_a else _a

	to.stop()
	to.stream = stream
	to.volume_db = -80.0
	to.play()

	var dur := maxf(0.01, crossfade_duration)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(from, "volume_db", -80.0, dur)
	t.tween_property(to, "volume_db", 0.0, dur)
	t.set_parallel(false)
	t.tween_callback(func():
		from.stop()
	)

	_active_is_a = not _active_is_a
	_current_track_id = track_id

func stop(fade_duration: float = 0.5) -> void:
	var from := _a if _active_is_a else _b
	if from == null:
		return
	var t := create_tween()
	t.tween_property(from, "volume_db", -80.0, maxf(0.01, fade_duration))
	t.tween_callback(func():
		from.stop()
	)
	_current_track_id = ""

#
# Stream resolution: MP3 if present, otherwise procedural WAV.
#

func _resolve_stream(track_id: String) -> AudioStream:
	var path := String(TRACKS.get(track_id, ""))
	if path != "" and ResourceLoader.exists(path):
		var s := ResourceLoader.load(path) as AudioStream
		if s != null:
			return s
	# Fallback: procedural
	return _proc_streams.get(track_id, null) as AudioStream

func _pick_bus() -> String:
	# If the project hasn't created a Music bus yet, fall back to Master.
	return "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"

#
# Procedural music
#

func _build_procedural_streams() -> void:
	_proc_streams.clear()
	# Loops (12s)
	_proc_streams["menu"] = _make_menu_loop(12.0)
	_proc_streams["combat"] = _make_combat_loop(12.0)
	# Stingers (3–4s)
	_proc_streams["victory"] = _make_victory_stinger(3.2)
	_proc_streams["defeat"] = _make_defeat_stinger(3.2)

func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
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
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

func _env(t: float, dur: float, a: float, d: float) -> float:
	if t < a:
		return t / maxf(0.0001, a)
	var td := (t - a) / maxf(0.0001, d)
	return clampf(1.0 - td, 0.0, 1.0)

func _soft_clip(x: float) -> float:
	# Cheap saturation
	return tanh(x * 1.25)

func _pulse(phase: float, duty: float) -> float:
	# phase in [0..1)
	return 1.0 if phase < duty else -1.0

func _note_hz(midi: int) -> float:
	return 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)

func _make_menu_loop(dur: float) -> AudioStreamWAV:
	# Dark ambient pad + sparse bell. Theme fit: arcane/graveyard.
	var n := int(round(dur * float(SAMPLE_RATE)))
	var out := PackedFloat32Array()
	out.resize(n)

	var root: int = 45 # A2-ish
	var fifth: int = root + 7
	var minor3: int = root + 3
	var bell_notes: Array[int] = [root + 12, minor3 + 12, fifth + 12, minor3 + 24]

	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		# slow drift
		var lfo := sin(TAU * 0.08 * t) * 0.5 + sin(TAU * 0.031 * t) * 0.5

		var f0 := _note_hz(root) * (1.0 + lfo * 0.002)
		var f1 := _note_hz(fifth) * (1.0 - lfo * 0.0015)
		var f2 := _note_hz(minor3) * (1.0 + lfo * 0.0012)

		var pad := sin(TAU * f0 * t) * 0.28
		pad += sin(TAU * f1 * t) * 0.18
		pad += sin(TAU * f2 * t) * 0.14
		pad += sin(TAU * f0 * 0.5 * t) * 0.08

		# "grave dust" noise (cheap hash noise)
		var hn: float = sin(float(i) * 12.9898) * 43758.5453
		var noise: float = (hn - floor(hn)) * 2.0 - 1.0
		pad += noise * 0.015 * (0.4 + 0.6 * (0.5 + 0.5 * sin(TAU * 0.05 * t)))

		# Sparse bell every 2.0s with long decay
		var bell := 0.0
		var beat_len := 2.0
		var k := int(floor(t / beat_len))
		var tk := t - float(k) * beat_len
		var midi: int = bell_notes[k % bell_notes.size()]
		var bf := _note_hz(midi)
		bell += sin(TAU * bf * tk) * _env(tk, beat_len, 0.01, 1.4) * 0.28
		bell += sin(TAU * bf * 2.01 * tk) * _env(tk, beat_len, 0.01, 1.2) * 0.12

		out[i] = _soft_clip(pad + bell)

	return _to_wav(out, true)

func _make_combat_loop(dur: float) -> AudioStreamWAV:
	# Energetic pulse + kick/snare. Still dark.
	var n := int(round(dur * float(SAMPLE_RATE)))
	var out := PackedFloat32Array()
	out.resize(n)

	var bpm := 136.0
	var spb := 60.0 / bpm
	var bar := spb * 4.0
	var root: int = 45 # A2
	var scale: Array[int] = [0, 3, 5, 7, 10] # minor pentatonic

	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)

		# Sequencer (16th notes)
		var step_t := spb / 4.0
		var step := int(floor(t / step_t))
		var st := t - float(step) * step_t
		var deg: int = scale[(step * 3 + (step / 4)) % scale.size()]
		var midi: int = root + 12 + deg
		var hz := _note_hz(midi)

		var ph := fmod(hz * st, 1.0)
		var lead := _pulse(ph, 0.18) * _env(st, step_t, 0.001, step_t * 0.9) * 0.22
		lead += sin(TAU * hz * 2.0 * st) * _env(st, step_t, 0.001, step_t * 0.7) * 0.06

		# Bass on 8ths
		var bstep_t := spb / 2.0
		var bstep := int(floor(t / bstep_t))
		var bt := t - float(bstep) * bstep_t
		var bdeg: int = scale[(bstep) % scale.size()]
		var bhz := _note_hz(root + bdeg)
		var bass := sin(TAU * bhz * bt) * _env(bt, bstep_t, 0.002, bstep_t * 0.95) * 0.26

		# Drums (simple synthesized kick/snare/hat)
		var drum := 0.0
		var bar_t := fmod(t, bar)
		var beat := int(floor(bar_t / spb))
		var beat_t := bar_t - float(beat) * spb

		# Kick on beats 0 and 2
		if beat == 0 or beat == 2:
			var kt := beat_t
			var kf := lerpf(110.0, 46.0, clampf(kt / 0.10, 0.0, 1.0))
			drum += sin(TAU * kf * kt) * _env(kt, spb, 0.001, 0.18) * 0.55

		# Snare on beats 1 and 3
		if beat == 1 or beat == 3:
			var nt := beat_t
			var hn: float = sin((float(i) + float(beat) * 777.0) * 12.9898) * 43758.5453
			var noise: float = (hn - floor(hn)) * 2.0 - 1.0
			drum += noise * _env(nt, spb, 0.001, 0.12) * 0.24
			drum += sin(TAU * 190.0 * nt) * _env(nt, spb, 0.001, 0.08) * 0.12

		# Hats on 16ths
		var ht := st
		var hn2: float = sin((float(i) + 999.0) * 78.233) * 19341.343
		var noise2: float = (hn2 - floor(hn2)) * 2.0 - 1.0
		drum += noise2 * _env(ht, step_t, 0.0005, 0.03) * 0.07

		var mix := lead + bass + drum
		out[i] = _soft_clip(mix * 1.05)

	return _to_wav(out, true)

func _make_victory_stinger(dur: float) -> AudioStreamWAV:
	# Bright arcane major-ish flourish.
	var n := int(round(dur * float(SAMPLE_RATE)))
	var out := PackedFloat32Array()
	out.resize(n)
	var notes: Array[int] = [69, 73, 76, 81] # A4 C#5 E5 A5
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var seg := dur / float(notes.size())
		var k := int(floor(t / seg))
		var tk := t - float(k) * seg
		var midi: int = notes[clampi(k, 0, notes.size() - 1)]
		var f := _note_hz(midi)
		var s := sin(TAU * f * tk) * _env(tk, seg, 0.01, seg * 0.92) * 0.65
		s += sin(TAU * f * 2.0 * tk) * _env(tk, seg, 0.01, seg * 0.80) * 0.18
		out[i] = _soft_clip(s)
	return _to_wav(out, false)

func _make_defeat_stinger(dur: float) -> AudioStreamWAV:
	# Low, ominous fall.
	var n := int(round(dur * float(SAMPLE_RATE)))
	var out := PackedFloat32Array()
	out.resize(n)
	var start: int = 52 # E3
	var endn: int = 45  # A2
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var a := clampf(t / maxf(0.001, dur), 0.0, 1.0)
		var midi: int = int(round(lerpf(float(start), float(endn), a)))
		var f := _note_hz(midi)
		var s := sin(TAU * f * t) * _env(t, dur, 0.01, dur * 0.98) * 0.62
		s += sin(TAU * f * 0.5 * t) * _env(t, dur, 0.01, dur * 0.95) * 0.18
		out[i] = _soft_clip(s)
	return _to_wav(out, false)


