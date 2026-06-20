extends Node
## Placeholder combat audio. Swap streams via set_*_stream() when WAV assets are ready.

var _gunshot_stream: AudioStream
var _death_stream: AudioStream

@onready var _gunshot_player: AudioStreamPlayer = $GunshotPlayer
@onready var _death_player: AudioStreamPlayer = $DeathPlayer


func _ready() -> void:
	_gunshot_stream = _generate_gunshot()
	_death_stream = _generate_death()


func set_gunshot_stream(stream: AudioStream) -> void:
	_gunshot_stream = stream


func set_death_stream(stream: AudioStream) -> void:
	_death_stream = stream


func play_gunshot() -> void:
	_play(_gunshot_player, _gunshot_stream)


func play_death() -> void:
	_play(_death_player, _death_stream)


func _play(player: AudioStreamPlayer, stream: AudioStream) -> void:
	if stream == null:
		return
	player.stream = stream
	player.play()


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
