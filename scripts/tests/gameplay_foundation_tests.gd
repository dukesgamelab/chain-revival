extends Node
## Headless regression suite for the Gameplay Foundation refactor.
##
## Run:
##   Godot_v4.x_console.exe --headless --path <project> res://scripts/tests/gameplay_foundation_tests.tscn

const MapDataClass := preload("res://scripts/map/map_data.gd")
const MapLoaderClass := preload("res://scripts/map/map_loader.gd")
const GameSessionClass := preload("res://scripts/core/game_session.gd")
const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")
const CommandContextClass := preload("res://scripts/core/command_context.gd")
const MoveCommandClass := preload("res://scripts/commands/move_command.gd")
const FireCommandClass := preload("res://scripts/commands/fire_command.gd")
const GrenadeCommandClass := preload("res://scripts/commands/grenade_command.gd")
const CoverSystemClass := preload("res://scripts/combat/cover_system.gd")
const LOSSystemClass := preload("res://scripts/combat/los_system.gd")
const MapObjectRegistryClass := preload("res://scripts/map/map_object_registry.gd")
const MovementModeClass := preload("res://scripts/enums/movement_mode.gd")
const CombatSystemClass := preload("res://scripts/combat/combat_system.gd")
const PositionStateClass := preload("res://scripts/enums/position_state.gd")
const MapAssetRegistryClass := preload("res://scripts/map/map_asset_registry.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_bootstrap()
	_test_fortress_map_loads()
	_test_soldier_movement()
	_test_firing()
	_test_grenade_throwing()
	_test_los_fixture()
	_test_climb_short_wall_fire_over()
	_test_wall_cover_fixture()
	_test_corner_peek_around_wall_end()
	_test_corner_idle_at_wall_end()
	_test_directional_cover()
	_test_rng_seed_reproducibility()
	_test_firing_sequence_reproducibility()
	_test_grenade_sequence_reproducibility()
	_test_policy_defaults_unchanged()
	_test_recovered_weapon_stats()
	_test_smg_vs_rifle_range_falloff()
	_test_grenade_range_cap()
	_test_stress_model()
	_test_fixed_simulation_tick()
	_test_movement_frame_rate_independence()
	_test_object_id_and_registry()
	_test_map_object_registry()
	_test_grenade_object_registry()
	_test_team_soldier_key_consistent()
	_test_perception_cache_incremental()

	print("")
	print("Gameplay foundation tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _bootstrap() -> void:
	SimulationClock.reset()
	GameRandom.reseed(GameRandom.DEFAULT_SEED)
	GameplayPolicies.reset_all_to_defaults()


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


func _make_session(map_data: MapDataClass) -> GameSessionClass:
	var blue: Array[Vector2i] = map_data.team_1_spawn_points
	var red: Array[Vector2i] = map_data.team_2_spawn_points
	if blue.is_empty():
		blue = MapDataClass.default_usa_spawn_points()
	if red.is_empty():
		red = MapDataClass.default_germany_spawn_points()
	return GameSessionClass.new(blue, red)


func _make_game_state(map_data: MapDataClass = null) -> GameState:
	if map_data == null:
		map_data = MapDataClass.create_default()
	var session := _make_session(map_data)
	var game_state := session.create_game_state(map_data)
	ActionResolverClass.apply_match_start_setup(game_state)
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
	var came_from: Dictionary = {}
	came_from[from_cell] = from_cell
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == to_cell:
			break
		for offset in offsets:
			var next_cell: Vector2i = current + offset
			if came_from.has(next_cell):
				continue
			if not map_data.is_walkable(next_cell):
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


func _path_context(map_data: MapDataClass) -> CommandContextClass:
	var ctx := CommandContextClass.new()
	ctx.find_path = func(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
		return _bfs_path(map_data, from_cell, to_cell)
	return ctx


func _test_fortress_map_loads() -> void:
	var map_data := MapLoaderClass.load_fortress()
	_assert(
		"Fortress map loads successfully",
		map_data != null and map_data.width > 0 and map_data.height > 0,
		"width=%s height=%s name=%s"
		% [
			str(map_data.width if map_data else null),
			str(map_data.height if map_data else null),
			str(map_data.map_name if map_data else null),
		],
	)
	if map_data != null:
		_assert(
			"Fortress map has spawn points",
			not map_data.team_1_spawn_points.is_empty()
			and not map_data.team_2_spawn_points.is_empty(),
			"usa=%d germany=%d"
			% [map_data.team_1_spawn_points.size(), map_data.team_2_spawn_points.size()],
		)


func _test_soldier_movement() -> void:
	_bootstrap()
	var game_state := _make_game_state()
	var soldier := game_state.get_soldier(Team.USA, 1)
	var start := soldier.grid_position
	var target := start + Vector2i(2, 0)
	if not game_state.map_data.is_walkable(target):
		target = start + Vector2i(0, 2)

	var cmd := MoveCommandClass.new()
	cmd.team_id = Team.USA
	cmd.soldier_id = 1
	cmd.target_cell = target
	cmd.movement_mode = MovementModeClass.RUN
	cmd.scope = MoveCommandClass.Scope.SINGLE

	var result := ActionResolverClass.execute_move(
		game_state,
		cmd,
		_path_context(game_state.map_data),
	)
	_assert("Soldier movement order succeeds", result.success, result.status_message)
	_assert(
		"Soldier movement sets path",
		soldier.is_moving and soldier.current_path.size() >= 2,
		"is_moving=%s path_len=%d" % [soldier.is_moving, soldier.current_path.size()],
	)

	## Advance via simulation ticks until arrival (not presentation lerp).
	var guard := 0
	while soldier.is_moving and guard < 10000:
		SimulationClock.advance_tick()
		ActionResolverClass.process_movement_tick(game_state)
		guard += 1
	_assert("Soldier movement completes via sim ticks", not soldier.is_moving, "guard=%d" % guard)
	_assert(
		"Soldier movement ends on target cell",
		soldier.grid_position == target,
		"expected %s got %s" % [target, soldier.grid_position],
	)


func _test_firing() -> void:
	_bootstrap()
	var map_data := MapDataClass.create_default()
	## Clear default cover between teams so LOS is clear for the shot.
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)

	var game_state := _make_game_state(map_data)
	var shooter := game_state.get_soldier(Team.USA, 1)
	var target := game_state.get_soldier(Team.GERMANY, 1)
	## Place close with clear LOS and facing for spotting/fire.
	shooter.grid_position = Vector2i(20, 30)
	target.grid_position = Vector2i(24, 30)
	shooter.clear_path()
	target.clear_path()
	game_state.session.get_fireteam(Team.USA).face_toward_tile(1, target.grid_position)
	CombatSystemClass.update_spotting(game_state)
	shooter.record_last_seen_enemy(target)

	var ammo_before := shooter.ammo_current
	var fire_cmd := FireCommandClass.new()
	fire_cmd.team_id = Team.USA
	fire_cmd.soldier_id = 1
	fire_cmd.target_team_id = Team.GERMANY
	fire_cmd.target_soldier_id = 1
	fire_cmd.aim_world = IsometricGrid.grid_to_world(target.grid_position)
	fire_cmd.scope = FireCommandClass.Scope.SINGLE

	var fire_ctx := CommandContextClass.new()
	fire_ctx.shooter_ids = [1]
	var fire_result := ActionResolverClass.execute_fire(game_state, fire_cmd, fire_ctx)
	_assert("Firing engagement succeeds", fire_result.success, fire_result.status_message)
	_assert("Firing engagement marks sustained fire", shooter.is_sustained_fire())

	var fired := false
	for _attempt in range(4):
		SimulationClock.advance_msec(int(GameplayPolicies.hit.fire_prep_delay_sec * 1000.0) + 50)
		var tick := ActionResolverClass.process_combat_tick(game_state)
		if tick.combat_shots.size() >= 1 and shooter.ammo_current < ammo_before:
			fired = true
			break
	_assert(
		"Firing combat tick discharges a shot",
		fired,
		"ammo %d -> %d sustained=%s engaged=%d:%d"
		% [
			ammo_before,
			shooter.ammo_current,
			shooter.is_sustained_fire(),
			shooter.engaged_target_team_id,
			shooter.engaged_target_soldier_id,
		],
	)


func _test_grenade_throwing() -> void:
	_bootstrap()
	var game_state := _make_game_state()
	var thrower := game_state.get_soldier(Team.USA, 1)
	thrower.grid_position = Vector2i(20, 30)
	thrower.clear_path()
	var target_cell := Vector2i(22, 30)
	var count_before := thrower.grenade_count

	var cmd := GrenadeCommandClass.new()
	cmd.team_id = Team.USA
	cmd.soldier_id = 1
	cmd.target_cell = target_cell
	var result := ActionResolverClass.execute_grenade(
		game_state,
		cmd,
		CommandContextClass.new(),
	)
	_assert("Grenade throw succeeds", result.success, result.status_message)
	_assert(
		"Grenade throw consumes inventory and arms fuse",
		thrower.grenade_count == count_before - 1
		and thrower.has_pending_grenade()
		and thrower.pending_grenade_target == target_cell,
		"count=%d pending=%s target=%s"
		% [thrower.grenade_count, thrower.has_pending_grenade(), thrower.pending_grenade_target],
	)

	SimulationClock.advance_msec(GameplayPolicies.grenade.fuse_msec + 1)
	var tick := ActionResolverClass.process_combat_tick(game_state)
	_assert(
		"Grenade fuse detonates on simulation clock",
		tick.grenade_explosions.size() == 1 and not thrower.has_pending_grenade(),
		"explosions=%d pending=%s"
		% [tick.grenade_explosions.size(), thrower.has_pending_grenade()],
	)


func _test_los_fixture() -> void:
	_bootstrap()
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)

	var from_cell := Vector2i(10, 10)
	var to_cell := Vector2i(14, 10)
	var clear_los := LOSSystemClass.evaluate(from_cell, to_cell, map_data, null)
	_assert(
		"LOS fixture clear open ground",
		clear_los.status == LOSSystemClass.Status.CLEAR,
		"status=%s" % LOSSystemClass.status_name(clear_los.status),
	)

	var blocker := Vector2i(12, 10)
	map_data.set_object(blocker, MapObjectRegistryClass.TYPE_TREE)
	var blocked_los := LOSSystemClass.evaluate(from_cell, to_cell, map_data, null)
	_assert(
		"LOS fixture tree blocks line of fire",
		blocked_los.status == LOSSystemClass.Status.BLOCKED,
		"status=%s type=%s" % [LOSSystemClass.status_name(blocked_los.status), blocked_los.blocking_type],
	)


func _test_climb_short_wall_fire_over() -> void:
	## Climb / height-1 short walls (WH00): standing shooters fire over them, even at prone targets.
	_bootstrap()
	MapAssetRegistryClass.ensure_loaded()
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)

	var wall := Vector2i(22, 30)
	map_data.place_family_object(wall, "WH00", 0)
	_assert("WH00 is climb terrain", map_data.is_climb(wall))
	_assert("WH00 height is 1", map_data.obstruction_height(wall) == 1)
	_assert(
		"WH00 does not block standing vision",
		not map_data.blocks_vision(wall, false, false),
	)
	_assert(
		"WH00 does not block standing→prone vision",
		not map_data.blocks_vision(wall, false, true),
	)
	_assert(
		"WH00 blocks prone observer vision",
		map_data.blocks_vision(wall, true, false),
	)

	var game_state := _make_game_state(map_data)
	var shooter := game_state.get_soldier(Team.USA, 1)
	var target := game_state.get_soldier(Team.GERMANY, 1)
	## Shooter immediately behind the short wall; target beyond it (prone, as in Farm Fight).
	shooter.grid_position = Vector2i(21, 30)
	target.grid_position = Vector2i(24, 30)
	target.position_state = PositionStateClass.DOWN
	shooter.clear_path()
	target.clear_path()
	game_state.session.get_fireteam(Team.USA).face_toward_tile(1, target.grid_position)
	CombatSystemClass.update_spotting(game_state)
	shooter.record_last_seen_enemy(target)

	var los := LOSSystemClass.evaluate(
		shooter.grid_position,
		target.grid_position,
		map_data,
		game_state,
	)
	_assert(
		"Standing over WH00 at prone target is not BLOCKED",
		los.status != LOSSystemClass.Status.BLOCKED,
		"status=%s type=%s" % [LOSSystemClass.status_name(los.status), los.blocking_type],
	)

	var ammo_before := shooter.ammo_current
	var fire_cmd := FireCommandClass.new()
	fire_cmd.team_id = Team.USA
	fire_cmd.soldier_id = 1
	fire_cmd.target_team_id = Team.GERMANY
	fire_cmd.target_soldier_id = 1
	fire_cmd.aim_world = IsometricGrid.grid_to_world(target.grid_position)
	fire_cmd.scope = FireCommandClass.Scope.SINGLE
	var fire_ctx := CommandContextClass.new()
	fire_ctx.shooter_ids = [1]
	var fire_result := ActionResolverClass.execute_fire(game_state, fire_cmd, fire_ctx)
	_assert("Fire At over short wall engages", fire_result.success, fire_result.status_message)

	var fired := false
	for _attempt in range(4):
		SimulationClock.advance_msec(int(GameplayPolicies.hit.fire_prep_delay_sec * 1000.0) + 50)
		var tick := ActionResolverClass.process_combat_tick(game_state)
		if tick.combat_shots.size() >= 1 and shooter.ammo_current < ammo_before:
			fired = true
			break
	_assert(
		"Fire At over short wall discharges a shot",
		fired,
		"ammo %d -> %d status=%s"
		% [ammo_before, shooter.ammo_current, fire_result.status_message],
	)

	## Prone shooter without adjacent peek cannot see over mid-line climb cover.
	shooter.position_state = PositionStateClass.DOWN
	shooter.grid_position = Vector2i(20, 30) ## wall at 22 is not adjacent
	var prone_los := LOSSystemClass.evaluate(
		shooter.grid_position,
		target.grid_position,
		map_data,
		game_state,
	)
	_assert(
		"Prone shooter mid-line WH00 is BLOCKED",
		prone_los.status == LOSSystemClass.Status.BLOCKED,
		"status=%s type=%s" % [LOSSystemClass.status_name(prone_los.status), prone_los.blocking_type],
	)


func _test_wall_cover_fixture() -> void:
	_bootstrap()
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)

	var shooter := Vector2i(10, 10)
	var wall := Vector2i(11, 10)
	var target := Vector2i(13, 10)
	map_data.set_object(wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)

	var usage := CoverSystemClass.evaluate_wall_cover_usage(shooter, target, map_data)
	_assert(
		"Wall cover fixture detects shooter wall usage",
		usage.shooter_using_wall_cover and usage.shooter_cover_cell == wall,
		"shooter_using=%s cell=%s"
		% [usage.shooter_using_wall_cover, usage.shooter_cover_cell],
	)

	var los := LOSSystemClass.evaluate(shooter, target, map_data, null)
	_assert(
		"Wall cover fixture allows peek LOS over adjacent wall",
		los.status != LOSSystemClass.Status.BLOCKED,
		"status=%s shooter_cover=%s target_cover=%s"
		% [
			LOSSystemClass.status_name(los.status),
			los.shooter_using_wall_cover,
			los.target_using_wall_cover,
		],
	)

	## Mid-line wall (neither side adjacent): hard BLOCKED — cannot shoot through a solid wall.
	## Adjacent wall-end peek is allowed separately (corner peek / adjacent fixture above).
	var far_shooter := Vector2i(8, 10)
	var far_target := Vector2i(14, 10)
	var mid_wall := Vector2i(11, 10)
	map_data.clear_object(wall)
	map_data.set_object(mid_wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var mid_line := LOSSystemClass.evaluate(far_shooter, far_target, map_data, null)
	_assert(
		"Wall cover fixture mid-line wall is BLOCKED",
		mid_line.status == LOSSystemClass.Status.BLOCKED,
		"status=%s type=%s"
		% [LOSSystemClass.status_name(mid_line.status), mid_line.blocking_type],
	)


func _test_corner_peek_around_wall_end() -> void:
	## Offensive corner peek: shooter adjacent to a wall END can fire around it.
	## A second hard wall further down the Bresenham line still hard-blocks.
	_bootstrap()
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)

	## Wall end adjacent to shooter; target around the corner (line hits only that end).
	##   S # .
	##   . . T
	var shooter := Vector2i(10, 10)
	var wall_end := Vector2i(11, 10)
	var target_around := Vector2i(12, 11)
	map_data.set_object(wall_end, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)

	var peek_los := LOSSystemClass.evaluate(shooter, target_around, map_data, null)
	_assert(
		"Corner peek allows shot around wall end",
		peek_los.status != LOSSystemClass.Status.BLOCKED,
		"status=%s peek=%s side=%s"
		% [
			LOSSystemClass.status_name(peek_los.status),
			peek_los.corner_peek,
			CoverSystemClass.peek_side_name(peek_los.peek_side),
		],
	)
	_assert(
		"Corner peek sets peek_side for animation",
		peek_los.corner_peek and peek_los.peek_side != CoverSystemClass.PeekSide.NONE,
		"peek=%s side=%s" % [peek_los.corner_peek, peek_los.peek_side],
	)

	## Second wall further along the line — not adjacent to shooter or target.
	## Line (10,10)->(14,12) visits (11,10)/(12,11)/(13,11); deeper wall at (12,11) blocks.
	var wall_deeper := Vector2i(12, 11)
	var target_behind := Vector2i(14, 12)
	map_data.set_object(wall_deeper, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var blocked_los := LOSSystemClass.evaluate(shooter, target_behind, map_data, null)
	_assert(
		"Corner peek does not pierce continuous wall",
		blocked_los.status == LOSSystemClass.Status.BLOCKED,
		"status=%s type=%s"
		% [LOSSystemClass.status_name(blocked_los.status), blocked_los.blocking_type],
	)

	## Target of a peek shot still receives cover eval (PseudoCover / corner when geometry fits).
	var cover := CoverSystemClass.evaluate_target_cover(shooter, target_around, map_data)
	_assert(
		"Peek target cover eval still runs",
		cover != null,
		"cover_type=%s qualifier=%s" % [cover.cover_type, cover.qualifier],
	)


func _test_corner_idle_at_wall_end() -> void:
	## Standing idle at a wall-end uses facing as synthetic aim (no shot target).
	_bootstrap()
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)

	var soldier := Vector2i(10, 10)
	var wall_end := Vector2i(11, 10)
	map_data.set_object(wall_end, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)

	var idle := CoverSystemClass.corner_idle_at_cell(soldier, Vector2i(1, 0), map_data)
	_assert(
		"Corner idle detects wall-end from facing",
		idle.is_corner and idle.peek_side != CoverSystemClass.PeekSide.NONE,
		"corner=%s side=%s cell=%s" % [idle.is_corner, idle.peek_side, idle.corner_cell],
	)

	var open := CoverSystemClass.corner_idle_at_cell(soldier, Vector2i(-1, 0), map_data)
	## Facing away may still find the adjacent end; require at least no crash / valid enum.
	_assert(
		"Corner idle returns a defined peek side enum",
		(
			open.peek_side == CoverSystemClass.PeekSide.NONE
			or open.peek_side == CoverSystemClass.PeekSide.LEFT
			or open.peek_side == CoverSystemClass.PeekSide.RIGHT
		),
		"side=%s" % open.peek_side,
	)


func _test_directional_cover() -> void:
	_bootstrap()
	var CoverPolicyClass := preload("res://scripts/gameplay_policies/cover_policy.gd")
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)

	var target := Vector2i(20, 20)
	var wall := Vector2i(19, 20) ## west of target
	map_data.set_object(wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)

	## Shooter west of wall: wall is between shooter and target → cover.
	var west_shooter := Vector2i(16, 20)
	var covered := CoverSystemClass.evaluate_target_cover(west_shooter, target, map_data)
	_assert(
		"Directional cover: wall on shooter-facing side grants cover",
		covered.cover_type != CoverSystemClass.CoverType.NONE
		and covered.source_cell == wall,
		"type=%s cell=%s" % [covered.cover_type, covered.source_cell],
	)

	## Flank from the east: same wall is behind the target relative to the shot → no cover.
	var east_shooter := Vector2i(24, 20)
	var flanked := CoverSystemClass.evaluate_target_cover(east_shooter, target, map_data)
	_assert(
		"Directional cover: flanking defeats the same wall",
		flanked.cover_type == CoverSystemClass.CoverType.NONE,
		"type=%s cell=%s" % [flanked.cover_type, flanked.source_cell],
	)

	## Obstruction beside target but off the shot vector grants no cover.
	map_data.clear_object(wall)
	var side_wall := Vector2i(20, 19) ## north of target; shot is east-west
	map_data.set_object(side_wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var side_check := CoverSystemClass.evaluate_target_cover(west_shooter, target, map_data)
	_assert(
		"Directional cover: off-axis adjacent wall grants no cover",
		side_check.cover_type == CoverSystemClass.CoverType.NONE,
		"type=%s cells=%s" % [side_check.cover_type, str(side_check.qualifying_cells)],
	)

	## Wall 4+ tiles from target is outside INITCoverRangeLimit.
	map_data.clear_object(side_wall)
	var far_wall := Vector2i(15, 20) ## Chebyshev 5 from target
	map_data.set_object(far_wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var far_check := GameplayPolicies.cover.cover_check(west_shooter, target, map_data)
	_assert(
		"Directional cover: wall beyond range limit grants no cover",
		not far_check.in_cover,
		"cells=%s limit=%d" % [str(far_check.qualifying_cells), GameplayPolicies.cover.cover_range_limit],
	)

	## Height 1 (haybail) and height 2 (wall) both grant cover when on the facing side.
	map_data.clear_object(far_wall)
	var low_cover := Vector2i(19, 20)
	map_data.set_object(low_cover, MapObjectRegistryClass.TYPE_HAYBAIL)
	_assert(
		"Directional cover: height-1 tile can grant cover",
		map_data.obstruction_height(low_cover) >= 1
		and CoverSystemClass.evaluate_target_cover(west_shooter, target, map_data).cover_type
		!= CoverSystemClass.CoverType.NONE,
		"height=%d" % map_data.obstruction_height(low_cover),
	)
	map_data.clear_object(low_cover)
	var high_cover := Vector2i(19, 20)
	map_data.set_object(high_cover, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	_assert(
		"Directional cover: height-2 tile can grant cover",
		map_data.obstruction_height(high_cover) >= 2
		and CoverSystemClass.evaluate_target_cover(west_shooter, target, map_data).cover_type
		!= CoverSystemClass.CoverType.NONE,
		"height=%d" % map_data.obstruction_height(high_cover),
	)

	## Corner offset relative to shot → PseudoCover / CORNER qualifier.
	map_data.clear_object(high_cover)
	var corner := Vector2i(19, 19)
	map_data.set_object(corner, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var corner_check := GameplayPolicies.cover.cover_check(west_shooter, target, map_data)
	_assert(
		"Directional cover: diagonal facing tile is CORNER qualifier",
		corner_check.in_cover and corner_check.qualifier == CoverPolicyClass.Qualifier.CORNER,
		"in_cover=%s qualifier=%s" % [corner_check.in_cover, corner_check.qualifier],
	)


func _test_rng_seed_reproducibility() -> void:
	GameRandom.reseed(42)
	var a: Array[float] = []
	for i in range(8):
		a.append(GameRandom.randf())

	GameRandom.reseed(42)
	var b: Array[float] = []
	for i in range(8):
		b.append(GameRandom.randf())

	_assert("Same RNG seed produces identical sequence", a == b, "a=%s b=%s" % [str(a), str(b)])

	GameRandom.reseed(99)
	var c: Array[float] = []
	for i in range(8):
		c.append(GameRandom.randf())
	_assert("Different RNG seed diverges", a != c)

	## Snapshot/restore for replay debugging.
	GameRandom.reseed(7)
	GameRandom.randf()
	GameRandom.randf()
	var snap := GameRandom.get_snapshot()
	var next_a := GameRandom.randf()
	GameRandom.restore_snapshot(snap)
	var next_b := GameRandom.randf()
	_assert(
		"RNG snapshot restore continues the same stream",
		is_equal_approx(next_a, next_b),
		"a=%s b=%s" % [next_a, next_b],
	)
	## Bounded probability helpers (isolated seed so they cannot pollute later tests).
	GameRandom.reseed(1)
	_assert("chance(1.0) always true", GameRandom.chance(1.0))
	GameRandom.reseed(1)
	_assert("chance(0.0) always false", not GameRandom.chance(0.0))


func _capture_shot_outcomes(seed_value: int) -> Array[bool]:
	_bootstrap()
	GameRandom.reseed(seed_value)
	SimulationClock.reset()

	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var game_state := _make_game_state(map_data)
	var shooter := game_state.get_soldier(Team.USA, 1)
	var target := game_state.get_soldier(Team.GERMANY, 1)
	shooter.grid_position = Vector2i(20, 30)
	target.grid_position = Vector2i(23, 30)
	shooter.clear_path()
	target.clear_path()

	var hits: Array[bool] = []
	for i in range(6):
		target.is_dead = false
		target.position_state = 0
		shooter.ammo_current = maxi(shooter.ammo_current, 30)
		game_state.session.get_fireteam(Team.USA).face_toward_tile(1, target.grid_position)
		CombatSystemClass.begin_fire_prep(shooter)
		SimulationClock.advance_msec(int(GameplayPolicies.hit.fire_prep_delay_sec * 1000.0) + 50)
		var shot := CombatSystemClass.resolve_shot(game_state, shooter, target, false)
		hits.append(shot.fired and shot.hit)
		SimulationClock.advance_msec(2000)
	return hits


func _test_firing_sequence_reproducibility() -> void:
	var first := _capture_shot_outcomes(777)
	var second := _capture_shot_outcomes(777)
	_assert(
		"Same firing sequence produces identical outcomes",
		first == second and first.size() == 6,
		"first=%s second=%s" % [str(first), str(second)],
	)


func _capture_grenade_outcomes(seed_value: int) -> Array[String]:
	_bootstrap()
	GameRandom.reseed(seed_value)
	SimulationClock.reset()

	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var game_state := _make_game_state(map_data)
	var thrower := game_state.get_soldier(Team.USA, 1)
	var victim := game_state.get_soldier(Team.GERMANY, 1)
	thrower.grid_position = Vector2i(20, 30)
	victim.grid_position = Vector2i(21, 30)
	thrower.clear_path()
	victim.clear_path()

	var outcomes: Array[String] = []
	for i in range(5):
		thrower.is_dead = false
		victim.is_dead = false
		victim.stunned_until_msec = 0
		victim.stand_on_stun_recovery = false
		victim.position_state = 0
		var explosion := CombatSystemClass.resolve_grenade(game_state, thrower, victim.grid_position)
		if not explosion.killed.is_empty():
			outcomes.append("kill")
		elif not explosion.stunned.is_empty():
			outcomes.append("stun")
		else:
			outcomes.append("none")
	return outcomes


func _test_grenade_sequence_reproducibility() -> void:
	var first := _capture_grenade_outcomes(12345)
	var second := _capture_grenade_outcomes(12345)
	_assert(
		"Same grenade sequence produces identical outcomes",
		first == second and first.size() == 5,
		"first=%s second=%s" % [str(first), str(second)],
	)


func _test_policy_defaults_unchanged() -> void:
	GameplayPolicies.reset_all_to_defaults()
	_assert("Hit chance policy base unchanged", is_equal_approx(GameplayPolicies.hit.clear_base_hit_chance, 0.78))
	_assert("Grenade policy range is recovered 5", GameplayPolicies.grenade.throw_range == 5)
	_assert("Grenade policy blast unchanged", GameplayPolicies.grenade.blast_radius == 3)
	_assert("Grenade policy kill chance unchanged", is_equal_approx(GameplayPolicies.grenade.kill_chance, 0.25))
	_assert("Suppression pinned threshold unchanged", is_equal_approx(GameplayPolicies.suppression.pinned_threshold, 45.0))
	_assert("Movement run speed unchanged", is_equal_approx(GameplayPolicies.movement.speed_run, 2.0))
	_assert("Vision cone range bonus unchanged", GameplayPolicies.vision.cone_range_bonus == 8)
	_assert("Cover moderate hit mult unchanged", is_equal_approx(GameplayPolicies.cover.moderate_hit_mult, 0.5))
	_assert("LOS peek adjacency unchanged", GameplayPolicies.los.peek_adjacency_chebyshev == 1)
	var garand := GameplayPolicies.weapons.create_weapon("m1_garand")
	_assert(
		"Weapon policy M1 Garand cooldown unchanged",
		garand != null and is_equal_approx(garand.fire_interval_sec, 1.2),
		"interval=%s" % [garand.fire_interval_sec if garand else "null"],
	)
	_assert(
		"Weapon policy M1 Garand range unchanged",
		garand != null and garand.range_tiles == 18,
		"range=%s" % [garand.range_tiles if garand else "null"],
	)
	GameplayPolicies.reload_from_config()
	_assert(
		"Config reload preserves M1 Garand interval",
		is_equal_approx(GameplayPolicies.weapons.fire_interval_sec("m1_garand"), 1.2),
	)
	_assert("Simulation tick hz default 20", SimulationClock.tick_hz == 20)
	_assert("Simulation tick msec is 50", SimulationClock.tick_msec() == 50)


func _test_recovered_weapon_stats() -> void:
	GameplayPolicies.reset_all_to_defaults()
	var WeaponPolicyClass := preload("res://scripts/gameplay_policies/weapon_policy.gd")
	var expected := {
		"m1_garand": {"rpa": 1, "ammo": 70, "speed": 6, "supp": 0.25, "sl": 25.0, "saf": 0.5, "fo": "cubic", "aim": 1.1},
		"kar98k": {"rpa": 1, "ammo": 70, "speed": 6, "supp": 0.25, "sl": 25.0, "saf": 0.5, "fo": "cubic", "aim": 1.1},
		"thompson": {"rpa": 4, "ammo": 200, "speed": 6, "supp": 2.0, "sl": 13.0, "saf": 1.5, "fo": "pentic", "aim": 1.1},
		"mp40": {"rpa": 5, "ammo": 200, "speed": 6, "supp": 2.0, "sl": 13.0, "saf": 1.5, "fo": "pentic", "aim": 1.1},
		"bar": {"rpa": 7, "ammo": 900, "speed": 6, "supp": 0.6, "sl": 25.0, "saf": 2.0, "fo": "cubic", "aim": 1.7},
		"mg42": {"rpa": 6, "ammo": 900, "speed": 7, "supp": 0.6, "sl": 25.0, "saf": 2.0, "fo": "cubic", "aim": 1.7},
	}
	for weapon_id in expected.keys():
		var w := GameplayPolicies.weapons.create_weapon(weapon_id)
		var e: Dictionary = expected[weapon_id]
		_assert(
			"%s recovered stats" % weapon_id,
			w != null
			and w.rounds_per_attack == int(e.rpa)
			and w.ammo_capacity == int(e.ammo)
			and w.bullet_speed == int(e.speed)
			and is_equal_approx(w.suppression_generated, float(e.supp))
			and is_equal_approx(w.stress_limit, float(e.sl))
			and is_equal_approx(w.stress_aim_factor, float(e.saf))
			and w.range_falloff == str(e.fo)
			and is_equal_approx(w.aim_delay_sec, float(e.aim)),
			"weapon=%s" % [w.weapon_id if w else "null"],
		)
	var bar := GameplayPolicies.weapons.create_weapon("bar")
	var mg42 := GameplayPolicies.weapons.create_weapon("mg42")
	var garand := GameplayPolicies.weapons.create_weapon("m1_garand")
	var thompson := GameplayPolicies.weapons.create_weapon("thompson")
	_assert(
		"aim_delay ordering: LMGs > rifles/SMGs",
		bar.aim_delay_sec > garand.aim_delay_sec
		and is_equal_approx(bar.aim_delay_sec, mg42.aim_delay_sec)
		and is_equal_approx(garand.aim_delay_sec, thompson.aim_delay_sec),
	)
	_assert("squad limit BAR is 1", WeaponPolicyClass.squad_limit("bar") == 1)
	_assert("squad limit Thompson is 2", WeaponPolicyClass.squad_limit("thompson") == 2)
	_assert("squad limit MG42 is 1", WeaponPolicyClass.squad_limit("mg42") == 1)
	_assert("squad limit MP40 is 2", WeaponPolicyClass.squad_limit("mp40") == 2)
	_assert("squad limit rifle unlimited", WeaponPolicyClass.squad_limit("m1_garand") == -1)


func _test_smg_vs_rifle_range_falloff() -> void:
	GameplayPolicies.reset_all_to_defaults()
	var from_cell := Vector2i(0, 0)
	var to_cell := Vector2i(12, 0)
	var rifle := GameplayPolicies.weapons.create_weapon("m1_garand")
	var smg := GameplayPolicies.weapons.create_weapon("thompson")
	var rifle_chance := CombatSystemClass.hit_chance(from_cell, to_cell, rifle)
	var smg_chance := CombatSystemClass.hit_chance(from_cell, to_cell, smg)
	_assert(
		"SMG hit chance at range 12 < rifle hit chance at range 12",
		smg_chance < rifle_chance,
		"smg=%.3f rifle=%.3f" % [smg_chance, rifle_chance],
	)


func _test_grenade_range_cap() -> void:
	_bootstrap()
	var game_state := _make_game_state()
	var thrower := game_state.get_soldier(Team.USA, 1)
	thrower.grid_position = Vector2i(20, 30)
	thrower.clear_path()
	var cmd := GrenadeCommandClass.new()
	cmd.team_id = Team.USA
	cmd.soldier_id = 1
	cmd.target_cell = Vector2i(26, 30) ## manhattan 6 > recovered throw_range 5
	var result := ActionResolverClass.execute_grenade(
		game_state,
		cmd,
		CommandContextClass.new(),
	)
	_assert(
		"Grenade throws beyond 5 tiles are refused",
		not result.success,
		result.status_message,
	)
	cmd.target_cell = Vector2i(25, 30) ## manhattan 5 == max
	result = ActionResolverClass.execute_grenade(
		game_state,
		cmd,
		CommandContextClass.new(),
	)
	_assert("Grenade throw at exactly 5 tiles succeeds", result.success, result.status_message)


func _test_stress_model() -> void:
	GameplayPolicies.reset_all_to_defaults()
	var SuppressionPolicyClass := preload("res://scripts/gameplay_policies/suppression_policy.gd")
	var policy := GameplayPolicies.suppression
	_assert(
		"STRESS_SCALE is single conversion constant",
		is_equal_approx(SuppressionPolicyClass.STRESS_SCALE, 100.0 / 7.0),
	)

	var thompson := GameplayPolicies.weapons.create_weapon("thompson")
	var garand := GameplayPolicies.weapons.create_weapon("m1_garand")
	var bar := GameplayPolicies.weapons.create_weapon("bar")
	var smg_gain := policy.suppression_gain_runtime(thompson.suppression_generated)
	var rifle_gain := policy.suppression_gain_runtime(garand.suppression_generated)
	_assert(
		"SMG fire generates more suppression than rifle fire",
		smg_gain > rifle_gain,
		"smg=%.3f rifle=%.3f" % [smg_gain, rifle_gain],
	)
	var smg_cap := policy.weapon_stress_cap_runtime(thompson.stress_limit)
	var lmg_cap := policy.weapon_stress_cap_runtime(bar.stress_limit)
	_assert(
		"LMG stress cap is higher than SMG cap",
		lmg_cap > smg_cap,
		"lmg=%.1f smg=%.1f" % [lmg_cap, smg_cap],
	)

	## Calm vs stressed: long-range accuracy falls harder than point-blank.
	var calm_near := policy.accuracy_modifier_for(0.0, 0, 1.0)
	var stressed_near := policy.accuracy_modifier_for(100.0, 0, 1.0)
	var calm_far := policy.accuracy_modifier_for(0.0, 6, 1.0)
	var stressed_far := policy.accuracy_modifier_for(100.0, 6, 1.0)
	var near_ratio := stressed_near / maxf(calm_near, 0.0001)
	var far_ratio := stressed_far / maxf(calm_far, 0.0001)
	_assert(
		"Stress hurts long-range accuracy more than point-blank",
		far_ratio < near_ratio,
		"near_ratio=%.3f far_ratio=%.3f" % [near_ratio, far_ratio],
	)

	## Decay toward 0 when unthreatened.
	var decayed := policy.apply_stress_decay(50.0, false)
	_assert("Stress decays when unthreatened", decayed < 50.0 and decayed >= 0.0, "decayed=%.3f" % decayed)
	var fully := 50.0
	for _i in 20:
		fully = policy.apply_stress_decay(fully, false)
	_assert("Stress decays to 0", is_equal_approx(fully, 0.0), "fully=%.5f" % fully)

	## Tier mapping is one documented function.
	var tier_calm := policy.effective_tier_from_stress(0.0)
	var tier_max := policy.effective_tier_from_stress(100.0)
	_assert(
		"effective_tier falls as stress rises",
		tier_calm > tier_max,
		"calm=%.2f max=%.2f" % [tier_calm, tier_max],
	)


func _test_fixed_simulation_tick() -> void:
	_bootstrap()
	SimulationClock.reset()
	SimulationClock.reset_tick_defaults()
	_assert("Tick hz is 20", SimulationClock.tick_hz == SimulationClock.DEFAULT_TICK_HZ)
	_assert("Tick msec is 50", SimulationClock.tick_msec() == 50)
	## 10 ticks = 500 ms = one combat scan interval at default policy.
	for _i in 10:
		SimulationClock.advance_tick()
	_assert(
		"10 ticks advance exactly 500 msec",
		SimulationClock.get_ticks_msec() == 500,
		"msec=%d" % SimulationClock.get_ticks_msec(),
	)
	## Combat scan cadence stays 0.5s of sim time (not every tick).
	var scan_msec := int(round(GameplayPolicies.hit.auto_fire_scan_interval * 1000.0))
	_assert("Combat scan interval still 500 msec", scan_msec == 500)
	_assert(
		"Combat scans per second unchanged at 2 Hz",
		scan_msec / SimulationClock.tick_msec() == 10,
		"ticks_per_scan=%d" % (scan_msec / SimulationClock.tick_msec()),
	)


func _test_movement_frame_rate_independence() -> void:
	## Same seed + same sim time ⇒ identical movement tiles regardless of render FPS.
	var fps_list: Array[int] = [30, 60, 120, 240]
	var timelines: Array[Dictionary] = []
	for fps in fps_list:
		timelines.append(_simulate_move_timeline_at_fps(fps))

	var reference: Dictionary = timelines[0]
	_assert(
		"Frame-rate move timelines are non-empty",
		not (reference.get("tiles", []) as Array).is_empty(),
	)
	for i in range(1, timelines.size()):
		var other: Dictionary = timelines[i]
		_assert(
			"Movement tiles identical at %d FPS vs 30 FPS" % fps_list[i],
			reference.get("tiles", []) == other.get("tiles", []),
			"ref=%s other=%s" % [reference.get("tiles", []), other.get("tiles", [])],
		)
		_assert(
			"Final cell identical at %d FPS vs 30 FPS" % fps_list[i],
			reference.get("final_cell", Vector2i(-1, -1)) == other.get("final_cell", Vector2i(-1, -1)),
		)
		_assert(
			"Completion sim msec identical at %d FPS vs 30 FPS" % fps_list[i],
			int(reference.get("complete_msec", -1)) == int(other.get("complete_msec", -2)),
			"ref=%s other=%s" % [reference.get("complete_msec", -1), other.get("complete_msec", -2)],
		)
		_assert(
			"RNG snapshot identical at %d FPS after move" % fps_list[i],
			reference.get("rng_snapshot", {}) == other.get("rng_snapshot", {}),
		)


func _simulate_move_timeline_at_fps(fps: int) -> Dictionary:
	_bootstrap()
	SimulationClock.reset()
	GameRandom.begin_match(GameRandom.DEFAULT_SEED)
	var game_state := _make_game_state()
	var soldier := game_state.get_soldier(Team.USA, 1)
	var start := soldier.grid_position
	var target := start + Vector2i(3, 0)
	if not game_state.map_data.is_walkable(target):
		target = start + Vector2i(0, 3)

	var cmd := MoveCommandClass.new()
	cmd.team_id = Team.USA
	cmd.soldier_id = 1
	cmd.target_cell = target
	cmd.movement_mode = MovementModeClass.RUN
	cmd.scope = MoveCommandClass.Scope.SINGLE
	var order := ActionResolverClass.execute_move(game_state, cmd, _path_context(game_state.map_data))
	if not order.success:
		return {"tiles": [], "final_cell": Vector2i(-1, -1), "complete_msec": -1, "rng_snapshot": {}}

	var frame_delta := 1.0 / float(fps)
	var accum := 0.0
	var tick_sec := SimulationClock.tick_sec()
	var tiles: Array[Vector2i] = [soldier.grid_position]
	var complete_msec := -1
	var guard := 0
	while soldier.is_moving and guard < 200000:
		guard += 1
		accum += frame_delta
		while accum >= tick_sec:
			accum -= tick_sec
			SimulationClock.advance_tick()
			var move_result := ActionResolverClass.process_movement_tick(game_state)
			for step in move_result.movement_steps:
				tiles.append(step.tile)
			if not move_result.movement_completions.is_empty() and complete_msec < 0:
				complete_msec = SimulationClock.get_ticks_msec()

	return {
		"tiles": tiles,
		"final_cell": soldier.grid_position,
		"complete_msec": complete_msec,
		"rng_snapshot": GameRandom.get_snapshot(),
	}


func _test_object_id_and_registry() -> void:
	_bootstrap()
	var game_state := _make_game_state()
	var soldier := game_state.get_soldier(Team.USA, 1)
	var expected_id := ObjectId.soldier(Team.USA, 1)
	_assert(
		"Soldier object_id is stable",
		soldier.object_id == expected_id and expected_id == "soldier:1:1",
		"object_id=%s expected=%s" % [soldier.object_id, expected_id],
	)
	var via_registry := game_state.objects.get_soldier(expected_id)
	var via_game_state := game_state.get_soldier_by_id(expected_id)
	_assert(
		"Soldier resolves via GameState.objects",
		via_registry == soldier and via_game_state == soldier,
		"registry=%s game_state=%s" % [via_registry != null, via_game_state != null],
	)


func _test_map_object_registry() -> void:
	_bootstrap()
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var game_state := _make_game_state(map_data)
	var cell := Vector2i(12, 14)
	map_data.set_object(cell, MapObjectRegistryClass.TYPE_TREE)
	game_state.objects.register_map_object(cell, MapObjectRegistryClass.TYPE_TREE)
	var oid := ObjectId.map_object(cell)
	var entry := game_state.objects.get_map_object(oid)
	var at_cell := game_state.objects.get_map_object_at(cell)
	_assert(
		"Map object registers at cell",
		game_state.objects.has(oid)
		and entry.get("type_id", "") == MapObjectRegistryClass.TYPE_TREE
		and at_cell.get("cell", Vector2i(-1, -1)) == cell,
		"oid=%s entry=%s" % [oid, str(entry)],
	)


func _test_grenade_object_registry() -> void:
	_bootstrap()
	var game_state := _make_game_state()
	var thrower := game_state.get_soldier(Team.USA, 1)
	thrower.grid_position = Vector2i(20, 30)
	thrower.clear_path()
	var target_cell := Vector2i(22, 30)
	var grenade_id := ObjectId.grenade(Team.USA, 1)

	var cmd := GrenadeCommandClass.new()
	cmd.team_id = Team.USA
	cmd.soldier_id = 1
	cmd.target_cell = target_cell
	var result := ActionResolverClass.execute_grenade(
		game_state,
		cmd,
		CommandContextClass.new(),
	)
	_assert("Grenade registry registers on throw", result.success, result.status_message)
	var pending := game_state.objects.get_grenade(grenade_id)
	_assert(
		"Grenade object present while fuse armed",
		pending != null
		and pending.target_cell == target_cell
		and game_state.objects.kind_of(grenade_id) == ObjectRegistry.KIND_GRENADE,
		"pending=%s" % [pending != null],
	)

	SimulationClock.advance_msec(GameplayPolicies.grenade.fuse_msec + 1)
	ActionResolverClass.process_combat_tick(game_state)
	_assert(
		"Grenade object clears on detonation",
		game_state.objects.get_grenade(grenade_id) == null
		and not game_state.objects.has(grenade_id),
		"still_registered=%s" % game_state.objects.has(grenade_id),
	)


func _test_team_soldier_key_consistent() -> void:
	_assert(
		"team_soldier_key matches Team.soldier_key",
		ObjectId.team_soldier_key(Team.USA, 2) == Team.soldier_key(Team.USA, 2)
		and ObjectId.team_soldier_key(Team.USA, 2) == "1:2"
		and SoldierState.enemy_tracking_key(Team.GERMANY, 3) == "2:3",
		"keys diverge",
	)


func _test_perception_cache_incremental() -> void:
	_bootstrap()
	const PerceptionCacheClass := preload("res://scripts/combat/perception_cache.gd")
	PerceptionCacheClass.clear_all()
	PerceptionCacheClass.reset_counters()
	var game_state := _make_game_state()
	var usa := game_state.get_soldier(Team.USA, 1)
	var ger := game_state.get_soldier(Team.GERMANY, 1)
	## Place within close-force distance on open ground.
	usa.grid_position = Vector2i(20, 30)
	ger.grid_position = Vector2i(24, 30)
	usa.facing_direction = Vector2i(1, 0)
	ger.facing_direction = Vector2i(-1, 0)

	var score1 := CombatSystemClass.get_visibility_score(usa, ger, game_state)
	var misses_after_first := PerceptionCacheClass.spot_cache_misses
	var los_after_first := PerceptionCacheClass.los_evals
	var score2 := CombatSystemClass.get_visibility_score(usa, ger, game_state)
	_assert(
		"Perception cache hit on unchanged pair",
		score1 == score2 and PerceptionCacheClass.spot_cache_hits >= 1,
		"score1=%s score2=%s hits=%d" % [score1, score2, PerceptionCacheClass.spot_cache_hits],
	)
	_assert(
		"Perception cache avoids second LOS",
		PerceptionCacheClass.los_evals == los_after_first,
		"los grew from %d to %d" % [los_after_first, PerceptionCacheClass.los_evals],
	)

	## Moving one soldier dirties only pairs involving that soldier.
	PerceptionCacheClass.reset_counters()
	usa.grid_position = Vector2i(21, 30)
	CombatSystemClass.notify_soldier_perception_dirty(game_state, usa)
	var dirty_after_move := PerceptionCacheClass.dirty_count()
	_assert(
		"Dirty queue enqueues affected pairs only",
		dirty_after_move > 0 and dirty_after_move <= 64,
		"dirty=%d misses_first=%d" % [dirty_after_move, misses_after_first],
	)
	CombatSystemClass.process_perception_tick(game_state)
	_assert(
		"Dirty budget processes pairs",
		PerceptionCacheClass.dirty_processed > 0,
		"processed=%d remaining=%d" % [
			PerceptionCacheClass.dirty_processed,
			PerceptionCacheClass.dirty_count(),
		],
	)
	print(
		"[Profiler baseline] perception incremental: dirty_enqueued=%d dirty_done=%d los=%d spotHit=%d"
		% [
			PerceptionCacheClass.dirty_enqueued,
			PerceptionCacheClass.dirty_processed,
			PerceptionCacheClass.los_evals,
			PerceptionCacheClass.spot_cache_hits,
		]
	)
