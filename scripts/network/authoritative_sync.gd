class_name AuthoritativeSync
extends RefCounted
## Apply server GameState snapshots / move results onto the local replica.
## Does not run ActionResolver — the Node server already did.

const ActionResultClass := preload("res://scripts/core/action_result.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")
const PositionStateClass := preload("res://scripts/enums/position_state.gd")
const FireControlStateClass := preload("res://scripts/enums/fire_control_state.gd")


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
		if entry.has("fireControlState") or entry.has("fire_control_state"):
			soldier.fire_control_state = int(
				entry.get("fireControlState", entry.get("fire_control_state", FireControlStateClass.FIRE_AT_WILL))
			)
		if entry.has("engagedTargetTeamId") or entry.has("engaged_target_team_id"):
			soldier.engaged_target_team_id = int(
				entry.get("engagedTargetTeamId", entry.get("engaged_target_team_id", -1))
			)
			soldier.engaged_target_soldier_id = int(
				entry.get("engagedTargetSoldierId", entry.get("engaged_target_soldier_id", -1))
			)
		if entry.has("sustainedFire") or entry.has("sustained_fire"):
			soldier.sustained_fire = bool(entry.get("sustainedFire", entry.get("sustained_fire", false)))


static func action_result_from_payload(payload: Dictionary) -> ActionResultClass:
	if not bool(payload.get("success", false)):
		return ActionResultClass.fail(str(payload.get("statusMessage", payload.get("status_message", "Command rejected."))))
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
			"movement_mode": int(order.get("movementMode", order.get("movement_mode", MovementMode.RUN))),
			"position_state": int(order.get("positionState", order.get("position_state", PositionStateClass.UP))),
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
	_append_stance_orders(result, payload)
	_apply_soldier_updates_to_result(result, payload)
	_append_target_updates(result, payload)
	result.sync_fire_at_ui = bool(payload.get("syncFireAtUi", payload.get("sync_fire_at_ui", false)))
	for raw in payload.get("faceUpdates", payload.get("face_updates", [])):
		if not raw is Dictionary:
			continue
		var face: Dictionary = raw
		result.face_updates.append({
			"team_id": int(face.get("teamId", face.get("team_id", -1))),
			"soldier_id": int(face.get("soldierId", face.get("soldier_id", -1))),
			"facing": _cell(face.get("facing", {})),
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
		if order.has("movement_mode"):
			soldier.movement_mode = int(order.movement_mode)
		if order.has("position_state"):
			soldier.position_state = int(order.position_state)
			soldier.clear_pending_position()
		soldier.assign_path(typed, float(order.get("speed_mult", 1.0)))
	_apply_soldier_update_dicts(game_state, result.soldier_updates)


static func apply_face_result(game_state: GameStateClass, result: ActionResultClass) -> void:
	if game_state == null or result == null or not result.success:
		return
	for update in result.face_updates:
		var soldier: SoldierState = game_state.get_soldier(int(update.team_id), int(update.soldier_id))
		if soldier == null:
			continue
		var facing: Vector2i = update.get("facing", Vector2i.ZERO)
		if facing == Vector2i.ZERO:
			continue
		soldier.facing_direction = FacingDirection.from_step(facing)


static func apply_position_result(game_state: GameStateClass, result: ActionResultClass) -> void:
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
	_apply_soldier_update_dicts(game_state, result.soldier_updates)
	for order in result.stance_transition_orders:
		var soldier: SoldierState = game_state.get_soldier(int(order.team_id), int(order.soldier_id))
		if soldier == null:
			continue
		var target := int(order.target_position_state)
		soldier.position_state = target
		soldier.pending_position_state = target


static func apply_target_result(game_state: GameStateClass, result: ActionResultClass) -> void:
	if game_state == null or result == null:
		return
	for halt in result.movement_halts:
		var halted: SoldierState = game_state.get_soldier(int(halt.team_id), int(halt.soldier_id))
		if halted == null:
			continue
		halted.clear_path()
		var snap: Variant = halt.get("snap_cell", null)
		if snap is Vector2i:
			halted.grid_position = snap
	if not result.success:
		return
	apply_face_result(game_state, result)
	for update in result.target_updates:
		if not update is Dictionary:
			continue
		var soldier: SoldierState = game_state.get_soldier(int(update.team_id), int(update.soldier_id))
		if soldier == null:
			continue
		soldier.fire_control_state = int(
			update.get("fire_control_state", soldier.fire_control_state)
		)
		soldier.engaged_target_team_id = int(update.get("engaged_target_team_id", -1))
		soldier.engaged_target_soldier_id = int(update.get("engaged_target_soldier_id", -1))
		soldier.sustained_fire = bool(update.get("sustained_fire", false))
		if not soldier.sustained_fire and not soldier.is_engaged():
			soldier.reset_fire_prep()


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


static func _append_stance_orders(result: ActionResultClass, payload: Dictionary) -> void:
	for raw in payload.get("stanceTransitionOrders", payload.get("stance_transition_orders", [])):
		if not raw is Dictionary:
			continue
		var order: Dictionary = raw
		result.stance_transition_orders.append({
			"team_id": int(order.get("teamId", order.get("team_id", -1))),
			"soldier_id": int(order.get("soldierId", order.get("soldier_id", -1))),
			"target_position_state": int(
				order.get("targetPositionState", order.get("target_position_state", PositionStateClass.UP))
			),
		})


static func _append_target_updates(result: ActionResultClass, payload: Dictionary) -> void:
	for raw in payload.get("targetUpdates", payload.get("target_updates", [])):
		if not raw is Dictionary:
			continue
		var update: Dictionary = raw
		result.target_updates.append({
			"team_id": int(update.get("teamId", update.get("team_id", -1))),
			"soldier_id": int(update.get("soldierId", update.get("soldier_id", -1))),
			"fire_control_state": int(
				update.get("fireControlState", update.get("fire_control_state", FireControlStateClass.FIRE_AT_WILL))
			),
			"engaged_target_team_id": int(
				update.get("engagedTargetTeamId", update.get("engaged_target_team_id", -1))
			),
			"engaged_target_soldier_id": int(
				update.get("engagedTargetSoldierId", update.get("engaged_target_soldier_id", -1))
			),
			"sustained_fire": bool(update.get("sustainedFire", update.get("sustained_fire", false))),
		})


static func _apply_soldier_updates_to_result(result: ActionResultClass, payload: Dictionary) -> void:
	for raw in payload.get("soldierUpdates", payload.get("soldier_updates", [])):
		if not raw is Dictionary:
			continue
		var update: Dictionary = raw
		result.soldier_updates.append({
			"team_id": int(update.get("teamId", update.get("team_id", -1))),
			"soldier_id": int(update.get("soldierId", update.get("soldier_id", -1))),
			"facing": _cell(update.get("facing", {})),
			"position_state": int(update.get("positionState", update.get("position_state", PositionStateClass.UP))),
			"movement_mode": int(update.get("movementMode", update.get("movement_mode", MovementMode.RUN))),
		})


static func _apply_soldier_update_dicts(game_state: GameStateClass, updates: Array) -> void:
	for update in updates:
		if not update is Dictionary:
			continue
		var soldier: SoldierState = game_state.get_soldier(int(update.team_id), int(update.soldier_id))
		if soldier == null:
			continue
		if update.has("facing"):
			var facing: Vector2i = update.facing
			if facing != Vector2i.ZERO:
				soldier.facing_direction = FacingDirection.from_step(facing)
		if update.has("position_state"):
			soldier.position_state = int(update.position_state)
		if update.has("movement_mode"):
			soldier.movement_mode = int(update.movement_mode)


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
