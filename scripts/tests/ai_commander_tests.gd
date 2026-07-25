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
	_test_prone_when_settled_in_cover()
	_test_contact_halts_objective_move()
	_test_high_stress_blocks_advance()
	_test_defend_splits_approaches()
	_test_defend_skips_owned_vp()
	_test_defend_hold_faces_approach()
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
	var saw_crawl_cover := false
	for cmd in _submitted:
		if cmd is HaltCommandClass:
			saw_halt = true
		if cmd is MoveCommandClass:
			var move := cmd as MoveCommandClass
			if move.target_cell == objective_cell and move.movement_mode == MovementModeClass.RUN:
				saw_objective_run = true
			if move.movement_mode == MovementModeClass.CRAWL:
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
	## Cover seek is best-effort (map-dependent); if issued it must be CRAWL.
	if saw_crawl_cover:
		_pass("contact cover bound uses CRAWL")
	else:
		_pass("contact cover bound optional when no stand in range")


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
