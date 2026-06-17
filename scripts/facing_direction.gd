class_name FacingDirection
extends RefCounted
## Cardinal facing directions for tactical grid units.
##
## Gameplay stores facing as Vector2i steps (NORTH = (0, -1)).
## Use the Direction enum when you want readable names in code or UI.

enum Direction { NORTH, EAST, SOUTH, WEST }

const NORTH := Vector2i(0, -1)
const SOUTH := Vector2i(0, 1)
const EAST := Vector2i(1, 0)
const WEST := Vector2i(-1, 0)


## Convert stored facing to enum (defaults to NORTH if invalid).
static func to_direction(facing: Vector2i) -> Direction:
	if facing == EAST:
		return Direction.EAST
	if facing == SOUTH:
		return Direction.SOUTH
	if facing == WEST:
		return Direction.WEST
	return Direction.NORTH


static func from_direction(dir: Direction) -> Vector2i:
	match dir:
		Direction.EAST:
			return EAST
		Direction.SOUTH:
			return SOUTH
		Direction.WEST:
			return WEST
		_:
			return NORTH


static func direction_name(facing: Vector2i) -> String:
	match to_direction(facing):
		Direction.EAST:
			return "EAST"
		Direction.SOUTH:
			return "SOUTH"
		Direction.WEST:
			return "WEST"
		_:
			return "NORTH"


## Arrow / sprite rotation in degrees (placeholder art default points east).
static func to_degrees(facing: Vector2i) -> float:
	match normalize(facing):
		NORTH:
			return -90.0
		SOUTH:
			return 90.0
		WEST:
			return 180.0
		_:
			return 0.0


## Snap any facing vector to the nearest cardinal direction.
static func normalize(facing: Vector2i) -> Vector2i:
	return from_step(facing)


## Convert a movement step into a facing direction.
static func from_step(step: Vector2i) -> Vector2i:
	if step == Vector2i.ZERO:
		return NORTH
	if abs(step.x) >= abs(step.y):
		return EAST if step.x > 0 else WEST
	return SOUTH if step.y > 0 else NORTH


## Face from one grid cell toward another (uses dominant axis for diagonals).
static func toward_cell(from_cell: Vector2i, target_cell: Vector2i) -> Vector2i:
	return from_step(target_cell - from_cell)
