class_name MovementPolicy
extends RefCounted
## Configurable movement speed + open-ground hit multipliers (Stage 7).

const MovementModeClass := preload("res://scripts/enums/movement_mode.gd")

const DEFAULT_SPEED_RUN := 2.0 ## TEST: 4x normal (0.5); revert before release
const DEFAULT_SPEED_WALK := 0.6
const DEFAULT_SPEED_CRAWL := 0.3
## World units per second at multiplier 1.0 — matches Soldier presentation move_speed.
const BASE_WORLD_SPEED := 95.0 / 3.0

## RECOVERED MoveType pairs; state→value binding is ## TUNED (ambiguous by one slot in OIN).
## RUN: full type, strong crossing dodge. WALK: full type. CRAWL: hard to hit (low profile).
const DEFAULT_TYPE_MULT_RUN := 1.0
const DEFAULT_TYPE_MULT_WALK := 1.0
const DEFAULT_TYPE_MULT_CRAWL := 0.4
const DEFAULT_MOVE_MULT_RUN := 0.8
const DEFAULT_MOVE_MULT_WALK := 0.9
const DEFAULT_MOVE_MULT_CRAWL := 1.0
## RECOVERED degree→radian factor used with abs(sin(Δheading)).
const DEG_TO_RAD_OG := 0.0174533

var speed_run: float = DEFAULT_SPEED_RUN
var speed_walk: float = DEFAULT_SPEED_WALK
var speed_crawl: float = DEFAULT_SPEED_CRAWL
var type_mult_run: float = DEFAULT_TYPE_MULT_RUN
var type_mult_walk: float = DEFAULT_TYPE_MULT_WALK
var type_mult_crawl: float = DEFAULT_TYPE_MULT_CRAWL
var move_mult_run: float = DEFAULT_MOVE_MULT_RUN
var move_mult_walk: float = DEFAULT_MOVE_MULT_WALK
var move_mult_crawl: float = DEFAULT_MOVE_MULT_CRAWL


func reset_to_defaults() -> void:
	speed_run = DEFAULT_SPEED_RUN
	speed_walk = DEFAULT_SPEED_WALK
	speed_crawl = DEFAULT_SPEED_CRAWL
	type_mult_run = DEFAULT_TYPE_MULT_RUN
	type_mult_walk = DEFAULT_TYPE_MULT_WALK
	type_mult_crawl = DEFAULT_TYPE_MULT_CRAWL
	move_mult_run = DEFAULT_MOVE_MULT_RUN
	move_mult_walk = DEFAULT_MOVE_MULT_WALK
	move_mult_crawl = DEFAULT_MOVE_MULT_CRAWL


func speed_multiplier(mode: int) -> float:
	## Mode ints match MovementMode.Mode: RUN=0, WALK=1, CRAWL=2.
	match mode:
		MovementModeClass.WALK:
			return speed_walk
		MovementModeClass.CRAWL:
			return speed_crawl
		_:
			return speed_run


## Open-ground TypeMultipler for a movement mode (## TUNED binding).
func type_multiplier(mode: int) -> float:
	match mode:
		MovementModeClass.WALK:
			return type_mult_walk
		MovementModeClass.CRAWL:
			return type_mult_crawl
		_:
			return type_mult_run


## Open-ground MoveMultipler for the sine crossing term (## TUNED binding).
func move_multiplier(mode: int) -> float:
	match mode:
		MovementModeClass.WALK:
			return move_mult_walk
		MovementModeClass.CRAWL:
			return move_mult_crawl
		_:
			return move_mult_run


## 1 − MoveMultipler × abs(sin(Δheading)). Δheading in OG degree units.
func angle_hit_multiplier(shooter_facing: Vector2i, target_heading: Vector2i, mode: int) -> float:
	var move_m := move_multiplier(mode)
	var delta_deg := FacingDirection.to_degrees(shooter_facing) - FacingDirection.to_degrees(target_heading)
	var delta_rad := delta_deg * DEG_TO_RAD_OG
	return clampf(1.0 - move_m * absf(sin(delta_rad)), 0.0, 1.0)


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
	if section.has("type_mult_run"):
		type_mult_run = float(section.type_mult_run)
	if section.has("type_mult_walk"):
		type_mult_walk = float(section.type_mult_walk)
	if section.has("type_mult_crawl"):
		type_mult_crawl = float(section.type_mult_crawl)
	if section.has("move_mult_run"):
		move_mult_run = float(section.move_mult_run)
	if section.has("move_mult_walk"):
		move_mult_walk = float(section.move_mult_walk)
	if section.has("move_mult_crawl"):
		move_mult_crawl = float(section.move_mult_crawl)
