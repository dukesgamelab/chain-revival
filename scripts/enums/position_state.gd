class_name PositionState
extends RefCounted
## Standing (UP) or prone/down (DOWN) posture for a soldier.

enum State { UP, DOWN }

const UP := State.UP
const DOWN := State.DOWN


static func display_name(state: int) -> String:
	if state == DOWN:
		return "DOWN"
	return "UP"
