class_name GrenadeState
extends RefCounted
## Thin view of an in-flight grenade. Authority stays on SoldierState.


var object_id: String = ""
var thrower_team_id: int = -1
var thrower_soldier_id: int = -1
var target_cell: Vector2i = Vector2i(-999, -999)
var explode_at_msec: int = 0


static func from_soldier(soldier: SoldierState) -> GrenadeState:
	if soldier == null or not soldier.has_pending_grenade():
		return null
	var state := GrenadeState.new()
	state.thrower_team_id = soldier.team_id
	state.thrower_soldier_id = soldier.soldier_id
	state.object_id = ObjectId.grenade(soldier.team_id, soldier.soldier_id)
	state.target_cell = soldier.pending_grenade_target
	state.explode_at_msec = soldier.grenade_explode_at_msec
	return state
