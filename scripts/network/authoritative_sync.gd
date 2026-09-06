class_name AuthoritativeSync
extends RefCounted
## Apply server GameState snapshots / move results onto the local replica.
## Does not run ActionResolver — the Node server already did.

const ActionResultClass := preload("res://scripts/core/action_result.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")
const PositionStateClass := preload("res://scripts/enums/position_state.gd")


static func apply_snapshot(game_state: GameStateClass, snapshot: Dictionary) -> void:
	if game_state == null:
		return
	var soldiers: Variant = snapshot.get("soldiers", [])
	if not soldiers is Array:
		return
	for raw in soldiers:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var team_id := int(entry.get("teamId", entry.get("team_id", -1)))
		var soldier_id := int(entry.get("soldierId", entry.get("soldier_id", -1)))
		var soldier: SoldierState = game_state.get_soldier(team_id, soldier_id)
		if soldier == null:
			continue
		soldier.grid_position = _cell(entry.get("gridPosition", entry.get("grid_position", {})))
		soldier.facing_direction = _cell(entry.get("facing", {}))
		if soldier.facing_direction == Vector2i.ZERO:
			soldier.facing_direction = FacingDirection.NORTH
		soldier.position_state = int(entry.get("positionState", entry.get("position_state", PositionStateClass.UP)))
		soldier.movement_mode = int(entry.get("movementMode", entry.get("movement_mode", MovementMode.RUN)))
		soldier.is_dead = bool(entry.get("isDead", entry.get("is_dead", false)))
		var path := _path(entry.get("currentPath", entry.get("current_path", [])))
		var speed := float(entry.get("moveSpeedMult", entry.get("move_speed_mult", 1.0)))
		if bool(entry.get("isMoving", entry.get("is_moving", false))) and path.size() > 1:
			soldier.assign_path(path, speed)
			soldier.path_index = int(entry.get("pathIndex", entry.get("path_index", 1)))
		else:
			soldier.clear_path()


static func action_result_from_payload(payload: Dictionary) -> ActionResultClass:
	if not bool(payload.get("success", false)):
		return ActionResultClass.fail(str(payload.get("statusMessage", payload.get("status_message", "Move rejected."))))
	var result := ActionResultClass.new()
	result.success = true
	result.status_message = str(payload.get("statusMessage", payload.get("status_message", "")))
	result.refresh_views = false
	for raw in payload.get("moveOrders", payload.get("move_orders", [])):
		if not raw is Dictionary:
			continue
		var order: Dictionary = raw
		result.move_orders.append({
			"team_id": int(order.get("teamId", order.get("team_id", -1))),
			"soldier_id": int(order.get("soldierId", order.get("soldier_id", -1))),
			"path": _path(order.get("path", [])),
			"speed_mult": float(order.get("speedMult", order.get("speed_mult", 1.0))),
		})
	for raw in payload.get("movementHalts", payload.get("movement_halts", [])):
		if not raw is Dictionary:
			continue
		var halt: Dictionary = raw
		result.movement_halts.append({
			"team_id": int(halt.get("teamId", halt.get("team_id", -1))),
			"soldier_id": int(halt.get("soldierId", halt.get("soldier_id", -1))),
			"snap_cell": _cell(halt.get("snapCell", halt.get("snap_cell", {}))),
		})
	return result


static func apply_move_result(game_state: GameStateClass, result: ActionResultClass) -> void:
	if game_state == null or result == null:
		return
	for halt in result.movement_halts:
		var soldier: SoldierState = game_state.get_soldier(int(halt.team_id), int(halt.soldier_id))
		if soldier == null:
			continue
		soldier.clear_path()
		var snap: Variant = halt.get("snap_cell", null)
		if snap is Vector2i:
			soldier.grid_position = snap
	if not result.success:
		return
	for order in result.move_orders:
		var soldier: SoldierState = game_state.get_soldier(int(order.team_id), int(order.soldier_id))
		if soldier == null:
			continue
		var path: Array = order.get("path", [])
		var typed: Array[Vector2i] = []
		for cell in path:
			if cell is Vector2i:
				typed.append(cell)
		soldier.assign_path(typed, float(order.get("speed_mult", 1.0)))


static func apply_movement_tick(game_state: GameStateClass, payload: Dictionary) -> ActionResultClass:
	var result := ActionResultClass.new()
	result.success = true
	result.refresh_views = false
	if game_state == null:
		return result
	for raw in payload.get("movementSteps", payload.get("movement_steps", [])):
		if not raw is Dictionary:
			continue
		var step: Dictionary = raw
		var team_id := int(step.get("teamId", step.get("team_id", -1)))
		var soldier_id := int(step.get("soldierId", step.get("soldier_id", -1)))
		var tile := _cell(step.get("tile", {}))
		var delta := _cell(step.get("stepDelta", step.get("step_delta", {})))
		var soldier: SoldierState = game_state.get_soldier(team_id, soldier_id)
		if soldier != null:
			soldier.grid_position = tile
			if delta != Vector2i.ZERO:
				soldier.facing_direction = FacingDirection.from_step(delta)
			if soldier.is_moving:
				soldier.path_index = mini(soldier.path_index + 1, maxi(soldier.current_path.size() - 1, 0))
		result.movement_steps.append({
			"team_id": team_id,
			"soldier_id": soldier_id,
			"tile": tile,
			"step_delta": delta,
		})
	for raw in payload.get("movementCompletions", payload.get("movement_completions", [])):
		if not raw is Dictionary:
			continue
		var done: Dictionary = raw
		var team_id := int(done.get("teamId", done.get("team_id", -1)))
		var soldier_id := int(done.get("soldierId", done.get("soldier_id", -1)))
		var soldier: SoldierState = game_state.get_soldier(team_id, soldier_id)
		if soldier != null:
			soldier.clear_path()
		result.movement_completions.append({
			"team_id": team_id,
			"soldier_id": soldier_id,
		})
	return result


static func _cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO


static func _path(value: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not value is Array:
		return out
	for entry in value:
		out.append(_cell(entry))
	return out
