class_name AiCommander
extends RefCounted
## Per-player AI brain. Issues gameplay commands only via CommandRouter.
## Never mutates GameState soldier/map fields directly.

const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const AiOrderClass := preload("res://scripts/ai/ai_order.gd")
const AiCommanderStateClass := preload("res://scripts/ai/ai_commander_state.gd")
const AiObjectiveClass := preload("res://scripts/ai/ai_objective.gd")
const AiSectorObjectivesClass := preload("res://scripts/ai/ai_sector_objectives.gd")
const MoveCommandClass := preload("res://scripts/commands/move_command.gd")
const FaceCommandClass := preload("res://scripts/commands/face_command.gd")
const FireCommandClass := preload("res://scripts/commands/fire_command.gd")
const GrenadeCommandClass := preload("res://scripts/commands/grenade_command.gd")
const CommandContextClass := preload("res://scripts/core/command_context.gd")
const MovementModeClass := preload("res://scripts/enums/movement_mode.gd")

## TUNED — replan cadence (msec). Not recovered.
const DEFAULT_REPLAN_INTERVAL_MSEC := 1500
## TUNED — max Move/Face/Fire/Grenade submits per think tick.
const MAX_COMMANDS_PER_TICK := 2
## TUNED — consider objective reached within this Manhattan distance.
const OBJECTIVE_ARRIVE_DIST := 2
## TUNED — grenade only if clustered enemies within this Chebyshev range of impact.
const GRENADE_CLUSTER_CHEBYSHEV := 2
## TUNED — while fighting, only press forward if this far from the objective.
const FIGHT_ADVANCE_MIN_DIST := 6

## Extension hooks (unused now — future suppression/morale/difficulty/personality).
var aggression: float = 1.0
var difficulty: float = 1.0
var personality: String = "default"
var retreat_threshold: float = 0.0
var radio_delay_msec: int = 0

var player_id: int = -1
var state_id: String = AiCommanderStateClass.PLAN
var current_objective: AiObjectiveClass = null
var human_order_id: String = AiOrderClass.ID_NONE
var human_order_cell: Vector2i = Vector2i(-999, -999)
var current_target_key: String = ""
var last_replan_msec: int = -999999
var needs_replan: bool = true
var _commands_this_tick: int = 0
var _debug_last_action: String = ""


func _init(p_player_id: int = -1) -> void:
	player_id = p_player_id


func get_active_plan(game_state) -> String:
	return game_state.get_active_ai_plan(player_id)


func request_replan(reason: String = "") -> void:
	needs_replan = true
	if not reason.is_empty():
		_debug_last_action = "replan:%s" % reason


func apply_human_order(order_id: String, target_cell: Vector2i = Vector2i(-999, -999)) -> void:
	var normalized := AiOrderClass.normalize_id(order_id)
	if normalized == AiOrderClass.ID_RESUME_PLAN or normalized == AiOrderClass.ID_NONE:
		human_order_id = AiOrderClass.ID_NONE
		human_order_cell = Vector2i(-999, -999)
		request_replan("resume_plan")
		state_id = AiCommanderStateClass.PLAN
		return
	human_order_id = normalized
	human_order_cell = target_cell
	request_replan("human_order")
	match normalized:
		AiOrderClass.ID_HOLD:
			state_id = AiCommanderStateClass.FIGHT
		AiOrderClass.ID_RETREAT:
			state_id = AiCommanderStateClass.MOVE
		AiOrderClass.ID_MOVE_TO, AiOrderClass.ID_FACE_DIRECTION:
			state_id = AiCommanderStateClass.MOVE
		AiOrderClass.ID_ATTACK:
			state_id = AiCommanderStateClass.ADVANCE
		AiOrderClass.ID_DEFEND:
			state_id = AiCommanderStateClass.MOVE
		_:
			state_id = AiCommanderStateClass.PLAN


func _sync_human_order_from_hierarchy(game_state) -> void:
	## Pull authoritative order written by ActionResolver / issue_order.
	var order_id: String = game_state.command_hierarchy.get_active_ai_order(player_id)
	var cell: Vector2i = game_state.command_hierarchy.get_active_ai_order_cell(player_id)
	if order_id == AiOrderClass.ID_NONE or order_id.is_empty():
		if human_order_id != AiOrderClass.ID_NONE:
			apply_human_order(AiOrderClass.ID_RESUME_PLAN)
		return
	if order_id != human_order_id or cell != human_order_cell:
		apply_human_order(order_id, cell)


func debug_snapshot(game_state) -> Dictionary:
	var obj_label := "—"
	if current_objective != null and current_objective.is_valid():
		obj_label = current_objective.label
	return {
		"player_id": player_id,
		"plan": get_active_plan(game_state) if game_state != null else "",
		"state": state_id,
		"objective": obj_label,
		"order": human_order_id if human_order_id != AiOrderClass.ID_NONE else AiOrderClass.ID_RESUME_PLAN,
		"target": current_target_key,
		"last_action": _debug_last_action,
	}


## One think step. submit_command: Callable(command, context) -> ActionResult
func tick(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	claimed_objectives: Array[Vector2i],
	now_msec: int,
) -> Vector2i:
	_commands_this_tick = 0
	if game_state == null or player_id <= 0:
		return Vector2i(-999, -999)
	if not game_state.command_hierarchy.is_ai_player(player_id):
		return Vector2i(-999, -999)
	if game_state.is_deployment_phase():
		return Vector2i(-999, -999)

	var visible := _visible_enemies(game_state)
	_update_current_target(visible)
	_sync_human_order_from_hierarchy(game_state)

	if needs_replan or (now_msec - last_replan_msec) >= DEFAULT_REPLAN_INTERVAL_MSEC:
		_replan(game_state, claimed_objectives, visible)
		last_replan_msec = now_msec
		needs_replan = false

	_run_state(game_state, find_path, submit_command, visible)

	if current_objective != null and current_objective.is_valid():
		return current_objective.cell
	return Vector2i(-999, -999)


func _replan(game_state, claimed: Array[Vector2i], visible: Array) -> void:
	## Human orders override plan objectives.
	match AiOrderClass.normalize_id(human_order_id):
		AiOrderClass.ID_RETREAT:
			current_objective = AiSectorObjectivesClass.retreat_objective(game_state, player_id)
			state_id = AiCommanderStateClass.MOVE
			return
		AiOrderClass.ID_MOVE_TO:
			if human_order_cell.x > -900:
				current_objective = AiObjectiveClass.make(
					"order_move", "Move To", human_order_cell, "order", 30
				)
				state_id = AiCommanderStateClass.MOVE
			return
		AiOrderClass.ID_DEFEND:
			var cell := human_order_cell
			if cell.x <= -900:
				cell = AiSectorObjectivesClass.retreat_objective(game_state, player_id).cell
			current_objective = AiObjectiveClass.make("order_defend", "Defend", cell, "cover", 30)
			state_id = AiCommanderStateClass.MOVE
			return
		AiOrderClass.ID_HOLD:
			var hold_cell := _formation_center(game_state)
			current_objective = AiSectorObjectivesClass.hold_objective_at(hold_cell)
			state_id = AiCommanderStateClass.FIGHT if not visible.is_empty() else AiCommanderStateClass.MOVE
			return
		AiOrderClass.ID_FACE_DIRECTION:
			return
		AiOrderClass.ID_ATTACK:
			## Fall through to plan objectives but prefer aggression.
			pass

	var plan := get_active_plan(game_state)
	var options: Array = AiSectorObjectivesClass.objectives_for_plan(
		game_state, player_id, plan, claimed
	)
	if options.is_empty():
		current_objective = null
		state_id = AiCommanderStateClass.PLAN
		return
	current_objective = options[0]
	## Enter CONTACT from movement/planning only — never demote FIGHT back to CONTACT
	## on every replan interval (that starved Fire/Grenade forever).
	if not visible.is_empty():
		match state_id:
			AiCommanderStateClass.PLAN, AiCommanderStateClass.MOVE, \
			AiCommanderStateClass.ADVANCE, AiCommanderStateClass.OBJECTIVE_COMPLETE:
				state_id = AiCommanderStateClass.CONTACT
	elif state_id == AiCommanderStateClass.OBJECTIVE_COMPLETE or state_id == AiCommanderStateClass.PLAN:
		state_id = AiCommanderStateClass.MOVE


func _run_state(game_state, find_path: Callable, submit_command: Callable, visible: Array) -> void:
	if AiOrderClass.normalize_id(human_order_id) == AiOrderClass.ID_FACE_DIRECTION:
		_order_face(game_state, submit_command)
		if not visible.is_empty():
			_try_fire(game_state, submit_command, visible)
		return

	match state_id:
		AiCommanderStateClass.PLAN:
			state_id = AiCommanderStateClass.MOVE
		AiCommanderStateClass.MOVE, AiCommanderStateClass.ADVANCE:
			if not visible.is_empty():
				state_id = AiCommanderStateClass.CONTACT
			else:
				_move_toward_objective(game_state, find_path, submit_command)
				if _objective_reached(game_state):
					state_id = AiCommanderStateClass.OBJECTIVE_COMPLETE
					request_replan("objective_complete")
		AiCommanderStateClass.CONTACT:
			state_id = AiCommanderStateClass.FIGHT
			## Orient FT first when needed; fire still same think tick.
			_face_threat(game_state, submit_command, visible)
			_try_fire(game_state, submit_command, visible)
			_try_grenade(game_state, submit_command, visible)
		AiCommanderStateClass.FIGHT:
			## Fire first in sustained contact so budget isn't only re-facing.
			_try_fire(game_state, submit_command, visible)
			_try_grenade(game_state, submit_command, visible)
			_face_threat(game_state, submit_command, visible)
			if visible.is_empty():
				if AiOrderClass.normalize_id(human_order_id) == AiOrderClass.ID_HOLD:
					state_id = AiCommanderStateClass.FIGHT
				else:
					state_id = AiCommanderStateClass.ADVANCE
					request_replan("contact_lost")
			elif AiOrderClass.normalize_id(human_order_id) in [
				AiOrderClass.ID_ATTACK,
				AiOrderClass.ID_NONE,
				"",
			]:
				## Occasional press — only if still far and the fireteam is idle.
				if (
					get_active_plan(game_state) != AiPlanClass.ID_DEFEND
					and _formation_objective_distance(game_state) >= FIGHT_ADVANCE_MIN_DIST
				):
					_move_toward_objective(game_state, find_path, submit_command)
		AiCommanderStateClass.OBJECTIVE_COMPLETE:
			state_id = AiCommanderStateClass.PLAN
		_:
			state_id = AiCommanderStateClass.PLAN


func _visible_enemies(game_state) -> Array:
	var out: Array = []
	var keys: Array = game_state.get_visible_enemies(player_id)
	for key in keys:
		var parts := str(key).split(":")
		if parts.size() < 2:
			continue
		var enemy = game_state.get_soldier(int(parts[0]), int(parts[1]))
		if enemy != null and not enemy.is_dead:
			out.append(enemy)
	return out


func _update_current_target(visible: Array) -> void:
	if visible.is_empty():
		current_target_key = ""
		return
	var best = visible[0]
	current_target_key = "%d:%d" % [best.team_id, best.soldier_id]


func _formation_center(game_state) -> Vector2i:
	var soldiers := _living_soldiers(game_state)
	if soldiers.is_empty():
		return Vector2i(0, 0)
	var sx := 0
	var sy := 0
	for s in soldiers:
		sx += s.grid_position.x
		sy += s.grid_position.y
	return Vector2i(sx / soldiers.size(), sy / soldiers.size())


func _formation_objective_distance(game_state) -> int:
	if current_objective == null or not current_objective.is_valid():
		return 0
	var center := _formation_center(game_state)
	return absi(center.x - current_objective.cell.x) + absi(center.y - current_objective.cell.y)


func _living_soldiers(game_state) -> Array:
	## Owned fireteam only — never other players' soldiers on the same side.
	var out: Array = []
	var ids: Array = game_state.command_hierarchy.get_soldier_ids(player_id)
	var team_id: int = game_state.command_hierarchy.get_team_id(player_id)
	for sid in ids:
		var soldier = game_state.get_soldier(team_id, int(sid))
		if soldier != null and not soldier.is_dead and not soldier.is_stunned():
			out.append(soldier)
	return out


func _fireteam_is_moving(game_state) -> bool:
	for soldier in _living_soldiers(game_state):
		if soldier.is_moving:
			return true
	return false


func _lead_soldier(game_state):
	var soldiers := _living_soldiers(game_state)
	if soldiers.is_empty():
		return null
	return soldiers[0]


func _objective_reached(game_state) -> bool:
	if current_objective == null or not current_objective.is_valid():
		return false
	return _formation_objective_distance(game_state) <= OBJECTIVE_ARRIVE_DIST


func _move_toward_objective(game_state, find_path: Callable, submit_command: Callable) -> void:
	if current_objective == null or not current_objective.is_valid():
		return
	if _commands_this_tick >= MAX_COMMANDS_PER_TICK:
		return
	## One fireteam order — wait until the whole FT finishes before re-pathing.
	if _fireteam_is_moving(game_state):
		return
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	var target := current_objective.cell
	if not game_state.map_data.is_walkable(target):
		return
	var cmd := MoveCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.target_cell = target
	## SQUAD + acting_player_id → ActionResolver moves only this player's owned FT.
	cmd.scope = MoveCommandClass.Scope.SQUAD
	cmd.movement_mode = MovementModeClass.RUN
	var ctx := _make_context(find_path)
	var result = submit_command.call(cmd, ctx)
	if result != null and result.success:
		_commands_this_tick += 1
		_debug_last_action = "move FT→%s" % target


func _face_threat(game_state, submit_command: Callable, visible: Array) -> void:
	if visible.is_empty() or _commands_this_tick >= MAX_COMMANDS_PER_TICK:
		return
	var threat = visible[0]
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	## Skip if the whole owned FT already faces the threat.
	var needs_face := false
	for soldier in _living_soldiers(game_state):
		if not CombatSystem.is_facing_target(soldier, threat):
			needs_face = true
			break
	if not needs_face:
		return
	var cmd := FaceCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.target_cell = threat.grid_position
	cmd.scope = FaceCommandClass.Scope.SQUAD
	var result = submit_command.call(cmd, _make_context(Callable()))
	if result != null and result.success:
		_commands_this_tick += 1
		_debug_last_action = "face FT→%s" % threat.grid_position


func _order_face(game_state, submit_command: Callable) -> void:
	if human_order_cell.x <= -900:
		return
	if _commands_this_tick >= MAX_COMMANDS_PER_TICK:
		return
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	var cmd := FaceCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.target_cell = human_order_cell
	cmd.scope = FaceCommandClass.Scope.SQUAD
	var result = submit_command.call(cmd, _make_context(Callable()))
	if result != null and result.success:
		_commands_this_tick += 1


func _try_fire(game_state, submit_command: Callable, visible: Array) -> void:
	if visible.is_empty() or _commands_this_tick >= MAX_COMMANDS_PER_TICK:
		return
	var threat = visible[0]
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	## Owned fireteam shooters only (idle + ammo).
	var shooters: Array[int] = []
	for soldier in _living_soldiers(game_state):
		if soldier.ammo_current <= 0:
			continue
		if soldier.is_moving:
			continue
		shooters.append(soldier.soldier_id)
	if shooters.is_empty():
		return
	var cmd := FireCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = shooters[0]
	cmd.target_team_id = threat.team_id
	cmd.target_soldier_id = threat.soldier_id
	cmd.scope = FireCommandClass.Scope.SQUAD
	cmd.aim_world = IsometricGrid.soldier_aim_point(threat.grid_position)
	var ctx := _make_context(Callable())
	ctx.shooter_ids = shooters
	var result = submit_command.call(cmd, ctx)
	if result != null and result.success:
		_commands_this_tick += 1
		_debug_last_action = "fire FT→%d:%d" % [threat.team_id, threat.soldier_id]
		current_target_key = "%d:%d" % [threat.team_id, threat.soldier_id]


func _try_grenade(game_state, submit_command: Callable, visible: Array) -> void:
	if visible.is_empty() or _commands_this_tick >= MAX_COMMANDS_PER_TICK:
		return
	## Require a small cluster — avoid wasting grenades.
	var impact: Vector2i = visible[0].grid_position
	var cluster := 0
	for enemy in visible:
		if (
			maxi(absi(enemy.grid_position.x - impact.x), absi(enemy.grid_position.y - impact.y))
			<= GRENADE_CLUSTER_CHEBYSHEV
		):
			cluster += 1
	if cluster < 2 and aggression < 1.5:
		return
	for soldier in _living_soldiers(game_state):
		if soldier.grenade_count <= 0:
			continue
		if soldier.has_pending_grenade():
			continue
		var cmd := GrenadeCommandClass.new()
		cmd.team_id = soldier.team_id
		cmd.soldier_id = soldier.soldier_id
		cmd.target_cell = impact
		var result = submit_command.call(cmd, _make_context(Callable()))
		if result != null and result.success:
			_commands_this_tick += 1
			_debug_last_action = "grenade %d→%s" % [soldier.soldier_id, impact]
		break


func _make_context(find_path: Callable) -> CommandContextClass:
	var ctx := CommandContextClass.new()
	ctx.acting_player_id = player_id
	if find_path.is_valid():
		ctx.find_path = find_path
	return ctx
