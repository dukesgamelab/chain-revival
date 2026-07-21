extends Node
## Deprecated compatibility alias for GameRandom.
## Prefer GameRandom in new code. Kept so older scripts/tests keep working
## if any still reference DeterministicRNG during transition.

func begin_match(seed_value: int = GameRandom.DEFAULT_SEED) -> void:
	GameRandom.begin_match(seed_value)


func reseed(seed_value: int) -> void:
	GameRandom.reseed(seed_value)


func get_seed() -> int:
	return GameRandom.get_seed()


func get_call_count() -> int:
	return GameRandom.get_call_count()


func chance(probability: float) -> bool:
	return GameRandom.chance(probability)


func randf() -> float:
	return GameRandom.randf()


func randf_range(from: float, to: float) -> float:
	return GameRandom.randf_range(from, to)


func randi() -> int:
	return GameRandom.randi()


func randi_range(from: int, to: int) -> int:
	return GameRandom.randi_range(from, to)


func get_snapshot() -> Dictionary:
	return GameRandom.get_snapshot()


func restore_snapshot(snapshot: Dictionary) -> void:
	GameRandom.restore_snapshot(snapshot)


## Expose DEFAULT_SEED for callers using DeterministicRNG.DEFAULT_SEED.
const DEFAULT_SEED := 1
