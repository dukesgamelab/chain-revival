class_name AiCommander
extends RefCounted
## Per-player AI brain. Issues gameplay commands only via CommandRouter.
## Never mutates GameState soldier/map fields directly.

const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const AiOrderClass := preload("res://scripts/ai/ai_order.gd")
const AiCommanderStateClass := preload("res://scripts/ai/ai_commander_state.gd")
const AiObjectiveClass := preload("res://scripts/ai/ai_objective.gd")
const AiSectorObjectivesClass := preload("res://scripts/ai/ai_sector_objectives.gd")
const AiBattlefieldSnapshotClass := preload("res://scripts/ai/ai_battlefield_snapshot.gd")
const PerceptionCacheClass := preload("res://scripts/combat/perception_cache.gd")
const MoveCommandClass := preload("res://scripts/commands/move_command.gd")
const FaceCommandClass := preload("res://scripts/commands/face_command.gd")
const FireCommandClass := preload("res://scripts/commands/fire_command.gd")
const GrenadeCommandClass := preload("res://scripts/commands/grenade_command.gd")
const PositionCommandClass := preload("res://scripts/commands/position_command.gd")
const HaltCommandClass := preload("res://scripts/commands/halt_command.gd")
const CommandContextClass := preload("res://scripts/core/command_context.gd")
const MovementModeClass := preload("res://scripts/enums/movement_mode.gd")
const PositionStateClass := preload("res://scripts/enums/position_state.gd")

## TEMP DIAGNOSTIC (lag isolation): every AI only marches to the enemy spawn anchor.
## No plans / contact / cover / fire / grenades. Keep false for normal play.
## Tests also force this off in _ready so commander behavior suites still run.
static var DIAGNOSTIC_SIMPLE_RUSH: bool = false

## TUNED — replan cadence (msec). Not recovered.
const DEFAULT_REPLAN_INTERVAL_MSEC := 2000
## TUNED — max Move/Face/Fire/Grenade submits per think tick.
const MAX_COMMANDS_PER_TICK := 2
## TUNED — consider objective reached within this Manhattan distance.
const OBJECTIVE_ARRIVE_DIST := 2
## TUNED — grenade only if clustered enemies within this Chebyshev range of impact.
const GRENADE_CLUSTER_CHEBYSHEV := 2
## TUNED — max distance to seek cover on first contact.
const COVER_SEEK_MAX_DIST := 14
## TUNED — enemy within this Manhattan = "close"; only seek cover this far.
const CLOSE_RANGE_DIST := 4
## TUNED — cover seek radius when already in close contact.
const CLOSE_COVER_SEEK_MAX_DIST := 3
## TUNED — max length of a contact cover-to-cover crawl bound.
const CONTACT_BOUND_MAX_DIST := 6
## TUNED — never bound closer than this Manhattan to a visible threat.
const CONTACT_THREAT_STANDOFF := 3
## TUNED — re-bound if threat cell moves at least this Chebyshev from last bound axis.
const COVER_THREAT_SHIFT_CHEBYSHEV := 3
## TUNED — avg fireteam stress at/above this → favor cover + prone over pushing.
const STRESS_COVER_PRIORITY := 35.0

## Personality / difficulty hooks — aggression scales grenade; retreat_threshold gates stress.
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
## Settled behind directional cover for this contact (cleared on flank / contact lost).
var _settled_in_cover: bool = false
var _cover_bound_msec: int = -999999
var _cover_threat_cell: Vector2i = Vector2i(-999, -999)
## True while the active path is a contact cover / cover-to-cover bound (not objective RUN).
var _contact_bound_active: bool = false
## Shared snapshot for this think (set by framework; tests may leave null).
var _snapshot: AiBattlefieldSnapshotClass = null
## Dedup — skip identical Move/Face/Fire intents.
var _last_move_cell: Vector2i = Vector2i(-999, -999)
var _last_face_cell: Vector2i = Vector2i(-999, -999)
var _last_fire_key: String = ""
var _last_path_request_msec: int = 0
var _last_command_label: String = ""


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
		"last_command": _last_command_label,
		"last_move_cell": _last_move_cell,
		"last_path_request_msec": _last_path_request_msec,
	}


## One think step. submit_command: Callable(command, context) -> ActionResult
## snapshot: shared battlefield read from the framework (preferred). If null, builds a
## one-commander snapshot for tests — still no forced LOS rebuild.
func tick(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	claimed_objectives: Array[Vector2i],
	now_msec: int,
	snapshot: AiBattlefieldSnapshotClass = null,
) -> Vector2i:
	_commands_this_tick = 0
	_snapshot = snapshot
	AiSectorObjectivesClass.cover_checks_this_think = 0
	if game_state == null or player_id <= 0:
		return Vector2i(-999, -999)
	if not game_state.command_hierarchy.is_ai_player(player_id):
		return Vector2i(-999, -999)
	if game_state.is_deployment_phase():
		return Vector2i(-999, -999)

	## TEMP: ignore plans/orders/combat — just walk to enemy deployment.
	if DIAGNOSTIC_SIMPLE_RUSH:
		return _tick_simple_rush(game_state, find_path, submit_command)

	if _snapshot == null:
		_snapshot = AiBattlefieldSnapshotClass.build(game_state, [player_id])

	var visible: Array = _snapshot.visible_for(player_id)
	_update_current_target(visible)
	_sync_human_order_from_hierarchy(game_state)

	var replan_usec := 0
	if needs_replan or (now_msec - last_replan_msec) >= DEFAULT_REPLAN_INTERVAL_MSEC:
		var r0 := Time.get_ticks_usec()
		_replan(game_state, claimed_objectives, visible)
		replan_usec = Time.get_ticks_usec() - r0
		last_replan_msec = now_msec
		needs_replan = false

	var state_t0 := Time.get_ticks_usec()
	_run_state(game_state, find_path, submit_command, visible)
	var state_usec := Time.get_ticks_usec() - state_t0
	## Surface brain hot spots when a single think exceeds 50ms (pathfind is timed separately).
	var brain_msec := float(replan_usec + state_usec) / 1000.0
	if brain_msec >= 50.0:
		GameLog.log_system(
			"[BRAIN-SPIKE] pid=%d state=%s replan_ms=%.2f run_ms=%.2f visible=%d cover_checks=%d"
			% [
				player_id,
				state_id,
				float(replan_usec) / 1000.0,
				float(state_usec) / 1000.0,
				visible.size(),
				AiSectorObjectivesClass.cover_checks_this_think,
			]
		)

	if current_objective != null and current_objective.is_valid():
		return current_objective.cell
	return Vector2i(-999, -999)


## DIAGNOSTIC only: march to enemy spawn. No fire/cover/replan/visibility.
func _tick_simple_rush(
	game_state,
	find_path: Callable,
	submit_command: Callable,
) -> Vector2i:
	if _snapshot == null:
		_snapshot = AiBattlefieldSnapshotClass.build(game_state, [player_id], true)
	current_objective = AiSectorObjectivesClass.enemy_deployment_objective(game_state, player_id)
	state_id = AiCommanderStateClass.ADVANCE
	current_target_key = ""
	human_order_id = AiOrderClass.ID_NONE
	if not _fireteam_is_moving(game_state):
		_move_toward_objective(game_state, find_path, submit_command)
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
			current_objective = AiObjectiveClass.make("order_defend", "Defend", cell, "hold", 30)
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
			pass

	var plan := get_active_plan(game_state)
	var options: Array = AiSectorObjectivesClass.objectives_for_plan(
		game_state, player_id, plan, claimed
	)
	if options.is_empty():
		current_objective = null
		state_id = AiCommanderStateClass.PLAN
		return
	## Prefer high-priority, least-claimed option (DEFEND lanes spread via claims).
	var selected = AiSectorObjectivesClass.select_for_claims(options, claimed)
	current_objective = selected if selected != null else options[0]
	## Enter CONTACT from movement/planning only — never demote FIGHT back to CONTACT
	## on every replan interval (that starved Fire/Grenade forever).
	if not visible.is_empty():
		match state_id:
			AiCommanderStateClass.PLAN, AiCommanderStateClass.MOVE, \
			AiCommanderStateClass.ADVANCE, AiCommanderStateClass.OBJECTIVE_COMPLETE:
				state_id = AiCommanderStateClass.CONTACT
				_clear_cover_settlement()
	elif _is_hold_objective() and _objective_reached(game_state):
		## Stay on the defensive post — do not replan into a chase.
		state_id = AiCommanderStateClass.FIGHT
	elif state_id == AiCommanderStateClass.OBJECTIVE_COMPLETE or state_id == AiCommanderStateClass.PLAN:
		state_id = AiCommanderStateClass.MOVE


func _is_hold_objective() -> bool:
	if current_objective == null or not current_objective.is_valid():
		return false
	var kind := str(current_objective.kind)
	return kind == "hold" or kind == "cover"


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
				_clear_cover_settlement()
				_engage_contact(game_state, find_path, submit_command, visible)
			elif _under_suppression(game_state):
				## Under fire but no LOS yet — hold advance; look for local cover.
				_try_take_cover(game_state, find_path, submit_command, [])
			elif not _fireteam_is_moving(game_state):
				if _is_hold_objective() and _objective_reached(game_state):
					## Arrived at defensive hold — face the approach and watch.
					_hold_defensive_post(game_state, submit_command, visible)
					state_id = AiCommanderStateClass.FIGHT
				else:
					_move_toward_objective(game_state, find_path, submit_command)
					if _objective_reached(game_state):
						if _is_hold_objective():
							_hold_defensive_post(game_state, submit_command, visible)
							state_id = AiCommanderStateClass.FIGHT
						else:
							state_id = AiCommanderStateClass.OBJECTIVE_COMPLETE
							request_replan("objective_complete")
		AiCommanderStateClass.CONTACT:
			_engage_contact(game_state, find_path, submit_command, visible)
			state_id = AiCommanderStateClass.FIGHT
		AiCommanderStateClass.FIGHT:
			if visible.is_empty():
				_clear_cover_settlement()
				if (
					_is_hold_objective()
					or AiOrderClass.normalize_id(human_order_id) == AiOrderClass.ID_HOLD
				):
					## Defend / Hold — stay put and keep facing the approach.
					_hold_defensive_post(game_state, submit_command, visible)
					state_id = AiCommanderStateClass.FIGHT
				else:
					state_id = AiCommanderStateClass.ADVANCE
					request_replan("contact_lost")
			else:
				## Fight from cover — do not push the objective while enemies are visible.
				_engage_contact(game_state, find_path, submit_command, visible)
		AiCommanderStateClass.OBJECTIVE_COMPLETE:
			if _is_hold_objective():
				state_id = AiCommanderStateClass.FIGHT
			else:
				state_id = AiCommanderStateClass.PLAN
		_:
			state_id = AiCommanderStateClass.PLAN


## Face the enemy approach (or visible threat) and hunker when holding a defensive post.
func _hold_defensive_post(game_state, submit_command: Callable, visible: Array) -> void:
	if not visible.is_empty():
		_face_threat(game_state, submit_command, visible)
		if _formation_in_directional_cover(game_state, visible[0].grid_position):
			_try_go_prone(game_state, submit_command)
		return
	var approach := AiSectorObjectivesClass.enemy_approach_cell(game_state, player_id)
	if approach.x <= -900:
		return
	if _commands_this_tick >= MAX_COMMANDS_PER_TICK:
		return
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	if approach == _last_face_cell:
		PerceptionCacheClass.duplicate_commands_skipped += 1
		return
	var cmd := FaceCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.target_cell = approach
	cmd.scope = FaceCommandClass.Scope.SQUAD
	var result = submit_command.call(cmd, _make_context(Callable()))
	if result != null and result.success:
		_commands_this_tick += 1
		_last_face_cell = approach
		_debug_last_action = "hold-face→%s" % approach


func _clear_cover_settlement() -> void:
	_settled_in_cover = false
	_cover_threat_cell = Vector2i(-999, -999)
	_contact_bound_active = false


## Take directional cover first, go prone, then face/fire.
## Contact always cancels an objective RUN before seeking cover.
func _engage_contact(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	visible: Array,
) -> void:
	if visible.is_empty():
		return
	var threat = visible[0]
	var center := _formation_center(game_state)
	var threat_cell: Vector2i = threat.grid_position
	var threat_dist := absi(center.x - threat_cell.x) + absi(center.y - threat_cell.y)
	var seek_max := COVER_SEEK_MAX_DIST
	if threat_dist < CLOSE_RANGE_DIST:
		seek_max = CLOSE_COVER_SEEK_MAX_DIST

	## 1) Halt objective / open-ground runs immediately. Cover bounds may continue.
	if _fireteam_is_moving(game_state) and not _contact_bound_active:
		_halt_fireteam_movement(game_state, submit_command)

	## Flank / bad pick: drop settlement when no longer covered vs current threat.
	if (
		_settled_in_cover
		and not _fireteam_is_moving(game_state)
		and _should_rebound_cover(game_state, threat_cell)
	):
		_settled_in_cover = false
		_contact_bound_active = false
		_debug_last_action = "cover-reeval"

	## 2) Bound into directional cover (CRAWL while enemies visible).
	if not _settled_in_cover:
		if _formation_in_directional_cover(game_state, threat_cell):
			_mark_cover_settled(threat_cell)
		elif _contact_bound_active and _fireteam_is_moving(game_state):
			## Already crawling to cover — wait; do not re-issue objective moves.
			return
		else:
			## One cover query — reuse for both “crawl there” and “exists but order failed”.
			var nearby_cover := AiSectorObjectivesClass.nearest_cover_within(
				game_state, center, threat_cell, seek_max
			)
			var cover_reachable := (
				nearby_cover.x > -900
				and absi(nearby_cover.x - center.x) + absi(nearby_cover.y - center.y) > 1
			)
			if cover_reachable and _try_take_cover(
				game_state,
				find_path,
				submit_command,
				visible,
				seek_max,
				MovementModeClass.CRAWL,
				false,
				nearby_cover,
			):
				return
			## Cover missing, unreachable, or order failed — fight from here (never keep old RUN).
			_settled_in_cover = true
			_contact_bound_active = false

	## Still on a cover bound — suppress only if budget remains; no objective push.
	if _fireteam_is_moving(game_state) and _contact_bound_active:
		_try_fire(game_state, submit_command, visible)
		return

	## 3) Hunker once settled behind cover.
	if _settled_in_cover and _formation_in_directional_cover(game_state, threat_cell):
		_try_go_prone(game_state, submit_command)

	## 4) Face + suppress. Grenade last — command budget is 2.
	_face_threat(game_state, submit_command, visible)
	_try_fire(game_state, submit_command, visible)
	_try_grenade(game_state, submit_command, visible)

	## 5) Optional short cover-to-cover crawl if objective remains and threat is not point-blank.
	if (
		_settled_in_cover
		and not _fireteam_is_moving(game_state)
		and not _objective_reached(game_state)
		and threat_dist >= CLOSE_RANGE_DIST
		and _commands_this_tick < MAX_COMMANDS_PER_TICK
	):
		_try_contact_bound_forward(game_state, find_path, submit_command, visible)


func _mark_cover_settled(threat_cell: Vector2i) -> void:
	_settled_in_cover = true
	_contact_bound_active = false
	_cover_threat_cell = threat_cell
	_cover_bound_msec = SimulationClock.get_ticks_msec()


func _should_rebound_cover(game_state, threat_cell: Vector2i) -> bool:
	var now := SimulationClock.get_ticks_msec()
	if now - _cover_bound_msec < DEFAULT_REPLAN_INTERVAL_MSEC:
		return false
	if not _formation_in_directional_cover(game_state, threat_cell):
		return true
	if _cover_threat_cell.x <= -900:
		return false
	var shift := maxi(
		absi(threat_cell.x - _cover_threat_cell.x),
		absi(threat_cell.y - _cover_threat_cell.y),
	)
	return shift >= COVER_THREAT_SHIFT_CHEBYSHEV


## Formation center is covered vs threat (CoverPolicy: threat shoots at center).
func _formation_in_directional_cover(game_state, threat_cell: Vector2i) -> bool:
	if game_state == null or game_state.map_data == null or threat_cell.x <= -900:
		return false
	var center := _formation_center(game_state)
	return AiSectorObjectivesClass.stand_covered_vs_threat(
		center, threat_cell, game_state.map_data
	)


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
	## Prefer shared snapshot — avoid re-walking hierarchy per helper call.
	if _snapshot != null:
		return _snapshot.living_for(player_id)
	var out: Array = []
	var ids: Array = game_state.command_hierarchy.get_soldier_ids(player_id)
	var team_id: int = game_state.command_hierarchy.get_team_id(player_id)
	for sid in ids:
		var soldier = game_state.get_soldier(team_id, int(sid))
		if soldier != null and not soldier.is_dead and not soldier.is_stunned():
			out.append(soldier)
	return out


func _fireteam_is_moving(game_state) -> bool:
	## Always read live soldier flags — snapshot.fireteam_moving is stale after a same-tick halt.
	for soldier in _living_soldiers(game_state):
		if soldier.is_moving:
			return true
	return false


## Cancel in-progress paths via HaltCommand → ActionResolver movement_halts.
func _halt_fireteam_movement(game_state, submit_command: Callable) -> bool:
	if _commands_this_tick >= MAX_COMMANDS_PER_TICK:
		return false
	if not _fireteam_is_moving(game_state):
		return false
	var lead = _lead_soldier(game_state)
	if lead == null:
		return false
	var cmd := HaltCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.scope = HaltCommandClass.Scope.SQUAD
	var result = submit_command.call(cmd, _make_context(Callable()))
	if result != null and result.success:
		_commands_this_tick += 1
		_contact_bound_active = false
		_last_move_cell = Vector2i(-999, -999)
		_last_command_label = "Halt"
		_debug_last_action = "halt-contact"
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
	if _fireteam_is_moving(game_state):
		return
	## Already on a defensive hold — stay; do not drift.
	if _is_hold_objective() and _objective_reached(game_state):
		return
	## High stress — do not push; prefer holding / looking for cover.
	if _under_suppression(game_state):
		return
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	var target := current_objective.cell
	if not game_state.map_data.is_walkable(target):
		return
	## Already ordered this destination — do not resubmit identical MoveCommands.
	## If we are halted short of the goal (budget starve / interrupt), allow remarch.
	if target == _last_move_cell:
		var dist_left := absi(lead.grid_position.x - target.x) + absi(lead.grid_position.y - target.y)
		if dist_left <= OBJECTIVE_ARRIVE_DIST:
			PerceptionCacheClass.duplicate_commands_skipped += 1
			return
		_last_move_cell = Vector2i(-999, -999)
	var cmd := MoveCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.target_cell = target
	cmd.scope = MoveCommandClass.Scope.SQUAD
	cmd.movement_mode = MovementModeClass.RUN
	var ctx := _make_context(find_path)
	_last_path_request_msec = SimulationClock.get_ticks_msec()
	var result = submit_command.call(cmd, ctx)
	PerceptionCacheClass.move_commands += 1
	if result != null and result.success:
		_commands_this_tick += 1
		_last_move_cell = target
		_last_command_label = "Move→%s" % target
		_settled_in_cover = false
		_contact_bound_active = false
		_debug_last_action = "move FT→%s" % target


func _try_take_cover(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	visible: Array,
	seek_max: int = COVER_SEEK_MAX_DIST,
	movement_mode: int = MovementModeClass.RUN,
	require_short_of_threat: bool = false,
	precomputed_cover: Vector2i = Vector2i(-999, -999),
) -> bool:
	if _commands_this_tick >= MAX_COMMANDS_PER_TICK:
		return false
	## Only block a NEW cover order while an existing contact cover bound is in progress.
	if _contact_bound_active and _fireteam_is_moving(game_state):
		PerceptionCacheClass.duplicate_commands_skipped += 1
		return true
	var center := _formation_center(game_state)
	var threat_cell := Vector2i(-999, -999)
	if not visible.is_empty():
		threat_cell = visible[0].grid_position
	elif _cover_threat_cell.x > -900:
		threat_cell = _cover_threat_cell
	var cover := precomputed_cover
	if cover.x <= -900:
		cover = AiSectorObjectivesClass.nearest_cover_within(
			game_state,
			center,
			threat_cell,
			seek_max,
		)
	if cover.x <= -900:
		return false
	if absi(cover.x - center.x) + absi(cover.y - center.y) <= 1:
		return false
	if (
		require_short_of_threat
		and threat_cell.x > -900
		and not _cover_is_short_of_threat(center, cover, threat_cell)
	):
		return false
	var lead = _lead_soldier(game_state)
	if lead == null:
		return false
	## Already ordered this cover cell and still moving there.
	if cover == _last_move_cell and _fireteam_is_moving(game_state):
		_contact_bound_active = true
		PerceptionCacheClass.duplicate_commands_skipped += 1
		return true
	if cover == _last_move_cell and not _fireteam_is_moving(game_state):
		## Arrived / failed previously — don't spam identical Move.
		PerceptionCacheClass.duplicate_commands_skipped += 1
		return false
	var cmd := MoveCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.target_cell = cover
	cmd.scope = MoveCommandClass.Scope.SQUAD
	cmd.movement_mode = movement_mode
	_last_path_request_msec = SimulationClock.get_ticks_msec()
	var result = submit_command.call(cmd, _make_context(find_path))
	PerceptionCacheClass.move_commands += 1
	if result != null and result.success:
		_commands_this_tick += 1
		_last_move_cell = cover
		_last_command_label = "MoveCover→%s" % cover
		_contact_bound_active = true
		_cover_bound_msec = SimulationClock.get_ticks_msec()
		if threat_cell.x > -900:
			_cover_threat_cell = threat_cell
		_debug_last_action = "cover→%s" % cover
		return true
	return false


## Short cover-to-cover CRAWL toward the objective — never past / onto the threat.
func _try_contact_bound_forward(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	visible: Array,
) -> bool:
	if visible.is_empty() or current_objective == null or not current_objective.is_valid():
		return false
	if _is_hold_objective():
		return false
	var threat_cell: Vector2i = visible[0].grid_position
	var center := _formation_center(game_state)
	var obj := current_objective.cell
	var old_obj_dist := absi(center.x - obj.x) + absi(center.y - obj.y)
	var cover := AiSectorObjectivesClass.nearest_cover_within(
		game_state,
		center,
		threat_cell,
		CONTACT_BOUND_MAX_DIST,
	)
	if cover.x <= -900:
		return false
	if not _cover_is_short_of_threat(center, cover, threat_cell):
		return false
	var new_obj_dist := absi(cover.x - obj.x) + absi(cover.y - obj.y)
	## Only bound if it makes progress on the objective (no sideways / retreat crawls).
	if new_obj_dist >= old_obj_dist:
		return false
	return _try_take_cover(
		game_state,
		find_path,
		submit_command,
		visible,
		CONTACT_BOUND_MAX_DIST,
		MovementModeClass.CRAWL,
		true,
	)


## Cover must stay short of the threat: standoff distance, and not past the enemy.
func _cover_is_short_of_threat(
	from_cell: Vector2i,
	cover: Vector2i,
	threat_cell: Vector2i,
) -> bool:
	if cover.x <= -900 or threat_cell.x <= -900:
		return false
	var cover_to_threat := absi(cover.x - threat_cell.x) + absi(cover.y - threat_cell.y)
	if cover_to_threat < CONTACT_THREAT_STANDOFF:
		return false
	## Past the enemy if continuing beyond the threat along the approach axis.
	var to_threat := threat_cell - from_cell
	var threat_to_cover := cover - threat_cell
	var dot := to_threat.x * threat_to_cover.x + to_threat.y * threat_to_cover.y
	if dot > 0:
		return false
	return true


## Issue DOWN for standing soldiers once behind cover. Respects command budget.
func _try_go_prone(game_state, submit_command: Callable) -> void:
	if _commands_this_tick >= MAX_COMMANDS_PER_TICK:
		return
	for soldier in _living_soldiers(game_state):
		if _commands_this_tick >= MAX_COMMANDS_PER_TICK:
			return
		if soldier.position_state == PositionStateClass.DOWN:
			continue
		if soldier.pending_position_state >= 0:
			continue
		if soldier.is_moving:
			continue
		var cmd := PositionCommandClass.new()
		cmd.team_id = soldier.team_id
		cmd.soldier_id = soldier.soldier_id
		cmd.position_state = PositionStateClass.DOWN
		var result = submit_command.call(cmd, _make_context(Callable()))
		if result != null and result.success:
			_commands_this_tick += 1
			_debug_last_action = "prone %d" % soldier.soldier_id


func _fireteam_avg_stress(game_state) -> float:
	var soldiers := _living_soldiers(game_state)
	if soldiers.is_empty():
		return 0.0
	var total := 0.0
	for s in soldiers:
		total += float(s.stress)
	return total / float(soldiers.size())


func _under_suppression(game_state) -> bool:
	var avg := _fireteam_avg_stress(game_state)
	if retreat_threshold > 0.0 and avg >= retreat_threshold:
		return true
	return avg >= STRESS_COVER_PRIORITY


func _face_threat(game_state, submit_command: Callable, visible: Array) -> void:
	if visible.is_empty() or _commands_this_tick >= MAX_COMMANDS_PER_TICK:
		return
	var threat = visible[0]
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	if threat.grid_position == _last_face_cell:
		PerceptionCacheClass.duplicate_commands_skipped += 1
		return
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
		_last_face_cell = threat.grid_position
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
	var fire_key := "%d:%d" % [threat.team_id, threat.soldier_id]
	## Already engaged on this threat — combat tick sustains fire.
	if _fireteam_already_engaging(game_state, threat):
		current_target_key = fire_key
		return
	if fire_key == _last_fire_key:
		PerceptionCacheClass.duplicate_commands_skipped += 1
		return
	## Include movers — FireCommand halts them so the FT stops to shoot.
	var shooters: Array[int] = []
	for soldier in _living_soldiers(game_state):
		if soldier.ammo_current <= 0:
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
		_last_fire_key = fire_key
		_last_move_cell = Vector2i(-999, -999) ## Halted — allow remarch later.
		_debug_last_action = "fire FT→%d:%d" % [threat.team_id, threat.soldier_id]
		current_target_key = fire_key


func _fireteam_already_engaging(game_state, threat) -> bool:
	if threat == null:
		return false
	var engaged := 0
	var ready := 0
	for soldier in _living_soldiers(game_state):
		if soldier.ammo_current <= 0:
			continue
		ready += 1
		if (
			soldier.is_sustained_fire()
			and soldier.engaged_target_team_id == threat.team_id
			and soldier.engaged_target_soldier_id == threat.soldier_id
		):
			engaged += 1
	return ready > 0 and engaged >= ready


func _try_grenade(game_state, submit_command: Callable, visible: Array) -> void:
	if visible.is_empty() or _commands_this_tick >= MAX_COMMANDS_PER_TICK:
		return
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
		if soldier.is_moving:
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
