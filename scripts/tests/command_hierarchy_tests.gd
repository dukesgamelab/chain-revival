extends Node
## Command hierarchy (commander / subordinate) regression tests.
##
## Run:
##   Godot_v4.x_console.exe --headless --path <project> res://scripts/tests/command_hierarchy_tests.tscn

const MapDataClass := preload("res://scripts/map/map_data.gd")
const GameSessionClass := preload("res://scripts/core/game_session.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")
const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")
const AssignCommanderCommandClass := preload("res://scripts/commands/assign_commander_command.gd")
const BreakCommandLinkCommandClass := preload("res://scripts/commands/break_command_link_command.gd")
const SetMissionCommanderCommandClass := preload("res://scripts/commands/set_mission_commander_command.gd")
const CommandHierarchyClass := preload("res://scripts/core/command_hierarchy.gd")
const CombatSystemClass := preload("res://scripts/combat/combat_system.gd")
const EnemyVisibilityResultClass := preload("res://scripts/combat/enemy_visibility_result.gd")
const FacingDirectionClass := preload("res://scripts/enums/facing_direction.gd")
const ActionResultClass := preload("res://scripts/core/action_result.gd")
const MatchConfigClass := preload("res://scripts/core/match_config.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_link_and_break()
	_test_validation_messages()
	_test_shared_subordinate_visibility()
	_test_command_vis_no_reverse_share()
	_test_command_vis_transitive_and_break()
	_test_command_vis_does_not_alter_los()
	_test_works_with_ai_players()
	print("")
	print("Command hierarchy tests: %d passed, %d failed" % [_passed, _failed])
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


func _make_game_state() -> GameStateClass:
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var blue: Array[Vector2i] = map_data.team_1_spawn_points
	var red: Array[Vector2i] = map_data.team_2_spawn_points
	if blue.is_empty():
		blue = MapDataClass.default_usa_spawn_points()
	if red.is_empty():
		red = MapDataClass.default_germany_spawn_points()
	## 2v2 so hierarchy has allied AI fireteams (YOU + USA AI) matching commander tests.
	var cfg = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.SINGLE_PLAYER,
		MatchConfigClass.MatchType.TWO_V_TWO,
	)
	var session := GameSessionClass.from_match_config(cfg, blue, red)
	return session.create_game_state(map_data)


func _submit(game_state: GameStateClass, command: RefCounted) -> ActionResultClass:
	## Call ActionResolver directly (same path CommandRouter uses offline).
	return ActionResolverClass.execute(game_state, command)


func _test_link_and_break() -> void:
	var game_state: GameStateClass = _make_game_state()
	var hierarchy: CommandHierarchyClass = game_state.command_hierarchy
	var commander_id := 1 ## YOU rank 3
	var subordinate_id := 2 ## FTD rank 1

	var cmd := AssignCommanderCommandClass.new()
	cmd.commander_id = commander_id
	cmd.subordinate_id = subordinate_id
	var result = _submit(game_state, cmd)
	_assert("Link lower-rank to higher-rank succeeds", result.success, result.status_message)

	var links := game_state.all_command_links()
	_assert(
		"Pair appears in Connections",
		links.size() == 1
		and int(links[0].commander_id) == commander_id
		and int(links[0].subordinate_id) == subordinate_id,
		"links=%s" % str(links),
	)
	_assert(
		"Subordinate leaves players_without_commanders",
		subordinate_id not in game_state.players_without_commanders(),
	)
	_assert(
		"Commander still listed when under cap",
		commander_id in game_state.commanders_with_openings(),
	)

	var brk := BreakCommandLinkCommandClass.new()
	brk.subordinate_id = subordinate_id
	result = _submit(game_state, brk)
	_assert("Break removes the link", result.success, result.status_message)
	_assert("No links after break", game_state.all_command_links().is_empty())
	_assert(
		"Both return to correct lists after break",
		commander_id in game_state.commanders_with_openings()
		and subordinate_id in game_state.players_without_commanders(),
	)


func _test_validation_messages() -> void:
	var game_state: GameStateClass = _make_game_state()
	var hierarchy: CommandHierarchyClass = game_state.command_hierarchy

	var cmd := AssignCommanderCommandClass.new()
	cmd.commander_id = -1
	cmd.subordinate_id = 2
	var miss_cmd = _submit(game_state, cmd)
	_assert(
		"Choose a commander first",
		not miss_cmd.success and miss_cmd.status_message == "Choose a commander first",
		miss_cmd.status_message,
	)

	cmd.commander_id = 1
	cmd.subordinate_id = -1
	var miss_sub = _submit(game_state, cmd)
	_assert(
		"Choose a subordinate first",
		miss_sub.status_message == "Choose a subordinate first",
		miss_sub.status_message,
	)

	cmd.commander_id = 1
	cmd.subordinate_id = 1
	var self_link = _submit(game_state, cmd)
	_assert(
		"Subordinate cannot be the commander",
		self_link.status_message == "Subordinate cannot be the commander",
		self_link.status_message,
	)

	## Rank order: FRITZ (1) cannot command HANS (3).
	cmd.commander_id = 4 ## FRITZ rank 1
	cmd.subordinate_id = 3 ## HANS rank 3
	var rank_fail = _submit(game_state, cmd)
	_assert(
		"Rank order broken",
		rank_fail.status_message == "Rank order broken",
		rank_fail.status_message,
	)

	## Valid link then already commanded / already in list / cycle / full.
	cmd.commander_id = 1
	cmd.subordinate_id = 2
	var setup = _submit(game_state, cmd)
	_assert("Setup link for further rules", setup.success, setup.status_message)

	cmd.commander_id = 3 ## HANS try to take FTD
	cmd.subordinate_id = 2
	var other_cmd = _submit(game_state, cmd)
	_assert(
		"Already commanded by another player",
		other_cmd.status_message == "Already commanded by another player",
		other_cmd.status_message,
	)

	cmd.commander_id = 1
	cmd.subordinate_id = 2
	var dup = _submit(game_state, cmd)
	_assert(
		"Already in subordinate list",
		dup.status_message == "Already in subordinate list",
		dup.status_message,
	)

	## Cycle: FTD tries to command YOU while YOU commands FTD (cycle before rank).
	cmd.commander_id = 2
	cmd.subordinate_id = 1
	var cycle = _submit(game_state, cmd)
	_assert(
		"Commander can't be subordinate of subordinate",
		cycle.status_message == "Commander can't be subordinate of subordinate",
		cycle.status_message,
	)

	## Fill commander to cap with temporary players.
	hierarchy.break_link(2)
	hierarchy.register_player("A", 0, Team.USA, true, [] as Array[int])
	hierarchy.register_player("B", 0, Team.USA, true, [] as Array[int])
	hierarchy.register_player("C", 0, Team.USA, true, [] as Array[int])
	hierarchy.register_player("D", 0, Team.USA, true, [] as Array[int])
	hierarchy.register_player("E", 0, Team.USA, true, [] as Array[int])
	var extras: Array[int] = []
	for pid in hierarchy.all_player_ids():
		if hierarchy.get_display_name(pid) in ["A", "B", "C", "D"]:
			extras.append(pid)
	for sid in extras:
		cmd.commander_id = 1
		cmd.subordinate_id = sid
		var fill_result = _submit(game_state, cmd)
		_assert("Fill slot %d" % sid, fill_result.success, fill_result.status_message)
	## Fifth should fail (cap 4). Find E.
	var e_id := -1
	for pid in hierarchy.all_player_ids():
		if hierarchy.get_display_name(pid) == "E":
			e_id = pid
			break
	cmd.commander_id = 1
	cmd.subordinate_id = e_id
	_assert(
		"This commander is full",
		_submit(game_state, cmd).status_message == "This commander is full",
	)

	var mc := SetMissionCommanderCommandClass.new()
	mc.player_id = 2
	_assert("Set mission commander works", _submit(game_state, mc).success)


func _test_shared_subordinate_visibility() -> void:
	var game_state: GameStateClass = _make_game_state()
	## Player 1 owns USA 1–2; player 2 owns USA 3–4. Face player-2 soldier at enemy; hide player-1.
	var cmd_soldier := game_state.get_soldier(Team.USA, 1)
	var sub_soldier := game_state.get_soldier(Team.USA, 3)
	var enemy := game_state.get_soldier(Team.GERMANY, 1)
	cmd_soldier.grid_position = Vector2i(10, 10)
	cmd_soldier.facing_direction = FacingDirectionClass.NORTH ## look away from enemy
	sub_soldier.grid_position = Vector2i(20, 30)
	enemy.grid_position = Vector2i(24, 30)
	sub_soldier.facing_direction = FacingDirectionClass.toward_cell(
		sub_soldier.grid_position,
		enemy.grid_position,
	)
	cmd_soldier.clear_path()
	sub_soldier.clear_path()
	enemy.clear_path()

	_assert(
		"Commander alone cannot spot distant reverse-facing enemy",
		not CombatSystemClass.is_enemy_visible_to_player(game_state, 1, enemy),
	)
	_assert(
		"Subordinate can spot the enemy",
		CombatSystemClass.is_enemy_visible_to_player(game_state, 2, enemy),
	)

	var link := AssignCommanderCommandClass.new()
	link.commander_id = 1
	link.subordinate_id = 2
	_assert("Link for shared vis", _submit(game_state, link).success)

	var vis = CombatSystemClass.get_enemy_visibility_for_player(game_state, 1, enemy)
	_assert(
		"Commander sees enemies spotted by subordinates",
		vis.visible and vis.spotter_soldier_id in [3, 4],
		"visible=%s source=%s spotter=%d"
		% [vis.visible, vis.source, vis.spotter_soldier_id],
	)
	_assert(
		"Shared visibility source is SUBORDINATE",
		vis.source == EnemyVisibilityResultClass.Source.SUBORDINATE,
		"source=%s" % vis.source,
	)


func _test_command_vis_no_reverse_share() -> void:
	## Subordinate must NOT see an enemy spotted only by their commander.
	var game_state: GameStateClass = _make_game_state()
	var hierarchy: CommandHierarchyClass = game_state.command_hierarchy
	hierarchy.set_soldier_ids(1, [1] as Array[int])
	hierarchy.set_soldier_ids(2, [3] as Array[int])
	var cmd_soldier := game_state.get_soldier(Team.USA, 1) ## player 1
	var sub_soldier := game_state.get_soldier(Team.USA, 3) ## player 2
	var idle := game_state.get_soldier(Team.USA, 2)
	var idle2 := game_state.get_soldier(Team.USA, 4)
	var enemy := game_state.get_soldier(Team.GERMANY, 1)
	cmd_soldier.grid_position = Vector2i(20, 30)
	enemy.grid_position = Vector2i(24, 30)
	cmd_soldier.facing_direction = FacingDirectionClass.toward_cell(
		cmd_soldier.grid_position,
		enemy.grid_position,
	)
	sub_soldier.grid_position = Vector2i(10, 10)
	sub_soldier.facing_direction = FacingDirectionClass.NORTH
	## Park unused USA soldiers far away facing away.
	idle.grid_position = Vector2i(2, 2)
	idle.facing_direction = FacingDirectionClass.NORTH
	idle2.grid_position = Vector2i(3, 2)
	idle2.facing_direction = FacingDirectionClass.NORTH
	cmd_soldier.clear_path()
	sub_soldier.clear_path()
	idle.clear_path()
	idle2.clear_path()
	enemy.clear_path()
	CombatSystemClass.clear_player_visibility_cache()

	_assert(
		"Commander can spot the enemy alone",
		CombatSystemClass.is_enemy_visible_to_player(game_state, 1, enemy),
	)
	_assert(
		"Subordinate alone cannot spot that enemy",
		not CombatSystemClass.is_enemy_visible_to_player(game_state, 2, enemy),
	)

	var link := AssignCommanderCommandClass.new()
	link.commander_id = 1
	link.subordinate_id = 2
	_assert("Link for reverse-share check", _submit(game_state, link).success)
	_assert(
		"Subordinate does NOT see commander's exclusive spot",
		not CombatSystemClass.is_enemy_visible_to_player(game_state, 2, enemy),
	)


func _test_command_vis_transitive_and_break() -> void:
	var game_state: GameStateClass = _make_game_state()
	var hierarchy: CommandHierarchyClass = game_state.command_hierarchy
	## Chain YOU (rank 3) → MID (rank 2) → FTD (rank 1). Leaf FTD owns USA soldier 3.
	hierarchy.set_soldier_ids(1, [1, 2] as Array[int])
	hierarchy.set_soldier_ids(2, [3] as Array[int])
	var mid_id := hierarchy.register_player("MID", 2, Team.USA, true, [4] as Array[int])

	var leaf_soldier := game_state.get_soldier(Team.USA, 3)
	var mid_soldier := game_state.get_soldier(Team.USA, 4)
	var cmd_soldier := game_state.get_soldier(Team.USA, 1)
	var enemy := game_state.get_soldier(Team.GERMANY, 1)
	leaf_soldier.grid_position = Vector2i(20, 30)
	enemy.grid_position = Vector2i(24, 30)
	leaf_soldier.facing_direction = FacingDirectionClass.toward_cell(
		leaf_soldier.grid_position,
		enemy.grid_position,
	)
	mid_soldier.grid_position = Vector2i(8, 8)
	mid_soldier.facing_direction = FacingDirectionClass.NORTH
	cmd_soldier.grid_position = Vector2i(6, 6)
	cmd_soldier.facing_direction = FacingDirectionClass.NORTH
	leaf_soldier.clear_path()
	mid_soldier.clear_path()
	cmd_soldier.clear_path()
	enemy.clear_path()

	var link_mid := AssignCommanderCommandClass.new()
	link_mid.commander_id = mid_id
	link_mid.subordinate_id = 2
	var mid_result = _submit(game_state, link_mid)
	_assert("Link mid→leaf", mid_result.success, mid_result.status_message)

	var link_top := AssignCommanderCommandClass.new()
	link_top.commander_id = 1
	link_top.subordinate_id = mid_id
	var top_result = _submit(game_state, link_top)
	_assert("Link commander→mid", top_result.success, top_result.status_message)

	_assert(
		"Leaf spots enemy",
		CombatSystemClass.is_enemy_visible_to_player(game_state, 2, enemy),
	)
	_assert(
		"Mid sees via direct subordinate",
		CombatSystemClass.is_enemy_visible_to_player(game_state, mid_id, enemy),
	)
	_assert(
		"Commander sees transitive sub-of-sub spot",
		CombatSystemClass.is_enemy_visible_to_player(game_state, 1, enemy),
	)

	var brk := BreakCommandLinkCommandClass.new()
	brk.subordinate_id = mid_id
	var brk_result = _submit(game_state, brk)
	_assert("Break mid from commander", brk_result.success, brk_result.status_message)
	_assert(
		"Breaking link immediately removes shared visibility",
		not CombatSystemClass.is_enemy_visible_to_player(game_state, 1, enemy),
	)
	_assert(
		"Mid still sees leaf after commander unlink",
		CombatSystemClass.is_enemy_visible_to_player(game_state, mid_id, enemy),
	)


func _los_snapshot(game_state: GameStateClass, from_cell: Vector2i, to_cell: Vector2i) -> String:
	var LOSSystemClass := preload("res://scripts/combat/los_system.gd")
	var los = LOSSystemClass.evaluate(from_cell, to_cell, game_state.map_data, game_state)
	return "%s|%s|%s|%s|%s|%s" % [
		los.status,
		los.cover_type,
		los.cover_source_cell,
		los.blocking_cell,
		los.blocking_type,
		los.shooter_using_wall_cover,
	]


func _test_command_vis_does_not_alter_los() -> void:
	var game_state: GameStateClass = _make_game_state()
	var map_data = game_state.map_data
	var wall := Vector2i(22, 30)
	map_data.set_object(wall, preload("res://scripts/map/map_object_registry.gd").TYPE_WALL_STRAIGHT)
	var from_a := Vector2i(20, 30)
	var to_a := Vector2i(24, 30)
	var from_b := Vector2i(10, 10)
	var to_b := Vector2i(14, 10)
	var before_a := _los_snapshot(game_state, from_a, to_a)
	var before_b := _los_snapshot(game_state, from_b, to_b)

	var link := AssignCommanderCommandClass.new()
	link.commander_id = 1
	link.subordinate_id = 2
	_assert("Link for LOS regression", _submit(game_state, link).success)

	var after_a := _los_snapshot(game_state, from_a, to_a)
	var after_b := _los_snapshot(game_state, from_b, to_b)
	_assert(
		"LOS results unchanged after command link",
		before_a == after_a and before_b == after_b,
		"a %s -> %s | b %s -> %s" % [before_a, after_a, before_b, after_b],
	)

	var brk := BreakCommandLinkCommandClass.new()
	brk.subordinate_id = 2
	_submit(game_state, brk)
	var after_break_a := _los_snapshot(game_state, from_a, to_a)
	_assert(
		"LOS results unchanged after command break",
		before_a == after_break_a,
		"%s -> %s" % [before_a, after_break_a],
	)


func _test_works_with_ai_players() -> void:
	var game_state: GameStateClass = _make_game_state()
	var hierarchy: CommandHierarchyClass = game_state.command_hierarchy
	## Germany AI players 3 (HANS) and 4 (FRITZ).
	_assert("AI players registered", hierarchy.has_player(3) and hierarchy.has_player(4))
	_assert("AI flag on FRITZ", bool(hierarchy.get_entry(4).get("is_ai", false)))
	var cmd := AssignCommanderCommandClass.new()
	cmd.commander_id = 3
	cmd.subordinate_id = 4
	_assert("AI commander link works offline", _submit(game_state, cmd).success)
