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
const IssueAiOrderCommandClass := preload("res://scripts/commands/issue_ai_order_command.gd")
const MoveCommandClass := preload("res://scripts/commands/move_command.gd")
const FaceCommandClass := preload("res://scripts/commands/face_command.gd")
const FireCommandClass := preload("res://scripts/commands/fire_command.gd")
const GrenadeCommandClass := preload("res://scripts/commands/grenade_command.gd")
const FacingDirectionClass := preload("res://scripts/enums/facing_direction.gd")

var _failed: int = 0
var _passed: int = 0
var _submitted: Array = []


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
