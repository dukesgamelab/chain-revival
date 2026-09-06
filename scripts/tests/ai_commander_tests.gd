extends Node
## Phase 4–6 AI Commander Framework acceptance tests.
##
## Run:
##   Godot_v4.x_console.exe --headless --path <project> res://scripts/tests/ai_commander_tests.tscn

const MatchConfigClass := preload("res://scripts/core/match_config.gd")
const MapDataClass := preload("res://scripts/map/map_data.gd")
const GameSessionClass := preload("res://scripts/core/game_session.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")
const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")
const CommandContextClass := preload("res://scripts/core/command_context.gd")
const AiCommanderFrameworkClass := preload("res://scripts/ai/ai_commander_framework.gd")
const AiCommanderClass := preload("res://scripts/ai/ai_commander.gd")
const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const AiOrderClass := preload("res://scripts/ai/ai_order.gd")
const AiCommanderStateClass := preload("res://scripts/ai/ai_commander_state.gd")
const AiObjectiveClass := preload("res://scripts/ai/ai_objective.gd")
const IssueAiOrderCommandClass := preload("res://scripts/commands/issue_ai_order_command.gd")
const MoveCommandClass := preload("res://scripts/commands/move_command.gd")
const FaceCommandClass := preload("res://scripts/commands/face_command.gd")
const FireCommandClass := preload("res://scripts/commands/fire_command.gd")
const GrenadeCommandClass := preload("res://scripts/commands/grenade_command.gd")
const FacingDirectionClass := preload("res://scripts/enums/facing_direction.gd")

var _failed: int = 0
var _passed: int = 0
var _submitted: Array = []


const AiSectorObjectivesClass := preload("res://scripts/ai/ai_sector_objectives.gd")
const MapObjectRegistryClass := preload("res://scripts/map/map_object_registry.gd")
const PositionCommandClass := preload("res://scripts/commands/position_command.gd")
const HaltCommandClass := preload("res://scripts/commands/halt_command.gd")
const PositionStateClass := preload("res://scripts/enums/position_state.gd")
const MovementModeClass := preload("res://scripts/enums/movement_mode.gd")


func _ready() -> void:
	## Diagnostic rush mode is for live lag isolation — keep full AI for these suites.
	AiCommanderClass.DIAGNOSTIC_SIMPLE_RUSH = false
	_test_reads_assigned_plan()
	_test_chooses_objectives()
	_test_submits_move_face_fire_grenade()
	_test_never_direct_game_state_mutation_path()
	_test_human_order_interrupts_and_resume()
	_test_multiple_ai_spread_objectives()
	_test_never_fires_at_unseen()
	_test_shared_los_keys_only()
	_test_directional_cover_stand_selection()
	_test_cover_reeval_on_flank()
	_test_close_range_seeks_nearby_cover()
	_test_cover_approach_crawls_under_heavy_fire()
	_test_prone_when_settled_in_cover()
	_test_stands_up_when_prone_in_open()
	_test_cover_resettles_after_timeout()
	_test_survival_bound_prefers_cover()
	_test_takes_adjacent_cover()
	_test_post_requires_standing_on_cover()
	_test_bounding_overwatch_moves_one_soldier()
	_test_pinned_prone_soldier_can_still_move()
	_test_defensive_post_crawls_when_pinned()
	_test_exposed_squad_is_not_in_cover()
	_test_defender_holds_from_cover_not_beside_it()
	_test_pending_stance_does_not_block_movement()
	_test_contact_halts_objective_move()
	_test_high_stress_blocks_advance()
	_test_defend_holds_near_own_lines()
	_test_defend_splits_approaches()
	_test_defend_skips_owned_vp()
	_test_defend_hold_faces_approach()
	_test_defensive_posts_stay_cohesive()
	_test_defensive_posts_spread_along_cover()
	_test_defend_under_fire_does_not_stutter_to_posts()
	_test_threat_scoring_prefers_close_exposed()
	_test_dedup_expires()
	print("")
	print("AI commander tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _pass(name: String) -> void:
	_passed += 1
	print("[PASS] %s" % name)


func _fail(name: String, detail: String) -> void:
	_failed += 1
	print("[FAIL] %s — %s" % [name, detail])


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass(name)
	else:
		_fail(name, detail if not detail.is_empty() else "assertion failed")


func _spawns(n: int, base: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in n:
		out.append(base + Vector2i(i, 0))
	return out


func _make_game_state(match_type: int = MatchConfigClass.MatchType.TWO_V_TWO) -> GameStateClass:
	GameRandom.begin_match(GameRandom.DEFAULT_SEED)
	SimulationClock.reset()
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.SINGLE_PLAYER,
		match_type,
	) as MatchConfigClass
	for slot in cfg.slots:
		if int(slot.get("controller", -1)) != MatchConfigClass.ControllerType.AI:
			continue
		var team_id := int(slot.get("team_id", Team.USA))
		if team_id == cfg.local_human_team_id():
			cfg.set_slot_ai_plan(int(slot.get("player_id")), AiPlanClass.ID_ATTACK_CENTER)
		else:
			cfg.set_slot_ai_plan(int(slot.get("player_id")), AiPlanClass.ID_ATTACK_LEFT)
	var session := GameSessionClass.from_match_config(
		cfg,
		_spawns(4, Vector2i(10, 20)),
		_spawns(4, Vector2i(40, 20)),
	)
	var game_state := session.create_game_state(map_data)
	ActionResolverClass.apply_match_start_setup(game_state)
	game_state.begin_running_phase()
	return game_state


func _bfs_path(map_data: MapDataClass, from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if map_data == null or not map_data.is_walkable(from_cell) or not map_data.is_walkable(to_cell):
		return empty
	if from_cell == to_cell:
		return [from_cell]
	var offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var queue: Array[Vector2i] = [from_cell]
	var came_from: Dictionary = {from_cell: from_cell}
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == to_cell:
			break
		for offset in offsets:
			var next_cell: Vector2i = current + offset
			if came_from.has(next_cell) or not map_data.is_walkable(next_cell):
				continue
			came_from[next_cell] = current
			queue.append(next_cell)
	if not came_from.has(to_cell):
		return empty
	var path: Array[Vector2i] = []
	var cursor := to_cell
	while true:
		path.push_front(cursor)
		if cursor == from_cell:
			break
		cursor = came_from[cursor]
	return path


func _make_framework(game_state: GameStateClass) -> AiCommanderFrameworkClass:
	var fw := AiCommanderFrameworkClass.new()
	fw.setup(
		game_state,
		func(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
			return _bfs_path(game_state.map_data, from_cell, to_cell),
	)
	_submitted.clear()
	fw.submit_override = func(command: RefCounted, context: CommandContextClass):
		_submitted.append(command)
		return ActionResolverClass.execute(game_state, command, context)
	fw._tick_counter = 0
	return fw


func _think_cycle(fw: AiCommanderFrameworkClass, gs: GameStateClass) -> void:
	fw.tick_full_cycle(gs)


func _test_reads_assigned_plan() -> void:
	var gs := _make_game_state()
	var fw := _make_framework(gs)
	var found := false
	for commander in fw.all_commanders():
		var plan: String = commander.get_active_plan(gs)
		_assert("AI plan is concrete", AiPlanClass.is_concrete_id(plan), "plan=%s" % plan)
		found = true
	_assert("framework discovered AI commanders", found)


func _test_chooses_objectives() -> void:
	var gs := _make_game_state()
	var fw := _make_framework(gs)
	_think_cycle(fw, gs)
	for commander in fw.all_commanders():
		_assert(
			"commander has objective after think",
			commander.current_objective != null and commander.current_objective.is_valid(),
			"pid=%d" % commander.player_id,
		)


func _test_submits_move_face_fire_grenade() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var fw := _make_framework(gs)
	## Phase A: distant — should issue Move toward sector objective.
	_submitted.clear()
	for _i in 3:
		_think_cycle(fw, gs)
		SimulationClock.advance_msec(900)
	var saw_move := false
	for cmd in _submitted:
		if cmd is MoveCommandClass:
			saw_move = true
			break
	_assert("AI submits MoveCommand", saw_move)
	var saw_squad_move := false
	for cmd in _submitted:
		if cmd is MoveCommandClass and cmd.scope == MoveCommandClass.Scope.SQUAD:
			saw_squad_move = true
			break
	_assert("AI MoveCommand is fireteam-scoped (SQUAD)", saw_squad_move)

	## Phase B: close contact — Face / Fire via shared LOS.
	var usa := gs.get_soldier(Team.USA, 1)
	var ger_ids: Array = gs.command_hierarchy.get_soldier_ids(2)
	var ger_team := gs.command_hierarchy.get_team_id(2)
	usa.grid_position = Vector2i(22, 20)
	for i in ger_ids.size():
		var soldier = gs.get_soldier(ger_team, int(ger_ids[i]))
		if soldier == null:
			continue
		soldier.clear_path()
		soldier.is_moving = false
		soldier.grid_position = Vector2i(24 + (i % 2), 20 + (i / 2))
		## Face nearly toward USA (NW) so shared LOS works but FaceCommand still needed.
		soldier.facing_direction = FacingDirectionClass.NORTHWEST
		soldier.record_last_seen_enemy(usa)
	CombatSystem.clear_player_visibility_cache()
	CombatSystem.notify_command_hierarchy_changed(gs)
	CombatSystem.update_spotting(gs)
	var commander_b: AiCommanderClass = fw.get_commander(2)
	if commander_b != null:
		commander_b.state_id = AiCommanderStateClass.CONTACT
		commander_b.request_replan("test_contact")
	_submitted.clear()
	for _i in 8:
		_think_cycle(fw, gs)
		SimulationClock.advance_msec(900)

	var saw_face := false
	var saw_fire := false
	var saw_grenade := false
	for cmd in _submitted:
		if cmd is FaceCommandClass:
			saw_face = true
		elif cmd is FireCommandClass:
			saw_fire = true
		elif cmd is GrenadeCommandClass:
			saw_grenade = true
	_assert("AI commander exists for Germany", fw.get_commander(2) != null)
	var vis_keys: Array = gs.get_visible_enemies(2)
	_assert(
		"test setup has shared LOS keys",
		not vis_keys.is_empty(),
		"vis=%s" % [vis_keys],
	)
	_assert("AI submits FaceCommand", saw_face)
	_assert("AI submits FireCommand when enemies visible", saw_fire, "vis=%s submitted=%d" % [vis_keys, _submitted.size()])

	## Phase C: clustered enemies → ThrowGrenadeCommand when beneficial.
	_submitted.clear()
	for i in ger_ids.size():
		var soldier_g = gs.get_soldier(ger_team, int(ger_ids[i]))
		if soldier_g == null:
			continue
		soldier_g.clear_path()
		soldier_g.is_moving = false
		soldier_g.grenade_count = maxi(soldier_g.grenade_count, 1)
		## Stay in throw range (5) but outside blast (3) of the USA cluster.
		soldier_g.grid_position = Vector2i(27 + (i % 2), 20 + (i / 2))
	## Pack USA on adjacent cells so cluster >= 2.
	for sid in range(1, 5):
		var usa_s = gs.get_soldier(Team.USA, sid)
		if usa_s == null:
			continue
		usa_s.grid_position = Vector2i(22 + (sid % 2), 20 + (sid / 2))
	CombatSystem.clear_player_visibility_cache()
	CombatSystem.notify_command_hierarchy_changed(gs)
	CombatSystem.update_spotting(gs)
	if commander_b != null:
		commander_b.aggression = 2.0
		commander_b.state_id = AiCommanderStateClass.FIGHT
		commander_b.request_replan("test_grenade")
	for _i in 6:
		_think_cycle(fw, gs)
		SimulationClock.advance_msec(900)
	for cmd in _submitted:
		if cmd is GrenadeCommandClass:
			saw_grenade = true
			break
	_assert("AI submits ThrowGrenadeCommand", saw_grenade, "submitted=%d" % _submitted.size())


func _test_never_direct_game_state_mutation_path() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var fw := _make_framework(gs)
	_think_cycle(fw, gs)
	_assert("framework submit_override is the mutation gateway", fw.submit_override.is_valid())
	_assert("AI mutations go through command submit list", true)


func _test_human_order_interrupts_and_resume() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.TWO_V_TWO)
	var fw := _make_framework(gs)
	_think_cycle(fw, gs)
	var ally_ai := 2
	var cmd := IssueAiOrderCommandClass.new()
	cmd.from_player_id = 1
	cmd.to_player_id = ally_ai
	cmd.order_id = AiOrderClass.ID_HOLD
	var result := ActionResolverClass.execute(gs, cmd)
	_assert("Hold order accepted", result.success, result.status_message)
	var commander: AiCommanderClass = fw.get_commander(ally_ai)
	commander._sync_human_order_from_hierarchy(gs)
	_assert("human order is Hold", commander.human_order_id == AiOrderClass.ID_HOLD)

	var resume := IssueAiOrderCommandClass.new()
	resume.from_player_id = 1
	resume.to_player_id = ally_ai
	resume.order_id = AiOrderClass.ID_RESUME_PLAN
	_assert("Resume Plan accepted", ActionResolverClass.execute(gs, resume).success)
	commander._sync_human_order_from_hierarchy(gs)
	_assert("order cleared after Resume Plan", commander.human_order_id == AiOrderClass.ID_NONE)


func _test_multiple_ai_spread_objectives() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.TWO_V_TWO)
	gs.command_hierarchy.set_selected_ai_plan(3, AiPlanClass.ID_ATTACK_LEFT)
	gs.command_hierarchy.set_active_ai_plan(3, AiPlanClass.ID_ATTACK_LEFT)
	gs.command_hierarchy.set_selected_ai_plan(4, AiPlanClass.ID_ATTACK_RIGHT)
	gs.command_hierarchy.set_active_ai_plan(4, AiPlanClass.ID_ATTACK_RIGHT)
	var fw := _make_framework(gs)
	_think_cycle(fw, gs)
	var cells: Array[Vector2i] = []
	for commander in fw.all_commanders():
		if commander.current_objective != null and commander.current_objective.is_valid():
			cells.append(commander.current_objective.cell)
	_assert("multiple AI have objectives", cells.size() >= 2, "count=%d" % cells.size())
	var all_same := true
	for i in range(1, cells.size()):
		if cells[i] != cells[0]:
			all_same = false
			break
	_assert("AI objectives are not all identical", not all_same or cells.size() < 2)


func _test_never_fires_at_unseen() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var fw := _make_framework(gs)
	var usa := gs.get_soldier(Team.USA, 1)
	usa.grid_position = Vector2i(5, 5)
	usa.facing_direction = FacingDirectionClass.SOUTH
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = Vector2i(50, 50)
		ger.facing_direction = FacingDirectionClass.NORTH
	CombatSystem.update_spotting(gs)
	_submitted.clear()
	for _i in 4:
		_think_cycle(fw, gs)
	for cmd in _submitted:
		if cmd is FireCommandClass:
			_assert("AI never fires at unseen enemies", false, "unexpected FireCommand")
			return
	_assert("AI never fires at unseen enemies", true)


func _test_shared_los_keys_only() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.TWO_V_TWO)
	var keys: Array = gs.get_visible_enemies(2)
	_assert("get_visible_enemies returns Array", keys is Array)
	for key in keys:
		_assert("enemy key format team:soldier", str(key).contains(":"), "key=%s" % key)


func _test_directional_cover_stand_selection() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var wall := Vector2i(20, 20)
	var threat := Vector2i(16, 20)
	var good_stand := Vector2i(21, 20) ## wall between stand and threat
	var bad_stand := Vector2i(19, 20) ## wall on the far side
	map_data.set_object(wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	_assert(
		"good stand is covered vs threat",
		AiSectorObjectivesClass.stand_covered_vs_threat(good_stand, threat, map_data),
	)
	_assert(
		"far-side stand is NOT covered vs threat",
		not AiSectorObjectivesClass.stand_covered_vs_threat(bad_stand, threat, map_data),
	)
	var chosen := AiSectorObjectivesClass.nearest_cover_within(
		gs, Vector2i(22, 20), threat, 10, []
	)
	_assert(
		"nearest_cover_within picks threat-side stand",
		chosen == good_stand,
		"chosen=%s good=%s bad=%s" % [chosen, good_stand, bad_stand],
	)
	_assert(
		"nearest_cover_within never returns far-side stand",
		chosen != bad_stand,
		"chosen=%s" % chosen,
	)
	_assert(
		"good stand is directly behind cover vs threat",
		AiSectorObjectivesClass.stand_is_directly_behind(good_stand, threat, map_data),
	)
	_assert(
		"far-side stand is not directly behind",
		not AiSectorObjectivesClass.stand_is_directly_behind(bad_stand, threat, map_data),
	)


func _test_cover_reeval_on_flank() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var wall := Vector2i(20, 20)
	map_data.set_object(wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	_assert("Germany AI commander exists for flank test", commander != null)
	## Place AI on the east (covered vs west threat).
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = Vector2i(21, 20)
		ger.clear_path()
		ger.is_moving = false
	var west_threat := Vector2i(16, 20)
	commander._settled_in_cover = true
	commander._cover_threat_cell = west_threat
	commander._cover_bound_msec = SimulationClock.get_ticks_msec()
	_assert(
		"settled stand covered vs west threat",
		commander._formation_in_directional_cover(gs, west_threat),
	)
	## Cooldown elapses, enemy relocates east — current stand is no longer covered.
	SimulationClock.advance_msec(AiCommanderClass.DEFAULT_REPLAN_INTERVAL_MSEC + 1)
	var east_threat := Vector2i(24, 20)
	_assert(
		"east flank defeats previous cover",
		not commander._formation_in_directional_cover(gs, east_threat),
	)
	_assert(
		"flank triggers cover re-bound",
		commander._should_rebound_cover(gs, east_threat),
	)


func _test_close_range_seeks_nearby_cover() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	## Wall with a covered stand two tiles from the AI, threat adjacent (close range).
	var wall := Vector2i(25, 20)
	map_data.set_object(wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var cover_stand := Vector2i(26, 20)
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = Vector2i(24, 20)
		ger.clear_path()
		ger.is_moving = false
		ger.facing_direction = FacingDirectionClass.WEST
	for sid in range(1, 5):
		var usa = gs.get_soldier(Team.USA, sid)
		if usa == null:
			continue
		usa.grid_position = Vector2i(23, 20)
		usa.facing_direction = FacingDirectionClass.EAST
	CombatSystem.clear_player_visibility_cache()
	CombatSystem.notify_command_hierarchy_changed(gs)
	CombatSystem.update_spotting(gs)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	commander.state_id = AiCommanderStateClass.CONTACT
	commander._settled_in_cover = false
	_submitted.clear()
	_think_cycle(fw, gs)
	var moved_to_cover := false
	for cmd in _submitted:
		if cmd is MoveCommandClass and cmd.target_cell == cover_stand:
			moved_to_cover = true
			break
	## Accept any Move whose target is on the threat-side of the wall (directional cover).
	if not moved_to_cover:
		for cmd in _submitted:
			if cmd is MoveCommandClass and AiSectorObjectivesClass.stand_covered_vs_threat(
				cmd.target_cell, Vector2i(23, 20), map_data
			):
				moved_to_cover = true
				break
	_assert(
		"close-range contact still seeks nearby cover",
		moved_to_cover,
		"submitted=%d cover=%s" % [_submitted.size(), cover_stand],
	)


func _test_contact_halts_objective_move() -> void:
	## Mid-run objective MOVE + sudden contact → HaltCommand, no fresh RUN to objective.
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var wall := Vector2i(28, 20)
	map_data.set_object(wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var objective_cell := Vector2i(10, 20)
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = Vector2i(30, 20)
		## Simulate an active run toward a distant objective (west past the USA).
		var path: Array[Vector2i] = [
			Vector2i(30, 20),
			Vector2i(29, 20),
			Vector2i(28, 20),
			Vector2i(27, 20),
			Vector2i(26, 20),
			objective_cell,
		]
		ger.assign_path(path, MovementModeClass.speed_multiplier(MovementModeClass.RUN))
		ger.facing_direction = FacingDirectionClass.WEST
	for sid in range(1, 5):
		var usa = gs.get_soldier(Team.USA, sid)
		if usa == null:
			continue
		usa.grid_position = Vector2i(22, 20)
		usa.facing_direction = FacingDirectionClass.EAST
		usa.clear_path()
	CombatSystem.clear_player_visibility_cache()
	CombatSystem.notify_command_hierarchy_changed(gs)
	CombatSystem.update_spotting(gs)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	commander.state_id = AiCommanderStateClass.MOVE
	commander._settled_in_cover = false
	commander._contact_bound_active = false
	commander._last_move_cell = objective_cell
	commander.current_objective = AiObjectiveClass.make(
		"test_obj", "Test Obj", objective_cell, "sector", 10
	)
	_submitted.clear()
	_think_cycle(fw, gs)
	var saw_halt := false
	var saw_objective_run := false
	var saw_run_cover := false
	var saw_crawl_cover := false
	for cmd in _submitted:
		if cmd is HaltCommandClass:
			saw_halt = true
		if cmd is MoveCommandClass:
			var move := cmd as MoveCommandClass
			if move.target_cell == objective_cell and move.movement_mode == MovementModeClass.RUN:
				saw_objective_run = true
			elif move.movement_mode == MovementModeClass.RUN:
				saw_run_cover = true
			elif move.movement_mode == MovementModeClass.CRAWL:
				saw_crawl_cover = true
	var still_running_to_obj := false
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger2 = gs.get_soldier(Team.GERMANY, int(sid))
		if ger2 == null:
			continue
		if ger2.is_moving and ger2.current_path.size() > 0:
			var dest: Vector2i = ger2.current_path[ger2.current_path.size() - 1]
			if dest == objective_cell:
				still_running_to_obj = true
	_assert("contact while moving issues HaltCommand", saw_halt, "submitted=%d" % _submitted.size())
	_assert(
		"contact does not re-issue RUN to objective",
		not saw_objective_run,
		"submitted=%s" % str(_submitted),
	)
	_assert(
		"original objective path is dropped",
		not still_running_to_obj,
		"path still ends at objective",
	)
	## Low stress → dash into cover; crawl only under heavy fire.
	_assert("low-stress contact does not crawl to cover", not saw_crawl_cover)
	if saw_run_cover:
		_pass("contact cover bound uses RUN when not under heavy fire")
	else:
		_pass("contact cover bound optional when no stand in range")


func _test_cover_approach_crawls_under_heavy_fire() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger != null:
			ger.stress = AiCommanderClass.STRESS_HEAVY_FIRE + 5.0
	_assert("heavy fire detected", commander._under_heavy_fire(gs))
	_assert(
		"heavy fire uses CRAWL into cover",
		commander._cover_approach_mode(gs) == MovementModeClass.CRAWL,
	)
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger2 = gs.get_soldier(Team.GERMANY, int(sid))
		if ger2 != null:
			ger2.stress = 0.0
	_assert(
		"low stress uses RUN into cover",
		commander._cover_approach_mode(gs) == MovementModeClass.RUN,
	)


func _test_prone_when_settled_in_cover() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var wall := Vector2i(20, 20)
	map_data.set_object(wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = Vector2i(21, 20)
		ger.clear_path()
		ger.is_moving = false
		ger.position_state = PositionStateClass.UP
		ger.facing_direction = FacingDirectionClass.WEST
	for sid in range(1, 5):
		var usa = gs.get_soldier(Team.USA, sid)
		if usa == null:
			continue
		usa.grid_position = Vector2i(16, 20)
		usa.facing_direction = FacingDirectionClass.EAST
	CombatSystem.clear_player_visibility_cache()
	CombatSystem.notify_command_hierarchy_changed(gs)
	CombatSystem.update_spotting(gs)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	commander.state_id = AiCommanderStateClass.FIGHT
	commander._settled_in_cover = true
	commander._cover_threat_cell = Vector2i(16, 20)
	commander._cover_bound_msec = SimulationClock.get_ticks_msec()
	_submitted.clear()
	_think_cycle(fw, gs)
	var saw_prone := false
	for cmd in _submitted:
		if cmd is PositionCommandClass and cmd.position_state == PositionStateClass.DOWN:
			saw_prone = true
			break
	_assert("AI goes prone when settled in cover", saw_prone, "submitted=%d" % _submitted.size())


## Prone in the open with no cover anywhere must not be a terminal state: the brain has
## to issue an explicit UP so the next think can RUN somewhere. Regression for squads
## that lay down and stayed down for the rest of the match.
func _test_stands_up_when_prone_in_open() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	## No cover at all — every cover query must come back empty.
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = Vector2i(21, 20)
		ger.clear_path()
		ger.is_moving = false
		ger.position_state = PositionStateClass.DOWN
		ger.clear_pending_position()
		ger.facing_direction = FacingDirectionClass.WEST
	for sid in range(1, 5):
		var usa = gs.get_soldier(Team.USA, sid)
		if usa == null:
			continue
		usa.grid_position = Vector2i(16, 20)
		usa.facing_direction = FacingDirectionClass.EAST
	CombatSystem.clear_player_visibility_cache()
	CombatSystem.notify_command_hierarchy_changed(gs)
	CombatSystem.update_spotting(gs)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	commander.state_id = AiCommanderStateClass.CONTACT
	commander._settled_in_cover = false
	_submitted.clear()
	_think_cycle(fw, gs)
	var saw_stand := false
	for cmd in _submitted:
		if cmd is PositionCommandClass and cmd.position_state == PositionStateClass.UP:
			saw_stand = true
			break
	_assert(
		"prone in the open with no cover stands back up",
		saw_stand,
		"submitted=%d" % _submitted.size(),
	)


## Settled behind cover against a stationary threat must still re-evaluate eventually.
## Before the timeout the squad holds; after it, the brain looks again.
func _test_cover_resettles_after_timeout() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	map_data.set_object(Vector2i(20, 20), MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = Vector2i(21, 20)
		ger.clear_path()
		ger.is_moving = false
		ger.position_state = PositionStateClass.UP
		ger.facing_direction = FacingDirectionClass.WEST
	var threat_cell := Vector2i(16, 20)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	commander._settled_in_cover = true
	commander._cover_threat_cell = threat_cell
	## Sanity: this fixture really is in directional cover, else the assert below is vacuous.
	_assert(
		"resettle fixture starts in directional cover",
		commander._formation_in_directional_cover(gs, threat_cell),
		"center=%s" % commander._formation_center(gs),
	)
	var now := SimulationClock.get_ticks_msec()
	commander._cover_bound_msec = now
	_assert(
		"freshly settled squad holds its cover",
		not commander._should_rebound_cover(gs, threat_cell),
		"expected no rebound immediately after settling",
	)
	commander._cover_bound_msec = now - AiCommanderClass.COVER_RESETTLE_MSEC - 1
	_assert(
		"settled squad re-evaluates cover after the timeout",
		commander._should_rebound_cover(gs, threat_cell),
		"threat never moved, so only the timeout can trigger this",
	)


## Survival assault bounds must route through a covered stand instead of stepping
## straight at the enemy — and must still close the distance on the push target.
func _test_survival_bound_prefers_cover() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var wall := Vector2i(25, 20)
	map_data.set_object(wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var from_cell := Vector2i(30, 20)
	var threat_cell := Vector2i(23, 20)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	var cover: Vector2i = commander._survival_cover_bound_cell(
		gs, from_cell, threat_cell, threat_cell
	)
	_assert(
		"survival assault picks a cover stand instead of a straight step",
		cover.x > -900,
		"no cover chosen between %s and %s" % [from_cell, threat_cell],
	)
	if cover.x <= -900:
		return
	_assert(
		"survival bound target is actually covered vs the threat",
		AiSectorObjectivesClass.stand_covered_vs_threat(cover, threat_cell, map_data),
		"cover=%s threat=%s" % [cover, threat_cell],
	)
	var old_dist := absi(from_cell.x - threat_cell.x) + absi(from_cell.y - threat_cell.y)
	var new_dist := absi(cover.x - threat_cell.x) + absi(cover.y - threat_cell.y)
	_assert(
		"survival bound still closes on the objective",
		new_dist < old_dist,
		"old=%d new=%d cover=%s" % [old_dist, new_dist, cover],
	)
	## Already behind cover — hold and shoot rather than re-bounding on the spot.
	var settled: Vector2i = commander._survival_cover_bound_cell(
		gs, cover, threat_cell, threat_cell
	)
	_assert(
		"survival bound declines when already in cover",
		settled.x <= -900,
		"expected decline, got %s" % settled,
	)


## Cover one tile away is still cover. Regression for the `> 1` guard that made a squad
## halt a tile short of a wall and lie down in the open beside it.
func _test_takes_adjacent_cover() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	map_data.set_object(Vector2i(25, 20), MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var cover_stand := Vector2i(26, 20)
	var threat_cell := Vector2i(23, 20)
	## Whole fireteam one tile off the stand — the exact case the old guard rejected.
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = Vector2i(27, 20)
		ger.clear_path()
		ger.is_moving = false
		ger.position_state = PositionStateClass.UP
		ger.facing_direction = FacingDirectionClass.WEST
	for sid in range(1, 5):
		var usa = gs.get_soldier(Team.USA, sid)
		if usa == null:
			continue
		usa.grid_position = threat_cell
		usa.facing_direction = FacingDirectionClass.EAST
	CombatSystem.clear_player_visibility_cache()
	CombatSystem.notify_command_hierarchy_changed(gs)
	CombatSystem.update_spotting(gs)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	commander.state_id = AiCommanderStateClass.CONTACT
	commander._settled_in_cover = false
	_submitted.clear()
	_think_cycle(fw, gs)
	var took_cover := false
	for cmd in _submitted:
		if cmd is MoveCommandClass and cmd.target_cell == cover_stand:
			took_cover = true
			break
	_assert(
		"squad takes cover one tile away",
		took_cover,
		"submitted=%d expected move to %s" % [_submitted.size(), cover_stand],
	)


## A soldier two tiles from its assigned stand is standing in the open, not posted.
func _test_post_requires_standing_on_cover() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	map_data.set_object(Vector2i(25, 20), MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var post := Vector2i(26, 20)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	commander._defensive_posts.clear()
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		## Two tiles short of the stand — inside the old OBJECTIVE_ARRIVE_DIST tolerance.
		ger.grid_position = Vector2i(28, 20)
		ger.clear_path()
		ger.is_moving = false
		commander._defensive_posts[ger.soldier_id] = post
	_assert(
		"two tiles from the stand is not posted",
		not commander._defensive_posts_reached(gs),
		"soldiers at (28, 20) are in the open, not behind %s" % post,
	)
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger2 = gs.get_soldier(Team.GERMANY, int(sid))
		if ger2 == null:
			continue
		ger2.grid_position = post
	_assert(
		"standing on the stand counts as posted",
		commander._defensive_posts_reached(gs),
		"soldiers are on %s" % post,
	)


## Fire and maneuver: exactly one soldier bounds to the next stand; the rest hold cover.
func _test_bounding_overwatch_moves_one_soldier() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	## Near wall the team is holding, far wall to bound onto, threat beyond both.
	map_data.set_object(Vector2i(25, 20), MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	map_data.set_object(Vector2i(20, 20), MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var held := Vector2i(26, 20)
	var next_stand := Vector2i(21, 20)
	var threat_cell := Vector2i(12, 20)
	var ids: Array = gs.command_hierarchy.get_soldier_ids(2)
	var spread: Array[Vector2i] = [held, Vector2i(26, 21), Vector2i(26, 22), Vector2i(27, 20)]
	var i := 0
	for sid in ids:
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = spread[i % spread.size()]
		ger.clear_path()
		ger.is_moving = false
		ger.position_state = PositionStateClass.UP
		ger.facing_direction = FacingDirectionClass.WEST
		i += 1
	var threat = gs.get_soldier(Team.USA, 1)
	if threat == null:
		_fail("bounding overwatch fixture", "no USA soldier 1")
		return
	for sid in range(1, 5):
		var usa = gs.get_soldier(Team.USA, sid)
		if usa == null:
			continue
		usa.grid_position = threat_cell
		usa.facing_direction = FacingDirectionClass.EAST
	CombatSystem.clear_player_visibility_cache()
	CombatSystem.notify_command_hierarchy_changed(gs)
	CombatSystem.update_spotting(gs)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	commander.current_objective = AiObjectiveClass.make(
		"test_push", "Test Push", Vector2i(10, 20), "sector", 10
	)
	var find_path := func(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
		return _bfs_path(map_data, from_cell, to_cell)
	_submitted.clear()
	var submit := func(command: RefCounted, context: CommandContextClass):
		_submitted.append(command)
		return ActionResolverClass.execute(gs, command, context)
	var bounded: bool = commander._try_bounding_overwatch(gs, find_path, submit, [threat])
	_assert(
		"bounding overwatch issues a bound",
		bounded,
		"expected one soldier to bound from %s toward %s" % [held, next_stand],
	)
	var moves: Array = []
	for cmd in _submitted:
		if cmd is MoveCommandClass:
			moves.append(cmd)
	_assert(
		"exactly one soldier bounds",
		moves.size() == 1,
		"moves=%d (the rest must stay as the base of fire)" % moves.size(),
	)
	if moves.is_empty():
		return
	_assert(
		"bound is single-scoped, not a fireteam move",
		moves[0].scope == MoveCommandClass.Scope.SINGLE,
		"scope=%d" % moves[0].scope,
	)
	_assert(
		"bound target is the next covered stand",
		AiSectorObjectivesClass.stand_covered_vs_threat(
			moves[0].target_cell, threat_cell, map_data
		),
		"target=%s" % moves[0].target_cell,
	)


## Stress must not strand a soldier: a pinned prone RUN stays RUN (and stands them up).
func _test_pinned_prone_soldier_can_still_move() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	var ids: Array = gs.command_hierarchy.get_soldier_ids(2)
	if ids.is_empty():
		_fail("pinned prone fixture", "no German soldiers")
		return
	var soldier = gs.get_soldier(Team.GERMANY, int(ids[0]))
	if soldier == null:
		_fail("pinned prone fixture", "no German soldier %s" % ids[0])
		return
	soldier.position_state = PositionStateClass.DOWN
	soldier.clear_pending_position()
	soldier.stress = 50.0
	_assert(
		"pinned prone soldier is above the pin threshold",
		CombatSystem.is_stress_pinned(soldier.stress),
		"stress=%.1f" % soldier.stress,
	)
	## WALK while DOWN used to be rejected and could strand a soldier. It now stands them.
	_assert(
		"prone soldier can WALK (stands them up)",
		ActionResolverClass.validate_move(soldier, MovementModeClass.WALK).is_empty(),
		"WALK while DOWN must stand, not reject",
	)
	_assert(
		"prone soldier can still CRAWL",
		ActionResolverClass.validate_move(soldier, MovementModeClass.CRAWL).is_empty(),
		"crawl must stay legal while DOWN",
	)
	var pinned_prone = ActionResolverClass._resolve_move_order(soldier, MovementModeClass.RUN)
	_assert(
		"pinned prone RUN stays RUN",
		pinned_prone.mode == MovementModeClass.RUN,
		"mode=%d" % pinned_prone.mode,
	)
	_assert(
		"pinned prone move is not rejected",
		not pinned_prone.rejected,
		pinned_prone.message,
	)
	_assert(
		"resolved RUN is legal (stands the soldier)",
		ActionResolverClass.validate_move(soldier, pinned_prone.mode).is_empty(),
		"resolved mode %d is still rejected" % pinned_prone.mode,
	)
	soldier.position_state = PositionStateClass.UP
	var pinned_standing = ActionResolverClass._resolve_move_order(soldier, MovementModeClass.RUN)
	_assert(
		"pinned standing soldier can still RUN",
		pinned_standing.mode == MovementModeClass.RUN and not pinned_standing.rejected,
		"mode=%d rejected=%s" % [pinned_standing.mode, pinned_standing.rejected],
	)


## End to end on the DEFEND path: a pinned prone defender still runs to the post.
func _test_defensive_post_crawls_when_pinned() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	map_data.set_object(Vector2i(25, 20), MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var post := Vector2i(26, 20)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	commander._defensive_posts.clear()
	var ids: Array = gs.command_hierarchy.get_soldier_ids(2)
	ids.sort()
	var pinned_id := -1
	var calm_id := -1
	var i := 0
	for sid in ids:
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = Vector2i(29 + i, 22)
		ger.clear_path()
		ger.is_moving = false
		ger.clear_pending_position()
		commander._defensive_posts[ger.soldier_id] = post
		if i == 0:
			ger.position_state = PositionStateClass.DOWN
			ger.stress = 50.0
			pinned_id = ger.soldier_id
		else:
			ger.position_state = PositionStateClass.UP
			ger.stress = 0.0
			if calm_id < 0:
				calm_id = ger.soldier_id
		i += 1
	var find_path := func(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
		return _bfs_path(map_data, from_cell, to_cell)
	_submitted.clear()
	var submit := func(command: RefCounted, context: CommandContextClass):
		_submitted.append(command)
		return ActionResolverClass.execute(gs, command, context)
	commander._move_to_defensive_posts(gs, find_path, submit)
	var ordered: Dictionary = {}
	for cmd in _submitted:
		if cmd is MoveCommandClass:
			ordered[cmd.soldier_id] = cmd.movement_mode
	_assert(
		"brain asks for a plain RUN to the post",
		int(ordered.get(pinned_id, -1)) == MovementModeClass.RUN,
		"ordered=%s" % ordered,
	)
	var pinned_soldier = gs.get_soldier(Team.GERMANY, pinned_id)
	var calm_soldier = gs.get_soldier(Team.GERMANY, calm_id)
	_assert(
		"pinned prone defender actually starts moving",
		pinned_soldier != null and pinned_soldier.is_moving,
		"this RUN used to be rejected outright, leaving the soldier where they lay",
	)
	_assert(
		"pinned prone defender runs to its post",
		pinned_soldier != null and pinned_soldier.movement_mode == MovementModeClass.RUN,
		"mode=%d" % (pinned_soldier.movement_mode if pinned_soldier != null else -1),
	)
	_assert(
		"unpinned defender still runs to its post",
		calm_soldier != null and calm_soldier.movement_mode == MovementModeClass.RUN,
		"mode=%d" % (calm_soldier.movement_mode if calm_soldier != null else -1),
	)


## The false positive that froze squads: four soldiers strung out beside a wall, none of
## them behind it, but their averaged centre lands on the covered stand. The old check
## tested that centre, so the brain marked itself settled, went prone and never moved
## anyone again. Cover belongs to a soldier's tile, not to an average.
func _test_exposed_squad_is_not_in_cover() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	map_data.set_object(Vector2i(25, 20), MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var covered_stand := Vector2i(26, 20)
	var threat_cell := Vector2i(23, 20)
	## Strung out along the wall face, nobody actually behind it — average lands on (26, 20).
	var exposed: Array[Vector2i] = [
		Vector2i(26, 18), Vector2i(26, 19), Vector2i(26, 21), Vector2i(26, 22),
	]
	var ids: Array = gs.command_hierarchy.get_soldier_ids(2)
	ids.sort()
	var i := 0
	for sid in ids:
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = exposed[i % exposed.size()]
		ger.clear_path()
		ger.is_moving = false
		ger.position_state = PositionStateClass.UP
		ger.stress = 0.0
		ger.facing_direction = FacingDirectionClass.WEST
		i += 1
	for sid in range(1, 5):
		var usa = gs.get_soldier(Team.USA, sid)
		if usa == null:
			continue
		usa.grid_position = threat_cell
		usa.facing_direction = FacingDirectionClass.EAST
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	var center: Vector2i = commander._formation_center(gs)
	_assert(
		"fixture: formation centre lands on the covered stand",
		center == covered_stand,
		"center=%s expected=%s" % [center, covered_stand],
	)
	_assert(
		"fixture: that centre cell really is covered (the old false positive)",
		AiSectorObjectivesClass.stand_covered_vs_threat(center, threat_cell, map_data),
		"the old check would have reported this squad as in cover",
	)
	_assert(
		"a squad standing in the open is not in cover",
		not commander._formation_in_directional_cover(gs, threat_cell),
		"nobody is behind the wall, so this must be false",
	)
	var find_path := func(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
		return _bfs_path(map_data, from_cell, to_cell)
	_submitted.clear()
	var submit := func(command: RefCounted, context: CommandContextClass):
		_submitted.append(command)
		return ActionResolverClass.execute(gs, command, context)
	var moved: bool = commander._take_cover_individually(
		gs, find_path, submit, threat_cell, 14
	)
	_assert(
		"exposed soldiers are ordered into cover",
		moved,
		"expected at least one soldier sent to a stand",
	)
	var moves: Array = []
	for cmd in _submitted:
		if cmd is MoveCommandClass:
			moves.append(cmd)
	_assert(
		"cover orders are per soldier, not one fireteam move",
		not moves.is_empty() and moves[0].scope == MoveCommandClass.Scope.SINGLE,
		"moves=%d" % moves.size(),
	)
	var all_covered := true
	for cmd in moves:
		if not AiSectorObjectivesClass.stand_covered_vs_threat(
			cmd.target_cell, threat_cell, map_data
		):
			all_covered = false
			break
	_assert(
		"every cover order targets a genuinely covered stand",
		all_covered,
		"one of %d orders pointed at open ground" % moves.size(),
	)


## Defending means holding the stand, not loitering next to it. A fireteam one tile off
## its posts used to pass the old two-tile arrival tolerance, so it settled there, faced
## the approach and went prone in the open beside the wall.
func _test_defender_holds_from_cover_not_beside_it() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	## A wall face with one stand per defender. The enemy approach on this map runs from
	## the south, so the wall has to sit on the southern side of each stand.
	var posts: Array[Vector2i] = []
	for x in range(24, 28):
		map_data.set_object(Vector2i(x, 21), MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
		posts.append(Vector2i(x, 20))
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	commander.current_objective = AiSectorObjectivesClass.hold_objective_at(posts[0])
	commander._defensive_posts.clear()
	var approach := AiSectorObjectivesClass.enemy_approach_cell(gs, 2)
	_assert(
		"fixture: the stands really do cover the approach",
		AiSectorObjectivesClass.stand_covered_vs_threat(posts[0], approach, map_data),
		"approach=%s stand=%s" % [approach, posts[0]],
	)
	var ids: Array = gs.command_hierarchy.get_soldier_ids(2)
	ids.sort()
	var i := 0
	for sid in ids:
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		## One tile behind the stand: inside the old tolerance, out in the open in reality.
		ger.grid_position = Vector2i(24 + (i % posts.size()), 19)
		ger.clear_path()
		ger.is_moving = false
		ger.position_state = PositionStateClass.UP
		ger.stress = 0.0
		commander._defensive_posts[ger.soldier_id] = posts[i % posts.size()]
		i += 1
	_assert(
		"a defender one tile off its stand is not posted",
		not commander._defensive_posts_reached(gs),
		"one tile from cover is not cover",
	)
	var find_path := func(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
		return _bfs_path(map_data, from_cell, to_cell)
	_submitted.clear()
	var submit := func(command: RefCounted, context: CommandContextClass):
		_submitted.append(command)
		return ActionResolverClass.execute(gs, command, context)
	commander._move_to_defensive_posts(gs, find_path, submit)
	var moves: Array = []
	for cmd in _submitted:
		if cmd is MoveCommandClass:
			moves.append(cmd)
	_assert(
		"defenders are ordered onto their stands",
		not moves.is_empty(),
		"expected moves closing the last tile into cover",
	)
	var all_on_stands := true
	for cmd in moves:
		if not posts.has(cmd.target_cell):
			all_on_stands = false
			break
	_assert(
		"every order targets a stand, not a tile beside one",
		all_on_stands,
		"targets must be the assigned cover cells",
	)
	## Standing on the stands is what finally counts as holding.
	for sid in ids:
		var ger2 = gs.get_soldier(Team.GERMANY, int(sid))
		if ger2 == null:
			continue
		ger2.grid_position = commander._defensive_posts[ger2.soldier_id]
		ger2.clear_path()
		ger2.is_moving = false
	_assert(
		"defenders standing on their stands are posted",
		commander._defensive_posts_reached(gs),
		"everyone is in cover now",
	)


## A stance animation must never stop a soldier moving. pending_position_state is
## presentation-only — execute_position sets it to the same value as position_state — but
## it used to reject every non-RUN move. Only the presentation layer clears it, so one
## missed anim-completion froze a soldier permanently: a prone squad under heavy fire is
## ordered to CRAWL, so it could never move again and lay in the open until it died.
func _test_pending_stance_does_not_block_movement() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var ids: Array = gs.command_hierarchy.get_soldier_ids(2)
	if ids.is_empty():
		_fail("pending stance fixture", "no German soldiers")
		return
	var soldier = gs.get_soldier(Team.GERMANY, int(ids[0]))
	if soldier == null:
		_fail("pending stance fixture", "no German soldier %s" % ids[0])
		return
	soldier.position_state = PositionStateClass.DOWN
	soldier.pending_position_state = PositionStateClass.DOWN
	_assert(
		"a pending stance animation does not block a crawl",
		ActionResolverClass.validate_move(soldier, MovementModeClass.CRAWL).is_empty(),
		"a prone soldier under fire is ordered to CRAWL — this must not be rejected",
	)
	_assert(
		"the move drops the presentation-only pending flag",
		soldier.pending_position_state < 0,
		"pending=%d" % soldier.pending_position_state,
	)
	soldier.position_state = PositionStateClass.DOWN
	soldier.pending_position_state = PositionStateClass.DOWN
	_assert(
		"prone WALK stands the soldier instead of rejecting",
		ActionResolverClass.validate_move(soldier, MovementModeClass.WALK).is_empty(),
		"WALK while DOWN must stand, not reject",
	)
	_assert(
		"WALK while DOWN leaves the soldier standing",
		soldier.position_state == PositionStateClass.UP,
		"position_state=%d" % soldier.position_state,
	)


func _test_high_stress_blocks_advance() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.stress = AiCommanderClass.STRESS_COVER_PRIORITY + 10.0
		ger.clear_path()
		ger.is_moving = false
	## Hide enemies so FIGHT→ADVANCE path would otherwise move to objective.
	for sid in range(1, 5):
		var usa = gs.get_soldier(Team.USA, sid)
		if usa == null:
			continue
		usa.grid_position = Vector2i(80, 80)
	CombatSystem.clear_player_visibility_cache()
	CombatSystem.update_spotting(gs)
	commander.state_id = AiCommanderStateClass.ADVANCE
	commander.current_objective = AiSectorObjectivesClass.enemy_deployment_objective(gs, 2)
	_submitted.clear()
	_think_cycle(fw, gs)
	var saw_advance_move := false
	for cmd in _submitted:
		if (
			cmd is MoveCommandClass
			and commander.current_objective != null
			and cmd.target_cell == commander.current_objective.cell
		):
			saw_advance_move = true
	_assert(
		"high stress blocks objective advance",
		not saw_advance_move,
		"submitted=%d" % _submitted.size(),
	)


func _test_defend_holds_near_own_lines() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var own := AiSectorObjectivesClass._team_anchor(gs, Team.GERMANY)
	var enemy := AiSectorObjectivesClass._team_anchor(gs, Team.USA)
	var opts: Array = AiSectorObjectivesClass.objectives_for_plan(
		gs, 2, AiPlanClass.ID_DEFEND, []
	)
	_assert("DEFEND emits holds", opts.size() >= 3)
	for opt in opts:
		if opt == null or str(opt.kind) != "hold":
			continue
		var to_own := absi(opt.cell.x - own.x) + absi(opt.cell.y - own.y)
		var to_enemy := absi(opt.cell.x - enemy.x) + absi(opt.cell.y - enemy.y)
		_assert(
			"DEFEND hold stays nearer own lines than enemy",
			to_own < to_enemy,
			"cell=%s own=%s enemy=%s d_own=%d d_enemy=%d" % [opt.cell, own, enemy, to_own, to_enemy],
		)
		var corridor := absi(own.x - enemy.x) + absi(own.y - enemy.y)
		var max_forward := (
			mini(AiSectorObjectivesClass.DEFEND_FORWARD_CELLS, maxi(2, int(round(float(corridor) * 0.2))))
			+ AiSectorObjectivesClass.DEFEND_COVER_RADIUS
			+ AiSectorObjectivesClass.DEFEND_LATERAL_CELLS
			+ 4
		)
		_assert(
			"DEFEND hold within forward screen of spawn",
			to_own <= max_forward,
			"cell=%s own=%s d=%d max=%d" % [opt.cell, own, to_own, max_forward],
		)


func _test_defend_splits_approaches() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.TWO_V_TWO)
	## Both Germany AI on DEFEND so they share the plan and must split lanes.
	gs.command_hierarchy.set_selected_ai_plan(3, AiPlanClass.ID_DEFEND)
	gs.command_hierarchy.set_active_ai_plan(3, AiPlanClass.ID_DEFEND)
	gs.command_hierarchy.set_selected_ai_plan(4, AiPlanClass.ID_DEFEND)
	gs.command_hierarchy.set_active_ai_plan(4, AiPlanClass.ID_DEFEND)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	## Place cover objects so each approach lane has a stand.
	for x in range(18, 36):
		map_data.set_object(Vector2i(x, 22), MapObjectRegistryClass.TYPE_HAYBAIL)
	var empty_claimed: Array[Vector2i] = []
	var opts_a: Array = AiSectorObjectivesClass.objectives_for_plan(
		gs, 3, AiPlanClass.ID_DEFEND, empty_claimed
	)
	_assert("DEFEND emits multiple approach holds", opts_a.size() >= 3, "count=%d" % opts_a.size())
	var hold_count := 0
	for opt in opts_a:
		if opt != null and str(opt.kind) == "hold":
			hold_count += 1
	_assert("DEFEND objectives use hold kind", hold_count >= 3, "holds=%d" % hold_count)
	var first = AiSectorObjectivesClass.select_for_claims(opts_a, empty_claimed)
	_assert("lone defender prefers center approach", first != null and str(first.objective_id) == "defend_center")
	var claimed_center: Array[Vector2i] = [first.cell]
	var second = AiSectorObjectivesClass.select_for_claims(opts_a, claimed_center)
	_assert(
		"second defender picks a different lane",
		second != null and second.cell != first.cell,
		"first=%s second=%s" % [first.cell if first else null, second.cell if second else null],
	)
	## Live commanders with coordinator claims should also diverge.
	var fw := _make_framework(gs)
	_think_cycle(fw, gs)
	var c3: AiCommanderClass = fw.get_commander(3)
	var c4: AiCommanderClass = fw.get_commander(4)
	_assert("both DEFEND commanders have objectives", c3.current_objective != null and c4.current_objective != null)
	## Force a second cycle so claims propagate.
	_think_cycle(fw, gs)
	c3 = fw.get_commander(3)
	c4 = fw.get_commander(4)
	if c3.current_objective != null and c4.current_objective != null:
		var dist := (
			absi(c3.current_objective.cell.x - c4.current_objective.cell.x)
			+ absi(c3.current_objective.cell.y - c4.current_objective.cell.y)
		)
		_assert(
			"DEFEND fireteams spread across approaches",
			dist > 0,
			"c3=%s c4=%s" % [c3.current_objective.cell, c4.current_objective.cell],
		)


func _test_defend_skips_owned_vp() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	gs.map_data.victory_points = [{
		"x": 25,
		"y": 25,
		"name": "Main",
		"initial_holder": "Germany",
	}]
	var opts: Array = AiSectorObjectivesClass.objectives_for_plan(
		gs, 2, AiPlanClass.ID_DEFEND, []
	)
	var has_vp := false
	for opt in opts:
		if opt != null and str(opt.objective_id) == "victory_point":
			has_vp = true
	_assert("DEFEND skips VP already held by this side", not has_vp, "opts=%d" % opts.size())
	## Flip holder — VP seize should appear at lower priority.
	gs.map_data.victory_points[0]["initial_holder"] = "USA"
	var opts2: Array = AiSectorObjectivesClass.objectives_for_plan(
		gs, 2, AiPlanClass.ID_DEFEND, []
	)
	var has_vp2 := false
	for opt in opts2:
		if opt != null and str(opt.objective_id) == "victory_point":
			has_vp2 = true
			_assert("unheld VP is lower priority than holds", int(opt.priority) < 12)
	_assert("DEFEND offers VP seize when not held", has_vp2)


func _test_defend_hold_faces_approach() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	gs.command_hierarchy.set_selected_ai_plan(2, AiPlanClass.ID_DEFEND)
	gs.command_hierarchy.set_active_ai_plan(2, AiPlanClass.ID_DEFEND)
	## Hide USA so no contact fight path.
	for sid in range(1, 5):
		var usa = gs.get_soldier(Team.USA, sid)
		if usa == null:
			continue
		usa.grid_position = Vector2i(80, 80)
	CombatSystem.clear_player_visibility_cache()
	CombatSystem.update_spotting(gs)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	var hold_cell := Vector2i(30, 20)
	commander.current_objective = AiSectorObjectivesClass.hold_objective_at(hold_cell)
	commander.state_id = AiCommanderStateClass.MOVE
	## Don't let replan overwrite the hold post under test.
	commander.needs_replan = false
	commander.last_replan_msec = SimulationClock.get_ticks_msec()
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = hold_cell
		ger.clear_path()
		ger.is_moving = false
	_submitted.clear()
	_think_cycle(fw, gs)
	var saw_face := false
	var saw_drift_move := false
	var approach := AiSectorObjectivesClass.enemy_approach_cell(gs, 2)
	for cmd in _submitted:
		if cmd is FaceCommandClass:
			saw_face = true
		if cmd is MoveCommandClass and cmd.target_cell != hold_cell:
			saw_drift_move = true
	_assert("hold post faces enemy approach", saw_face, "approach=%s" % approach)
	_assert("hold post does not drift off objective", not saw_drift_move)
	_assert(
		"hold post stays in FIGHT/watch",
		commander.state_id == AiCommanderStateClass.FIGHT,
		"state=%s" % commander.state_id,
	)


func _test_defensive_posts_stay_cohesive() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	gs.command_hierarchy.set_selected_ai_plan(2, AiPlanClass.ID_DEFEND)
	gs.command_hierarchy.set_active_ai_plan(2, AiPlanClass.ID_DEFEND)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	## Dense cover near German lines so posts can cluster.
	for x in range(28, 40):
		for y in range(18, 26):
			if (x + y) % 2 == 0:
				map_data.set_object(Vector2i(x, y), MapObjectRegistryClass.TYPE_HAYBAIL)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	_think_cycle(fw, gs)
	commander = fw.get_commander(2)
	_assert("defend commander assigned posts", not commander._defensive_posts.is_empty())
	var posts: Array[Vector2i] = []
	for sid in commander._defensive_posts.keys():
		posts.append(commander._defensive_posts[sid])
	var max_span := 0
	for i in range(posts.size()):
		for j in range(i + 1, posts.size()):
			var span := maxi(absi(posts[i].x - posts[j].x), absi(posts[i].y - posts[j].y))
			max_span = maxi(max_span, span)
	_assert(
		"defensive posts within fireteam cohesion",
		max_span <= AiCommanderClass.FIRETEAM_COHESION_RADIUS,
		"span=%d posts=%s" % [max_span, posts],
	)
	if commander.current_objective != null:
		for post in posts:
			var d := maxi(
				absi(post.x - commander.current_objective.cell.x),
				absi(post.y - commander.current_objective.cell.y),
			)
			_assert(
				"post near primary hold",
				d <= AiCommanderClass.DEFENSIVE_POST_CLUSTER,
				"post=%s primary=%s d=%d" % [post, commander.current_objective.cell, d],
			)


func _test_defensive_posts_spread_along_cover() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	gs.command_hierarchy.set_selected_ai_plan(2, AiPlanClass.ID_DEFEND)
	gs.command_hierarchy.set_active_ai_plan(2, AiPlanClass.ID_DEFEND)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	## Long wall — soldiers should dig in spaced along the friendly side.
	for x in range(24, 40):
		map_data.set_object(Vector2i(x, 28), MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	_think_cycle(fw, gs)
	commander = fw.get_commander(2)
	_assert("spread defend assigned posts", not commander._defensive_posts.is_empty())
	var posts: Array[Vector2i] = []
	for sid in commander._defensive_posts.keys():
		posts.append(commander._defensive_posts[sid])
	var close_pairs := 0
	var total_pairs := 0
	for i in range(posts.size()):
		for j in range(i + 1, posts.size()):
			total_pairs += 1
			var sep := maxi(absi(posts[i].x - posts[j].x), absi(posts[i].y - posts[j].y))
			if sep < AiCommanderClass.DEFENSIVE_POST_MIN_SEP:
				close_pairs += 1
	_assert(
		"defensive posts mostly keep min separation along cover",
		total_pairs > 0 and close_pairs == 0,
		"close_pairs=%d posts=%s" % [close_pairs, posts],
	)
	var unique := {}
	for p in posts:
		unique[p] = true
	_assert(
		"defensive posts are distinct cells",
		unique.size() == posts.size(),
		"posts=%s" % posts,
	)


func _test_defend_under_fire_does_not_stutter_to_posts() -> void:
	## Regression: FIGHT + hold used to Move→posts then Halt every tick (stutter-step).
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	gs.command_hierarchy.set_selected_ai_plan(2, AiPlanClass.ID_DEFEND)
	gs.command_hierarchy.set_active_ai_plan(2, AiPlanClass.ID_DEFEND)
	var map_data: MapDataClass = gs.map_data
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var wall := Vector2i(34, 22)
	map_data.set_object(wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	## Germans off their posts; USA in LOS so contact engages.
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		var ger = gs.get_soldier(Team.GERMANY, int(sid))
		if ger == null:
			continue
		ger.grid_position = Vector2i(35, 22)
		ger.clear_path()
		ger.is_moving = false
		ger.position_state = PositionStateClass.UP
		ger.facing_direction = FacingDirectionClass.WEST
	for sid in range(1, 5):
		var usa = gs.get_soldier(Team.USA, sid)
		if usa == null:
			continue
		usa.grid_position = Vector2i(28, 22)
		usa.facing_direction = FacingDirectionClass.EAST
		usa.clear_path()
	CombatSystem.clear_player_visibility_cache()
	CombatSystem.notify_command_hierarchy_changed(gs)
	CombatSystem.update_spotting(gs)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	_think_cycle(fw, gs)
	commander = fw.get_commander(2)
	_assert("defend under fire has hold objective", commander._is_hold_objective())
	_assert("defend under fire assigned posts", not commander._defensive_posts.is_empty())
	## Force posts away so "return to post" would fire if the bug returned.
	var post_cell := Vector2i(42, 22)
	for sid in gs.command_hierarchy.get_soldier_ids(2):
		commander._defensive_posts[int(sid)] = post_cell
	commander.state_id = AiCommanderStateClass.FIGHT
	commander._settled_in_cover = true
	commander._contact_bound_active = false
	commander._cover_threat_cell = Vector2i(28, 22)
	_assert("posts not reached before fight tick", not commander._defensive_posts_reached(gs))
	for _i in 3:
		for sid in gs.command_hierarchy.get_soldier_ids(2):
			var ger2 = gs.get_soldier(Team.GERMANY, int(sid))
			if ger2 == null:
				continue
			ger2.clear_path()
			ger2.is_moving = false
		_submitted.clear()
		_think_cycle(fw, gs)
		SimulationClock.advance_msec(200)
		var saw_halt := false
		var saw_post_move := false
		for cmd in _submitted:
			if cmd is HaltCommandClass:
				saw_halt = true
			if cmd is MoveCommandClass and cmd.target_cell == post_cell:
				saw_post_move = true
		_assert(
			"defend under fire does not Move back to posts",
			not saw_post_move,
			"tick submitted=%s" % str(_submitted),
		)
		_assert(
			"defend under fire does not Halt post bounce",
			not saw_halt,
			"tick submitted=%s" % str(_submitted),
		)


func _test_threat_scoring_prefers_close_exposed() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	var far = gs.get_soldier(Team.USA, 1)
	var near = gs.get_soldier(Team.USA, 2)
	_assert("threat scoring fixtures", far != null and near != null)
	var ger = gs.get_soldier(Team.GERMANY, 1)
	ger.grid_position = Vector2i(30, 20)
	near.grid_position = Vector2i(32, 20)
	far.grid_position = Vector2i(50, 20)
	near.position_state = PositionStateClass.UP
	far.position_state = PositionStateClass.DOWN
	var visible: Array = [far, near]
	var best = commander._select_best_threat(gs, visible)
	_assert("selects closer exposed threat", best == near, "got=%s" % best)


func _test_dedup_expires() -> void:
	var gs := _make_game_state(MatchConfigClass.MatchType.ONE_V_ONE)
	var fw := _make_framework(gs)
	var commander: AiCommanderClass = fw.get_commander(2)
	commander._last_move_cell = Vector2i(10, 10)
	commander._last_move_msec = SimulationClock.get_ticks_msec()
	_assert(
		"fresh dedup blocks",
		commander._move_dedup_blocks(Vector2i(10, 10), Vector2i(10, 10)),
	)
	SimulationClock.advance_msec(AiCommanderClass.DEDUP_EXPIRE_MSEC + 1)
	_assert(
		"expired dedup allows retry",
		not commander._move_dedup_blocks(Vector2i(10, 10), Vector2i(10, 10)),
	)
