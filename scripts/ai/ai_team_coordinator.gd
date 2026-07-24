class_name AiTeamCoordinator
extends RefCounted
## Soft multi-AI coordination: claimed objectives, flank spread, no perfect sync.

const AiCommanderClass := preload("res://scripts/ai/ai_commander.gd")

## player_id -> claimed objective cell
var _claims: Dictionary = {}


func clear() -> void:
	_claims.clear()


func claimed_cells_for(player_id: int) -> Array[Vector2i]:
	## All claims except this player's own.
	var out: Array[Vector2i] = []
	for pid in _claims.keys():
		if int(pid) == player_id:
			continue
		var cell: Vector2i = _claims[pid]
		if cell.x > -900:
			out.append(cell)
	return out


func set_claim(player_id: int, cell: Vector2i) -> void:
	if cell.x > -900:
		_claims[player_id] = cell
	elif _claims.has(player_id):
		_claims.erase(player_id)


## If two AIs claim nearly the same cell, nudge the lower-priority (higher player_id) to replan.
func resolve_duplicate_claims(commanders: Array) -> void:
	var cells: Array[Vector2i] = []
	var owners: Array[int] = []
	for commander in commanders:
		if commander == null:
			continue
		var claim: Vector2i = _claims.get(commander.player_id, Vector2i(-999, -999))
		if claim.x <= -900:
			continue
		for i in cells.size():
			var other: Vector2i = cells[i]
			var dist := absi(claim.x - other.x) + absi(claim.y - other.y)
			if dist <= 3:
				## Ask the later commander to replan away from the duplicate.
				commander.request_replan("duplicate_objective")
				break
		cells.append(claim)
		owners.append(commander.player_id)
