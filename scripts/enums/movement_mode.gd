class_name MovementMode
extends RefCounted
## How a soldier moves when given a move order.

const PositionStateClass := preload("res://scripts/enums/position_state.gd")
const MovementPolicyClass := preload("res://scripts/gameplay_policies/movement_policy.gd")

enum Mode { RUN, WALK, CRAWL }

const RUN := Mode.RUN
const WALK := Mode.WALK
const CRAWL := Mode.CRAWL

const SPEED_RUN := MovementPolicyClass.DEFAULT_SPEED_RUN ## TEST: 4x normal (0.5); revert before release
const SPEED_WALK := MovementPolicyClass.DEFAULT_SPEED_WALK
const SPEED_CRAWL := MovementPolicyClass.DEFAULT_SPEED_CRAWL


static func display_name(mode: int) -> String:
	match mode:
		Mode.WALK:
			return "WALK"
		Mode.CRAWL:
			return "CRAWL"
		_:
			return "RUN"


## UI status column label while moving.
static func status_name(mode: int) -> String:
	match mode:
		Mode.WALK:
			return "Walking"
		Mode.CRAWL:
			return "Crawling"
		_:
			return "Running"


static func speed_multiplier(mode: int) -> float:
	return GameplayPolicies.movement.speed_multiplier(mode)


## RUN auto-stands prone soldiers. DOWN soldiers may otherwise only crawl.
static func is_allowed(position_state: int, mode: int) -> bool:
	if mode == RUN:
		return true
	if position_state == PositionStateClass.DOWN:
		return mode == CRAWL
	return true
