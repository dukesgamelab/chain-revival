class_name AiCommanderState
extends RefCounted
## Lightweight AI Commander state machine states (extensible string ids).

const PLAN := "plan"
const MOVE := "move"
const CONTACT := "contact"
const FIGHT := "fight"
const ADVANCE := "advance"
const OBJECTIVE_COMPLETE := "objective_complete"

const ALL: Array[String] = [
	PLAN,
	MOVE,
	CONTACT,
	FIGHT,
	ADVANCE,
	OBJECTIVE_COMPLETE,
]


static func display_name(state_id: String) -> String:
	match str(state_id):
		PLAN:
			return "PLAN"
		MOVE:
			return "MOVE"
		CONTACT:
			return "CONTACT"
		FIGHT:
			return "FIGHT"
		ADVANCE:
			return "ADVANCE"
		OBJECTIVE_COMPLETE:
			return "OBJECTIVE COMPLETE"
		_:
			return str(state_id).to_upper()
