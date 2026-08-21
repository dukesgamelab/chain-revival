class_name SurvivalModeController
extends RefCounted
## Survival Mode: 1 v All — timed GE reinforcements toward the US objective.

const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const FireControlStateClass := preload("res://scripts/enums/fire_control_state.gd")
const MatchConfigClass := preload("res://scripts/core/match_config.gd")

const WAVE_INTERVAL_SEC := 60.0
const SOLDIERS_PER_WAVE := 4

var wave_count: int = 1
var wave_timer_sec: float = 0.0
var next_player_id: int = 3
var next_ge_soldier_id_base: int = 5
var last_spawned_fireteam: Fireteam = null


func reset() -> void:
	wave_count = 1
	wave_timer_sec = 0.0
	next_player_id = 3
	next_ge_soldier_id_base = 5
	last_spawned_fireteam = null


static func is_active(match_config) -> bool:
	if match_config == null:
		return false
	return match_config.is_survival_1v_all()


static func us_objective_cell(map_data) -> Vector2i:
	if map_data == null:
		return Vector2i(-999, -999)
	for entry in map_data.victory_points:
		if entry is Dictionary:
			return Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
	if not map_data.team_1_spawn_points.is_empty():
		var anchor := map_data.team_1_spawn_points[0]
		return anchor
	return Vector2i(21, 16)


static func pick_wave_spawn_cells(map_data, wave_index: int) -> Array[Vector2i]:
	var pool: Array[Vector2i] = map_data.team_2_spawn_points.duplicate()
	if pool.is_empty():
		pool.assign([
			Vector2i(30, 70),
			Vector2i(31, 70),
			Vector2i(32, 70),
			Vector2i(30, 71),
		])
	var out: Array[Vector2i] = []
	var start := ((wave_index - 1) * SOLDIERS_PER_WAVE) % maxi(pool.size(), 1)
	for i in SOLDIERS_PER_WAVE:
		out.append(pool[(start + i) % pool.size()])
	return out


static func count_deployed_enemy_fireteams(session) -> int:
	## Fireteams with at least one living German soldier on the field.
	if session == null:
		return 0
	var count := 0
	for ft in session.owned_fireteams_for_team(Team.GERMANY):
		for state in ft.soldiers:
			if state != null and not state.is_dead:
				count += 1
				break
	return count


func time_until_next_wave() -> float:
	return maxf(0.0, WAVE_INTERVAL_SEC - wave_timer_sec)


func process_tick(
	game_state,
	session,
	enable_ai_commander: Callable,
) -> String:
	if game_state == null or session == null:
		return ""
	if game_state.scenario_ended or game_state.is_deployment_phase():
		return ""
	wave_timer_sec += SimulationClock.tick_sec()
	if wave_timer_sec < WAVE_INTERVAL_SEC:
		return ""
	wave_timer_sec = 0.0
	wave_count += 1
	return spawn_reinforcement_wave(game_state, session, enable_ai_commander)


func spawn_reinforcement_wave(
	game_state,
	session,
	enable_ai_commander: Callable,
) -> String:
	var map_data = game_state.map_data
	var spawn_cells := pick_wave_spawn_cells(map_data, wave_count)
	var soldier_ids: Array[int] = []
	for i in SOLDIERS_PER_WAVE:
		soldier_ids.append(next_ge_soldier_id_base + i)
	next_ge_soldier_id_base += SOLDIERS_PER_WAVE

	var next_ft_id := session.owned_fireteams.size() + 1
	var ft := Fireteam.create_owned(
		next_ft_id,
		next_player_id,
		Team.GERMANY,
		soldier_ids,
		spawn_cells,
	)
	next_player_id += 1

	session.append_owned_fireteam(ft)
	last_spawned_fireteam = ft
	_register_wave_player(game_state, ft, wave_count)
	_bootstrap_wave_soldiers(game_state, ft)
	game_state.rebuild_object_registry()
	game_state.rebuild_cell_occupancy()
	for state in ft.soldiers:
		CombatSystem.notify_soldier_perception_dirty(game_state, state)

	if enable_ai_commander.is_valid():
		enable_ai_commander.call(ft.owner_player_id)

	return (
		"Survival wave %d: German reinforcements inbound (%d soldiers)."
		% [wave_count, ft.soldiers.size()]
	)


func _register_wave_player(game_state, ft: Fireteam, wave_num: int) -> void:
	var soldier_ids: Array[int] = []
	for state in ft.soldiers:
		soldier_ids.append(int(state.soldier_id))
	var display_name := "GE Wave %d" % wave_num
	game_state.command_hierarchy.register_player(
		display_name,
		1,
		Team.GERMANY,
		true,
		soldier_ids,
		ft.owner_player_id,
	)
	game_state.command_hierarchy.set_selected_ai_plan(
		ft.owner_player_id,
		AiPlanClass.ID_ATTACK_CENTER,
	)
	game_state.resolve_ai_plans()
	game_state.weapon_cache.bootstrap_player_cache(ft.owner_player_id, Team.GERMANY)


func _bootstrap_wave_soldiers(game_state, ft: Fireteam) -> void:
	var objective := us_objective_cell(game_state.map_data)
	for state in ft.soldiers:
		if objective.x > -900:
			state.facing_direction = FacingDirection.toward_cell(
				state.grid_position,
				objective,
			)
		state.fire_control_state = FireControlStateClass.FIRE_AT_WILL
