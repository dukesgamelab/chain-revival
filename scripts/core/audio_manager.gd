extends Node
## Combat, movement, and ambient audio with volume controls.
## Plays OG Chain of Command WAVs when available, falls back to generated samples.

const AUDIO_ROOT := "res://assets/audio/original/"
const SETTINGS_PATH := "user://audio_settings.cfg"

const WEAPON_VOLUME_DB := 0.0
const GRENADE_VOLUME_DB := 0.0
const DEATH_VOLUME_DB := 0.0
const FOOTSTEP_VOLUME_DB := -6.0
const THROW_VOLUME_DB := -2.0

const WEAPON_PLAYER_COUNT := 8
const DEATH_PLAYER_COUNT := 4
const GRENADE_PLAYER_COUNT := 2
const FOOTSTEP_PLAYER_COUNT := 4
const THROW_PLAYER_COUNT := 2

const FOOTSTEP_MIN_INTERVAL := 0.1

const WeaponRegistryClass := preload("res://scripts/combat/weapon_registry.gd")

const WEAPON_STREAM_PATHS := {
	WeaponRegistryClass.ID_M1_GARAND: AUDIO_ROOT + "gun.wav",
	WeaponRegistryClass.ID_KAR98K: AUDIO_ROOT + "gun2.wav",
	WeaponRegistryClass.ID_THOMPSON: AUDIO_ROOT + "mchgun8.wav",
	WeaponRegistryClass.ID_MP40: AUDIO_ROOT + "mchgun9.wav",
	WeaponRegistryClass.ID_BAR: AUDIO_ROOT + "mg34.wav",
	WeaponRegistryClass.ID_MG42: AUDIO_ROOT + "Mg42-1.WAV",
}

const DEATH_STREAM_PATHS: Array[String] = [
	AUDIO_ROOT + "scream.wav",
	AUDIO_ROOT + "scream1.wav",
	AUDIO_ROOT + "scream3.wav",
	AUDIO_ROOT + "scream4.wav",
	AUDIO_ROOT + "scream5.wav",
	AUDIO_ROOT + "scream7.wav",
	AUDIO_ROOT + "scream8.wav",
	AUDIO_ROOT + "scream9.wav",
	AUDIO_ROOT + "scream10.wav",
	AUDIO_ROOT + "scream11.wav",
]

const GRENADE_STREAM_PATH := AUDIO_ROOT + "granad3.wav"

const FOOTSTEP_STREAM_PATHS: Array[String] = [
	AUDIO_ROOT + "Mdwn.wav",
	AUDIO_ROOT + "Mup.wav",
]

## Bus names — created at startup if missing.
const BUS_SFX := &"SFX"
const BUS_AMBIENT := &"Ambient"

## Volume state (0.0–1.0 linear).
var master_volume := 1.0:
	set(v):
		master_volume = clampf(v, 0.0, 1.0)
		_apply_bus_volume(0, master_volume)
var sfx_volume := 1.0:
	set(v):
		sfx_volume = clampf(v, 0.0, 1.0)
		_apply_bus_volume(_sfx_bus_idx, sfx_volume)
var ambient_volume := 0.5:
	set(v):
		ambient_volume = clampf(v, 0.0, 1.0)
		_apply_bus_volume(_ambient_bus_idx, ambient_volume)

var _sfx_bus_idx := -1
var _ambient_bus_idx := -1

var _weapon_streams: Dictionary = {}
var _death_streams: Array[AudioStream] = []
var _grenade_stream: AudioStream
var _footstep_streams: Array[AudioStream] = []
var _throw_stream: AudioStream
var _ambient_stream: AudioStream

var _fallback_weapon_stream: AudioStream
var _fallback_death_stream: AudioStream
var _fallback_footstep_stream: AudioStream

var _weapon_players: Array[AudioStreamPlayer] = []
var _death_players: Array[AudioStreamPlayer] = []
var _grenade_players: Array[AudioStreamPlayer] = []
var _footstep_players: Array[AudioStreamPlayer] = []
var _throw_players: Array[AudioStreamPlayer] = []
var _ambient_player: AudioStreamPlayer

var _weapon_pool_index := 0
var _death_pool_index := 0
var _grenade_pool_index := 0
var _footstep_pool_index := 0
var _throw_pool_index := 0

var _footstep_cooldown := 0.0
var _warned_missing: Dictionary = {}


func _ready() -> void:
	_setup_buses()
	_fallback_weapon_stream = _generate_gunshot()
	_fallback_death_stream = _generate_death()
	_fallback_footstep_stream = _generate_footstep()
	_load_weapon_streams()
	_load_death_streams()
	_grenade_stream = _load_stream(GRENADE_STREAM_PATH, "grenade explosion")
	_load_footstep_streams()
	_throw_stream = _generate_throw()
	_ambient_stream = _generate_ambient_loop()
	_build_player_pools()
	_load_settings()


func _process(delta: float) -> void:
	if _footstep_cooldown > 0.0:
		_footstep_cooldown -= delta


# ── Public API ──────────────────────────────────────────────────────────────

func play_weapon_fire(weapon_id: String) -> void:
	var stream := _weapon_streams.get(weapon_id, _fallback_weapon_stream) as AudioStream
	if stream == null:
		if not weapon_id.is_empty() and not _warned_missing.has("weapon:%s" % weapon_id):
			_warned_missing["weapon:%s" % weapon_id] = true
			push_warning("AudioManager: unknown weapon_id '%s', using generated gunshot." % weapon_id)
		stream = _fallback_weapon_stream
	_play_from_pool(
		_weapon_players, _weapon_pool_index, stream,
		WEAPON_VOLUME_DB, randf_range(0.97, 1.03),
	)
	_weapon_pool_index = (_weapon_pool_index + 1) % _weapon_players.size()


func play_grenade_explosion() -> void:
	var stream := _grenade_stream if _grenade_stream != null else _fallback_weapon_stream
	_play_from_pool(
		_grenade_players, _grenade_pool_index, stream,
		GRENADE_VOLUME_DB, 1.0,
	)
	_grenade_pool_index = (_grenade_pool_index + 1) % _grenade_players.size()


func play_death(_team_id: int = -1) -> void:
	var stream := _pick_death_stream()
	_play_from_pool(
		_death_players, _death_pool_index, stream,
		DEATH_VOLUME_DB, randf_range(0.96, 1.04),
	)
	_death_pool_index = (_death_pool_index + 1) % _death_players.size()


func play_footstep(crawling: bool = false) -> void:
	if _footstep_cooldown > 0.0:
		return
	_footstep_cooldown = FOOTSTEP_MIN_INTERVAL
	var stream := _pick_footstep_stream()
	var pitch := randf_range(0.85, 1.15) if crawling else randf_range(0.92, 1.08)
	var vol := FOOTSTEP_VOLUME_DB - 4.0 if crawling else FOOTSTEP_VOLUME_DB
	_play_from_pool(
		_footstep_players, _footstep_pool_index, stream,
		vol, pitch,
	)
	_footstep_pool_index = (_footstep_pool_index + 1) % _footstep_players.size()


func play_grenade_throw() -> void:
	_play_from_pool(
		_throw_players, _throw_pool_index, _throw_stream,
		THROW_VOLUME_DB, randf_range(0.95, 1.05),
	)
	_throw_pool_index = (_throw_pool_index + 1) % _throw_players.size()


func start_ambient() -> void:
	if _ambient_player == null:
		return
	if _ambient_player.playing:
		return
	_ambient_player.stream = _ambient_stream
	_ambient_player.volume_db = -6.0
	_ambient_player.play()


func stop_ambient() -> void:
	if _ambient_player != null:
		_ambient_player.stop()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("audio", "ambient", ambient_volume)
	config.save(SETTINGS_PATH)


# ── Setup ───────────────────────────────────────────────────────────────────

func _setup_buses() -> void:
	_sfx_bus_idx = AudioServer.get_bus_index(BUS_SFX)
	if _sfx_bus_idx == -1:
		_sfx_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_sfx_bus_idx)
		AudioServer.set_bus_name(_sfx_bus_idx, BUS_SFX)
		AudioServer.set_bus_send(_sfx_bus_idx, &"Master")

	_ambient_bus_idx = AudioServer.get_bus_index(BUS_AMBIENT)
	if _ambient_bus_idx == -1:
		_ambient_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_ambient_bus_idx)
		AudioServer.set_bus_name(_ambient_bus_idx, BUS_AMBIENT)
		AudioServer.set_bus_send(_ambient_bus_idx, &"Master")


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		_apply_bus_volume(0, master_volume)
		_apply_bus_volume(_sfx_bus_idx, sfx_volume)
		_apply_bus_volume(_ambient_bus_idx, ambient_volume)
		return
	master_volume = config.get_value("audio", "master", 1.0)
	sfx_volume = config.get_value("audio", "sfx", 1.0)
	ambient_volume = config.get_value("audio", "ambient", 0.5)


func _apply_bus_volume(bus_idx: int, linear: float) -> void:
	if bus_idx < 0 or bus_idx >= AudioServer.bus_count:
		return
	if linear <= 0.0:
		AudioServer.set_bus_mute(bus_idx, true)
	else:
		AudioServer.set_bus_mute(bus_idx, false)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(linear))


# ── Stream loading ──────────────────────────────────────────────────────────

func _load_weapon_streams() -> void:
	for weapon_id in WEAPON_STREAM_PATHS:
		var path: String = WEAPON_STREAM_PATHS[weapon_id]
		var stream := _load_stream(path, "weapon:%s" % weapon_id)
		if stream != null:
			_weapon_streams[weapon_id] = stream


func _load_death_streams() -> void:
	for path in DEATH_STREAM_PATHS:
		var stream := _load_stream(path, path)
		if stream != null:
			_death_streams.append(stream)


func _load_footstep_streams() -> void:
	for path in FOOTSTEP_STREAM_PATHS:
		var stream := _load_stream(path, "footstep")
		if stream != null:
			_footstep_streams.append(stream)


func _pick_death_stream() -> AudioStream:
	if _death_streams.is_empty():
		return _fallback_death_stream
	return _death_streams[randi() % _death_streams.size()]


func _pick_footstep_stream() -> AudioStream:
	if _footstep_streams.is_empty():
		return _fallback_footstep_stream
	return _footstep_streams[randi() % _footstep_streams.size()]


func _load_stream(path: String, warn_key: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		if not _warned_missing.has(warn_key):
			_warned_missing[warn_key] = true
			push_warning("AudioManager: missing audio '%s', using generated fallback." % path)
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		if not _warned_missing.has(warn_key):
			_warned_missing[warn_key] = true
			push_warning("AudioManager: failed to load audio '%s', using generated fallback." % path)
	return stream


# ── Player pools ────────────────────────────────────────────────────────────

func _build_player_pools() -> void:
	_weapon_players = _create_players(WEAPON_PLAYER_COUNT, "WeaponPlayer", BUS_SFX)
	_death_players = _create_players(DEATH_PLAYER_COUNT, "DeathPlayer", BUS_SFX)
	_grenade_players = _create_players(GRENADE_PLAYER_COUNT, "GrenadePlayer", BUS_SFX)
	_footstep_players = _create_players(FOOTSTEP_PLAYER_COUNT, "FootstepPlayer", BUS_SFX)
	_throw_players = _create_players(THROW_PLAYER_COUNT, "ThrowPlayer", BUS_SFX)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "AmbientPlayer"
	_ambient_player.bus = BUS_AMBIENT
	add_child(_ambient_player)
	_ambient_player.finished.connect(_on_ambient_finished)


func _on_ambient_finished() -> void:
	if _ambient_player != null and _ambient_stream != null:
		_ambient_player.play()


func _create_players(count: int, prefix: String, bus: StringName = &"Master") -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = []
	for i in count:
		var player := AudioStreamPlayer.new()
		player.name = "%s%d" % [prefix, i]
		player.bus = bus
		add_child(player)
		players.append(player)
	return players


func _play_from_pool(
	players: Array[AudioStreamPlayer],
	start_index: int,
	stream: AudioStream,
	volume_db: float,
	pitch_scale: float,
) -> void:
	if stream == null or players.is_empty():
		return
	var player := _acquire_player(players, start_index)
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.stream = stream
	player.play()


func _acquire_player(players: Array[AudioStreamPlayer], start_index: int) -> AudioStreamPlayer:
	for offset in players.size():
		var player := players[(start_index + offset) % players.size()]
		if not player.playing:
			return player
	return players[start_index % players.size()]


# ── Generated fallback samples ──────────────────────────────────────────────

func _generate_gunshot() -> AudioStreamWAV:
	return _build_stream(0.2, 22050, func(t: float, progress: float) -> float:
		var env := (1.0 - progress) * (1.0 - progress)
		var noise := randf_range(-1.0, 1.0)
		var tone := sin(t * 900.0 * TAU) * 0.35
		return (noise * 0.65 + tone) * env * 0.55
	)


func _generate_death() -> AudioStreamWAV:
	return _build_stream(0.5, 22050, func(t: float, progress: float) -> float:
		var env := (1.0 - progress) * (1.0 - progress)
		var freq := lerpf(180.0, 60.0, progress)
		return sin(t * freq * TAU) * env * 0.7
	)


func _generate_footstep() -> AudioStreamWAV:
	return _build_stream(0.08, 22050, func(t: float, progress: float) -> float:
		var env := (1.0 - progress) * (1.0 - progress) * (1.0 - progress)
		var noise := randf_range(-1.0, 1.0) * 0.4
		var thump := sin(t * 120.0 * TAU) * 0.6
		return (noise + thump) * env * 0.5
	)


func _generate_throw() -> AudioStreamWAV:
	return _build_stream(0.25, 22050, func(t: float, progress: float) -> float:
		var env := sin(progress * PI) * (1.0 - progress * 0.5)
		var freq := lerpf(200.0, 800.0, progress)
		var noise := randf_range(-1.0, 1.0) * 0.7
		var sweep := sin(t * freq * TAU) * 0.3
		return (noise + sweep) * env * 0.4
	)


func _generate_ambient_loop() -> AudioStreamWAV:
	var duration := 8.0
	var sample_rate := 22050
	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var prev := 0.0
	for i in sample_count:
		var progress := float(i) / float(sample_count)
		var noise := randf_range(-1.0, 1.0)
		## Low-pass filter for wind-like character.
		prev = prev * 0.96 + noise * 0.04
		## Slow volume swell so the loop breathes.
		var swell := 0.7 + 0.3 * sin(progress * TAU * 2.0)
		var sample := prev * swell * 0.25
		var s16 := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = sample_count
	stream.data = data
	return stream


func _build_stream(
	duration: float,
	sample_rate: int,
	sample_fn: Callable,
) -> AudioStreamWAV:
	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(sample_rate)
		var progress := float(i) / float(sample_count)
		var sample: float = sample_fn.call(t, progress)
		var s16 := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
