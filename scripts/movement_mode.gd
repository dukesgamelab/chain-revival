class_name MovementMode
extends RefCounted
## How a soldier moves when given a move order.

const PositionStateClass := preload("res://scripts/position_state.gd")

enum Mode { RUN, WALK, CRAWL }

const RUN := Mode.RUN
const WALK := Mode.WALK
const CRAWL := Mode.CRAWL

const SPEED_RUN := 1.0
const SPEED_WALK := 0.6
const SPEED_CRAWL := 0.3


static func display_name(mode: int) -> String:
	match mode:
		Mode.WALK:
			return "WALK"
		Mode.CRAWL:
			return "CRAWL"
		_:
			return "RUN"


static func speed_multiplier(mode: int) -> float:
	match mode:
		Mode.WALK:
			return SPEED_WALK
		Mode.CRAWL:
			return SPEED_CRAWL
		_:
			return SPEED_RUN


## RUN auto-stands prone soldiers. DOWN soldiers may otherwise only crawl.
static func is_allowed(position_state: int, mode: int) -> bool:
	if mode == RUN:
		return true
	if position_state == PositionStateClass.DOWN:
		return mode == CRAWL
	return true
