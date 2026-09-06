class_name MovementMode
extends RefCounted
## How a soldier moves when given a move order.

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


## Locomotion is always legal. RUN/WALK stand a prone soldier; CRAWL stays down.
static func is_allowed(_position_state: int, _mode: int) -> bool:
	return true
