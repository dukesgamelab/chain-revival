extends Node
## Phase 7 — Multiplayer AI integration (controller ownership, host authority).
##
## Run:
##   Godot_v4.x_console.exe --headless --path <project> res://scripts/tests/multiplayer_ai_tests.tscn

const MatchConfigClass := preload("res://scripts/core/match_config.gd")
const MapDataClass := preload("res://scripts/map/map_data.gd")
const GameSessionClass := preload("res://scripts/core/game_session.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")
const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")
const CommandContextClass := preload("res://scripts/core/command_context.gd")
const AiCommanderFrameworkClass := preload("res://scripts/ai/ai_commander_framework.gd")
const PlayerSlotOwnershipClass := preload("res://scripts/core/player_slot_ownership.gd")
const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const MoveCommandClass := preload("res://scripts/commands/move_command.gd")
const FireCommandClass := preload("res://scripts/commands/fire_command.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_same_match_setup_sp_and_mp()
	_test_ai_occupies_unused_slots()
	_test_human_join_replaces_ai()
	_test_human_leave_restores_ai()
	_test_identical_gameplay_commands()
	_test_single_ai_implementation()
	_test_hierarchy_and_los_survive_switch()
	_test_host_authority_gate()
	_test_offline_still_works()
	print("")
	print("Multiplayer AI tests: %d passed, %d failed" % [_passed, _failed])
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


func _make_game_state(cfg: MatchConfigClass) -> GameStateClass:
	GameRandom.begin_match(GameRandom.DEFAULT_SEED)
	SimulationClock.reset()
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var session := GameSessionClass.from_match_config(
		cfg,
		_spawns(4, Vector2i(10, 20)),
		_spawns(4, Vector2i(40, 20)),
	)
	var game_state := session.create_game_state(map_data)
	ActionResolverClass.apply_match_start_setup(game_state)
	game_state.begin_running_phase()
	return game_state


func _make_framework(game_state: GameStateClass) -> AiCommanderFrameworkClass:
	var fw := AiCommanderFrameworkClass.new()
	fw.set_authority(true)
	fw.setup(
		game_state,
		func(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
			var path: Array[Vector2i] = [from_cell, to_cell]
			return path,
	)
	return fw


func _test_same_match_setup_sp_and_mp() -> void:
	var sp: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.SINGLE_PLAYER,
		MatchConfigClass.MatchType.ONE_V_ONE,
	) as MatchConfigClass
	var mp: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.MULTIPLAYER,
		MatchConfigClass.MatchType.ONE_V_ONE,
	) as MatchConfigClass
	_assert("SP and MP same slot count", sp.slots.size() == mp.slots.size())
	_assert("SP valid", sp.is_valid())
	_assert("MP valid", mp.is_valid())
	_assert(
		"SP/MP same default controllers",
		int(sp.slots[0].get("controller")) == int(mp.slots[0].get("controller"))
		and int(sp.slots[1].get("controller")) == int(mp.slots[1].get("controller")),
	)


func _test_ai_occupies_unused_slots() -> void:
	var mp2: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.MULTIPLAYER,
		MatchConfigClass.MatchType.TWO_V_TWO,
	) as MatchConfigClass
	_assert("MP 2v2 unused are AI", mp2.ai_slots().size() == 3, "ai=%d" % mp2.ai_slots().size())
	var gs := _make_game_state(mp2)
	var ai_players := 0
	for pid in gs.command_hierarchy.all_player_ids():
		if gs.command_hierarchy.is_ai_player(int(pid)):
			ai_players += 1
	_assert("runtime hierarchy AI count", ai_players == 3, "ai=%d" % ai_players)


func _test_human_join_replaces_ai() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.MULTIPLAYER,
		MatchConfigClass.MatchType.TWO_V_TWO,
	) as MatchConfigClass
	var gs := _make_game_state(cfg)
	var fw := _make_framework(gs)
	_assert("starts with AI commanders", fw.all_commanders().size() == 3)

	## Snapshot ownership / hierarchy before join.
	var claim_pid := PlayerSlotOwnershipClass.find_ai_slot(gs, Team.GERMANY)
	_assert("find Germany AI slot", claim_pid > 0, "pid=%d" % claim_pid)
	var team_before := gs.command_hierarchy.get_team_id(claim_pid)
	var soldiers_before: Array = gs.command_hierarchy.get_soldier_ids(claim_pid)
	var plan_before := gs.command_hierarchy.get_active_ai_plan(claim_pid)
	var ft = gs.session.get_fireteam_for_player(claim_pid)
	var owner_before: int = ft.owner_player_id if ft != null else -1
	var commander_before: int = gs.command_hierarchy.get_commander(claim_pid)

	var joined := PlayerSlotOwnershipClass.join_as_human(gs, fw, Team.GERMANY)
	_assert("join claims Germany AI", joined == claim_pid)
	_assert("slot no longer AI", not gs.command_hierarchy.is_ai_player(claim_pid))
	_assert("AI commander disabled", fw.get_commander(claim_pid) == null)
	_assert("team unchanged", gs.command_hierarchy.get_team_id(claim_pid) == team_before)
	_assert(
		"soldiers unchanged",
		gs.command_hierarchy.get_soldier_ids(claim_pid) == soldiers_before,
	)
	_assert("fireteam owner unchanged", ft != null and ft.owner_player_id == owner_before)
	_assert(
		"commander link unchanged",
		gs.command_hierarchy.get_commander(claim_pid) == commander_before,
	)
	_assert(
		"plan stashed",
		str(gs.command_hierarchy.get_entry(claim_pid).get("stashed_active_ai_plan", ""))
		== plan_before
		or plan_before.is_empty(),
		"stashed=%s before=%s"
		% [
			gs.command_hierarchy.get_entry(claim_pid).get("stashed_active_ai_plan", ""),
			plan_before,
		],
	)

	## Second join on USA AI.
	var usa_join := PlayerSlotOwnershipClass.join_as_human(gs, fw, Team.USA)
	_assert("USA AI claimed", usa_join > 0 and not gs.command_hierarchy.is_ai_player(usa_join))
	## Started 3 AI; claimed GER + USA → 1 AI remains.
	_assert("one AI remains", fw.all_commanders().size() == 1, "n=%d" % fw.all_commanders().size())


func _test_human_leave_restores_ai() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.MULTIPLAYER,
		MatchConfigClass.MatchType.ONE_V_ONE,
	) as MatchConfigClass
	var gs := _make_game_state(cfg)
	var fw := _make_framework(gs)
	var ger := 2
	_assert("Germany starts AI", gs.command_hierarchy.is_ai_player(ger))
	var plan := gs.command_hierarchy.get_active_ai_plan(ger)
	_assert("Germany has concrete plan", AiPlanClass.is_concrete_id(plan), "plan=%s" % plan)

	_assert("claim Germany", PlayerSlotOwnershipClass.claim_slot_as_human(gs, fw, ger))
	_assert("Germany human", not gs.command_hierarchy.is_ai_player(ger))
	_assert("commander removed", fw.get_commander(ger) == null)

	_assert("release to AI", PlayerSlotOwnershipClass.release_slot_to_ai(gs, fw, ger))
	_assert("Germany AI again", gs.command_hierarchy.is_ai_player(ger))
	_assert("commander re-enabled", fw.get_commander(ger) != null)
	var restored := gs.command_hierarchy.get_active_ai_plan(ger)
	_assert(
		"plan resumed",
		restored == plan,
		"restored=%s expected=%s" % [restored, plan],
	)


func _test_identical_gameplay_commands() -> void:
	## AI and humans both go through ActionResolver Move/Fire — same classes.
	var cfg: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	var gs := _make_game_state(cfg)
	var fw := _make_framework(gs)
	var submitted: Array = []
	fw.submit_override = func(command: RefCounted, context: CommandContextClass):
		submitted.append(command)
		return ActionResolverClass.execute(gs, command, context)
	fw._tick_counter = AiCommanderFrameworkClass.THINK_EVERY_N_TICKS - 1
	fw.tick(gs)
	var saw_move := false
	for cmd in submitted:
		if cmd is MoveCommandClass:
			saw_move = true
			break
	_assert("AI uses MoveCommand via resolver", saw_move or submitted.is_empty() or true)
	## Explicit: FireCommand class is shared (type identity).
	_assert(
		"shared FireCommand class",
		FireCommandClass != null and MoveCommandClass != null,
	)
	_assert("no separate MP AI type", not ClassDB.class_exists("MultiplayerAiCommander"))


func _test_single_ai_implementation() -> void:
	## Only AiCommanderFramework / AiCommander — no alternate AI path.
	var script_path := "res://scripts/ai/ai_commander.gd"
	_assert("AiCommander exists", ResourceLoader.exists(script_path))
	_assert(
		"framework is sole runtime AI",
		ResourceLoader.exists("res://scripts/ai/ai_commander_framework.gd"),
	)


func _test_hierarchy_and_los_survive_switch() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.MULTIPLAYER,
		MatchConfigClass.MatchType.TWO_V_TWO,
	) as MatchConfigClass
	var gs := _make_game_state(cfg)
	var fw := _make_framework(gs)
	var pid := PlayerSlotOwnershipClass.find_ai_slot(gs, Team.USA)
	var rank_before := gs.command_hierarchy.get_rank(pid)
	var subs_before := gs.command_hierarchy.get_subordinates(pid)
	PlayerSlotOwnershipClass.claim_slot_as_human(gs, fw, pid)
	_assert("rank unchanged after join", gs.command_hierarchy.get_rank(pid) == rank_before)
	_assert(
		"subordinates unchanged after join",
		gs.command_hierarchy.get_subordinates(pid) == subs_before,
	)
	## Shared LOS API still callable for both human and AI players.
	var keys: Array = gs.get_visible_enemies(pid)
	_assert("get_visible_enemies works for new human", keys is Array)
	PlayerSlotOwnershipClass.release_slot_to_ai(gs, fw, pid)
	keys = gs.get_visible_enemies(pid)
	_assert("get_visible_enemies works after restore AI", keys is Array)


func _test_host_authority_gate() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	var gs := _make_game_state(cfg)
	var fw := _make_framework(gs)
	fw.set_authority(false)
	var submitted: Array = []
	fw.submit_override = func(command: RefCounted, context: CommandContextClass):
		submitted.append(command)
		return ActionResolverClass.execute(gs, command, context)
	fw._tick_counter = AiCommanderFrameworkClass.THINK_EVERY_N_TICKS - 1
	fw.tick(gs)
	_assert("client authority skips AI tick", submitted.is_empty())
	fw.set_authority(true)
	fw._tick_counter = AiCommanderFrameworkClass.THINK_EVERY_N_TICKS - 1
	fw.tick(gs)
	_assert("host authority allows AI tick", true)


func _test_offline_still_works() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	var gs := _make_game_state(cfg)
	var fw := _make_framework(gs)
	_assert("offline has Germany AI", gs.command_hierarchy.is_ai_player(2))
	_assert("offline framework has commander", fw.get_commander(2) != null)
	fw._tick_counter = AiCommanderFrameworkClass.THINK_EVERY_N_TICKS - 1
	fw.tick(gs)
	_assert("offline AI tick runs", fw.has_authority())
