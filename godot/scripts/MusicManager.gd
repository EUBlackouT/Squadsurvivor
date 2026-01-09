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
	# Loops
	_proc_streams["menu"] = _make_menu_loop(32.0)
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
	# Menu music: bass-forward + catchy groove (less "annoying", more hook).
	# Goal: simple bass motif, soft hats (no noise static), and a punchy kick with light sidechain.
	var n := int(round(dur * float(SAMPLE_RATE)))
	var out := PackedFloat32Array()
	out.resize(n)

	var bpm := 106.0
	var spb := 60.0 / bpm
	var step_len := spb / 4.0 # 16ths
	var bar_len := spb * 4.0

	# Tonality: D minor pentatonic (dark + catchy).
	var root_midi := 38 # D2
	var scale: Array[int] = [0, 3, 5, 7, 10] # minor pentatonic degrees

	# Harmonic movement (per bar): Dm → Bb → C → A (repeat).
	var bar_roots: Array[int] = [38, 34, 36, 33, 38, 34, 36, 33]

	# Bass hook: 2-bar phrase (32 steps). -1 = rest.
	# Catchiness tricks used:
	# - repetition (same 2-bar phrase repeated twice)
	# - anticipation (notes on step 15/31 before downbeat)
	# - octave pop (occasional +12)
	var bass_hook_a: Array[int] = [
		0, -1, 0, 0, 3, -1, 0, 5,   0, -1, 0, -1, 7, -1, 5, 3,
		0, -1, 0, 0, 3, -1, 0, 10,  0, -1, 7, -1, 5, -1, 3, 0
	]
	var bass_hook_b: Array[int] = [
		0, -1, 0, 3, 5, -1, 3, 0,   0, -1, 7, -1, 5, -1, 3, 0,
		0, -1, 10, -1, 7, -1, 5, 3, 0, -1, 7, -1, 5, -1, 3, 0
	]

	# Sparse "call" stabs (adds hook identity without fatiguing).
	# Values are scale degrees above root (+24 for mid range). -1 = rest.
	var stab_pat: Array[int] = [
		-1, -1, -1, -1, 7, -1, -1, -1,  -1, -1, 5, -1, -1, -1, -1, -1,
		-1, -1, -1, -1, 10, -1, -1, -1, -1, -1, 7, -1, -1, -1, -1, -1
	]

	# Lead melody hook (32 steps): simple, singable, repeated.
	# 1) “call” on bar 1, 2) “response” on bar 2. Keep rests for groove.
	var lead_pat_a: Array[int] = [
		-1, -1, 7, -1, 5, -1, 3, -1,  0, -1, 3, -1, 5, -1, 7, -1,
		-1, -1, 10, -1, 7, -1, 5, -1, 3, -1, 5, -1, 7, -1, 10, -1
	]
	var lead_pat_b: Array[int] = [
		-1, -1, 7, -1, 5, -1, 3, -1,  0, -1, 3, -1, 5, -1, 7, -1,
		-1, -1, 12, -1, 10, -1, 7, -1, 5, -1, 7, -1, 10, -1, 7, -1
	]

	var lp: float = 0.0
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var bar_idx := int(floor(fmod(t, bar_len * 8.0) / bar_len))
		var bar_t := fmod(t, bar_len)
		var step_in_bar := int(floor(bar_t / step_len))
		var st := bar_t - float(step_in_bar) * step_len
		var gstep := int(floor(t / step_len))
		var step_2bar := gstep % 32

		# Micro-swing (gentle)
		if (step_in_bar % 2) == 1:
			st = maxf(0.0, st - step_len * 0.05)

		# Kick (4-on-floor), used for sidechain.
		var beat := int(floor(bar_t / spb))
		var beat_t := bar_t - float(beat) * spb
		var kick := 0.0
		if beat == 0 or beat == 2:
			var kt := beat_t
			var kenv := _env(kt, spb, 0.001, 0.18)
			var kf := lerpf(108.0, 46.0, clampf(kt / 0.10, 0.0, 1.0))
			kick = sin(TAU * kf * kt) * kenv * 0.62

		# Sidechain amount (duck bass on kick)
		var duck := clampf(1.0 - absf(kick) * 0.55, 0.40, 1.0)

		# Bass: 2-bar hook + response.
		var pat := bass_hook_a if bar_idx < 4 else bass_hook_b
		var deg := pat[step_2bar]
		var bass := 0.0
		if deg != -1:
			# Use bar root for harmony, and continuous phase (t) for smoother bass.
			var base_midi := int(bar_roots[clampi(bar_idx, 0, bar_roots.size() - 1)])
			var midi := base_midi + int(deg)
			# octave pop on selected steps
			if step_2bar == 7 or step_2bar == 23:
				midi += 12
			var hz := _note_hz(midi)
			var env := _env(st, step_len, 0.002, step_len * 0.92)
			var sub := sin(TAU * hz * t) * env * 0.62
			var bite := _pulse(fmod(hz * t, 1.0), 0.18) * env * 0.10
			bass = _soft_clip((sub + bite) * 0.92) * duck

		# Clap/snare (tone burst, no noise)
		var clap := 0.0
		if beat == 1 or beat == 3:
			var nt := beat_t
			var nenv := _env(nt, spb, 0.001, 0.10)
			clap += sin(TAU * 210.0 * nt) * nenv * 0.20
			clap += sin(TAU * 420.0 * nt) * nenv * 0.10

		# Hats: soft high pulse on 8ths (no noise)
		var hat := 0.0
		if (step_in_bar % 2) == 1:
			var hh := 6200.0
			hat = _pulse(fmod(hh * st, 1.0), 0.10) * _env(st, step_len, 0.0006, 0.018) * 0.05

		# Mid stabs (call/response identity)
		var stab := 0.0
		var sdeg := stab_pat[step_2bar]
		if sdeg != -1:
			var base_midi := int(bar_roots[clampi(bar_idx, 0, bar_roots.size() - 1)])
			var midi := base_midi + 24 + int(sdeg)
			var hz := _note_hz(midi)
			var envs := _env(st, step_len, 0.001, step_len * 0.55)
			stab += _pulse(fmod(hz * t, 1.0), 0.12) * envs * 0.07
			stab += sin(TAU * hz * t) * envs * 0.03

		# Lead hook (melodic): pulse+sine blend, lightly ducked by kick.
		var lead := 0.0
		var lpat := lead_pat_a if bar_idx < 4 else lead_pat_b
		var ldeg := lpat[step_2bar]
		if ldeg != -1:
			var base_midi := int(bar_roots[clampi(bar_idx, 0, bar_roots.size() - 1)])
			var midi := base_midi + 36 + int(ldeg) # up an octave+ for melody
			var hz := _note_hz(midi)
			var envl := _env(st, step_len, 0.001, step_len * 0.75)
			# a touch of vibrato (very subtle)
			var vib := 1.0 + 0.006 * sin(t * 7.0)
			var s1 := sin(TAU * hz * vib * t) * envl * 0.10
			var s2 := _pulse(fmod(hz * vib * t, 1.0), 0.12) * envl * 0.05
			lead = _soft_clip((s1 + s2) * 1.1) * duck

		# Soft pad glue (triad-ish): extremely quiet, just to make it feel like music.
		var pad := 0.0
		var base_midi := int(bar_roots[clampi(bar_idx, 0, bar_roots.size() - 1)])
		# Minor triad: root, m3, 5
		var p0 := _note_hz(base_midi + 24)
		var p1 := _note_hz(base_midi + 24 + 3)
		var p2 := _note_hz(base_midi + 24 + 7)
		pad += sin(TAU * p0 * t) * 0.015
		pad += sin(TAU * p1 * t) * 0.012
		pad += sin(TAU * p2 * t) * 0.010

		# Tiny fill on last bar: extra hat ticks (still no noise).
		if bar_idx == 7 and (step_in_bar % 4) == 3:
			hat += _pulse(fmod(8200.0 * st, 1.0), 0.08) * _env(st, step_len, 0.0005, 0.016) * 0.02

		var mix := kick + bass + clap + hat + stab + lead + pad
		# Warm lowpass + softclip
		lp = lerpf(lp, mix, 0.055)
		out[i] = _soft_clip(lp * 1.05)

	return _to_wav(out, true)

func _make_combat_loop(dur: float) -> AudioStreamWAV:
	# In-map / combat music: bass-first, halftime groove (less hiss/noise, more punch).
	var n := int(round(dur * float(SAMPLE_RATE)))
	var out := PackedFloat32Array()
	out.resize(n)

	# "Ballxpit-ish" feel: 140bpm halftime = 70 groove.
	var bpm := 140.0
	var spb := 60.0 / bpm
	var bar := spb * 4.0
	var step_len := spb / 4.0
	var root := 33 # A1 (subby)
	var scale: Array[int] = [0, 3, 5, 7, 10]

	# Bass hook: 2-bar (32 steps) so it actually feels like a "riff" instead of a pattern.
	var bass_hook_a: Array[int] = [
		0, -1, 0, 7, -1, 3, -1, 0,   0, -1, 10, -1, 7, -1, 3, 5,
		0, -1, 0, 7, -1, 5, -1, 3,   0, -1, 10, -1, 7, 5, 3, 0
	]
	var bass_hook_b: Array[int] = [
		0, -1, 3, -1, 0, 7, -1, 5,   0, -1, 10, -1, 7, -1, 5, 3,
		0, -1, 0, 7, -1, 3, -1, 0,   0, -1, 10, -1, 7, 5, 3, 0
	]

	# Lead hook for combat (32 steps): higher register, sparse, repeats every 2 bars.
	var lead_pat_a: Array[int] = [
		-1, -1, 7, -1, -1, 5, -1, -1,  0, -1, 3, -1, -1, 5, -1, -1,
		-1, -1, 10, -1, -1, 7, -1, -1, 5, -1, 3, -1, -1, 0, -1, -1
	]
	var lead_pat_b: Array[int] = [
		-1, -1, 7, -1, -1, 5, -1, -1,  0, -1, 3, -1, -1, 5, -1, -1,
		-1, -1, 12, -1, -1, 10, -1, -1, 7, -1, 5, -1, -1, 3, -1, -1
	]

	var lp: float = 0.0
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var bar_t := fmod(t, bar)
		var beat := int(floor(bar_t / spb))
		var beat_t := bar_t - float(beat) * spb
		var step := int(floor(bar_t / step_len))
		var st := bar_t - float(step) * step_len
		var gstep := int(floor(t / step_len))
		var step_2bar := gstep % 32

		# Kick: syncopated pattern + sub drop
		var kick := 0.0
		var is_kick := (beat == 0 and beat_t < 0.20) or (beat == 2 and beat_t < 0.20) or (beat == 0 and step == 6)
		if is_kick:
			var kt := beat_t if (beat == 0 or beat == 2) else st
			var kenv := _env(kt, spb, 0.001, 0.16)
			var kf := lerpf(125.0, 46.0, clampf(kt / 0.09, 0.0, 1.0))
			kick = sin(TAU * kf * kt) * kenv * 0.70

		# Sidechain duck amount derived from kick (must exist even if bass rests).
		var duck := clampf(1.0 - absf(kick) * 0.60, 0.35, 1.0)

		# Snare/clap: halftime on beat 2 (index 2) + ghost at end
		var sn := 0.0
		if beat == 2:
			var nt := beat_t
			var envn := _env(nt, spb, 0.001, 0.10)
			sn += sin(TAU * 220.0 * nt) * envn * 0.22
			sn += sin(TAU * 440.0 * nt) * envn * 0.10
		if beat == 3 and beat_t > spb * 0.75:
			var gt := beat_t - spb * 0.75
			sn += sin(TAU * 260.0 * gt) * _env(gt, spb * 0.25, 0.001, 0.05) * 0.07

		# Hats: pulse-based (no noise). Light rolls on bar end.
		var hat := 0.0
		if (step % 2) == 1:
			var hh := 7600.0
			hat = _pulse(fmod(hh * st, 1.0), 0.10) * _env(st, step_len, 0.0006, 0.02) * 0.06
		# roll on last beat
		if beat == 3 and beat_t > spb * 0.5:
			var rt := fmod(beat_t, step_len * 0.5)
			hat += _pulse(fmod(8800.0 * rt, 1.0), 0.08) * _env(rt, step_len * 0.5, 0.0004, 0.015) * 0.03

		# Bass with simple glide (portamento-ish): use previous sample phase continuity by using t.
		var bar_idx := int(floor(fmod(t, bar * 4.0) / bar))
		var pat := bass_hook_a if bar_idx < 2 else bass_hook_b
		var deg := pat[step_2bar]
		var bass := 0.0
		if deg != -1:
			var midi := root + deg
			var hz := _note_hz(midi)
			var envb := _env(st, step_len, 0.002, step_len * 0.90)
			# sub + distorted square
			var sub := sin(TAU * hz * t) * envb * 0.60
			var sq := _pulse(fmod(hz * t, 1.0), 0.22) * envb * 0.10
			bass = _soft_clip((sub + sq) * 0.95) * duck

		# Lead hook (melody) + light sidechain.
		var lead := 0.0
		var lpat := lead_pat_a if bar_idx < 2 else lead_pat_b
		var ldeg := lpat[step_2bar]
		if ldeg != -1:
			var midi := root + 36 + int(ldeg)
			var hz := _note_hz(midi)
			var envl := _env(st, step_len, 0.001, step_len * 0.70)
			var vib := 1.0 + 0.007 * sin(t * 8.0)
			lead += sin(TAU * hz * vib * t) * envl * 0.10
			lead += _pulse(fmod(hz * vib * t, 1.0), 0.12) * envl * 0.05
			lead = _soft_clip(lead * 1.05) * duck

		# Tiny mid "pluck" to keep energy (very low volume) + call/response.
		var pluck := 0.0
		if (step % 4) == 0:
			var pdeg := scale[(step / 4) % scale.size()]
			var phz := _note_hz(root + 24 + pdeg)
			pluck = sin(TAU * phz * st) * _env(st, step_len, 0.001, 0.05) * 0.06
		# response stab on bar 3 (hook variation)
		if bar_idx == 3 and (step % 8) == 4:
			var phz2 := _note_hz(root + 24 + 7)
			pluck += sin(TAU * phz2 * st) * _env(st, step_len, 0.001, 0.06) * 0.05

		# Very soft pad glue (keeps it musical without getting busy)
		var pad := 0.0
		var base_midi := root + 12
		pad += sin(TAU * _note_hz(base_midi) * t) * 0.012
		pad += sin(TAU * _note_hz(base_midi + 3) * t) * 0.010
		pad += sin(TAU * _note_hz(base_midi + 7) * t) * 0.008

		var mix := kick + sn + hat + bass + lead + pluck + pad
		lp = lerpf(lp, mix, 0.06)
		out[i] = _soft_clip(lp * 1.10)

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


