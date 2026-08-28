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
## TUNED — defensive posts stay within this Chebyshev of the primary hold.
## Tight with fireteam cohesion so dig-in stays a compact group.
const DEFENSIVE_POST_CLUSTER := 10
## TUNED — min Chebyshev gap between dig-in posts (spread along cover, not stacked).
const DEFENSIVE_POST_MIN_SEP := 2
## Must match ActionResolver.FIRETEAM_COHESION_RADIUS — AI posts never exceed this span.
const FIRETEAM_COHESION_RADIUS := 14
## TUNED — idle soldier this far (Chebyshev) from FT center is a straggler — rally first.
const STRAGGLER_CHEBYSHEV := 4
## TUNED — react to omniscient enemies within this Manhattan (not just LOS).
const CONTACT_REACT_DIST := 32
## TUNED — never bound closer than this Manhattan to a visible threat.
const CONTACT_THREAT_STANDOFF := 3
## TUNED — re-bound if threat cell moves at least this Chebyshev from last bound axis.
const COVER_THREAT_SHIFT_CHEBYSHEV := 3
## TUNED — force a cover re-evaluation this long after settling, even when the threat
## has not shifted. Without it a settled squad holds one stand (prone) for the whole match.
const COVER_RESETTLE_MSEC := 6000
## Cooldown between explicit stand-up orders (msec) — keeps stand/prone from ping-ponging.
const STAND_UP_COOLDOWN_MSEC := 1500
## TUNED — a cover post is only reached by standing ON the stand. Cover two tiles away is
## not cover: the old OBJECTIVE_ARRIVE_DIST tolerance is what left squads lying in the
## open a tile short of a wall, declaring themselves posted.
const COVER_POST_ARRIVE_DIST := 0
## TUNED — avg fireteam stress at/above this → favor cover over pushing.
const STRESS_COVER_PRIORITY := 35.0
## TUNED — crawl to cover only at/above this; below it, RUN into cover.
const STRESS_HEAVY_FIRE := 55.0
## TUNED — rare open-ground prone under heavy fire when cover unreachable (0–1).
const OPEN_PRONE_CHANCE := 0.12
## Cooldown between open-ground prone attempts (msec).
const OPEN_PRONE_COOLDOWN_MSEC := 8000
## Dedup keys expire so a failed/starved order can be retried.
const DEDUP_EXPIRE_MSEC := 2000
## No successful command + idle + no contact → clear dedup and replan.
const WATCHDOG_IDLE_MSEC := 5000
## Survival GE: switch to cover/assault when this close to US (Manhattan).
const SURVIVAL_ASSAULT_RANGE := 8
## Survival GE: cover search radius during assault bounds.
const SURVIVAL_ASSAULT_COVER_SEEK := 10

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
var _last_open_prone_msec: int = -999999
var _last_stand_up_msec: int = -999999
## Survival GE: rotate which soldier bounds forward under fire.
var _survival_bound_soldier_idx: int = 0
## Rotate which soldier takes the next overwatch bound, so one man does not lead every one.
var _bound_soldier_idx: int = 0


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

	## visible = LOS (firing); known = omniscient (contact / cover / facing).
	var visible: Array = _snapshot.visible_for(player_id)
	var known: Array = _snapshot.known_for(player_id)
	var survival_ge := _is_survival_germany_attacker(game_state)
	var reaction: Array = (
		_survival_reaction_threats(game_state, visible, known)
		if survival_ge
		else _threats_for_reaction(game_state, visible, known)
	)
	if reaction.is_empty():
		current_target_key = ""
	else:
		_select_best_threat(game_state, reaction)
	## After grenade stun recovery — drop stale cover settlement before acting.
	_consume_cover_recheck(game_state)
	_sync_human_order_from_hierarchy(game_state)
	_run_watchdog(game_state, reaction, now_msec)

	var replan_usec := 0
	if needs_replan or (now_msec - last_replan_msec) >= DEFAULT_REPLAN_INTERVAL_MSEC:
		var r0 := Time.get_ticks_usec()
		_replan(game_state, claimed_objectives, reaction)
		replan_usec = Time.get_ticks_usec() - r0
		last_replan_msec = now_msec
		needs_replan = false

	var state_t0 := Time.get_ticks_usec()
	if survival_ge:
		_run_survival_germany_state(
			game_state, find_path, submit_command, visible, known, reaction
		)
	else:
		_run_state(game_state, find_path, submit_command, visible, known, reaction)
	var state_usec := Time.get_ticks_usec() - state_t0
	## Surface brain hot spots when a single think exceeds 50ms (pathfind is timed separately).
	var brain_msec := float(replan_usec + state_usec) / 1000.0
	if brain_msec >= 50.0:
		GameLog.log_system(
			"[BRAIN-SPIKE] pid=%d state=%s replan_ms=%.2f run_ms=%.2f visible=%d known=%d cover_checks=%d"
			% [
				player_id,
				state_id,
				float(replan_usec) / 1000.0,
				float(state_usec) / 1000.0,
				visible.size(),
				known.size(),
				AiSectorObjectivesClass.cover_checks_this_think,
			]
		)

	if current_objective != null and current_objective.is_valid():
		if _is_survival_germany_attacker(game_state):
			## Each wave claims its formation center — not the shared VP cell.
			return _formation_center(game_state)
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
	if _is_survival_germany_attacker(game_state):
		current_objective = AiSectorObjectivesClass.survival_ge_lines_objective(game_state)
		_defensive_posts.clear()
		state_id = AiCommanderStateClass.MOVE
		return
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


func _run_state(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	visible: Array,
	known: Array,
	reaction: Array,
) -> void:
	if AiOrderClass.normalize_id(human_order_id) == AiOrderClass.ID_FACE_DIRECTION:
		_order_face(game_state, submit_command)
		if not visible.is_empty():
			_try_fire(game_state, submit_command, visible)
		return

	match state_id:
		AiCommanderStateClass.PLAN:
			state_id = AiCommanderStateClass.MOVE
		AiCommanderStateClass.MOVE, AiCommanderStateClass.ADVANCE:
			## Rally stragglers before the next bound so the FT moves as a group.
			if _has_stragglers(game_state) and _rally_stragglers(game_state, find_path, submit_command):
				return
			if not reaction.is_empty():
				state_id = AiCommanderStateClass.CONTACT
				_clear_cover_settlement()
				_engage_contact(game_state, find_path, submit_command, reaction, visible)
			elif _under_suppression(game_state):
				## Under fire — RUN to cover facing the nearest known enemy (not spawn anchor).
				var approach := _threat_cell_or_approach(game_state, known)
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
					_hold_defensive_post(game_state, submit_command, reaction)
					state_id = AiCommanderStateClass.FIGHT
				elif _is_hold_objective():
					_move_to_defensive_posts(game_state, find_path, submit_command)
					if _defensive_posts_reached(game_state):
						_hold_defensive_post(game_state, submit_command, reaction)
						state_id = AiCommanderStateClass.FIGHT
				else:
					_move_toward_objective(game_state, find_path, submit_command)
					if _objective_reached(game_state):
						state_id = AiCommanderStateClass.OBJECTIVE_COMPLETE
						request_replan("objective_complete")
		AiCommanderStateClass.CONTACT:
			_engage_contact(game_state, find_path, submit_command, reaction, visible)
			state_id = AiCommanderStateClass.FIGHT
		AiCommanderStateClass.FIGHT:
			if reaction.is_empty():
				_clear_cover_settlement()
				if (
					_is_hold_objective()
					or AiOrderClass.normalize_id(human_order_id) == AiOrderClass.ID_HOLD
				):
					## Defend / Hold — return to posts if drifted, else face approach.
					if not _defensive_posts_reached(game_state):
						_move_to_defensive_posts(game_state, find_path, submit_command)
					else:
						_hold_defensive_post(game_state, submit_command, reaction)
					state_id = AiCommanderStateClass.FIGHT
				else:
					state_id = AiCommanderStateClass.ADVANCE
					request_replan("contact_lost")
			else:
				## Fight from cover — do not push the objective while threats are in react range.
				_engage_contact(game_state, find_path, submit_command, reaction, visible)
		AiCommanderStateClass.OBJECTIVE_COMPLETE:
			if _is_hold_objective():
				state_id = AiCommanderStateClass.FIGHT
			else:
				state_id = AiCommanderStateClass.PLAN
		_:
			state_id = AiCommanderStateClass.PLAN


## Face the enemy approach (or known threat) and hunker when holding a defensive post.
func _hold_defensive_post(game_state, submit_command: Callable, threats: Array) -> void:
	if not threats.is_empty():
		var threat = _select_best_threat(game_state, threats)
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


## Grenade stun recovery marks needs_cover_recheck — re-evaluate before resuming.
func _consume_cover_recheck(game_state) -> void:
	var any := false
	for soldier in _living_soldiers(game_state):
		if soldier == null or not soldier.needs_cover_recheck:
			continue
		if soldier.is_stunned():
			continue
		soldier.needs_cover_recheck = false
		any = true
	if any:
		_clear_cover_settlement()


## Take directional cover first, go prone (only in cover), then face/fire.
## Contact always cancels an objective RUN before seeking cover.
## threats = reaction set (known-near / visible); los_targets = fog-visible for firing.
func _engage_contact(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	threats: Array,
	los_targets: Array = [],
) -> void:
	if threats.is_empty():
		return
	var threat = _select_best_threat(game_state, threats)
	if threat == null:
		return
	var fire_pool: Array = los_targets if not los_targets.is_empty() else []
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

	## 2) Bound into directional cover — RUN unless under heavy fire. Prefer cover over prone.
	if not _settled_in_cover:
		if _formation_in_directional_cover(game_state, threat_cell):
			_mark_cover_settled(threat_cell)
		else:
			## Cover is per soldier: move whoever is actually exposed onto their own stand.
			##
			## This deliberately runs BEFORE the "already bounding" gate below. That gate used
			## to swallow the entire think as soon as ONE soldier was en route to a stand, so
			## the other three stood in the open receiving no orders at all — and under heavy
			## fire the mover is crawling, so "wait for him" meant waiting most of the match.
			## _take_cover_individually already skips anyone mid-move, so it is safe here.
			if _take_cover_individually(
				game_state, find_path, submit_command, threat_cell, seek_max
			):
				return
			if _contact_bound_active and _fireteam_is_moving(game_state):
				## Everyone still exposed is already en route — wait, do not re-issue.
				return
			## One cover query — reuse for both “move there” and “exists but order failed”.
			var nearby_cover := AiSectorObjectivesClass.nearest_cover_within(
				game_state, center, threat_cell, seek_max, [], false, true
			)
			## Cover-quality re-evaluation: the close-range radius is deliberately tight, but
			## finding nothing inside it must not mean lying still — widen once before giving
			## up so a squad caught in the open still has somewhere to bound.
			if nearby_cover.x <= -900 and seek_max < COVER_SEEK_MAX_DIST:
				nearby_cover = AiSectorObjectivesClass.nearest_cover_within(
					game_state, center, threat_cell, COVER_SEEK_MAX_DIST, [], false, true
				)
			## A stand one tile away is still cover worth taking. The old `> 1` guard is why a
			## squad would halt a tile short of a wall and lie down in the open next to it.
			var cover_reachable := (
				nearby_cover.x > -900
				and nearby_cover != center
			)
			if cover_reachable and _try_take_cover(
				game_state,
				find_path,
				submit_command,
				threats,
				seek_max,
				_cover_approach_mode(game_state),
				false,
				nearby_cover,
			):
				return
			## No cover this tick — keep seeking next think; do NOT mark settled (avoids open prone).
			_contact_bound_active = false
			## Prone in the open with nothing to bound to is the stuck state — stand so the
			## next think can RUN to cover instead of crawling there (or never moving at all).
			_try_stand_up_off_cover(game_state, submit_command, threat_cell)
			_face_threat(game_state, submit_command, threats)
			_try_fire(game_state, submit_command, fire_pool)
			return

	## Still on a cover bound — suppress only if budget remains; no objective push.
	if _fireteam_is_moving(game_state) and _contact_bound_active:
		_try_fire(game_state, submit_command, fire_pool)
		return

	## 3) Hunker only when actually behind cover vs the threat (never open-ground default).
	if _settled_in_cover and _formation_in_directional_cover(game_state, threat_cell):
		_try_go_prone_on_posts(game_state, submit_command, threat_cell)

	## 4) Face (known) + suppress (LOS only). Grenade last.
	_face_threat(game_state, submit_command, threats)
	_try_fire(game_state, submit_command, fire_pool)
	_try_grenade(game_state, submit_command, fire_pool if not fire_pool.is_empty() else threats)

	## 5) Optional short cover-to-cover crawl if objective remains and threat is not point-blank.
	if (
		_settled_in_cover
		and not _fireteam_is_moving(game_state)
		and not _objective_reached(game_state)
		and threat_dist >= CLOSE_RANGE_DIST
		and _has_command_budget()
	):
		## Fire and maneuver first: one soldier bounds while the rest shoot from cover.
		## Only move the whole fireteam when no single bound qualifies.
		if not _try_bounding_overwatch(game_state, find_path, submit_command, [threat]):
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
	## Time-based re-evaluation — a squad that settled once must periodically look for
	## better cover or a forward bound instead of lying on the same stand all match.
	if now - _cover_bound_msec >= COVER_RESETTLE_MSEC:
		return true
	if _cover_threat_cell.x <= -900:
		return false
	var shift := maxi(
		absi(threat_cell.x - _cover_threat_cell.x),
		absi(threat_cell.y - _cover_threat_cell.y),
	)
	return shift >= COVER_THREAT_SHIFT_CHEBYSHEV


## Formation center is covered vs threat (CoverPolicy: threat shoots at center).
## EVERY living soldier individually behind cover vs the threat.
##
## This used to test the formation centre — a single averaged cell that is usually not
## where anybody is standing. A squad strung out beside a wall averages to a cell that
## reads as covered, so the brain marked itself settled, went prone and never repositioned
## anyone: the "fires one shot, lies down, stays there forever" bug. Cover is a property
## of a soldier's tile, so it has to be checked per soldier.
func _formation_in_directional_cover(game_state, threat_cell: Vector2i) -> bool:
	if game_state == null or game_state.map_data == null or threat_cell.x <= -900:
		return false
	var soldiers := _living_soldiers(game_state)
	if soldiers.is_empty():
		return false
	for soldier in soldiers:
		if not AiSectorObjectivesClass.stand_covered_vs_threat(
			soldier.grid_position, threat_cell, game_state.map_data
		):
			return false
	return true


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


## LOS enemies always react; omniscient known enemies react when within CONTACT_REACT_DIST.
func _threats_for_reaction(game_state, visible: Array, known: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for enemy in visible:
		if enemy == null or enemy.is_dead:
			continue
		var key := "%d:%d" % [enemy.team_id, enemy.soldier_id]
		seen[key] = true
		out.append(enemy)
	var center := _formation_center(game_state)
	for enemy in known:
		if enemy == null or enemy.is_dead:
			continue
		var key := "%d:%d" % [enemy.team_id, enemy.soldier_id]
		if seen.has(key):
			continue
		var dist := absi(center.x - enemy.grid_position.x) + absi(center.y - enemy.grid_position.y)
		if dist > CONTACT_REACT_DIST:
			continue
		out.append(enemy)
	return out


## Prefer nearest known enemy cell; fall back to deployment approach anchor.
func _threat_cell_or_approach(game_state, known: Array) -> Vector2i:
	var threat = _select_best_threat(game_state, known)
	if threat != null:
		return threat.grid_position
	return AiSectorObjectivesClass.enemy_approach_cell(game_state, player_id)


func _has_stragglers(game_state) -> bool:
	var center := _formation_center(game_state)
	for soldier in _living_soldiers(game_state):
		if soldier.is_moving:
			continue
		var d := maxi(
			absi(soldier.grid_position.x - center.x),
			absi(soldier.grid_position.y - center.y),
		)
		if d > STRAGGLER_CHEBYSHEV:
			return true
	return false


## Pull idle soldiers that drifted from the FT center back into the pack.
func _rally_stragglers(game_state, find_path: Callable, submit_command: Callable) -> bool:
	if not _has_command_budget():
		return false
	var center := _formation_center(game_state)
	var any := false
	var map_data = game_state.map_data
	for soldier in _living_soldiers(game_state):
		if not _has_command_budget():
			break
		if soldier.is_moving:
			continue
		var d := maxi(
			absi(soldier.grid_position.x - center.x),
			absi(soldier.grid_position.y - center.y),
		)
		if d <= STRAGGLER_CHEBYSHEV:
			continue
		var target := center
		if map_data != null and not map_data.is_walkable(target):
			## Step toward the pack if the exact center is blocked.
			var step: Vector2i = soldier.grid_position + Vector2i(
				signi(center.x - soldier.grid_position.x),
				signi(center.y - soldier.grid_position.y),
			)
			if map_data.is_walkable(step):
				target = step
			else:
				continue
		if target == soldier.grid_position:
			continue
		if _move_dedup_blocks(target, soldier.grid_position):
			continue
		var cmd := MoveCommandClass.new()
		cmd.team_id = soldier.team_id
		cmd.soldier_id = soldier.soldier_id
		cmd.target_cell = target
		cmd.scope = MoveCommandClass.Scope.SINGLE
		cmd.movement_mode = MovementModeClass.RUN
		if _submit_ai(
			game_state,
			submit_command,
			cmd,
			_make_context(find_path),
			"rally %d→%s" % [soldier.soldier_id, target],
		):
			_note_move_dedup(target)
			any = true
	return any


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
	## Keep the fireteam together — rally stragglers before the next squad bound.
	if _has_stragglers(game_state):
		_rally_stragglers(game_state, find_path, submit_command)
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
	var enemy_anchor := _threat_cell_or_approach(
		game_state,
		_snapshot.known_for(player_id) if _snapshot != null else [],
	)
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
	## Adjacent cover still counts — only decline when the fireteam is already on it.
	if cover == center:
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


## Move every soldier that is NOT behind cover onto its own stand. One squad-scoped move
## to a single cell cannot fix a fireteam that is half exposed — cover belongs to a tile,
## so each exposed man needs his own. Stands already held (or just ordered) are claimed so
## two soldiers do not pile onto the same one. Returns true if any order was issued.
func _take_cover_individually(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	threat_cell: Vector2i,
	seek_max: int,
) -> bool:
	var map_data = game_state.map_data if game_state != null else null
	if map_data == null or threat_cell.x <= -900:
		return false
	var soldiers := _living_soldiers(game_state)
	if soldiers.is_empty():
		return false
	var sorted: Array = soldiers.duplicate()
	sorted.sort_custom(func(a, b) -> bool: return a.soldier_id < b.soldier_id)
	var claimed: Array[Vector2i] = []
	for holder in sorted:
		if AiSectorObjectivesClass.stand_covered_vs_threat(
			holder.grid_position, threat_cell, map_data
		):
			claimed.append(holder.grid_position)
	var issued := false
	for soldier in sorted:
		if not _has_command_budget():
			break
		if soldier.is_moving:
			continue
		## Already behind something — that man stays and shoots.
		if AiSectorObjectivesClass.stand_covered_vs_threat(
			soldier.grid_position, threat_cell, map_data
		):
			continue
		var cover := AiSectorObjectivesClass.nearest_cover_within(
			game_state,
			soldier.grid_position,
			threat_cell,
			seek_max,
			claimed,
			true,
			true,
		)
		if cover.x <= -900 or cover == soldier.grid_position:
			continue
		if not map_data.is_walkable(cover):
			continue
		var cmd := MoveCommandClass.new()
		cmd.team_id = soldier.team_id
		cmd.soldier_id = soldier.soldier_id
		cmd.target_cell = cover
		cmd.scope = MoveCommandClass.Scope.SINGLE
		cmd.movement_mode = _cover_approach_mode(game_state)
		_last_path_request_msec = SimulationClock.get_ticks_msec()
		if _submit_ai(
			game_state,
			submit_command,
			cmd,
			_make_context(find_path),
			"cover %d→%s" % [soldier.soldier_id, cover],
		):
			claimed.append(cover)
			_contact_bound_active = true
			_cover_bound_msec = SimulationClock.get_ticks_msec()
			PerceptionCacheClass.move_commands += 1
			issued = true
	return issued


## Fire and maneuver: hold the fireteam's cover as a base of fire and push ONE soldier to
## the next stand. Fire is squad-scoped and the movement branch above keeps the static
## soldiers shooting, so the bound is covered instead of the whole team standing up at once.
## Declines when there is nobody left to cover the move, when the mover is not already in
## cover, or when no forward stand improves on where it stands — caller then falls back to
## the fireteam bound.
func _try_bounding_overwatch(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	threats: Array,
) -> bool:
	if not _has_command_budget() or _is_hold_objective():
		return false
	if current_objective == null or not current_objective.is_valid():
		return false
	if threats.is_empty() or _fireteam_is_moving(game_state):
		return false
	var map_data = game_state.map_data if game_state != null else null
	if map_data == null:
		return false
	var threat = _select_best_threat(game_state, threats)
	if threat == null:
		return false
	var threat_cell: Vector2i = threat.grid_position
	var soldiers := _living_soldiers(game_state)
	## Someone has to stay in cover and shoot, otherwise this is just a squad move.
	if soldiers.size() < 2:
		return false
	var sorted: Array = soldiers.duplicate()
	sorted.sort_custom(func(a, b) -> bool: return a.soldier_id < b.soldier_id)
	var obj: Vector2i = current_objective.cell
	for offset in sorted.size():
		var idx: int = (_bound_soldier_idx + offset) % sorted.size()
		var mover = sorted[idx]
		if mover.is_moving:
			continue
		var from_cell: Vector2i = mover.grid_position
		## Only bound FROM cover — leaving good cover to cross open ground is the bug.
		if not AiSectorObjectivesClass.stand_covered_vs_threat(from_cell, threat_cell, map_data):
			continue
		## Do not bound onto a stand a teammate is already holding.
		var claimed: Array[Vector2i] = []
		for other in sorted:
			if other.soldier_id != mover.soldier_id:
				claimed.append(other.grid_position)
		var cover := AiSectorObjectivesClass.nearest_cover_within(
			game_state,
			from_cell,
			threat_cell,
			ADVANCE_BOUND_MAX_DIST,
			claimed,
			true,
			true,
		)
		if cover.x <= -900 or cover == from_cell or not map_data.is_walkable(cover):
			continue
		if not _cover_is_short_of_threat(from_cell, cover, threat_cell):
			continue
		## The bound has to buy ground on the objective, not just shuffle sideways.
		var old_d := absi(from_cell.x - obj.x) + absi(from_cell.y - obj.y)
		var new_d := absi(cover.x - obj.x) + absi(cover.y - obj.y)
		if new_d >= old_d:
			continue
		var cmd := MoveCommandClass.new()
		cmd.team_id = mover.team_id
		cmd.soldier_id = mover.soldier_id
		cmd.target_cell = cover
		cmd.scope = MoveCommandClass.Scope.SINGLE
		cmd.movement_mode = _cover_approach_mode(game_state)
		_last_path_request_msec = SimulationClock.get_ticks_msec()
		if _submit_ai(
			game_state,
			submit_command,
			cmd,
			_make_context(find_path),
			"bound-ovw %d→%s" % [mover.soldier_id, cover],
		):
			_bound_soldier_idx = idx + 1
			_contact_bound_active = true
			_cover_bound_msec = SimulationClock.get_ticks_msec()
			PerceptionCacheClass.move_commands += 1
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


## In real cover vs the approach. This is the test that matters for "am I posted?" —
## as opposed to merely being near an assigned tile.
func _in_cover_vs_approach(cell: Vector2i, approach: Vector2i, map_data) -> bool:
	if map_data == null or approach.x <= -900:
		return false
	return AiSectorObjectivesClass.stand_covered_vs_threat(cell, approach, map_data)


## Stand a soldier back up when it is prone WITHOUT directional cover vs the threat.
## Nothing else in the brain issues an UP order — ActionResolver only auto-stands as a
## side effect of a RUN — so an open-ground prone squad otherwise stays down for good.
## One soldier per think on a cooldown: the command budget is 2, and starving Face/Fire
## to stand the whole fireteam at once is worse than un-proning over a few thinks.
func _try_stand_up_off_cover(
	game_state,
	submit_command: Callable,
	threat_cell: Vector2i,
) -> bool:
	if not _has_command_budget() or threat_cell.x <= -900:
		return false
	var map_data = game_state.map_data if game_state != null else null
	if map_data == null:
		return false
	var now := SimulationClock.get_ticks_msec()
	if now - _last_stand_up_msec < STAND_UP_COOLDOWN_MSEC:
		return false
	for soldier in _living_soldiers(game_state):
		if soldier.position_state != PositionStateClass.DOWN:
			continue
		if soldier.pending_position_state >= 0 or soldier.is_moving:
			continue
		## Actually behind something vs this threat — hunkering there is correct.
		if AiSectorObjectivesClass.stand_covered_vs_threat(
			soldier.grid_position, threat_cell, map_data
		):
			continue
		var cmd := PositionCommandClass.new()
		cmd.team_id = soldier.team_id
		cmd.soldier_id = soldier.soldier_id
		cmd.position_state = PositionStateClass.UP
		if _submit_ai(
			game_state,
			submit_command,
			cmd,
			_make_context(Callable()),
			"stand %d" % soldier.soldier_id,
		):
			_last_stand_up_msec = now
			return true
		return false
	return false


## Go prone when the soldier's stand has directional cover vs the approach.
## Open ground: almost never — rare under heavy fire only (prefer RUN to cover).
func _try_go_prone_on_posts(
	game_state,
	submit_command: Callable,
	threat_or_approach: Vector2i,
) -> void:
	if not _has_command_budget():
		return
	if threat_or_approach.x <= -900:
		return
	var map_data = game_state.map_data if game_state != null else null
	if map_data == null:
		return
	var now := SimulationClock.get_ticks_msec()
	var allow_open_prone := (
		_under_heavy_fire(game_state)
		and now - _last_open_prone_msec >= OPEN_PRONE_COOLDOWN_MSEC
		and randf() < OPEN_PRONE_CHANCE
	)
	for soldier in _living_soldiers(game_state):
		if not _has_command_budget():
			return
		if soldier.position_state == PositionStateClass.DOWN:
			continue
		if soldier.pending_position_state >= 0:
			continue
		if soldier.is_moving:
			continue
		var covered := AiSectorObjectivesClass.stand_covered_vs_threat(
			soldier.grid_position, threat_or_approach, map_data
		)
		if not covered and not allow_open_prone:
			continue
		var cmd := PositionCommandClass.new()
		cmd.team_id = soldier.team_id
		cmd.soldier_id = soldier.soldier_id
		cmd.position_state = PositionStateClass.DOWN
		if _submit_ai(
			game_state,
			submit_command,
			cmd,
			_make_context(Callable()),
			"prone %d" % soldier.soldier_id,
		):
			if not covered:
				_last_open_prone_msec = now
				allow_open_prone = false ## at most one open prone per window


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


## Survival Mode GE waves always press the GE Lines (US-held victory point).
func _is_survival_germany_attacker(game_state) -> bool:
	if game_state == null or not game_state.survival_mode:
		return false
	if game_state.command_hierarchy == null:
		return false
	return game_state.command_hierarchy.get_team_id(player_id) == Team.GERMANY


## Only treat incoming fire as "contact" for non-survival brains.
func _survival_reaction_threats(game_state, visible: Array, known: Array) -> Array:
	if not _survival_in_assault_range(game_state, visible, known):
		return []
	var out: Array = visible.duplicate()
	if not out.is_empty():
		return out
	var threat = _select_best_threat(game_state, known)
	if threat != null:
		out.append(threat)
	return out


func _survival_in_assault_range(game_state, visible: Array, known: Array) -> bool:
	return _survival_nearest_us_dist(game_state, visible, known) <= SURVIVAL_ASSAULT_RANGE


func _survival_nearest_us_dist(game_state, visible: Array, known: Array) -> int:
	var center := _formation_center(game_state)
	var best := 999999
	for enemy in visible:
		if enemy == null or enemy.is_dead:
			continue
		var d := absi(center.x - enemy.grid_position.x) + absi(center.y - enemy.grid_position.y)
		best = mini(best, d)
	for enemy in known:
		if enemy == null or enemy.is_dead:
			continue
		var d := absi(center.x - enemy.grid_position.x) + absi(center.y - enemy.grid_position.y)
		best = mini(best, d)
	if best < 999999:
		return best
	if current_objective != null and current_objective.is_valid():
		var obj: Vector2i = current_objective.cell
		return absi(center.x - obj.x) + absi(center.y - obj.y)
	return 999999


func _survival_push_cell(game_state, visible: Array, known: Array) -> Vector2i:
	if current_objective == null or not current_objective.is_valid():
		return Vector2i(-999, -999)
	var threat = _select_best_threat(game_state, visible)
	if threat == null:
		threat = _select_best_threat(game_state, known)
	if threat != null:
		return threat.grid_position
	return current_objective.cell


## Dedicated survival brain: run to GE Lines, assault within 8 tiles, bound one-by-one.
func _run_survival_germany_state(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	visible: Array,
	known: Array,
	reaction: Array,
) -> void:
	_ensure_survival_ge_lines_objective(game_state)
	if current_objective == null or not current_objective.is_valid():
		return
	var in_assault := _survival_in_assault_range(game_state, visible, known)
	if in_assault:
		if not visible.is_empty():
			_face_threat(game_state, submit_command, visible)
			_try_fire(game_state, submit_command, visible)
		_try_survival_grenade(game_state, submit_command, visible, known)
	elif not visible.is_empty():
		_face_threat(game_state, submit_command, visible)
		_try_fire(game_state, submit_command, visible)
	if _fireteam_is_moving(game_state):
		return
	if not in_assault:
		## Once the wave can actually be shot, close cover-to-cover toward GE Lines instead
		## of running the whole way in the open. Same bound machinery as normal contact.
		if (
			not visible.is_empty()
			and _try_contact_bound_forward(game_state, find_path, submit_command, visible)
		):
			return
		_survival_issue_squad_run(game_state, find_path, submit_command, current_objective.cell)
		return
	_survival_assault_one_soldier(
		game_state, find_path, submit_command, visible, known
	)


func _survival_issue_squad_run(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	target_cell: Vector2i,
) -> void:
	if not _has_command_budget() or target_cell.x <= -900:
		return
	var lead = _lead_soldier(game_state)
	if lead == null:
		return
	_clear_move_dedup()
	var cmd := MoveCommandClass.new()
	cmd.team_id = lead.team_id
	cmd.soldier_id = lead.soldier_id
	cmd.target_cell = target_cell
	cmd.scope = MoveCommandClass.Scope.SQUAD
	cmd.movement_mode = MovementModeClass.RUN
	var ctx := _make_survival_context(find_path)
	_last_path_request_msec = SimulationClock.get_ticks_msec()
	if _submit_ai(
		game_state,
		submit_command,
		cmd,
		ctx,
		"survival-run→%s" % target_cell,
	):
		_note_move_dedup(target_cell)
		_settled_in_cover = false
		_contact_bound_active = false
		PerceptionCacheClass.move_commands += 1
		return
	_survival_issue_single_steps(game_state, find_path, submit_command, target_cell)


func _survival_issue_single_steps(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	goal_cell: Vector2i,
) -> void:
	for soldier in _living_soldiers(game_state):
		if not _has_command_budget():
			break
		if soldier.is_moving:
			continue
		var step := _survival_step_toward_cell(game_state, soldier.grid_position, goal_cell)
		if step.x <= -900 or step == soldier.grid_position:
			continue
		var cmd := MoveCommandClass.new()
		cmd.team_id = soldier.team_id
		cmd.soldier_id = soldier.soldier_id
		cmd.target_cell = step
		cmd.scope = MoveCommandClass.Scope.SINGLE
		cmd.movement_mode = MovementModeClass.RUN
		if _submit_ai(
			game_state,
			submit_command,
			cmd,
			_make_survival_context(find_path),
			"survival-step %d→%s" % [soldier.soldier_id, step],
		):
			PerceptionCacheClass.move_commands += 1


func _ensure_survival_ge_lines_objective(game_state) -> void:
	var obj := AiSectorObjectivesClass.survival_ge_lines_objective(game_state)
	if obj.is_valid():
		current_objective = obj


func _survival_assault_one_soldier(
	game_state,
	find_path: Callable,
	submit_command: Callable,
	visible: Array,
	known: Array,
) -> void:
	if not _has_command_budget():
		return
	var soldiers := _living_soldiers(game_state)
	if soldiers.is_empty():
		return
	soldiers.sort_custom(func(a, b) -> bool:
		if a.soldier_id != b.soldier_id:
			return a.soldier_id < b.soldier_id
		return a.grid_position.x < b.grid_position.x
	)
	var idx := _survival_bound_soldier_idx % soldiers.size()
	_survival_bound_soldier_idx += 1
	var soldier = soldiers[idx]
	var push_cell := _survival_push_cell(game_state, visible, known)
	if push_cell.x <= -900:
		return
	var from_cell: Vector2i = soldier.grid_position
	var threat_cell := _survival_threat_cell(game_state, [], visible, known)
	var target: Vector2i = push_cell
	var mode := MovementModeClass.RUN
	var label := "survival-assault"
	## Bound to a covered stand when one lies between us and the enemy; only rush the last
	## open stretch. Declining falls through to the direct step — the wave never stops
	## attacking, it just stops crossing open ground in a straight line.
	var cover := _survival_cover_bound_cell(game_state, from_cell, threat_cell, push_cell)
	if cover.x > -900:
		target = cover
		mode = _cover_approach_mode(game_state)
		label = "survival-bound"
	else:
		var dist := absi(from_cell.x - push_cell.x) + absi(from_cell.y - push_cell.y)
		if dist > 1:
			target = _survival_step_toward_cell(game_state, from_cell, push_cell)
	if target.x <= -900 or target == from_cell:
		return
	_clear_move_dedup()
	var cmd := MoveCommandClass.new()
	cmd.team_id = soldier.team_id
	cmd.soldier_id = soldier.soldier_id
	cmd.target_cell = target
	cmd.scope = MoveCommandClass.Scope.SINGLE
	cmd.movement_mode = mode
	if _submit_ai(
		game_state,
		submit_command,
		cmd,
		_make_survival_context(find_path),
		"%s %d→%s" % [label, soldier.soldier_id, target],
	):
		_note_move_dedup(target)
		PerceptionCacheClass.move_commands += 1


## Cover stand for one survival assault bound. Reuses the contact-bound rules:
## directional cover vs the threat, short of the threat, and strictly closer to the push
## target — no sideways or backward bounds, so the wave still closes on the objective.
## Returns (-999, -999) to decline, which leaves the caller on its direct step.
func _survival_cover_bound_cell(
	game_state,
	from_cell: Vector2i,
	threat_cell: Vector2i,
	push_cell: Vector2i,
) -> Vector2i:
	var none := Vector2i(-999, -999)
	if threat_cell.x <= -900 or push_cell.x <= -900:
		return none
	if game_state == null or game_state.map_data == null:
		return none
	## Already behind something vs this threat — fire from here rather than re-bounding.
	if AiSectorObjectivesClass.stand_covered_vs_threat(
		from_cell, threat_cell, game_state.map_data
	):
		return none
	var cover := AiSectorObjectivesClass.nearest_cover_within(
		game_state,
		from_cell,
		threat_cell,
		SURVIVAL_ASSAULT_COVER_SEEK,
		[],
		false,
		true,
	)
	if cover.x <= -900 or cover == from_cell:
		return none
	if not _cover_is_short_of_threat(from_cell, cover, threat_cell):
		return none
	var old_dist := absi(from_cell.x - push_cell.x) + absi(from_cell.y - push_cell.y)
	var new_dist := absi(cover.x - push_cell.x) + absi(cover.y - push_cell.y)
	if new_dist >= old_dist:
		return none
	return cover


func _survival_threat_cell(
	game_state,
	reaction: Array,
	visible: Array,
	known: Array,
) -> Vector2i:
	var threat = _select_best_threat(game_state, reaction)
	if threat != null:
		return threat.grid_position
	threat = _select_best_threat(game_state, visible)
	if threat != null:
		return threat.grid_position
	threat = _select_best_threat(game_state, known)
	if threat != null:
		return threat.grid_position
	return Vector2i(-999, -999)


func _survival_step_toward_cell(
	game_state,
	from_cell: Vector2i,
	goal_cell: Vector2i,
) -> Vector2i:
	var map_data = game_state.map_data
	if map_data == null:
		return Vector2i(-999, -999)
	var step := from_cell + Vector2i(
		signi(goal_cell.x - from_cell.x),
		signi(goal_cell.y - from_cell.y),
	)
	if map_data.is_walkable(step) and step != from_cell:
		return step
	var best := Vector2i(-999, -999)
	var best_d := 999999
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var alt: Vector2i = from_cell + offset
		if not map_data.is_walkable(alt):
			continue
		var d := absi(alt.x - goal_cell.x) + absi(alt.y - goal_cell.y)
		if d < best_d:
			best_d = d
			best = alt
	return best


func _survival_step_toward_objective(
	game_state,
	from_cell: Vector2i,
	objective_cell: Vector2i,
) -> Vector2i:
	return _survival_step_toward_cell(game_state, from_cell, objective_cell)


func _try_survival_grenade(
	game_state,
	submit_command: Callable,
	visible: Array,
	known: Array,
) -> bool:
	var pool: Array = visible if not visible.is_empty() else known
	if pool.is_empty() or not _has_command_budget():
		return false
	var threat = _select_best_threat(game_state, pool)
	if threat == null:
		return false
	var impact: Vector2i = threat.grid_position
	var team_id: int = game_state.command_hierarchy.get_team_id(player_id)
	if CombatSystem.grenade_would_hit_friendly(game_state, team_id, impact):
		return false
	for soldier in _living_soldiers(game_state):
		if soldier.grenade_count <= 0 or soldier.has_pending_grenade():
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
		if _submit_ai(
			game_state,
			submit_command,
			cmd,
			_make_context(Callable()),
			"survival-grenade %d→%s" % [soldier.soldier_id, impact],
		):
			return true
	return false


## Heavy fire → crawl into cover; otherwise dash. Distinct from soft suppression.
func _under_heavy_fire(game_state) -> bool:
	return _fireteam_avg_stress(game_state) >= STRESS_HEAVY_FIRE


## Tactical choice only. The engine will execute RUN even when pinned or panicked;
## crawl here is the brain preferring a quieter approach under heavy fire.
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

## Assign living soldiers to behind-cover stands spread along the hold line.
## Prefer a wall-facing screen vs the enemy approach — not a stacked 2×2 blob.
func _assign_defensive_posts(game_state, hold_options: Array) -> void:
	_defensive_posts.clear()
	var soldiers := _living_soldiers(game_state)
	if soldiers.is_empty() or current_objective == null or not current_objective.is_valid():
		return
	var primary := current_objective.cell
	var approach := AiSectorObjectivesClass.enemy_approach_cell(game_state, player_id)
	## Optional nearby hold seeds widen the candidate search slightly.
	var search_centers: Array[Vector2i] = [primary]
	for opt in hold_options:
		if opt == null or not opt.is_valid():
			continue
		var kind := str(opt.kind)
		if kind != "hold" and kind != "cover":
			continue
		if opt.cell == primary:
			continue
		if maxi(absi(opt.cell.x - primary.x), absi(opt.cell.y - primary.y)) > DEFENSIVE_POST_CLUSTER:
			continue
		search_centers.append(opt.cell)
	var candidates := _collect_defend_post_candidates(game_state, search_centers, approach)
	var posts := _spread_defend_posts(game_state, candidates, soldiers.size(), primary, approach)
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


## Covered stands near the hold, facing the enemy approach.
func _collect_defend_post_candidates(
	game_state,
	search_centers: Array[Vector2i],
	approach: Vector2i,
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var map_data = game_state.map_data if game_state != null else null
	if map_data == null or search_centers.is_empty():
		return out
	var seen: Dictionary = {}
	var checks := 0
	for stand in map_data.get_cover_stand_cells():
		var near_hold := false
		for center in search_centers:
			if maxi(absi(stand.x - center.x), absi(stand.y - center.y)) <= DEFENSIVE_POST_CLUSTER:
				near_hold = true
				break
		if not near_hold or seen.has(stand):
			continue
		if approach.x > -900:
			if checks >= 160:
				break
			checks += 1
			AiSectorObjectivesClass.cover_checks_this_think += 1
			if not AiSectorObjectivesClass.stand_covered_vs_threat(stand, approach, map_data):
				continue
		seen[stand] = true
		out.append(stand)
	return out


## Spread posts along the axis perpendicular to the enemy approach (along the wall).
func _spread_defend_posts(
	game_state,
	candidates: Array[Vector2i],
	count: int,
	primary: Vector2i,
	approach: Vector2i,
) -> Array[Vector2i]:
	var posts: Array[Vector2i] = []
	if count <= 0:
		return posts
	var map_data = game_state.map_data if game_state != null else null
	## Fallback lateral axis = perpendicular to enemy approach.
	var ax := 1
	var ay := 0
	if approach.x > -900:
		ax = approach.x - primary.x
		ay = approach.y - primary.y
	var lx := -ay
	var ly := ax
	if lx == 0 and ly == 0:
		lx = 1
	var pool: Array[Vector2i] = []
	if not candidates.is_empty():
		## Prefer true behind-cover stands when we have enough to spread.
		var behind: Array[Vector2i] = []
		for stand in candidates:
			if (
				approach.x > -900
				and map_data != null
				and AiSectorObjectivesClass.stand_is_directly_behind(stand, approach, map_data)
			):
				behind.append(stand)
		pool = behind if behind.size() >= count else candidates.duplicate()
		## Spread along the cover line's long axis (wall length), not into a blob.
		var min_x := pool[0].x
		var max_x := pool[0].x
		var min_y := pool[0].y
		var max_y := pool[0].y
		for stand in pool:
			min_x = mini(min_x, stand.x)
			max_x = maxi(max_x, stand.x)
			min_y = mini(min_y, stand.y)
			max_y = maxi(max_y, stand.y)
		if max_x - min_x >= max_y - min_y:
			lx = 1
			ly = 0
		else:
			lx = 0
			ly = 1
		pool.sort_custom(func(a, b) -> bool:
			var pa: int = a.x * lx + a.y * ly
			var pb: int = b.x * lx + b.y * ly
			if pa != pb:
				return pa < pb
			var da := absi(a.x - primary.x) + absi(a.y - primary.y)
			var db := absi(b.x - primary.x) + absi(b.y - primary.y)
			if da != db:
				return da < db
			if a.x != b.x:
				return a.x < b.x
			return a.y < b.y
		)
		if count == 1:
			## Lone dig-in: pick nearest to primary among spaced pool.
			var best := pool[0]
			var best_d := 999999
			for stand in pool:
				var d := absi(stand.x - primary.x) + absi(stand.y - primary.y)
				if d < best_d:
					best_d = d
					best = stand
			posts.append(best)
		else:
			for i in count:
				var target_idx := int(round(float(i) * float(pool.size() - 1) / float(count - 1)))
				var picked := _pick_spaced_from_pool(pool, target_idx, posts, primary)
				if picked.x > -900:
					posts.append(picked)
	## Fill gaps with lateral walkable offsets if cover was sparse.
	var plen := maxf(1.0, sqrt(float(lx * lx + ly * ly)))
	var ux := float(lx) / plen
	var uy := float(ly) / plen
	var step := 0
	while posts.size() < count and step < 24:
		var side := 1 if (step % 2) == 0 else -1
		var mag := ((step / 2) + 1) * DEFENSIVE_POST_MIN_SEP
		var offset := Vector2i(int(round(ux * float(side * mag))), int(round(uy * float(side * mag))))
		if offset == Vector2i.ZERO:
			offset = Vector2i(side * mag, 0)
		var cell := primary + offset
		if map_data != null and not map_data.is_walkable(cell):
			step += 1
			continue
		if (
			cell not in posts
			and _post_fits_cluster(cell, posts, primary)
			and _post_has_min_sep(cell, posts)
		):
			posts.append(cell)
		step += 1
	## Last resort — allow closer posts rather than leaving soldiers unassigned.
	while posts.size() < count:
		var fallback := primary + Vector2i(posts.size() % 3 - 1, posts.size() / 3)
		if map_data != null and not map_data.is_walkable(fallback):
			fallback = primary
		if fallback in posts:
			fallback = primary + Vector2i(posts.size(), 0)
		posts.append(fallback)
	return posts


func _pick_spaced_from_pool(
	pool: Array[Vector2i],
	target_idx: int,
	posts: Array[Vector2i],
	primary: Vector2i,
) -> Vector2i:
	if pool.is_empty():
		return Vector2i(-999, -999)
	var none := Vector2i(-999, -999)
	var best_sep := none
	var best_sep_delta := 999999
	var best_any := none
	var best_any_delta := 999999
	for idx in pool.size():
		var cell: Vector2i = pool[idx]
		if cell in posts or not _post_fits_cluster(cell, posts, primary):
			continue
		var delta := absi(idx - target_idx)
		if _post_has_min_sep(cell, posts):
			if delta < best_sep_delta:
				best_sep_delta = delta
				best_sep = cell
		elif delta < best_any_delta:
			best_any_delta = delta
			best_any = cell
	if best_sep.x > -900:
		return best_sep
	return best_any

func _post_has_min_sep(cell: Vector2i, posts: Array[Vector2i]) -> bool:
	for other in posts:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) < DEFENSIVE_POST_MIN_SEP:
			return false
	return true


func _post_fits_cluster(cell: Vector2i, posts: Array[Vector2i], primary: Vector2i) -> bool:
	if maxi(absi(cell.x - primary.x), absi(cell.y - primary.y)) > DEFENSIVE_POST_CLUSTER:
		return false
	for other in posts:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) > FIRETEAM_COHESION_RADIUS:
			return false
	return true


## Defending means holding COVER, so every soldier has to be standing in some.
##
## The old version had three ways to call a squad "posted" while it stood in the open: an
## empty post table fell back to the formation centre being within two tiles of the
## objective, a soldier with no assigned post was skipped outright, and arrival was
## measured against a tile rather than against cover. All three ended the same way — the
## fireteam stopping a square short of the wall and lying down there.
## Stands have to exist before we can ask whether anybody is standing on one. Lazy so no
## caller can forget: an unassigned table used to mean "posted", which is how a squad
## claimed to be holding while stood in the open.
##
## When the map offers no cover at all, _assign_defensive_posts falls every soldier back to
## the objective cell itself — so holding in the open stays possible, it just stops being
## the answer whenever real cover was available and simply not taken.
func _ensure_defensive_posts(game_state) -> void:
	if not _defensive_posts.is_empty():
		return
	if current_objective == null or not current_objective.is_valid():
		return
	_assign_defensive_posts(game_state, [current_objective])


func _defensive_posts_reached(game_state) -> bool:
	var soldiers := _living_soldiers(game_state)
	if soldiers.is_empty():
		return true
	## Nothing assigned yet (replan has not run) — fall back to the objective. Assignment is
	## a mutation and belongs in _move_to_defensive_posts, not in a read-only query.
	if _defensive_posts.is_empty():
		return _objective_reached(game_state)
	var map_data = game_state.map_data if game_state != null else null
	var approach := AiSectorObjectivesClass.enemy_approach_cell(game_state, player_id)
	for soldier in soldiers:
		## Any stand that covers the approach counts — posts get swapped or blocked, and what
		## matters is being in cover, not on one particular tile.
		if _in_cover_vs_approach(soldier.grid_position, approach, map_data):
			continue
		var post: Vector2i = _defensive_posts.get(soldier.soldier_id, Vector2i(-999, -999))
		if post.x > -900 and soldier.grid_position == post:
			continue
		return false
	return true


func _move_to_defensive_posts(
	game_state,
	find_path: Callable,
	submit_command: Callable,
) -> void:
	## Drifting to the objective cell only ever gets the fireteam *near* cover, which is the
	## whole problem — work out the stands first.
	_ensure_defensive_posts(game_state)
	if _defensive_posts.is_empty():
		_move_toward_objective(game_state, find_path, submit_command)
		return
	if not _has_command_budget():
		return
	var sorted: Array = _living_soldiers(game_state)
	sorted.sort_custom(func(a, b) -> bool: return a.soldier_id < b.soldier_id)
	var post_map_data = game_state.map_data if game_state != null else null
	var post_approach := AiSectorObjectivesClass.enemy_approach_cell(game_state, player_id)
	for soldier in sorted:
		if not _has_command_budget():
			return
		if soldier.is_moving:
			continue
		var post: Vector2i = _defensive_posts.get(soldier.soldier_id, Vector2i(-999, -999))
		if post.x <= -900:
			## Nothing assigned to this man — put him in the nearest stand facing the approach
			## instead of leaving him standing in the open next to the fireteam.
			post = AiSectorObjectivesClass.nearest_cover_within(
				game_state,
				soldier.grid_position,
				post_approach,
				COVER_SEEK_MAX_DIST,
				[],
				false,
				true,
			)
			if post.x <= -900:
				continue
			_defensive_posts[soldier.soldier_id] = post
		var d := absi(soldier.grid_position.x - post.x) + absi(soldier.grid_position.y - post.y)
		## Close the last tile — stopping short of the stand leaves the soldier in the open.
		if d <= COVER_POST_ARRIVE_DIST:
			continue
		if _in_cover_vs_approach(soldier.grid_position, post_approach, post_map_data):
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


func _make_survival_context(find_path: Callable) -> CommandContextClass:
	var ctx := _make_context(find_path)
	ctx.survival_ge_advance = true
	return ctx
