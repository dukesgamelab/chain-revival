extends Node
## Autoload GameRandom — sole source of gameplay randomness.
##
## Use for: hit rolls, grenade outcomes, suppression/spotting/morale (future).
## Do NOT use for: audio pitch, tracer jitter, camera shake, cosmetics.
##
## Determinism:
## - Same seed + same ordered call stream → identical outcomes (replay / lockstep MP).
## - Reseed at match start; host should sync seed to peers before first gameplay roll.
## - get_snapshot() / restore_snapshot() support mid-match debug and replay scrubbing.
##
## Probabilities are unchanged vs prior DeterministicRNG / engine randf() usage —
## only the generator source is centralized.

const DEFAULT_SEED := 1

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seed: int = DEFAULT_SEED
var _call_count: int = 0


func _ready() -> void:
	reseed(DEFAULT_SEED)


## Begin a match (or test) with an authoritative seed. Resets call stream.
func begin_match(seed_value: int = DEFAULT_SEED) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	_seed = seed_value
	_call_count = 0
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value as int


func get_seed() -> int:
	return _seed


func get_call_count() -> int:
	return _call_count


## True with probability in [0, 1]. Same semantics as `randf() <= probability`.
func chance(probability: float) -> bool:
	## Must call self.randf() — bare randf() is Godot's global non-deterministic RNG.
	return self.randf() <= probability


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


## Capture RNG state for replay / desync debug (seed + engine state + call count).
func get_snapshot() -> Dictionary:
	return {
		"seed": _seed,
		"state": _rng.state,
		"call_count": _call_count,
	}


## Restore a prior snapshot. Used by debug/replay tools — not by normal gameplay.
func restore_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var seed_value := int(snapshot.get("seed", DEFAULT_SEED))
	_seed = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	## Restore engine stream position after seeding (do not reseed again — that would wipe state).
	if snapshot.has("state"):
		_rng.state = snapshot.state as int
	_call_count = int(snapshot.get("call_count", 0))
