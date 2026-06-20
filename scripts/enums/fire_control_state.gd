class_name FireControlState
extends RefCounted
## Automatic vs manual-only fire discipline for a soldier.

enum State { HOLD_FIRE, FIRE_AT_WILL }

const HOLD_FIRE := State.HOLD_FIRE
const FIRE_AT_WILL := State.FIRE_AT_WILL


static func display_name(state: int) -> String:
	if state == HOLD_FIRE:
		return "HOLD_FIRE"
	return "FIRE_AT_WILL"
