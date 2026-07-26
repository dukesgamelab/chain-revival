class_name ScenarioWinner
extends RefCounted
## Separate from ScenarioEndCause (original ScEnd Winner vs ScEnd Cause).

const NONE := 0
const USA := 1
const GERMANY := 2
const DRAW := 3


static func display_name(winner: int) -> String:
	match winner:
		USA:
			return "This mission was an American victory"
		GERMANY:
			return "This mission was a German victory"
		DRAW:
			return "This mission ended in a draw"
		_:
			return "This mission has no declared winner"


static func from_team_id(team_id: int) -> int:
	if team_id == Team.USA:
		return USA
	if team_id == Team.GERMANY:
		return GERMANY
	return NONE
