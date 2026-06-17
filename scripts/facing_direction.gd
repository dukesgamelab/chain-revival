class_name FacingDirection
extends RefCounted
## Grid-facing helpers. Facing is stored as a unit step on the logical grid (e.g. Vector2i(0, -1) = north).

const NORTH := Vector2i(0, -1)
const SOUTH := Vector2i(0, 1)
const EAST := Vector2i(1, 0)
const WEST := Vector2i(-1, 0)


## Convert a movement step into a facing direction (ignores zero-length deltas).
static func from_step(step: Vector2i) -> Vector2i:
	if step == Vector2i.ZERO:
		return NORTH
	if abs(step.x) >= abs(step.y):
		return EAST if step.x > 0 else WEST
	return SOUTH if step.y > 0 else NORTH


## Sprite rotation in degrees for the placeholder art (default sprite faces right).
static func to_degrees(facing: Vector2i) -> float:
	match facing:
		NORTH:
			return -90.0
		SOUTH:
			return 90.0
		WEST:
			return 180.0
		_:
			return 0.0
