extends Node
## OG Chain of Command combat audio with generated fallbacks when WAVs are missing.

const WEAPON_VOLUME_DB := 0.0
const GRENADE_VOLUME_DB := 0.0
const DEATH_VOLUME_DB := 0.0

const WEAPON_PLAYER_COUNT := 8
const DEATH_PLAYER_COUNT := 4
const GRENADE_PLAYER_COUNT := 2

const WeaponRegistryClass := preload("res://scripts/combat/weapon_registry.gd")

const AUDIO_ROOT := "res://assets/audio/original/"

# Provisional rifle/SMG/BAR assignments — may be swapped after in-game listening.
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

var _weapon_streams: Dictionary = {}
var _death_streams: Array[AudioStream] = []
var _grenade_stream: AudioStream
var _fallback_weapon_stream: AudioStream
var _fallback_death_stream: AudioStream

var _weapon_players: Array[AudioStreamPlayer] = []
var _death_players: Array[AudioStreamPlayer] = []
var _grenade_players: Array[AudioStreamPlayer] = []

var _weapon_pool_index := 0
var _death_pool_index := 0
var _grenade_pool_index := 0

var _warned_missing: Dictionary = {}


func _ready() -> void:
	_fallback_weapon_stream = _generate_gunshot()
	_fallback_death_stream = _generate_death()
	_load_weapon_streams()
	_load_death_streams()
	_grenade_stream = _load_stream(GRENADE_STREAM_PATH, "grenade explosion")
	_build_player_pools()


func play_weapon_fire(weapon_id: String) -> void:
	var stream := _weapon_streams.get(weapon_id, _fallback_weapon_stream) as AudioStream
	if stream == null:
		if not weapon_id.is_empty() and not _warned_missing.has("weapon:%s" % weapon_id):
			_warned_missing["weapon:%s" % weapon_id] = true
			push_warning("AudioManager: unknown weapon_id '%s', using generated gunshot." % weapon_id)
		stream = _fallback_weapon_stream
	_play_from_pool(
		_weapon_players,
		_weapon_pool_index,
		stream,
		WEAPON_VOLUME_DB,
		randf_range(0.97, 1.03),
	)
	_weapon_pool_index = (_weapon_pool_index + 1) % _weapon_players.size()


func play_grenade_explosion() -> void:
	var stream := _grenade_stream if _grenade_stream != null else _fallback_weapon_stream
	_play_from_pool(
		_grenade_players,
		_grenade_pool_index,
		stream,
		GRENADE_VOLUME_DB,
		1.0,
	)
	_grenade_pool_index = (_grenade_pool_index + 1) % _grenade_players.size()


func play_death(_team_id: int = -1) -> void:
	var stream := _pick_death_stream()
	_play_from_pool(
		_death_players,
		_death_pool_index,
		stream,
		DEATH_VOLUME_DB,
		randf_range(0.96, 1.04),
	)
	_death_pool_index = (_death_pool_index + 1) % _death_players.size()


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


func _pick_death_stream() -> AudioStream:
	if _death_streams.is_empty():
		return _fallback_death_stream
	return _death_streams[randi() % _death_streams.size()]


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


func _build_player_pools() -> void:
	_weapon_players = _create_players(WEAPON_PLAYER_COUNT, "WeaponPlayer")
	_death_players = _create_players(DEATH_PLAYER_COUNT, "DeathPlayer")
	_grenade_players = _create_players(GRENADE_PLAYER_COUNT, "GrenadePlayer")


func _create_players(count: int, prefix: String) -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = []
	for i in count:
		var player := AudioStreamPlayer.new()
		player.name = "%s%d" % [prefix, i]
		player.bus = &"Master"
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


## Short sharp burst (~0.2s) — noise + decaying tone.
func _generate_gunshot() -> AudioStreamWAV:
	return _build_stream(0.2, 22050, func(t: float, progress: float) -> float:
		var env := (1.0 - progress) * (1.0 - progress)
		var noise := randf_range(-1.0, 1.0)
		var tone := sin(t * 900.0 * TAU) * 0.35
		return (noise * 0.65 + tone) * env * 0.55
	)


## Low thump (~0.5s) — descending tone.
func _generate_death() -> AudioStreamWAV:
	return _build_stream(0.5, 22050, func(t: float, progress: float) -> float:
		var env := (1.0 - progress) * (1.0 - progress)
		var freq := lerpf(180.0, 60.0, progress)
		return sin(t * freq * TAU) * env * 0.7
	)


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
