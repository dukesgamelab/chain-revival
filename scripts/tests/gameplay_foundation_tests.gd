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

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_bootstrap()
	_test_fortress_map_loads()
	_test_soldier_movement()
	_test_firing()
	_test_grenade_throwing()
	_test_los_fixture()
	_test_wall_cover_fixture()
	_test_rng_seed_reproducibility()
	_test_firing_sequence_reproducibility()
	_test_grenade_sequence_reproducibility()
	_test_policy_defaults_unchanged()
	_test_object_id_and_registry()
	_test_map_object_registry()
	_test_grenade_object_registry()
	_test_team_soldier_key_consistent()

	print("")
	print("Gameplay foundation tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _bootstrap() -> void:
	SimulationClock.reset()
	DeterministicRNG.reseed(DeterministicRNG.DEFAULT_SEED)
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

	var step := soldier.current_path[1]
	var step_delta := step - start
	ActionResolverClass.on_movement_step(game_state, Team.USA, 1, step, step_delta)
	_assert(
		"Soldier movement advances grid position",
		soldier.grid_position == step,
		"expected %s got %s" % [step, soldier.grid_position],
	)

	ActionResolverClass.on_movement_complete(game_state, Team.USA, 1)
	_assert(
		"Soldier movement completion clears moving flag",
		not soldier.is_moving,
		"is_moving still true",
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

	## Mid-line wall: current behavior applies wall cover (COVER), not hard BLOCKED.
	## Trees hard-block; walls on the fire line without adjacent peek become cover modifiers.
	var far_shooter := Vector2i(8, 10)
	var far_target := Vector2i(14, 10)
	var mid_wall := Vector2i(11, 10)
	map_data.clear_object(wall)
	map_data.set_object(mid_wall, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	var mid_line := LOSSystemClass.evaluate(far_shooter, far_target, map_data, null)
	_assert(
		"Wall cover fixture mid-line wall yields cover status",
		mid_line.status == LOSSystemClass.Status.COVER
		and mid_line.cover_type != CoverSystemClass.CoverType.NONE,
		"status=%s cover=%s"
		% [LOSSystemClass.status_name(mid_line.status), mid_line.cover_type],
	)


func _test_rng_seed_reproducibility() -> void:
	DeterministicRNG.reseed(42)
	var a: Array[float] = []
	for i in range(8):
		a.append(DeterministicRNG.randf())

	DeterministicRNG.reseed(42)
	var b: Array[float] = []
	for i in range(8):
		b.append(DeterministicRNG.randf())

	_assert("Same RNG seed produces identical sequence", a == b, "a=%s b=%s" % [str(a), str(b)])

	DeterministicRNG.reseed(99)
	var c: Array[float] = []
	for i in range(8):
		c.append(DeterministicRNG.randf())
	_assert("Different RNG seed diverges", a != c)


func _capture_shot_outcomes(seed_value: int) -> Array[bool]:
	_bootstrap()
	DeterministicRNG.reseed(seed_value)
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
	DeterministicRNG.reseed(seed_value)
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
	_assert("Grenade policy range unchanged", GameplayPolicies.grenade.throw_range == 7)
	_assert("Grenade policy blast unchanged", GameplayPolicies.grenade.blast_radius == 3)
	_assert("Grenade policy kill chance unchanged", is_equal_approx(GameplayPolicies.grenade.kill_chance, 0.25))
	_assert("Suppression pinned threshold unchanged", is_equal_approx(GameplayPolicies.suppression.pinned_threshold, 45.0))
	_assert("Movement run speed unchanged", is_equal_approx(GameplayPolicies.movement.speed_run, 2.0))


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
