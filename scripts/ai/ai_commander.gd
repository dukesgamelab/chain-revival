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
## Hard cap on submits per think (pathfind budget is the real throttle).
const MAX_COMMANDS_PER_TICK := 6
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
## TUNED — advance bound length toward objective (cover-to-cover).
const ADVANCE_BOUND_MIN_DIST := 6
const ADVANCE_BOUND_MAX_DIST := 10
## TUNED — defensive posts stay within this Chebyshev of the primary hold (FT cohesion).
const DEFENSIVE_POST_CLUSTER := 12
## Must match ActionResolver.FIRETEAM_COHESION_RADIUS — AI posts never exceed this span.
const FIRETEAM_COHESION_RADIUS := 25
## TUNED — never bound closer than this Manhattan to a visible threat.
const CONTACT_THREAT_STANDOFF := 3
## TUNED — re-bound if threat cell moves at least this Chebyshev from last bound axis.
const COVER_THREAT_SHIFT_CHEBYSHEV := 3
## TUNED — avg fireteam stress at/above this → favor cover + prone over pushing.
const STRESS_COVER_PRIORITY := 35.0
## TUNED — crawl to cover only at/above this; below it, RUN into cover.
const STRESS_HEAVY_FIRE := 55.0
## Dedup keys expire so a failed/starved order can be retried.
const DEDUP_EXPIRE_MSEC := 3000
## No successful command + idle + no contact → clear dedup and replan.
const WATCHDOG_IDLE_MSEC := 5000

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
var _command_budget: int = 2
var _debug_last_action: String = ""
## Settled behind directional cover for this contact (cleared on flank / contact lost).
var _settled_in_cover: bool = false
var _cover_bound_msec: int = -999999
var _cover_threat_cell: Vector2i = Vector2i(-999, -999)
## True while the active path is a contact cover / cover-to-cover bound (not objective RUN).
var _contact_bound_active: bool = false
## Shared snapshot for this think (set by framework; tests may leave null).
var _snapshot: AiBattlefieldSnapshotClass = null
## Dedup — skip identical Move/Face/Fire intents (timestamped; expire after DEDUP_EXPIRE_MSEC).
var _last_move_cell: Vector2i = Vector2i(-999, -999)
var _last_move_msec: int = -999999
var _last_face_cell: Vector2i = Vector2i(-999, -999)
var _last_face_msec: int = -999999
var _last_fire_key: String = ""
var _last_fire_msec: int = -999999
var _last_path_request_msec: int = 0
var _last_command_label: String = ""
var _last_success_msec: int = 0
var _watchdog_logged: bool = false
## Per-soldier defensive posts for hold/cover objectives (soldier_id -> cell).
var _defensive_posts: Dictionary = {}


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
	var soldier_lines: Array = []
	if game_state != null:
		var approach := AiSectorObjectivesClass.enemy_approach_cell(game_state, player_id)
		for soldier in _living_soldiers(game_state):
			var post: Vector2i = _defensive_posts.get(soldier.soldier_id, Vector2i(-999, -999))
			var in_cover := false
			if approach.x > -900 and game_state.map_data != null:
				in_cover = AiSectorObjectivesClass.stand_covered_vs_threat(
					soldier.grid_position, approach, game_state.map_data
				)
			elif _cover_threat_cell.x > -900 and game_state.map_data != null:
				in_cover = AiSectorObjectivesClass.stand_covered_vs_threat(
					soldier.grid_position, _cover_threat_cell, game_state.map_data
				)
			soldier_lines.append({
				"id": soldier.soldier_id,
				"post": post,
				"cell": soldier.grid_position,
				"in_cover": in_cover,
				"position": soldier.position_state,
				"ammo": soldier.ammo_current,
				"stress": int(round(soldier.stress)),
				"target": current_target_key,
			})
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
		"soldiers": soldier_lines,
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

	var living_n := _living_soldiers(game_state).size()
	_command_budget = clampi(living_n, 1, MAX_COMMANDS_PER_TICK)

	var visible: Array = _snapshot.visible_for(player_id)
	if visible.is_empty():
		current_target_key = ""
	else:
		_select_best_threat(game_state, visible)
	_sync_human_order_from_hierarchy(game_state)
	_run_watchdog(game_state, visible, now_msec)

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
			_assign_defensive_posts(game_state, [current_objective])
			state_id = AiCommanderStateClass.MOVE
			return
		AiOrderClass.ID_HOLD:
			var hold_cell := _formation_center(game_state)
			current_objective = AiSectorObjectivesClass.hold_objective_at(hold_cell)
			_assign_defensive_posts(game_state, [current_objective])
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
	## Prefer high-priority, least-claimed option (DEFEND center first for a lone FT).
	var selected = AiSectorObjectivesClass.select_for_claims(options, claimed)
	current_objective = selected if selected != null else options[0]
	if _is_hold_objective():
		_assign_defensive_posts(game_state, options)
	else:
		_defensive_posts.clear()
	## Enter CONTACT from movement/planning only — never demote FIGHT back to CONTACT
	## on every replan interval (that starved Fire/Grenade forever).
	if not visible.is_empty():
		match state_id:
			AiCommanderStateClass.PLAN, AiCommanderStateClass.MOVE, \
			AiCommanderStateClass.ADVANCE, AiCommanderStateClass.OBJECTIVE_COMPLETE:
				state_id = AiCommanderStateClass.CONTACT
				_clear_cover_settlement()
	elif _is_hold_objective() and _defensive_posts_reached(game_state):
		## Stay on defensive posts — do not replan into a chase.
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
				## Under fire but no LOS yet — dash/crawl behind cover facing the approach.
				var approach := AiSectorObjectivesClass.enemy_approach_cell(game_state, player_id)
				var center := _formation_center(game_state)
				var cover := AiSectorObjectivesClass.nearest_cover_within(
					game_state, center, approach, COVER_SEEK_MAX_DIST, [], false, true
				)
				if cover.x > -900:
					_cover_threat_cell = approach
				_try_take_cover(
					game_state,
					find_path,
					submit_command,
					[],
					COVER_SEEK_MAX_DIST,
					_cover_approach_mode(game_state),
					false,
					cover,
				)
			elif not _fireteam_is_moving(game_state):
				if _is_hold_objective() and _defensive_posts_reached(game_state):
					## Arrived at defensive posts — face the approach and watch.
					_hold_defensive_post(game_state, submit_command, visible)
					state_id = AiCommanderStateClass.FIGHT
				elif _is_hold_objective():
					_move_to_defensive_posts(game_state, find_path, submit_command)
					if _defensive_posts_reached(game_state):
						_hold_defensive_post(game_state, submit_command, visible)
						state_id = AiCommanderStateClass.FIGHT
				else:
					_move_toward_objective(game_state, find_path, submit_command)
					if _objective_reached(game_state):
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
					## Defend / Hold — return to posts if drifted, else face approach.
					if not _defensive_posts_reached(game_state):
						_move_to_defensive_posts(game_state, find_path, submit_command)
					else:
						_hold_defensive_post(game_state, submit_command, visible)
					state_id = AiCommanderStateClass.FIGHT
				else:
					state_id = AiCommanderStateClass.ADVANCE
					request_replan("contact_lost")
			else:
				## Fight from cover — do not push the objective while enemies are visible.
				## Hold objectives: if a soldier left their post, send them back first.
				if _is_hold_objective() and not _defensive_posts_reached(game_state):
					_move_to_defensive_posts(game_state, find_path, submit_command)
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
		var threat = _select_best_threat(game_state, visible)
		if threat == null:
			return
		_face_threat(game_state, submit_command, [threat])
		_try_go_prone_on_posts(game_state, submit_command, threat.grid_position)
		return
	var approach := AiSectorObjectivesClass.enemy_approach_cell(game_state, player_id)
	if approach.x <= -900:
		return
	if not _has_command_budget():
		return
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	if _face_dedup_blocks(approach):
		return
	var cmd := FaceCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.target_cell = approach
	cmd.scope = FaceCommandClass.Scope.SQUAD
	if _submit_ai(game_state, submit_command, cmd, _make_context(Callable()), "hold-face→%s" % approach):
		_last_face_cell = approach
		_last_face_msec = SimulationClock.get_ticks_msec()
		_try_go_prone_on_posts(game_state, submit_command, approach)


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
	var threat = _select_best_threat(game_state, visible)
	if threat == null:
		return
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

	## 2) Bound into directional cover — RUN unless under heavy fire.
	if not _settled_in_cover:
		if _formation_in_directional_cover(game_state, threat_cell):
			_mark_cover_settled(threat_cell)
		elif _contact_bound_active and _fireteam_is_moving(game_state):
			## Already moving to cover — wait; do not re-issue objective moves.
			return
		else:
			## One cover query — reuse for both “move there” and “exists but order failed”.
			var nearby_cover := AiSectorObjectivesClass.nearest_cover_within(
				game_state, center, threat_cell, seek_max, [], false, true
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
				_cover_approach_mode(game_state),
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

	## 4) Face + suppress. Grenade last — respects per-think command budget.
	_face_threat(game_state, submit_command, visible)
	_try_fire(game_state, submit_command, visible)
	_try_grenade(game_state, submit_command, visible)

	## 5) Optional short cover-to-cover crawl if objective remains and threat is not point-blank.
	if (
		_settled_in_cover
		and not _fireteam_is_moving(game_state)
		and not _objective_reached(game_state)
		and threat_dist >= CLOSE_RANGE_DIST
		and _has_command_budget()
	):
		_try_contact_bound_forward(game_state, find_path, submit_command, [threat])


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
	## Scoring needs game_state; set after think has snapshot — best-effort from visible[0]
	## until _select_best_threat runs with full state.
	var best = visible[0]
	current_target_key = "%d:%d" % [best.team_id, best.soldier_id]


## Deterministic threat pick: closer, exposed, standing, engaging us, wounded — ties on (team, id).
func _select_best_threat(game_state, visible: Array):
	if visible.is_empty():
		return null
	var lead = _lead_soldier(game_state)
	var from_cell: Vector2i = (
		lead.grid_position if lead != null else _formation_center(game_state)
	)
	var map_data = game_state.map_data if game_state != null else null
	var best = null
	var best_score := -999999
	var best_team := 999
	var best_sid := 999
	for enemy in visible:
		if enemy == null or enemy.is_dead:
			continue
		var score := 0
		var dist := absi(from_cell.x - enemy.grid_position.x) + absi(from_cell.y - enemy.grid_position.y)
		score += maxi(0, 40 - dist) * 3
		if enemy.position_state != PositionStateClass.DOWN:
			score += 12
		if map_data != null:
			var cover = GameplayPolicies.cover.cover_check(from_cell, enemy.grid_position, map_data)
			if cover == null or not bool(cover.in_cover):
				score += 18
		if enemy.is_sustained_fire():
			for ours in _living_soldiers(game_state):
				if (
					enemy.engaged_target_team_id == ours.team_id
					and enemy.engaged_target_soldier_id == ours.soldier_id
				):
					score += 10
					break
		if enemy.stress >= 40.0 or enemy.ammo_current <= 2:
			score += 6
		var tid := int(enemy.team_id)
		var sid := int(enemy.soldier_id)
		if (
			score > best_score
			or (score == best_score and tid < best_team)
			or (score == best_score and tid == best_team and sid < best_sid)
		):
			best = enemy
			best_score = score
			best_team = tid
			best_sid = sid
	if best != null:
		current_target_key = "%d:%d" % [best.team_id, best.soldier_id]
	return best


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
	if not _has_command_budget():
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
	if _submit_ai(game_state, submit_command, cmd, _make_context(Callable()), "halt-contact"):
		_contact_bound_active = false
		_clear_move_dedup()
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
	if not _has_command_budget():
		return
	if _fireteam_is_moving(game_state):
		return
	## Already on a defensive hold — stay; do not drift.
	if _is_hold_objective() and _defensive_posts_reached(game_state):
		return
	## High stress — do not push; prefer holding / looking for cover.
	if _under_suppression(game_state):
		return
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	var objective_cell := current_objective.cell
	if not game_state.map_data.is_walkable(objective_cell):
		return
	var center := _formation_center(game_state)
	var visible: Array = _snapshot.visible_for(player_id) if _snapshot != null else []
	var enemy_anchor := AiSectorObjectivesClass.enemy_approach_cell(game_state, player_id)
	## Cover-to-cover bound: next stand that shortens distance to the objective.
	var target := _next_advance_cover_stand(game_state, center, objective_cell, enemy_anchor)
	var used_cover_bound := target.x > -900
	if not used_cover_bound:
		target = objective_cell
	if _move_dedup_blocks(target, lead.grid_position):
		return
	## Advance at a run; crawl only when pinned by heavy fire.
	var mode := _cover_approach_mode(game_state)
	var cmd := MoveCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.target_cell = target
	cmd.scope = MoveCommandClass.Scope.SQUAD
	cmd.movement_mode = mode
	var ctx := _make_context(find_path)
	_last_path_request_msec = SimulationClock.get_ticks_msec()
	var label := "bound→%s" % target if used_cover_bound else "move FT→%s" % target
	if _submit_ai(game_state, submit_command, cmd, ctx, label):
		_note_move_dedup(target)
		_settled_in_cover = false
		_contact_bound_active = false
		PerceptionCacheClass.move_commands += 1


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
	if not _has_command_budget():
		return false
	## Only block a NEW cover order while an existing contact cover bound is in progress.
	if _contact_bound_active and _fireteam_is_moving(game_state):
		PerceptionCacheClass.duplicate_commands_skipped += 1
		return true
	var center := _formation_center(game_state)
	var threat_cell := Vector2i(-999, -999)
	if not visible.is_empty():
		var threat = _select_best_threat(game_state, visible)
		if threat != null:
			threat_cell = threat.grid_position
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
	if cover == _last_move_cell and not _dedup_expired(_last_move_msec) and _fireteam_is_moving(game_state):
		_contact_bound_active = true
		PerceptionCacheClass.duplicate_commands_skipped += 1
		return true
	if cover == _last_move_cell and not _dedup_expired(_last_move_msec) and not _fireteam_is_moving(game_state):
		## Arrived / failed — expire eventually via watchdog / DEDUP_EXPIRE_MSEC.
		PerceptionCacheClass.duplicate_commands_skipped += 1
		return false
	var cmd := MoveCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.target_cell = cover
	cmd.scope = MoveCommandClass.Scope.SQUAD
	cmd.movement_mode = movement_mode
	_last_path_request_msec = SimulationClock.get_ticks_msec()
	PerceptionCacheClass.move_commands += 1
	if _submit_ai(game_state, submit_command, cmd, _make_context(find_path), "cover→%s" % cover):
		_note_move_dedup(cover)
		_contact_bound_active = true
		_cover_bound_msec = SimulationClock.get_ticks_msec()
		if threat_cell.x > -900:
			_cover_threat_cell = threat_cell
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
	var threat = _select_best_threat(game_state, visible)
	if threat == null:
		return false
	var threat_cell: Vector2i = threat.grid_position
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
		_cover_approach_mode(game_state),
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
	_try_go_prone_on_posts(game_state, submit_command, Vector2i(-999, -999))


## Go prone when the soldier's stand (or post) has directional cover vs the approach.
func _try_go_prone_on_posts(
	game_state,
	submit_command: Callable,
	threat_or_approach: Vector2i,
) -> void:
	if not _has_command_budget():
		return
	var map_data = game_state.map_data if game_state != null else null
	for soldier in _living_soldiers(game_state):
		if not _has_command_budget():
			return
		if soldier.position_state == PositionStateClass.DOWN:
			continue
		if soldier.pending_position_state >= 0:
			continue
		if soldier.is_moving:
			continue
		if threat_or_approach.x > -900 and map_data != null:
			if not AiSectorObjectivesClass.stand_covered_vs_threat(
				soldier.grid_position, threat_or_approach, map_data
			):
				continue
		var cmd := PositionCommandClass.new()
		cmd.team_id = soldier.team_id
		cmd.soldier_id = soldier.soldier_id
		cmd.position_state = PositionStateClass.DOWN
		_submit_ai(
			game_state,
			submit_command,
			cmd,
			_make_context(Callable()),
			"prone %d" % soldier.soldier_id,
		)


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


## Heavy fire → crawl into cover; otherwise dash. Distinct from soft suppression.
func _under_heavy_fire(game_state) -> bool:
	return _fireteam_avg_stress(game_state) >= STRESS_HEAVY_FIRE


func _cover_approach_mode(game_state) -> int:
	if _under_heavy_fire(game_state):
		return MovementModeClass.CRAWL
	return MovementModeClass.RUN


func _face_threat(game_state, submit_command: Callable, visible: Array) -> void:
	if visible.is_empty() or not _has_command_budget():
		return
	var threat = _select_best_threat(game_state, visible)
	if threat == null:
		return
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	if _face_dedup_blocks(threat.grid_position):
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
	if _submit_ai(
		game_state,
		submit_command,
		cmd,
		_make_context(Callable()),
		"face FT→%s" % threat.grid_position,
	):
		_last_face_cell = threat.grid_position
		_last_face_msec = SimulationClock.get_ticks_msec()


func _order_face(game_state, submit_command: Callable) -> void:
	if human_order_cell.x <= -900:
		return
	if not _has_command_budget():
		return
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	var cmd := FaceCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.target_cell = human_order_cell
	cmd.scope = FaceCommandClass.Scope.SQUAD
	_submit_ai(game_state, submit_command, cmd, _make_context(Callable()), "order-face")


func _try_fire(game_state, submit_command: Callable, visible: Array) -> void:
	if visible.is_empty() or not _has_command_budget():
		return
	var threat = _select_best_threat(game_state, visible)
	if threat == null:
		return
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	var fire_key := "%d:%d" % [threat.team_id, threat.soldier_id]
	## Already engaged on this threat — combat tick sustains fire.
	if _fireteam_already_engaging(game_state, threat):
		current_target_key = fire_key
		return
	if fire_key == _last_fire_key and not _dedup_expired(_last_fire_msec):
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
	if _submit_ai(
		game_state,
		submit_command,
		cmd,
		ctx,
		"fire FT→%d:%d" % [threat.team_id, threat.soldier_id],
	):
		_last_fire_key = fire_key
		_last_fire_msec = SimulationClock.get_ticks_msec()
		_clear_move_dedup() ## Halted — allow remarch later.
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
	if visible.is_empty() or not _has_command_budget():
		return
	var threat = _select_best_threat(game_state, visible)
	if threat == null:
		return
	var impact: Vector2i = threat.grid_position
	var cluster := 0
	for enemy in visible:
		if (
			maxi(absi(enemy.grid_position.x - impact.x), absi(enemy.grid_position.y - impact.y))
			<= GRENADE_CLUSTER_CHEBYSHEV
		):
			cluster += 1
	if cluster < 2 and aggression < 1.5:
		return
	var team_id: int = game_state.command_hierarchy.get_team_id(player_id)
	if CombatSystem.grenade_would_hit_friendly(game_state, team_id, impact):
		return
	## Prefer a thrower already in range (movers halt-and-throw from current cell).
	for soldier in _living_soldiers(game_state):
		if soldier.grenade_count <= 0:
			continue
		if soldier.has_pending_grenade():
			continue
		if (
			CombatSystem.grenade_throw_distance(soldier.grid_position, impact)
			> GameplayPolicies.grenade.throw_range
		):
			continue
		var cmd := GrenadeCommandClass.new()
		cmd.team_id = soldier.team_id
		cmd.soldier_id = soldier.soldier_id
		cmd.target_cell = impact
		_submit_ai(
			game_state,
			submit_command,
			cmd,
			_make_context(Callable()),
			"grenade %d→%s" % [soldier.soldier_id, impact],
		)
		break


## --- Defensive posts (Stage 2) + cohesion-safe clustering ---

## Assign living soldiers to nearby cover stands around the primary hold.
## Posts stay inside DEFENSIVE_POST_CLUSTER of the primary and within FT cohesion of each other.
func _assign_defensive_posts(game_state, hold_options: Array) -> void:
	_defensive_posts.clear()
	var soldiers := _living_soldiers(game_state)
	if soldiers.is_empty() or current_objective == null or not current_objective.is_valid():
		return
	var primary := current_objective.cell
	var approach := AiSectorObjectivesClass.enemy_approach_cell(game_state, player_id)
	var claimed: Array[Vector2i] = []
	## Prefer primary, then other hold options sorted by priority (already in options order).
	var seed_cells: Array[Vector2i] = [primary]
	for opt in hold_options:
		if opt == null or not opt.is_valid():
			continue
		var kind := str(opt.kind)
		if kind != "hold" and kind != "cover":
			continue
		if opt.cell == primary:
			continue
		## Only consider lane stands near the primary — never opposite map approaches.
		if maxi(absi(opt.cell.x - primary.x), absi(opt.cell.y - primary.y)) > DEFENSIVE_POST_CLUSTER:
			continue
		seed_cells.append(opt.cell)
	var posts: Array[Vector2i] = []
	for seed in seed_cells:
		if posts.size() >= soldiers.size():
			break
		## Dig in on the far side of cover from the enemy approach (USA for GE).
		var stand := AiSectorObjectivesClass.nearest_cover_within(
			game_state, seed, approach, DEFENSIVE_POST_CLUSTER, claimed, true, true
		)
		if stand.x <= -900:
			stand = seed
		if not _post_fits_cluster(stand, posts, primary):
			continue
		posts.append(stand)
		claimed.append(stand)
	## Fill remaining soldiers with nearby distinct cover around primary.
	while posts.size() < soldiers.size():
		var stand2 := AiSectorObjectivesClass.nearest_cover_within(
			game_state, primary, approach, DEFENSIVE_POST_CLUSTER, claimed, true, true
		)
		if stand2.x <= -900 or not _post_fits_cluster(stand2, posts, primary):
			## Offset walkable fallback near primary.
			stand2 = primary + Vector2i(posts.size() % 3 - 1, posts.size() / 3)
			if game_state.map_data != null and not game_state.map_data.is_walkable(stand2):
				stand2 = primary
			if stand2 in claimed or not _post_fits_cluster(stand2, posts, primary):
				break
		posts.append(stand2)
		claimed.append(stand2)
	## Assign nearest free post to each soldier (stable by soldier_id).
	var sorted_soldiers: Array = soldiers.duplicate()
	sorted_soldiers.sort_custom(func(a, b) -> bool: return a.soldier_id < b.soldier_id)
	var used: Dictionary = {}
	for soldier in sorted_soldiers:
		var best_i := -1
		var best_d := 999999
		for i in posts.size():
			if used.has(i):
				continue
			var d := (
				absi(soldier.grid_position.x - posts[i].x)
				+ absi(soldier.grid_position.y - posts[i].y)
			)
			if d < best_d:
				best_d = d
				best_i = i
		if best_i < 0:
			_defensive_posts[soldier.soldier_id] = primary
		else:
			used[best_i] = true
			_defensive_posts[soldier.soldier_id] = posts[best_i]


func _post_fits_cluster(cell: Vector2i, posts: Array[Vector2i], primary: Vector2i) -> bool:
	if maxi(absi(cell.x - primary.x), absi(cell.y - primary.y)) > DEFENSIVE_POST_CLUSTER:
		return false
	for other in posts:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) > FIRETEAM_COHESION_RADIUS:
			return false
	return true


func _defensive_posts_reached(game_state) -> bool:
	if _defensive_posts.is_empty():
		return _objective_reached(game_state)
	for soldier in _living_soldiers(game_state):
		var post: Vector2i = _defensive_posts.get(soldier.soldier_id, Vector2i(-999, -999))
		if post.x <= -900:
			continue
		var d := absi(soldier.grid_position.x - post.x) + absi(soldier.grid_position.y - post.y)
		if d > OBJECTIVE_ARRIVE_DIST:
			return false
	return true


func _move_to_defensive_posts(
	game_state,
	find_path: Callable,
	submit_command: Callable,
) -> void:
	if _defensive_posts.is_empty():
		_move_toward_objective(game_state, find_path, submit_command)
		return
	if not _has_command_budget():
		return
	var sorted: Array = _living_soldiers(game_state)
	sorted.sort_custom(func(a, b) -> bool: return a.soldier_id < b.soldier_id)
	for soldier in sorted:
		if not _has_command_budget():
			return
		if soldier.is_moving:
			continue
		var post: Vector2i = _defensive_posts.get(soldier.soldier_id, Vector2i(-999, -999))
		if post.x <= -900:
			continue
		var d := absi(soldier.grid_position.x - post.x) + absi(soldier.grid_position.y - post.y)
		if d <= OBJECTIVE_ARRIVE_DIST:
			continue
		if not game_state.map_data.is_walkable(post):
			continue
		var cmd := MoveCommandClass.new()
		cmd.team_id = soldier.team_id
		cmd.soldier_id = soldier.soldier_id
		cmd.target_cell = post
		cmd.scope = MoveCommandClass.Scope.SINGLE
		cmd.movement_mode = MovementModeClass.RUN
		_last_path_request_msec = SimulationClock.get_ticks_msec()
		PerceptionCacheClass.move_commands += 1
		if _submit_ai(
			game_state,
			submit_command,
			cmd,
			_make_context(find_path),
			"post %d→%s" % [soldier.soldier_id, post],
		):
			_note_move_dedup(post)


## Next cover stand along the advance axis (Stage 3). Empty if none qualify.
func _next_advance_cover_stand(
	game_state,
	from_cell: Vector2i,
	objective_cell: Vector2i,
	enemy_anchor: Vector2i,
) -> Vector2i:
	var old_dist := absi(from_cell.x - objective_cell.x) + absi(from_cell.y - objective_cell.y)
	if old_dist <= ADVANCE_BOUND_MAX_DIST:
		return Vector2i(-999, -999)
	var face := enemy_anchor if enemy_anchor.x > -900 else objective_cell
	var cover := AiSectorObjectivesClass.nearest_cover_within(
		game_state, from_cell, face, ADVANCE_BOUND_MAX_DIST
	)
	if cover.x <= -900:
		return Vector2i(-999, -999)
	var step := absi(cover.x - from_cell.x) + absi(cover.y - from_cell.y)
	if step < ADVANCE_BOUND_MIN_DIST:
		return Vector2i(-999, -999)
	var new_dist := absi(cover.x - objective_cell.x) + absi(cover.y - objective_cell.y)
	if new_dist >= old_dist:
		return Vector2i(-999, -999)
	return cover


## --- Dedup / watchdog / submit helpers (Stage 5 + 6) ---

func _has_command_budget() -> bool:
	return _commands_this_tick < _command_budget


func _dedup_expired(stamp_msec: int) -> bool:
	if stamp_msec < 0:
		return true
	return SimulationClock.get_ticks_msec() - stamp_msec >= DEDUP_EXPIRE_MSEC


func _clear_move_dedup() -> void:
	_last_move_cell = Vector2i(-999, -999)
	_last_move_msec = -999999


func _note_move_dedup(cell: Vector2i) -> void:
	_last_move_cell = cell
	_last_move_msec = SimulationClock.get_ticks_msec()


func _move_dedup_blocks(target: Vector2i, lead_cell: Vector2i) -> bool:
	if target != _last_move_cell or _dedup_expired(_last_move_msec):
		return false
	var dist_left := absi(lead_cell.x - target.x) + absi(lead_cell.y - target.y)
	if dist_left <= OBJECTIVE_ARRIVE_DIST:
		PerceptionCacheClass.duplicate_commands_skipped += 1
		return true
	## Halted short — allow remarch after expiry; clear now so next call proceeds.
	_clear_move_dedup()
	return false


func _face_dedup_blocks(cell: Vector2i) -> bool:
	if cell != _last_face_cell or _dedup_expired(_last_face_msec):
		return false
	PerceptionCacheClass.duplicate_commands_skipped += 1
	return true


func _clear_all_dedup() -> void:
	_clear_move_dedup()
	_last_face_cell = Vector2i(-999, -999)
	_last_face_msec = -999999
	_last_fire_key = ""
	_last_fire_msec = -999999


func _run_watchdog(game_state, visible: Array, now_msec: int) -> void:
	if _last_success_msec <= 0:
		_last_success_msec = now_msec
		return
	if now_msec - _last_success_msec < WATCHDOG_IDLE_MSEC:
		_watchdog_logged = false
		return
	if _fireteam_is_moving(game_state):
		return
	if not visible.is_empty():
		return
	_clear_all_dedup()
	request_replan("watchdog")
	if not _watchdog_logged:
		_watchdog_logged = true
		GameLog.log_system("[AI-WATCHDOG] pid=%d idle — cleared dedup, replanning" % player_id)


func _submit_ai(
	game_state,
	submit_command: Callable,
	command: RefCounted,
	context: CommandContextClass,
	debug_label: String,
) -> bool:
	if not _has_command_budget():
		return false
	var result = submit_command.call(command, context)
	if result == null or not result.success:
		return false
	_commands_this_tick += 1
	_last_success_msec = SimulationClock.get_ticks_msec()
	_last_command_label = debug_label
	_debug_last_action = debug_label
	_watchdog_logged = false
	if GameConfig.ai_verbose_enabled():
		var sid := -1
		if "soldier_id" in command:
			sid = int(command.soldier_id)
		var target_cell := Vector2i(-999, -999)
		if "target_cell" in command:
			target_cell = command.target_cell
		elif "aim_world" in command:
			target_cell = IsometricGrid.world_to_grid(command.aim_world)
		var type_name := command.get_class()
		var script_res = command.get_script()
		if script_res != null:
			type_name = str(script_res.resource_path).get_file().get_basename()
		GameLog.log_system(
			"[AI-CMD] pid=%d soldier=%d type=%s target=%s"
			% [player_id, sid, type_name, target_cell]
		)
	return true


func _make_context(find_path: Callable) -> CommandContextClass:
	var ctx := CommandContextClass.new()
	ctx.acting_player_id = player_id
	if find_path.is_valid():
		ctx.find_path = find_path
	return ctx
