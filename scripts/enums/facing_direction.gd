class_name FacingDirection
extends RefCounted
## Eight-direction facing for tactical grid units.
##
## Gameplay stores facing as normalized Vector2i steps (NORTH = (0, -1),
## NORTHEAST = (1, -1), …). Matches OG sprite family digits:
## 1=W, 2=SW, 3=S, 4=SE, 5=E, 6=NE, 7=N, 8=NW.

enum Direction {
	NORTH,
	NORTHEAST,
	EAST,
	SOUTHEAST,
	SOUTH,
	SOUTHWEST,
	WEST,
	NORTHWEST,
}

const NORTH := Vector2i(0, -1)
const NORTHEAST := Vector2i(1, -1)
const EAST := Vector2i(1, 0)
const SOUTHEAST := Vector2i(1, 1)
const SOUTH := Vector2i(0, 1)
const SOUTHWEST := Vector2i(-1, 1)
const WEST := Vector2i(-1, 0)
const NORTHWEST := Vector2i(-1, -1)

const ALL: Array[Vector2i] = [
	NORTH,
	NORTHEAST,
	EAST,
	SOUTHEAST,
	SOUTH,
	SOUTHWEST,
	WEST,
	NORTHWEST,
]


## Convert stored facing to enum (defaults to NORTH if invalid / zero).
static func to_direction(facing: Vector2i) -> Direction:
	match normalize(facing):
		NORTHEAST:
			return Direction.NORTHEAST
		EAST:
			return Direction.EAST
		SOUTHEAST:
			return Direction.SOUTHEAST
		SOUTH:
			return Direction.SOUTH
		SOUTHWEST:
			return Direction.SOUTHWEST
		WEST:
			return Direction.WEST
		NORTHWEST:
			return Direction.NORTHWEST
		_:
			return Direction.NORTH


static func from_direction(dir: Direction) -> Vector2i:
	match dir:
		Direction.NORTHEAST:
			return NORTHEAST
		Direction.EAST:
			return EAST
		Direction.SOUTHEAST:
			return SOUTHEAST
		Direction.SOUTH:
			return SOUTH
		Direction.SOUTHWEST:
			return SOUTHWEST
		Direction.WEST:
			return WEST
		Direction.NORTHWEST:
			return NORTHWEST
		_:
			return NORTH


static func direction_name(facing: Vector2i) -> String:
	match to_direction(facing):
		Direction.NORTHEAST:
			return "NORTHEAST"
		Direction.EAST:
			return "EAST"
		Direction.SOUTHEAST:
			return "SOUTHEAST"
		Direction.SOUTH:
			return "SOUTH"
		Direction.SOUTHWEST:
			return "SOUTHWEST"
		Direction.WEST:
			return "WEST"
		Direction.NORTHWEST:
			return "NORTHWEST"
		_:
			return "NORTH"


## Semantic animation suffix for world facing (before camera remapping).
static func to_anim_suffix(facing: Vector2i) -> String:
	match normalize(facing):
		NORTHEAST:
			return "ne"
		EAST:
			return "e"
		SOUTHEAST:
			return "se"
		SOUTH:
			return "s"
		SOUTHWEST:
			return "sw"
		WEST:
			return "w"
		NORTHWEST:
			return "nw"
		_:
			return "n"


## Arrow / sprite rotation in degrees in logical grid space (placeholder art).
## Prefer IsometricGrid.grid_facing_to_degrees for on-map presentation.
static func to_degrees(facing: Vector2i) -> float:
	var n := normalize(facing)
	return rad_to_deg(atan2(float(n.y), float(n.x)))


## Sign-normalize to one of the eight gameplay directions.
## Each component becomes -1, 0, or 1 independently. Zero → NORTH.
static func normalize(facing: Vector2i) -> Vector2i:
	return from_step(facing)


## Convert a movement / aim step into an 8-way facing (preserves diagonals).
static func from_step(step: Vector2i) -> Vector2i:
	if step == Vector2i.ZERO:
		return NORTH
	return Vector2i(clampi(step.x, -1, 1), clampi(step.y, -1, 1))


## Face from one grid cell toward another using all eight sectors.
static func toward_cell(from_cell: Vector2i, target_cell: Vector2i) -> Vector2i:
	return from_step(target_cell - from_cell)


## Face toward a clicked world point — uses target_cell when different, else mouse bearing.
static func toward_world_point(
	from_cell: Vector2i,
	target_cell: Vector2i,
	world_point: Vector2 = Vector2(-99999, -99999),
) -> Vector2i:
	if target_cell != from_cell:
		return toward_cell(from_cell, target_cell)
	if world_point.x < -90000:
		return Vector2i.ZERO
	var from_world := IsometricGrid.grid_to_world(from_cell)
	var dx := world_point.x - from_world.x
	var dy := world_point.y - from_world.y
	const MIN_AXIS := 2.0
	if abs(dx) < MIN_AXIS and abs(dy) < MIN_AXIS:
		return Vector2i.ZERO
	var step := Vector2i.ZERO
	if abs(dx) >= MIN_AXIS:
		step.x = 1 if dx > 0.0 else -1
	if abs(dy) >= MIN_AXIS:
		step.y = 1 if dy > 0.0 else -1
	return from_step(step)


## True if facing is already one of the eight normalized directions (or zero→false).
static func is_valid(facing: Vector2i) -> bool:
	if facing == Vector2i.ZERO:
		return false
	return facing == from_step(facing)
