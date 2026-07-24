class_name AiOrder
extends RefCounted
## Human commander orders issued to an AI player (Phase 4–6).
## Stable string IDs — never store display labels as authority.

enum Type {
	NONE,
	ATTACK,
	DEFEND,
	HOLD,
	RETREAT,
	MOVE_TO,
	FACE_DIRECTION,
	RESUME_PLAN,
}

const ID_NONE := "none"
const ID_ATTACK := "attack"
const ID_DEFEND := "defend"
const ID_HOLD := "hold"
const ID_RETREAT := "retreat"
const ID_MOVE_TO := "move_to"
const ID_FACE_DIRECTION := "face_direction"
const ID_RESUME_PLAN := "resume_plan"

const ALL_IDS: Array[String] = [
	ID_ATTACK,
	ID_DEFEND,
	ID_HOLD,
	ID_RETREAT,
	ID_MOVE_TO,
	ID_FACE_DIRECTION,
	ID_RESUME_PLAN,
]


static func normalize_id(order_id: String) -> String:
	return str(order_id).strip_edges().to_lower()


static func is_valid_id(order_id: String) -> bool:
	var n := normalize_id(order_id)
	return n == ID_NONE or n in ALL_IDS


static func display_name(order_id: String) -> String:
	match normalize_id(order_id):
		ID_ATTACK:
			return "Attack"
		ID_DEFEND:
			return "Defend"
		ID_HOLD:
			return "Hold"
		ID_RETREAT:
			return "Retreat"
		ID_MOVE_TO:
			return "Move To"
		ID_FACE_DIRECTION:
			return "Face Direction"
		ID_RESUME_PLAN:
			return "Resume Plan"
		ID_NONE, "":
			return "None"
		_:
			return "Unknown"


static func requires_target_cell(order_id: String) -> bool:
	var n := normalize_id(order_id)
	return n == ID_MOVE_TO or n == ID_FACE_DIRECTION or n == ID_DEFEND
