class_name MovementPolicy
extends RefCounted
## Configurable movement speed multipliers. Defaults match MovementMode.

const DEFAULT_SPEED_RUN := 2.0 ## TEST: 4x normal (0.5); revert before release
const DEFAULT_SPEED_WALK := 0.6
const DEFAULT_SPEED_CRAWL := 0.3

var speed_run: float = DEFAULT_SPEED_RUN
var speed_walk: float = DEFAULT_SPEED_WALK
var speed_crawl: float = DEFAULT_SPEED_CRAWL


func reset_to_defaults() -> void:
	speed_run = DEFAULT_SPEED_RUN
	speed_walk = DEFAULT_SPEED_WALK
	speed_crawl = DEFAULT_SPEED_CRAWL


func speed_multiplier(mode: int) -> float:
	## Mode ints match MovementMode.Mode: RUN=0, WALK=1, CRAWL=2.
	match mode:
		1:
			return speed_walk
		2:
			return speed_crawl
		_:
			return speed_run


func apply_config(section: Dictionary) -> void:
	if section.has("speed_run"):
		speed_run = float(section.speed_run)
	if section.has("speed_walk"):
		speed_walk = float(section.speed_walk)
	if section.has("speed_crawl"):
		speed_crawl = float(section.speed_crawl)
