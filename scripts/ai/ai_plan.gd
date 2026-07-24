class_name AiPlan
extends RefCounted
## Pre-game AI plan ids (Phase 3). Selection + resolution only — no behavior yet.
##
## Serialized values use stable string IDs (never display labels).

enum Type {
	ATTACK_LEFT,
	ATTACK_CENTER,
	ATTACK_RIGHT,
	DEFEND,
	FLANK,
	RANDOM,
}

const ID_ATTACK_LEFT := "attack_left"
const ID_ATTACK_CENTER := "attack_center"
const ID_ATTACK_RIGHT := "attack_right"
const ID_DEFEND := "defend"
const ID_FLANK := "flank"
const ID_RANDOM := "random"

## Concrete plans Random may resolve to (never Random itself).
const CONCRETE_IDS: Array[String] = [
	ID_ATTACK_LEFT,
	ID_ATTACK_CENTER,
	ID_ATTACK_RIGHT,
	ID_DEFEND,
	ID_FLANK,
]

const ALL_IDS: Array[String] = [
	ID_ATTACK_LEFT,
	ID_ATTACK_CENTER,
	ID_ATTACK_RIGHT,
	ID_DEFEND,
	ID_FLANK,
	ID_RANDOM,
]


static func id_for_type(plan_type: int) -> String:
	match plan_type:
		Type.ATTACK_LEFT:
			return ID_ATTACK_LEFT
		Type.ATTACK_CENTER:
			return ID_ATTACK_CENTER
		Type.ATTACK_RIGHT:
			return ID_ATTACK_RIGHT
		Type.DEFEND:
			return ID_DEFEND
		Type.FLANK:
			return ID_FLANK
		Type.RANDOM:
			return ID_RANDOM
		_:
			return ""


static func type_for_id(plan_id: String) -> int:
	match normalize_id(plan_id):
		ID_ATTACK_LEFT:
			return Type.ATTACK_LEFT
		ID_ATTACK_CENTER:
			return Type.ATTACK_CENTER
		ID_ATTACK_RIGHT:
			return Type.ATTACK_RIGHT
		ID_DEFEND:
			return Type.DEFEND
		ID_FLANK:
			return Type.FLANK
		ID_RANDOM:
			return Type.RANDOM
		_:
			return -1


static func normalize_id(plan_id: String) -> String:
	return str(plan_id).strip_edges().to_lower()


static func is_valid_id(plan_id: String) -> bool:
	return normalize_id(plan_id) in ALL_IDS


static func is_concrete_id(plan_id: String) -> bool:
	return normalize_id(plan_id) in CONCRETE_IDS


static func is_random_id(plan_id: String) -> bool:
	return normalize_id(plan_id) == ID_RANDOM


static func display_name(plan_id: String) -> String:
	match normalize_id(plan_id):
		ID_ATTACK_LEFT:
			return "Attack Left"
		ID_ATTACK_CENTER:
			return "Attack Center"
		ID_ATTACK_RIGHT:
			return "Attack Right"
		ID_DEFEND:
			return "Defend"
		ID_FLANK:
			return "Flank"
		ID_RANDOM:
			return "Random"
		_:
			return "Unknown"


## Default selected plan for a MatchConfig AI slot (pre-game).
## Friendly AI → Attack Center; enemy AI → Random.
static func default_selected_for_slot(
	controller: int,
	slot_team_id: int,
	local_human_team_id: int,
) -> String:
	## MatchConfig.ControllerType.AI == 1 — avoid importing MatchConfig here.
	const CONTROLLER_AI := 1
	if controller != CONTROLLER_AI:
		return ""
	if slot_team_id == local_human_team_id:
		return ID_ATTACK_CENTER
	return ID_RANDOM


## Resolve Random to one concrete plan using GameRandom (deterministic per match seed).
## Concrete ids pass through unchanged. Invalid/empty → ATTACK_CENTER fallback.
static func resolve_to_concrete(plan_id: String) -> String:
	var normalized := normalize_id(plan_id)
	if is_concrete_id(normalized):
		return normalized
	if not is_random_id(normalized) and not normalized.is_empty():
		## Unknown selection — fail safe to a concrete default.
		return ID_ATTACK_CENTER
	var index := GameRandom.randi_range(0, CONCRETE_IDS.size() - 1)
	return CONCRETE_IDS[index]


static func format_runtime_label(selected_id: String, active_id: String) -> String:
	var active_name := display_name(active_id)
	if is_random_id(selected_id) and is_concrete_id(active_id):
		return "Random → %s" % active_name
	return active_name
