class_name ScenarioEndCause
extends RefCounted
## Distinct from ScenarioWinner — original keeps ScEnd Cause and ScEnd Winner separate.

const NONE := 0
const TIME_GONE := 1
const WE_RETREATED := 2
const ENEMY_RETREATED := 3
const EXTERMINATION := 4
const VP_RESOLUTION := 5


static func display_name(cause: int) -> String:
	match cause:
		TIME_GONE:
			return "The mission ended because the mission time is up."
		WE_RETREATED:
			return "The mission ended because your side retreated."
		ENEMY_RETREATED:
			return "The mission ended because the enemy retreated."
		EXTERMINATION:
			return "The mission ended because one side was wiped out."
		VP_RESOLUTION:
			return "The mission ended by victory-point resolution."
		_:
			return "The mission has ended."


static func short_name(cause: int) -> String:
	match cause:
		TIME_GONE:
			return "TIME_GONE"
		WE_RETREATED:
			return "WE_RETREATED"
		ENEMY_RETREATED:
			return "ENEMY_RETREATED"
		EXTERMINATION:
			return "EXTERMINATION"
		VP_RESOLUTION:
			return "VP_RESOLUTION"
		_:
			return "NONE"
