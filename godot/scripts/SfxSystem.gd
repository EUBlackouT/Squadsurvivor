extends Node

# Hybrid SFX system:
# - Prefers external curated library clips (if present).
# - Falls back to procedural synthesis for any missing category.

@export var master_gain_db: float = -6.5
@export var max_voices: int = 20
@export var default_pitch_jitter: float = 0.06
@export var loud_mode: bool = false

const SAMPLE_RATE: int = 44100
const EXTERNAL_SFX_ROOT: String = "res://assets/audio/Fantasy_Game_24bit_Updated/Fantasy_Game_24bit_Updated/Fantasy_Game_24bit"
const MAX_VARIANTS_PER_STREAM: int = 10

var _streams: Dictionary = {} # id -> AudioStream
var _stream_variants: Dictionary = {} # id -> Array[AudioStream]
var _stream_variant_idx: Dictionary = {} # id -> int
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
	p.stream = _pick_stream_variant(id)
	if p.stream == null:
		return
	p.volume_db = master_gain_db + gain_db
	p.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()

func _pick_stream_variant(id: String) -> AudioStream:
	var variants := _stream_variants.get(id, []) as Array
	if variants != null and variants.size() > 0:
		var idx := int(_stream_variant_idx.get(id, 0))
		if idx < 0:
			idx = 0
		var s: AudioStream = variants[idx % variants.size()] as AudioStream
		_stream_variant_idx[id] = (idx + 1) % variants.size()
		if s != null:
			return s
	return _streams.get(id, null) as AudioStream

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
	var bus_name := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for i in range(maxi(4, max_voices)):
		var p := AudioStreamPlayer2D.new()
		p.bus = bus_name
		p.max_distance = 1200.0
		p.attenuation = 2.0
		p.panning_strength = 0.6
		add_child(p)
		_pool.append(p)

func _build_streams() -> void:
	_streams.clear()
	_stream_variants.clear()
	_stream_variant_idx.clear()
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
	# Passive procs (distinct accents)
	_streams["web_snare"] = _make_glass(0.12, 1080.0, 0.20)
	_streams["spore_bloom"] = _make_whoosh(0.18, 0.28)
	_streams["gel_mitosis"] = _make_tick(0.06, 760.0, 0.14)
	# New passive suite (unique tones)
	_streams["passive_explosive_rounds"] = _make_explosion(0.18, 160.0, 0.65)
	_streams["passive_chain_master"] = _make_zap(0.10, 1500.0, 320.0, 0.30)
	_streams["passive_scatter_specialist"] = _make_tick(0.06, 1320.0, 0.18)
	_streams["passive_boomerang_mastery"] = _make_whoosh(0.14, 0.22)
	_streams["passive_beam_focus"] = _make_beam(0.18, 320.0, 0.12)
	_streams["passive_slam_aftershock"] = _make_thump(0.14, 90.0, 0.70)
	_streams["passive_frost_mastery"] = _make_glass(0.16, 880.0, 0.30)
	_streams["passive_poison_mastery"] = _make_tick(0.12, 520.0, 0.25)
	_streams["passive_fire_mastery"] = _make_whoosh(0.16, 0.35)
	_streams["passive_orbital_precision"] = _make_chime(0.18, 780.0, 0.35)
	_streams["passive_reaper_hunger"] = _make_chime(0.14, 420.0, 0.20)
	_streams["passive_bomb_expert"] = _make_explosion(0.20, 140.0, 0.85)
	_streams["passive_ricochet_master"] = _make_tick(0.08, 1500.0, 0.20)
	_streams["passive_spirit_surge"] = _make_chime(0.16, 720.0, 0.35)
	_streams["passive_vampiric_mastery"] = _make_chime(0.18, 500.0, 0.25)
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
	_streams["ui_levelup"] = _make_levelup_chime(0.30)
	# Combat baseline
	_streams["player_slash"] = _make_whoosh(0.10, 0.18)
	_streams["player_shot"] = _make_tick(0.05, 1120.0, 0.12)
	_streams["hit_ranged"] = _make_tick(0.06, 860.0, 0.16)
	_streams["hit_melee"] = _make_thump(0.08, 160.0, 0.55)
	_streams["hit_crit"] = _make_thump(0.10, 210.0, 0.85)
	_streams["dash_whoosh"] = _make_whoosh(0.12, 0.20)
	_streams["telegraph_tick"] = _make_tick(0.06, 640.0, 0.10)
	_streams["enemy_die"] = _make_tick(0.06, 520.0, 0.18)
	_streams["enemy_spawn_elite"] = _make_thump(0.16, 82.0, 0.65)
	
	# Weapon-specific sounds
	_streams["weapon_slash"] = _make_slash(0.14, 0.35)
	_streams["weapon_bomb_launch"] = _make_whoosh(0.12, 0.25)
	_streams["weapon_bomb_explode"] = _make_explosion(0.22, 120.0, 0.75)
	_streams["weapon_chain_zap"] = _make_zap(0.08, 1400.0, 300.0, 0.30)
	_streams["weapon_pierce"] = _make_whoosh(0.08, 0.20)
	_streams["weapon_scatter"] = _make_tick(0.04, 1200.0, 0.15)
	_streams["weapon_boomerang"] = _make_whoosh(0.10, 0.18)
	_streams["weapon_beam"] = _make_beam(0.25, 280.0, 0.20)
	_streams["weapon_slam"] = _make_thump(0.18, 65.0, 0.90)
	_streams["weapon_poison"] = _make_tick(0.06, 680.0, 0.22)
	_streams["weapon_frost"] = _make_glass(0.12, 920.0, 0.28)
	_streams["weapon_fire"] = _make_whoosh(0.14, 0.35)
	_streams["weapon_spirit"] = _make_chime(0.12, 680.0, 0.30)
	_streams["weapon_vampiric"] = _make_chime(0.10, 440.0, 0.25)
	_streams["weapon_ricochet"] = _make_tick(0.05, 1100.0, 0.18)
	_streams["weapon_orbital_charge"] = _make_beam(0.35, 180.0, 0.15)
	_streams["weapon_orbital_strike"] = _make_explosion(0.30, 80.0, 0.95)
	_attach_external_library()

func _attach_external_library() -> void:
	if DirAccess.open(EXTERNAL_SFX_ROOT) == null:
		return
	var wav_paths := _scan_wav_paths(EXTERNAL_SFX_ROOT)
	if wav_paths.is_empty():
		return

	# Prefer purpose-built samples from the external pack.
	_attach_variants("arc_zap", wav_paths, PackedStringArray(["lightning", "electric", "zap"]))
	_attach_variants("shockwave", wav_paths, PackedStringArray(["impact", "drum_impact", "weapon_impact", "meteor_spell_hit"]))
	_attach_variants("frost_nova", wav_paths, PackedStringArray(["ice_", "ice_", "blizzard", "ice_long"]))
	_attach_variants("flame_burst", wav_paths, PackedStringArray(["fire_", "felflame", "molten", "lava"]))
	_attach_variants("holy_pulse", wav_paths, PackedStringArray(["holy", "light_magic", "magic_confirm"]))
	_attach_variants("focus_tick", wav_paths, PackedStringArray(["select", "tab_button", "rune"]))

	_attach_variants("web_snare", wav_paths, PackedStringArray(["trap", "wooden_trap"]))
	_attach_variants("spore_bloom", wav_paths, PackedStringArray(["poison", "organic_poof"]))
	_attach_variants("gel_mitosis", wav_paths, PackedStringArray(["water_bolt", "airy_sting"]))

	_attach_variants("passive_explosive_rounds", wav_paths, PackedStringArray(["meteor_spell_hit", "weapon_impact"]))
	_attach_variants("passive_chain_master", wav_paths, PackedStringArray(["lightning", "electric"]))
	_attach_variants("passive_scatter_specialist", wav_paths, PackedStringArray(["rain_of_arrows", "rain_of_bolts"]))
	_attach_variants("passive_boomerang_mastery", wav_paths, PackedStringArray(["axethrow", "knife_throw"]))
	_attach_variants("passive_beam_focus", wav_paths, PackedStringArray(["arcane_missile", "arcane_spell"]))
	_attach_variants("passive_slam_aftershock", wav_paths, PackedStringArray(["weapon_impact", "earth_", "meteor_spell_hit"]))
	_attach_variants("passive_frost_mastery", wav_paths, PackedStringArray(["ice_", "blizzard"]))
	_attach_variants("passive_poison_mastery", wav_paths, PackedStringArray(["poison", "debuff"]))
	_attach_variants("passive_fire_mastery", wav_paths, PackedStringArray(["fire_", "felflame"]))
	_attach_variants("passive_orbital_precision", wav_paths, PackedStringArray(["arcane_long_cast", "thunderstorm_cast"]))
	_attach_variants("passive_reaper_hunger", wav_paths, PackedStringArray(["shadow_spell", "dark_conjure"]))
	_attach_variants("passive_bomb_expert", wav_paths, PackedStringArray(["meteor_spell_hit", "molten_lave_hit", "weapon_impact"]))
	_attach_variants("passive_ricochet_master", wav_paths, PackedStringArray(["crossbow", "bow_"]))
	_attach_variants("passive_spirit_surge", wav_paths, PackedStringArray(["arcane", "essence"]))
	_attach_variants("passive_vampiric_mastery", wav_paths, PackedStringArray(["shadow", "dark_conjure", "weapon_impact_blood"]))

	_attach_variants("execute", wav_paths, PackedStringArray(["weapon_impact_blood", "weapon_impact"]))
	_attach_variants("ui_click", wav_paths, PackedStringArray(["select", "tab_button"]))
	_attach_variants("ui_confirm", wav_paths, PackedStringArray(["confirm"]))
	_attach_variants("ui_cancel", wav_paths, PackedStringArray(["select"]))
	_attach_variants("ui_reroll", wav_paths, PackedStringArray(["arcane_select", "magic_confirm"]))
	_attach_variants("ui_open", wav_paths, PackedStringArray(["gear_inventory", "inventory_material"]))
	_attach_variants("ui_drop", wav_paths, PackedStringArray(["accept_quest_drum_impact"]))
	_attach_variants("ui_victory", wav_paths, PackedStringArray(["upgrade", "skill_upgrade", "magic_confirm"]))
	_attach_variants("ui_defeat", wav_paths, PackedStringArray(["distant_soft_rumble", "weapon_impact"]))
	_attach_variants("ui_levelup", wav_paths, PackedStringArray(["skill_upgrade", "magic_action_rune"]))

	_attach_variants("player_slash", wav_paths, PackedStringArray(["blade_draw", "heavy_weapon", "sword"]))
	_attach_variants("player_shot", wav_paths, PackedStringArray(["bow_", "crossbow_", "magic_arrow"]))
	_attach_variants("hit_ranged", wav_paths, PackedStringArray(["crossbow", "bow_"]))
	_attach_variants("hit_melee", wav_paths, PackedStringArray(["weapon_impact", "clank", "armor_hit"]))
	_attach_variants("hit_crit", wav_paths, PackedStringArray(["weapon_impact_blood", "meteor_spell_hit"]))
	_attach_variants("dash_whoosh", wav_paths, PackedStringArray(["airy_sting", "dark_transition", "water_bolt"]))
	_attach_variants("telegraph_tick", wav_paths, PackedStringArray(["rune", "select"]))
	_attach_variants("enemy_die", wav_paths, PackedStringArray(["creature_growl", "weapon_impact_blood"]))
	_attach_variants("enemy_spawn_elite", wav_paths, PackedStringArray(["creature_high", "growl_loud", "distant_soft_rumble"]))

	_attach_variants("weapon_slash", wav_paths, PackedStringArray(["blade_draw", "sword", "heavy_weapon"]))
	_attach_variants("weapon_bomb_launch", wav_paths, PackedStringArray(["axethrow", "knife_throw"]))
	_attach_variants("weapon_bomb_explode", wav_paths, PackedStringArray(["meteor_spell_hit", "molten_lave_hit"]))
	_attach_variants("weapon_chain_zap", wav_paths, PackedStringArray(["lightning", "electric"]))
	_attach_variants("weapon_pierce", wav_paths, PackedStringArray(["crossbow", "bow_"]))
	_attach_variants("weapon_scatter", wav_paths, PackedStringArray(["rain_of_arrows", "rain_of_bolts", "crossbow"]))
	_attach_variants("weapon_boomerang", wav_paths, PackedStringArray(["axethrow", "knife_throw"]))
	_attach_variants("weapon_beam", wav_paths, PackedStringArray(["arcane_missile", "lightning_long_cast"]))
	_attach_variants("weapon_slam", wav_paths, PackedStringArray(["earth_", "weapon_impact", "meteor_spell_hit"]))
	_attach_variants("weapon_poison", wav_paths, PackedStringArray(["poison", "debuff"]))
	_attach_variants("weapon_frost", wav_paths, PackedStringArray(["ice_", "blizzard"]))
	_attach_variants("weapon_fire", wav_paths, PackedStringArray(["fire_", "felflame"]))
	_attach_variants("weapon_spirit", wav_paths, PackedStringArray(["arcane_spell", "essence", "shadow_spell"]))
	_attach_variants("weapon_vampiric", wav_paths, PackedStringArray(["weapon_impact_blood", "dark_conjure"]))
	_attach_variants("weapon_ricochet", wav_paths, PackedStringArray(["crossbow", "bow_"]))
	_attach_variants("weapon_orbital_charge", wav_paths, PackedStringArray(["thunderstorm_cast", "arcane_long_cast"]))
	_attach_variants("weapon_orbital_strike", wav_paths, PackedStringArray(["meteor_spell_hit", "molten_lave_hit", "weapon_impact"]))

func _attach_variants(stream_id: String, all_paths: Array[String], include_tokens: PackedStringArray) -> void:
	var picked := _pick_paths_by_tokens(all_paths, include_tokens)
	if picked.is_empty():
		return
	var variants: Array[AudioStream] = []
	for p in picked:
		if variants.size() >= MAX_VARIANTS_PER_STREAM:
			break
		var st := load(p) as AudioStream
		if st != null:
			variants.append(st)
	if variants.is_empty():
		return
	_stream_variants[stream_id] = variants
	_stream_variant_idx[stream_id] = 0
	# Use first clip as canonical stream for systems expecting one id.
	_streams[stream_id] = variants[0]

func _pick_paths_by_tokens(all_paths: Array[String], include_tokens: PackedStringArray) -> Array[String]:
	var scored: Array[Dictionary] = []
	for p in all_paths:
		var n := _norm_name(p)
		var score := 0
		for t in include_tokens:
			var token := _norm_name(String(t))
			if token != "" and n.contains(token):
				score += 1
		if score > 0:
			scored.append({"path": p, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	var out: Array[String] = []
	for row in scored:
		out.append(String(row.get("path", "")))
	return out

func _scan_wav_paths(root: String) -> Array[String]:
	var out: Array[String] = []
	_scan_wav_paths_recursive(root, out)
	return out

func _scan_wav_paths_recursive(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	while true:
		var name := d.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		var full := dir_path.path_join(name)
		var norm_full := full.to_lower().replace("\\", "/")
		if norm_full.contains("/__macosx/"):
			continue
		if name.begins_with("._"):
			continue
		if d.current_is_dir():
			_scan_wav_paths_recursive(full, out)
		elif name.to_lower().ends_with(".wav"):
			out.append(full)
	d.list_dir_end()

func _norm_name(s: String) -> String:
	var n := s.to_lower()
	n = n.replace("\\", "/")
	n = n.replace(" ", "_")
	n = n.replace("-", "_")
	return n

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
	_event_cfg["ui.pause_open"] = {"stream": "ui_open", "gain_db": 0.5 + loud, "pitch": 0.98, "jitter": 0.03, "min_ms_global": 200, "min_ms_emitter": 200}
	_event_cfg["ui.pause_close"] = {"stream": "ui_cancel", "gain_db": -1.0 + loud, "pitch": 1.0, "jitter": 0.03, "min_ms_global": 120, "min_ms_emitter": 120}
	_event_cfg["ui.save"] = {"stream": "ui_confirm", "gain_db": 1.0 + loud, "pitch": 0.95, "jitter": 0.02, "min_ms_global": 250, "min_ms_emitter": 250}
	_event_cfg["ui.resume_load"] = {"stream": "ui_confirm", "gain_db": 1.0 + loud, "pitch": 1.05, "jitter": 0.02, "min_ms_global": 250, "min_ms_emitter": 250}
	_event_cfg["ui.pick"] = {"stream": "ui_confirm", "gain_db": 0.5 + loud, "pitch": 1.02, "jitter": 0.03, "min_ms_global": 120, "min_ms_emitter": 120}
	_event_cfg["ui.levelup"] = {"stream": "ui_levelup", "gain_db": 3.0 + loud, "pitch": 1.0, "jitter": 0.02, "min_ms_global": 200, "min_ms_emitter": 200}

	# Core combat (very frequent -> per-emitter throttle)
	_event_cfg["player.shot"] = {"stream": "player_shot", "gain_db": -2.0 + loud, "pitch": 1.0, "jitter": 0.08, "min_ms_global": 0, "min_ms_emitter": 90}
	# Hits (very frequent): keep subtle + throttle per-emitter.
	_event_cfg["hit.ranged"] = {"stream": "hit_ranged", "gain_db": -3.0 + loud, "pitch": 1.0, "jitter": 0.06, "min_ms_global": 0, "min_ms_emitter": 80}
	_event_cfg["hit.melee"] = {"stream": "hit_melee", "gain_db": -1.5 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 0, "min_ms_emitter": 90}
	_event_cfg["hit.crit"] = {"stream": "hit_crit", "gain_db": 1.0 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 40, "min_ms_emitter": 120}
	_event_cfg["hit.enemy_melee"] = {"stream": "hit_melee", "gain_db": -2.0 + loud, "pitch": 0.98, "jitter": 0.05, "min_ms_global": 0, "min_ms_emitter": 110}
	_event_cfg["hit.enemy_ranged"] = {"stream": "hit_ranged", "gain_db": -3.0 + loud, "pitch": 0.98, "jitter": 0.06, "min_ms_global": 0, "min_ms_emitter": 110}
	_event_cfg["enemy.die"] = {"stream": "enemy_die", "gain_db": -2.0 + loud, "pitch": 1.0, "jitter": 0.08, "min_ms_global": 25, "min_ms_emitter": 0}
	_event_cfg["enemy.elite_spawn"] = {"stream": "enemy_spawn_elite", "gain_db": 2.0 + loud, "pitch": 1.0, "jitter": 0.03, "min_ms_global": 250, "min_ms_emitter": 250}
	_event_cfg["boss.spawn"] = {"stream": "enemy_spawn_elite", "gain_db": 4.0 + loud, "pitch": 0.92, "jitter": 0.02, "min_ms_global": 600, "min_ms_emitter": 600}

	# Synergy procs (big moments, but still throttled)
	_event_cfg["syn.arc"] = {"stream": "arc_zap", "gain_db": 0.5 + loud, "pitch": 1.0, "jitter": 0.06, "min_ms_global": 90, "min_ms_emitter": 140}
	_event_cfg["syn.shock"] = {"stream": "shockwave", "gain_db": 2.0 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 120, "min_ms_emitter": 180}
	_event_cfg["syn.frost"] = {"stream": "frost_nova", "gain_db": 2.0 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 160, "min_ms_emitter": 240}
	_event_cfg["syn.flame"] = {"stream": "flame_burst", "gain_db": 2.5 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 140, "min_ms_emitter": 220}
	_event_cfg["syn.wisp"] = {"stream": "focus_tick", "gain_db": -1.0 + loud, "pitch": 1.12, "jitter": 0.03, "min_ms_global": 60, "min_ms_emitter": 140}
	_event_cfg["syn.holy"] = {"stream": "holy_pulse", "gain_db": 0.5 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 120, "min_ms_emitter": 200}
	_event_cfg["syn.focus_tick"] = {"stream": "focus_tick", "gain_db": -3.0 + loud, "pitch": 1.0, "jitter": 0.02, "min_ms_global": 40, "min_ms_emitter": 120}
	_event_cfg["syn.execute"] = {"stream": "execute", "gain_db": 2.5 + loud, "pitch": 1.0, "jitter": 0.03, "min_ms_global": 120, "min_ms_emitter": 240}
	# Passive procs (rarer, punchier)
	_event_cfg["passive.web_snare"] = {"stream": "web_snare", "gain_db": 1.0 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 120, "min_ms_emitter": 220}
	_event_cfg["passive.spore_bloom"] = {"stream": "spore_bloom", "gain_db": 1.5 + loud, "pitch": 0.96, "jitter": 0.05, "min_ms_global": 140, "min_ms_emitter": 260}
	_event_cfg["passive.gel_mitosis"] = {"stream": "gel_mitosis", "gain_db": 0.5 + loud, "pitch": 1.05, "jitter": 0.05, "min_ms_global": 110, "min_ms_emitter": 220}
	_event_cfg["passive.explosive_rounds"] = {"stream": "passive_explosive_rounds", "gain_db": 2.5 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 120, "min_ms_emitter": 220}
	_event_cfg["passive.chain_master"] = {"stream": "passive_chain_master", "gain_db": 1.0 + loud, "pitch": 1.0, "jitter": 0.06, "min_ms_global": 120, "min_ms_emitter": 220}
	_event_cfg["passive.scatter_specialist"] = {"stream": "passive_scatter_specialist", "gain_db": 0.5 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 100, "min_ms_emitter": 200}
	_event_cfg["passive.boomerang_mastery"] = {"stream": "passive_boomerang_mastery", "gain_db": 0.5 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 140, "min_ms_emitter": 240}
	_event_cfg["passive.beam_focus"] = {"stream": "passive_beam_focus", "gain_db": 1.0 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 140, "min_ms_emitter": 240}
	_event_cfg["passive.slam_aftershock"] = {"stream": "passive_slam_aftershock", "gain_db": 2.0 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 160, "min_ms_emitter": 280}
	_event_cfg["passive.frost_mastery"] = {"stream": "passive_frost_mastery", "gain_db": 1.5 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 160, "min_ms_emitter": 280}
	_event_cfg["passive.poison_mastery"] = {"stream": "passive_poison_mastery", "gain_db": 0.0 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 160, "min_ms_emitter": 260}
	_event_cfg["passive.fire_mastery"] = {"stream": "passive_fire_mastery", "gain_db": 1.5 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 160, "min_ms_emitter": 260}
	_event_cfg["passive.orbital_precision"] = {"stream": "passive_orbital_precision", "gain_db": 1.5 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 200, "min_ms_emitter": 300}
	_event_cfg["passive.reaper_hunger"] = {"stream": "passive_reaper_hunger", "gain_db": 0.5 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 120, "min_ms_emitter": 220}
	_event_cfg["passive.bomb_expert"] = {"stream": "passive_bomb_expert", "gain_db": 2.0 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 150, "min_ms_emitter": 260}
	_event_cfg["passive.ricochet_master"] = {"stream": "passive_ricochet_master", "gain_db": -0.5 + loud, "pitch": 1.0, "jitter": 0.06, "min_ms_global": 80, "min_ms_emitter": 140}
	_event_cfg["passive.spirit_surge"] = {"stream": "passive_spirit_surge", "gain_db": 1.0 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 160, "min_ms_emitter": 260}
	_event_cfg["passive.vampiric_mastery"] = {"stream": "passive_vampiric_mastery", "gain_db": 0.5 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 160, "min_ms_emitter": 260}

	# Enemy special actions
	_event_cfg["enemy.dash"] = {"stream": "shockwave", "gain_db": 2.5 + loud, "pitch": 1.05, "jitter": 0.03, "min_ms_global": 120, "min_ms_emitter": 350}
	_event_cfg["enemy.spit"] = {"stream": "arc_zap", "gain_db": -2.5 + loud, "pitch": 1.20, "jitter": 0.05, "min_ms_global": 40, "min_ms_emitter": 180}
	_event_cfg["enemy.explode"] = {"stream": "flame_burst", "gain_db": 4.0 + loud, "pitch": 0.92, "jitter": 0.04, "min_ms_global": 90, "min_ms_emitter": 250}
	_event_cfg["enemy.arcane"] = {"stream": "arc_zap", "gain_db": 1.2 + loud, "pitch": 1.00, "jitter": 0.05, "min_ms_global": 80, "min_ms_emitter": 260}

	# Player / squad moments
	_event_cfg["player.dash"] = {"stream": "dash_whoosh", "gain_db": -1.0 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 60, "min_ms_emitter": 200}
	_event_cfg["unit.die"] = {"stream": "hit_melee", "gain_db": 0.5 + loud, "pitch": 0.92, "jitter": 0.04, "min_ms_global": 60, "min_ms_emitter": 120}
	_event_cfg["enemy.vampiric_heal"] = {"stream": "holy_pulse", "gain_db": -2.0 + loud, "pitch": 0.92, "jitter": 0.03, "min_ms_global": 80, "min_ms_emitter": 350}

	# Callouts (rare, should feel impactful)
	_event_cfg["callout.aegis"] = {"stream": "shockwave", "gain_db": 2.0 + loud, "pitch": 0.98, "jitter": 0.03, "min_ms_global": 300, "min_ms_emitter": 300}
	_event_cfg["callout.smoke"] = {"stream": "ui_open", "gain_db": 1.0 + loud, "pitch": 0.92, "jitter": 0.03, "min_ms_global": 300, "min_ms_emitter": 300}
	_event_cfg["callout.arc_surge"] = {"stream": "arc_zap", "gain_db": 1.0 + loud, "pitch": 0.98, "jitter": 0.04, "min_ms_global": 300, "min_ms_emitter": 300}
	_event_cfg["callout.beacon"] = {"stream": "holy_pulse", "gain_db": 1.5 + loud, "pitch": 1.0, "jitter": 0.03, "min_ms_global": 300, "min_ms_emitter": 300}

	# Telegraphs (should be audible but not annoying)
	_event_cfg["telegraph.charge"] = {"stream": "telegraph_tick", "gain_db": -3.0 + loud, "pitch": 1.0, "jitter": 0.02, "min_ms_global": 120, "min_ms_emitter": 300}
	
	# Weapon-specific sounds
	_event_cfg["weapon.reaper_slash"] = {"stream": "weapon_slash", "gain_db": 1.0 + loud, "pitch": 1.0, "jitter": 0.06, "min_ms_global": 60, "min_ms_emitter": 150}
	_event_cfg["weapon.bomb_launch"] = {"stream": "weapon_bomb_launch", "gain_db": -1.0 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 80, "min_ms_emitter": 200}
	_event_cfg["weapon.bomb_explode"] = {"stream": "weapon_bomb_explode", "gain_db": 3.0 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 100, "min_ms_emitter": 250}
	_event_cfg["weapon.chain_lightning"] = {"stream": "weapon_chain_zap", "gain_db": 0.5 + loud, "pitch": 1.0, "jitter": 0.08, "min_ms_global": 30, "min_ms_emitter": 80}
	_event_cfg["weapon.pierce"] = {"stream": "weapon_pierce", "gain_db": -0.5 + loud, "pitch": 1.05, "jitter": 0.06, "min_ms_global": 50, "min_ms_emitter": 120}
	_event_cfg["weapon.scatter"] = {"stream": "weapon_scatter", "gain_db": 0.5 + loud, "pitch": 1.0, "jitter": 0.08, "min_ms_global": 60, "min_ms_emitter": 150}
	_event_cfg["weapon.boomerang"] = {"stream": "weapon_boomerang", "gain_db": -1.0 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 100, "min_ms_emitter": 250}
	_event_cfg["weapon.beam"] = {"stream": "weapon_beam", "gain_db": 1.5 + loud, "pitch": 1.0, "jitter": 0.03, "min_ms_global": 150, "min_ms_emitter": 300}
	_event_cfg["weapon.slam"] = {"stream": "weapon_slam", "gain_db": 2.5 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 120, "min_ms_emitter": 280}
	_event_cfg["weapon.poison"] = {"stream": "weapon_poison", "gain_db": -2.0 + loud, "pitch": 1.0, "jitter": 0.06, "min_ms_global": 60, "min_ms_emitter": 140}
	_event_cfg["weapon.poison_hit"] = {"stream": "weapon_poison", "gain_db": -1.0 + loud, "pitch": 1.05, "jitter": 0.06, "min_ms_global": 40, "min_ms_emitter": 80}
	_event_cfg["weapon.frost"] = {"stream": "weapon_frost", "gain_db": 0.5 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 80, "min_ms_emitter": 180}
	_event_cfg["weapon.frost_hit"] = {"stream": "weapon_frost", "gain_db": 1.0 + loud, "pitch": 1.02, "jitter": 0.05, "min_ms_global": 40, "min_ms_emitter": 80}
	_event_cfg["weapon.fire"] = {"stream": "weapon_fire", "gain_db": 1.0 + loud, "pitch": 1.0, "jitter": 0.05, "min_ms_global": 100, "min_ms_emitter": 200}
	_event_cfg["weapon.spirit"] = {"stream": "weapon_spirit", "gain_db": 0.0 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 80, "min_ms_emitter": 160}
	_event_cfg["weapon.spirit_strike"] = {"stream": "weapon_spirit", "gain_db": 1.0 + loud, "pitch": 1.05, "jitter": 0.04, "min_ms_global": 60, "min_ms_emitter": 120}
	_event_cfg["weapon.vampiric"] = {"stream": "weapon_vampiric", "gain_db": -0.5 + loud, "pitch": 1.0, "jitter": 0.04, "min_ms_global": 100, "min_ms_emitter": 200}
	_event_cfg["weapon.ricochet"] = {"stream": "weapon_ricochet", "gain_db": -1.5 + loud, "pitch": 1.0, "jitter": 0.10, "min_ms_global": 30, "min_ms_emitter": 60}
	_event_cfg["weapon.ricochet_bounce"] = {"stream": "weapon_ricochet", "gain_db": -1.0 + loud, "pitch": 1.08, "jitter": 0.10, "min_ms_global": 30, "min_ms_emitter": 60}
	_event_cfg["weapon.orbital_warning"] = {"stream": "weapon_orbital_charge", "gain_db": 0.5 + loud, "pitch": 0.95, "jitter": 0.03, "min_ms_global": 180, "min_ms_emitter": 350}
	_event_cfg["weapon.orbital_charge"] = {"stream": "weapon_orbital_charge", "gain_db": 1.0 + loud, "pitch": 1.0, "jitter": 0.03, "min_ms_global": 200, "min_ms_emitter": 400}
	_event_cfg["weapon.orbital_strike"] = {"stream": "weapon_orbital_strike", "gain_db": 4.0 + loud, "pitch": 1.0, "jitter": 0.02, "min_ms_global": 300, "min_ms_emitter": 500}
	_event_cfg["weapon.orbital_beam"] = {"stream": "weapon_orbital_charge", "gain_db": 1.2 + loud, "pitch": 0.90, "jitter": 0.03, "min_ms_global": 150, "min_ms_emitter": 300}

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

func _make_levelup_chime(dur: float) -> AudioStreamWAV:
	# Exciting ascending arpeggio for level up / upgrade
	var n := int(round(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	# C5 -> E5 -> G5 -> C6 (major arpeggio)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.50]
	var note_dur := dur / float(notes.size())
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var note_idx := mini(int(t / note_dur), notes.size() - 1)
		var note_t := fmod(t, note_dur)
		var freq := notes[note_idx]
		var s := sin(TAU * freq * t) * 0.40
		s += sin(TAU * freq * 2.0 * t) * 0.20
		s += sin(TAU * freq * 3.0 * t) * 0.08
		# Per-note envelope
		var env := _env(note_t, note_dur, 0.003, note_dur * 0.85)
		# Overall envelope
		var overall := _env(t, dur, 0.001, dur * 0.70)
		out[i] = s * env * overall * 0.85
	return _to_wav(out)

func _make_slash(dur: float, noise_amt: float) -> AudioStreamWAV:
	# Swooshy slash sound - filtered noise with fast attack/decay
	var n := int(round(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hp_state := 0.0
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var env := _env(t, dur, 0.01, dur * 0.8)
		var noise := rng.randf_range(-1.0, 1.0) * noise_amt
		# High-pass filter for swoosh character
		var raw := noise * env
		hp_state = hp_state * 0.85 + raw * 0.15
		var hp := raw - hp_state
		# Pitch sweep down
		var sweep := sin(t * 600.0 * (1.0 - t / dur * 0.7)) * 0.3
		out[i] = clampf((hp + sweep) * env, -1.0, 1.0)
	return _to_wav(out)

func _make_explosion(dur: float, base_f: float, drive: float) -> AudioStreamWAV:
	# Deep explosion with rumble and noise
	var n := int(round(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var env := _env(t, dur, 0.005, dur * 0.9)
		# Low rumble
		var rumble := sin(t * base_f * (1.0 - t / dur * 0.5)) * 0.6
		# Noise burst
		var noise := rng.randf_range(-1.0, 1.0) * (1.0 - t / dur) * 0.5
		var raw := (rumble + noise) * env * drive
		out[i] = clampf(raw, -1.0, 1.0)
	return _to_wav(out)

func _make_beam(dur: float, base_f: float, noise_amt: float) -> AudioStreamWAV:
	# Sustained energy beam sound
	var n := int(round(dur * SAMPLE_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var env := _env(t, dur, 0.02, dur * 0.2)
		# Harmonic drone
		var drone := sin(t * base_f) * 0.4 + sin(t * base_f * 2.0) * 0.2 + sin(t * base_f * 3.0) * 0.1
		# Modulation wobble
		var wobble := sin(t * 12.0) * 0.15
		# Light noise
		var noise := rng.randf_range(-1.0, 1.0) * noise_amt
		out[i] = clampf((drone * (1.0 + wobble) + noise) * env, -1.0, 1.0)
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
