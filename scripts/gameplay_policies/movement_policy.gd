class_name MovementPolicy
extends RefCounted
## Configurable movement speed multipliers. Defaults match MovementMode.

const DEFAULT_SPEED_RUN := 2.0 ## TEST: 4x normal (0.5); revert before release
const DEFAULT_SPEED_WALK := 0.6
const DEFAULT_SPEED_CRAWL := 0.3
## World units per second at multiplier 1.0 — matches Soldier presentation move_speed.
const BASE_WORLD_SPEED := 95.0 / 3.0

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


## Deterministic msec to traverse one grid step at the given speed multiplier.
static func step_cost_msec(from_cell: Vector2i, to_cell: Vector2i, speed_mult: float) -> int:
	var from_world := IsometricGrid.grid_to_world(from_cell)
	var to_world := IsometricGrid.grid_to_world(to_cell)
	var dist := from_world.distance_to(to_world)
	var speed := BASE_WORLD_SPEED * maxf(speed_mult, 0.0001)
	var sec := dist / speed
	return maxi(1, int(round(sec * 1000.0)))


func apply_config(section: Dictionary) -> void:
	if section.has("speed_run"):
		speed_run = float(section.speed_run)
	if section.has("speed_walk"):
		speed_walk = float(section.speed_walk)
	if section.has("speed_crawl"):
		speed_crawl = float(section.speed_crawl)
