extends Node
## Autoload: single authoritative seeded RNG for gameplay rolls.
##
## Presentation (audio, tracer jitter) may keep engine randf — do not use this for cosmetics
## unless you intentionally want them in the replay stream.

const DEFAULT_SEED := 1

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seed: int = DEFAULT_SEED
var _call_count: int = 0


func _ready() -> void:
	reseed(DEFAULT_SEED)


func reseed(seed_value: int) -> void:
	_seed = seed_value
	_call_count = 0
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value


func get_seed() -> int:
	return _seed


func get_call_count() -> int:
	return _call_count


func randf() -> float:
	_call_count += 1
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	_call_count += 1
	return _rng.randf_range(from, to)


func randi() -> int:
	_call_count += 1
	return _rng.randi()


func randi_range(from: int, to: int) -> int:
	_call_count += 1
	return _rng.randi_range(from, to)
