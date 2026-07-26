class_name ScenarioRules
extends RefCounted
## Authoritative scenario clock, kill/VP scoring, and end resolution.
## Driven from SimulationClock ticks — never wall-clock time.
## Uses untyped game_state params to avoid a class_name cycle with GameState/CombatSystem.

const ScenarioEndCauseClass := preload("res://scripts/enums/scenario_end_cause.gd")
const ScenarioWinnerClass := preload("res://scripts/enums/scenario_winner.gd")
## Mirrors GameState.MatchPhase.ENDED (DEPLOYMENT=0, RUNNING=1, ENDED=2).
const _MATCH_PHASE_ENDED := 2

## RECOVERED TimeBased = 15 minutes.
const SCENARIO_TIME_SEC := 15 * 60
## RECOVERED INITPPconstOnKill / GPP_const_OnKill.
const KILL_POINTS := 4
## RECOVERED INITPPLostOnKilledSoldier.
const PP_LOST_PER_SOLDIER := 1
## RECOVERED SpecArea->PP_const (terrain hold — used as end-of-mission VP award unit scale).
const SPEC_AREA_POINTS := 1
## RECOVERED GPP->PP_const (in-scenario → career, 1:1).
const GPP_TO_PP := 1
## RECOVERED CheckVPTilesEach ≈ 1s — TUNED poll interval (exact OG cadence unrecovered).
const VP_POLL_INTERVAL_SEC := 1.0
## TUNED: linear decay from 100% at t=0 to this floor at TIME_GONE.
## Fact of decay is RECOVERED (`VP AsSoonAsYouCanDecr = 5`); exact curve is not.
const VP_DECAY_FLOOR := 0.25
## TUNED retreat rule (exact OG arithmetic UNKNOWN): retreating side loses the field;
## winner = non-retreating side; both sides keep earned kill/VP scores on the debrief.


## Called once when leaving deployment → Scenario Running.
static func begin_scenario(game_state) -> void:
	if game_state == null:
		return
	game_state.scenario_time_remaining_sec = float(SCENARIO_TIME_SEC)
	game_state.scenario_elapsed_sec = 0.0
	game_state.team_kill_points.clear()
	game_state.team_terrain_points.clear()
	game_state.team_kill_points[Team.USA] = 0
	game_state.team_kill_points[Team.GERMANY] = 0
	game_state.team_terrain_points[Team.USA] = 0
	game_state.team_terrain_points[Team.GERMANY] = 0
	game_state.end_cause = ScenarioEndCauseClass.NONE
	game_state.winner = ScenarioWinnerClass.NONE
	game_state.scenario_ended = false
	game_state._vp_poll_accum_sec = 0.0
	VictoryPointSystem.ensure_holders_initialized(game_state.map_data)
	## Seed capture timestamps so initial holders keep full value if held to the end.
	for entry in game_state.map_data.victory_points:
		if entry is Dictionary:
			entry["capture_elapsed_sec"] = 0.0


## Advance clock + VP poll from one SimulationClock tick. Returns true if scenario just ended.
static func process_tick(game_state, tick_sec: float) -> bool:
	if game_state == null or game_state.scenario_ended:
		return false
	if game_state.is_deployment_phase() or game_state.is_ended_phase():
		return false

	game_state.scenario_elapsed_sec += tick_sec
	game_state.scenario_time_remaining_sec = maxf(
		0.0,
		float(SCENARIO_TIME_SEC) - game_state.scenario_elapsed_sec,
	)

	game_state._vp_poll_accum_sec += tick_sec
	if game_state._vp_poll_accum_sec >= VP_POLL_INTERVAL_SEC:
		game_state._vp_poll_accum_sec = 0.0
		if VictoryPointSystem.update_capture(game_state, game_state.scenario_elapsed_sec):
			game_state.vp_holders_dirty = true

	if living_soldier_count(game_state, Team.USA) <= 0:
		_award_held_victory_points(game_state)
		return end_scenario(game_state, ScenarioEndCauseClass.EXTERMINATION, ScenarioWinnerClass.GERMANY)
	if living_soldier_count(game_state, Team.GERMANY) <= 0:
		_award_held_victory_points(game_state)
		return end_scenario(game_state, ScenarioEndCauseClass.EXTERMINATION, ScenarioWinnerClass.USA)

	if game_state.scenario_time_remaining_sec <= 0.0:
		return _end_by_score(game_state, ScenarioEndCauseClass.TIME_GONE)

	return false


## Authoritative kill scoring — call after mark_killed from combat.
static func on_soldier_killed(
	game_state,
	killer_team_id: int,
	victim: SoldierState,
) -> void:
	if game_state == null or victim == null or game_state.scenario_ended:
		return
	if killer_team_id == Team.USA or killer_team_id == Team.GERMANY:
		_add_kill_points(game_state, killer_team_id, KILL_POINTS)
		_award_killer_player_pp(game_state, killer_team_id, victim, KILL_POINTS * GPP_TO_PP)
	## Victim team loses PP_LOST_PER_SOLDIER from team score (RECOVERED).
	_add_kill_points(game_state, victim.team_id, -PP_LOST_PER_SOLDIER)
	## TODO(multiplayer): apply PP_LOST_ON_KILLED_BY_RANK + MC distribution to career PP
	## when full multiplayer career persistence is wired. Model constants live on CommandHierarchy.


static func request_retreat(game_state, retreating_team_id: int) -> bool:
	if game_state == null or game_state.scenario_ended:
		return false
	## TUNED: retreating side loses the field; winner = non-retreating side.
	## Both sides keep earned kill/terrain points on the debrief.
	var winner := (
		ScenarioWinnerClass.GERMANY
		if retreating_team_id == Team.USA
		else ScenarioWinnerClass.USA
	)
	var cause := (
		ScenarioEndCauseClass.WE_RETREATED
		if retreating_team_id == game_state.local_team_id()
		else ScenarioEndCauseClass.ENEMY_RETREATED
	)
	_award_held_victory_points(game_state)
	return end_scenario(game_state, cause, winner)


static func end_scenario(game_state, cause: int, winner: int) -> bool:
	if game_state == null or game_state.scenario_ended:
		return false
	game_state.scenario_ended = true
	game_state.end_cause = cause
	game_state.winner = winner
	game_state.match_phase = _MATCH_PHASE_ENDED
	game_state.scenario_time_remaining_sec = maxf(0.0, game_state.scenario_time_remaining_sec)
	## Prefer GameLog autoload when the tree is up; print keeps headless/unit paths visible.
	var line := (
		"[Scenario] END cause=%s winner=%s usa=%d ger=%d"
		% [
			ScenarioEndCauseClass.short_name(cause),
			ScenarioWinnerClass.display_name(winner),
			total_points(game_state, Team.USA),
			total_points(game_state, Team.GERMANY),
		]
	)
	print(line)
	return true


static func time_remaining(game_state) -> float:
	if game_state == null:
		return 0.0
	return maxf(0.0, game_state.scenario_time_remaining_sec)


static func total_points(game_state, team_id: int) -> int:
	if game_state == null:
		return 0
	return (
		int(game_state.team_kill_points.get(team_id, 0))
		+ int(game_state.team_terrain_points.get(team_id, 0))
	)


static func living_soldier_count(game_state, team_id: int) -> int:
	if game_state == null or game_state.session == null:
		return 0
	var ft: Fireteam = game_state.session.get_fireteam(team_id)
	if ft == null:
		return 0
	var n := 0
	for state in ft.soldiers:
		var s: SoldierState = state
		if s != null and not s.is_dead:
			n += 1
	return n


## TUNED decay curve — RECOVERED that decay exists; formula is not.
static func vp_decay_factor(elapsed_sec: float) -> float:
	var t := clampf(elapsed_sec / float(SCENARIO_TIME_SEC), 0.0, 1.0)
	return lerpf(1.0, VP_DECAY_FLOOR, t)


static func effective_vp_award(base_points: float, capture_elapsed_sec: float) -> int:
	var scaled := base_points * vp_decay_factor(capture_elapsed_sec) * float(SPEC_AREA_POINTS)
	return int(round(scaled))


static func _end_by_score(game_state, cause: int) -> bool:
	_award_held_victory_points(game_state)
	var usa := total_points(game_state, Team.USA)
	var ger := total_points(game_state, Team.GERMANY)
	var winner := ScenarioWinnerClass.DRAW
	if usa > ger:
		winner = ScenarioWinnerClass.USA
	elif ger > usa:
		winner = ScenarioWinnerClass.GERMANY
	return end_scenario(game_state, cause, winner)


static func _award_held_victory_points(game_state) -> void:
	if game_state == null or game_state.map_data == null:
		return
	VictoryPointSystem.ensure_holders_initialized(game_state.map_data)
	game_state.team_terrain_points[Team.USA] = 0
	game_state.team_terrain_points[Team.GERMANY] = 0
	for entry in game_state.map_data.victory_points:
		if not entry is Dictionary:
			continue
		var holder := str(entry.get("holder", entry.get("initial_holder", "Germany")))
		var capture_t := float(entry.get("capture_elapsed_sec", game_state.scenario_elapsed_sec))
		var team_id := Team.USA if VictoryPointSystem.holder_is_usa(holder) else Team.GERMANY
		var base := (
			float(entry.get("us_points", 0.0))
			if team_id == Team.USA
			else float(entry.get("gm_points", 0.0))
		)
		var award := effective_vp_award(base, capture_t)
		game_state.team_terrain_points[team_id] = (
			int(game_state.team_terrain_points.get(team_id, 0)) + award
		)


static func _add_kill_points(game_state, team_id: int, delta: int) -> void:
	var cur := int(game_state.team_kill_points.get(team_id, 0))
	game_state.team_kill_points[team_id] = cur + delta


static func _award_killer_player_pp(
	game_state,
	killer_team_id: int,
	_victim: SoldierState,
	pp: int,
) -> void:
	if game_state.command_hierarchy == null or pp <= 0:
		return
	## Single-player / offline: award the team's human player (or first player on team).
	var recipient := -1
	for pid in game_state.command_hierarchy.all_player_ids():
		if game_state.command_hierarchy.get_team_id(pid) != killer_team_id:
			continue
		if not game_state.command_hierarchy.is_ai_player(pid):
			recipient = pid
			break
		if recipient < 0:
			recipient = pid
	if recipient > 0:
		## TODO(multiplayer): full MC payout path when career PP persistence is wired.
		game_state.command_hierarchy.distribute_pp_award(recipient, pp)
