extends Node
## Headless tests for 8-direction facing, face command, cones, save/load, animation map.
## Run: Godot --headless --path <project> res://scripts/tests/facing_eight_way_tests.tscn


const MapDataClass := preload("res://scripts/map/map_data.gd")
const GameSessionClass := preload("res://scripts/core/game_session.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")
const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")
const CommandContextClass := preload("res://scripts/core/command_context.gd")
const FaceCommandClass := preload("res://scripts/commands/face_command.gd")
const MoveCommandClass := preload("res://scripts/commands/move_command.gd")
const MovementModeClass := preload("res://scripts/enums/movement_mode.gd")
const ConeOfFireClass := preload("res://scripts/combat/cone_of_fire.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	SimulationClock.reset()
	GameRandom.reseed(GameRandom.DEFAULT_SEED)
	GameplayPolicies.reset_all_to_defaults()
	_test_normalization()
	_test_toward_cell_octants()
	_test_face_command_eight_ways()
	_test_movement_final_facing()
	_test_save_load_eight_ways()
	_test_cone_cardinal_and_diagonal()
	_test_cone_covers_full_facing_sector()
	_test_animation_direction_mapping()
	print("")
	print("Facing eight-way tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail if not detail.is_empty() else "assertion failed"])


func _test_normalization() -> void:
	var cases: Array = [
		[Vector2i(0, -1), FacingDirection.NORTH],
		[Vector2i(1, -1), FacingDirection.NORTHEAST],
		[Vector2i(1, 0), FacingDirection.EAST],
		[Vector2i(1, 1), FacingDirection.SOUTHEAST],
		[Vector2i(0, 1), FacingDirection.SOUTH],
		[Vector2i(-1, 1), FacingDirection.SOUTHWEST],
		[Vector2i(-1, 0), FacingDirection.WEST],
		[Vector2i(-1, -1), FacingDirection.NORTHWEST],
		[Vector2i(5, 0), FacingDirection.EAST],
		[Vector2i(0, -4), FacingDirection.NORTH],
		[Vector2i(3, -8), FacingDirection.NORTHEAST],
		[Vector2i(8, -3), FacingDirection.NORTHEAST],
		[Vector2i(-7, 5), FacingDirection.SOUTHWEST],
		[Vector2i(-9, 2), FacingDirection.SOUTHWEST],
		[Vector2i(-2, -2), FacingDirection.NORTHWEST],
	]
	for entry in cases:
		var input: Vector2i = entry[0]
		var expected: Vector2i = entry[1]
		var got := FacingDirection.normalize(input)
		_assert(
			"normalize %s → %s" % [input, FacingDirection.direction_name(expected)],
			got == expected,
			"got %s (%s)" % [got, FacingDirection.direction_name(got)],
		)
	_assert("from_step diagonal NE", FacingDirection.from_step(Vector2i(1, -1)) == FacingDirection.NORTHEAST)
	_assert("from_step diagonal SW", FacingDirection.from_step(Vector2i(-1, 1)) == FacingDirection.SOUTHWEST)
	_assert("ZERO → NORTH", FacingDirection.normalize(Vector2i.ZERO) == FacingDirection.NORTH)


func _test_toward_cell_octants() -> void:
	var origin := Vector2i(20, 20)
	var targets := {
		FacingDirection.NORTH: Vector2i(20, 10),
		FacingDirection.NORTHEAST: Vector2i(25, 15),
		FacingDirection.EAST: Vector2i(30, 20),
		FacingDirection.SOUTHEAST: Vector2i(25, 25),
		FacingDirection.SOUTH: Vector2i(20, 30),
		FacingDirection.SOUTHWEST: Vector2i(15, 25),
		FacingDirection.WEST: Vector2i(10, 20),
		FacingDirection.NORTHWEST: Vector2i(15, 15),
	}
	for expected in targets.keys():
		var cell: Vector2i = targets[expected]
		var got := FacingDirection.toward_cell(origin, cell)
		_assert(
			"toward_cell %s" % FacingDirection.direction_name(expected),
			got == expected,
			"target=%s got=%s" % [cell, got],
		)


func _make_game_state() -> GameStateClass:
	var map_data: MapDataClass = MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var blue: Array[Vector2i] = map_data.team_1_spawn_points
	var red: Array[Vector2i] = map_data.team_2_spawn_points
	if blue.is_empty():
		blue = MapDataClass.default_usa_spawn_points()
	if red.is_empty():
		red = MapDataClass.default_germany_spawn_points()
	var session := GameSessionClass.new(blue, red)
	var game_state: GameStateClass = session.create_game_state(map_data)
	ActionResolverClass.apply_match_start_setup(game_state)
	return game_state


func _test_face_command_eight_ways() -> void:
	var game_state := _make_game_state()
	var soldier := game_state.get_soldier(Team.USA, 1)
	soldier.grid_position = Vector2i(40, 40)
	soldier.clear_path()
	var offsets := [
		[Vector2i(0, -3), FacingDirection.NORTH],
		[Vector2i(3, -3), FacingDirection.NORTHEAST],
		[Vector2i(3, 0), FacingDirection.EAST],
		[Vector2i(3, 3), FacingDirection.SOUTHEAST],
		[Vector2i(0, 3), FacingDirection.SOUTH],
		[Vector2i(-3, 3), FacingDirection.SOUTHWEST],
		[Vector2i(-3, 0), FacingDirection.WEST],
		[Vector2i(-3, -3), FacingDirection.NORTHWEST],
	]
	for entry in offsets:
		var offset: Vector2i = entry[0]
		var expected: Vector2i = entry[1]
		var cmd := FaceCommandClass.new()
		cmd.team_id = Team.USA
		cmd.soldier_id = 1
		cmd.target_cell = soldier.grid_position + offset
		cmd.scope = FaceCommandClass.Scope.SINGLE
		var result := ActionResolverClass.execute_face(game_state, cmd)
		_assert(
			"Face command %s succeeds" % FacingDirection.direction_name(expected),
			result.success,
			result.status_message,
		)
		_assert(
			"Face command sets %s" % FacingDirection.direction_name(expected),
			soldier.facing_direction == expected,
			"got %s status=%s" % [soldier.facing_direction, result.status_message],
		)
		_assert(
			"Face status names %s" % FacingDirection.direction_name(expected),
			result.status_message.contains(FacingDirection.direction_name(expected)),
			result.status_message,
		)


func _test_movement_final_facing() -> void:
	var game_state := _make_game_state()
	var soldier := game_state.get_soldier(Team.USA, 1)
	var start := Vector2i(30, 30)
	soldier.grid_position = start
	soldier.clear_path()
	## Path ends with a NE step.
	soldier.assign_path([start, start + Vector2i(1, 0), start + Vector2i(2, -1)], 2.0)
	var guard := 0
	while soldier.is_moving and guard < 5000:
		SimulationClock.advance_tick()
		ActionResolverClass.process_movement_tick(game_state)
		guard += 1
	_assert("Move NE path completes", not soldier.is_moving, "guard=%d" % guard)
	_assert(
		"Final facing is NORTHEAST",
		soldier.facing_direction == FacingDirection.NORTHEAST,
		"got %s at %s" % [soldier.facing_direction, soldier.grid_position],
	)

	soldier.grid_position = start
	soldier.assign_path([start, start + Vector2i(-1, 1)], 2.0)
	guard = 0
	while soldier.is_moving and guard < 5000:
		SimulationClock.advance_tick()
		ActionResolverClass.process_movement_tick(game_state)
		guard += 1
	_assert(
		"Final facing is SOUTHWEST",
		soldier.facing_direction == FacingDirection.SOUTHWEST,
		"got %s" % soldier.facing_direction,
	)


func _test_save_load_eight_ways() -> void:
	for facing in FacingDirection.ALL:
		var state := SoldierState.new(1, Vector2i(5, 5), Team.USA)
		state.facing_direction = facing
		var restored := SoldierState.from_dict(state.to_dict())
		_assert(
			"Save/load %s" % FacingDirection.direction_name(facing),
			restored.facing_direction == facing,
			"got %s" % restored.facing_direction,
		)


func _test_cone_cardinal_and_diagonal() -> void:
	var origin := Vector2i(50, 50)
	var max_range := 8
	## Cardinal: cell 6 east is inside forward arc.
	_assert(
		"Cone EAST includes far-east cell",
		ConeOfFireClass.is_cell_in_cone(origin, FacingDirection.EAST, origin + Vector2i(6, 0), max_range),
	)
	_assert(
		"Cone EAST excludes behind",
		not ConeOfFireClass.is_cell_in_cone(origin, FacingDirection.EAST, origin + Vector2i(-2, 0), max_range),
	)
	## Diagonal: 6 steps NE should be in range (not √2-stretched out of range).
	_assert(
		"Cone NE includes 6-step diagonal",
		ConeOfFireClass.is_cell_in_cone(
			origin, FacingDirection.NORTHEAST, origin + Vector2i(6, -6), max_range
		),
	)
	_assert(
		"Cone NE excludes opposite SW",
		not ConeOfFireClass.is_cell_in_cone(
			origin, FacingDirection.NORTHEAST, origin + Vector2i(-3, 3), max_range
		),
	)
	## Exact facing match.
	_assert(
		"is_facing_toward exact NE",
		ConeOfFireClass.is_facing_toward_target(
			origin, FacingDirection.NORTHEAST, origin + Vector2i(4, -4), max_range
		),
	)
	## Width: far lateral cell outside cone for cardinal facing.
	_assert(
		"Cone EAST rejects wide lateral",
		not ConeOfFireClass.is_cell_in_cone(origin, FacingDirection.EAST, origin + Vector2i(6, 20), max_range),
	)
	## Point-blank one tile off-axis must engage (min half-width floor).
	_assert(
		"Cone EAST includes near off-axis (2,1)",
		ConeOfFireClass.is_cell_in_cone(origin, FacingDirection.EAST, origin + Vector2i(2, 1), max_range),
	)


## Every cell whose bearing sits inside an 8-way facing sector (±22.5°) must be in-cone
## at ranges 1–20. This is the Stage 1 regression for the old atan(15/48)≈17.4° cone.
func _test_cone_covers_full_facing_sector() -> void:
	var origin := Vector2i(50, 50)
	var max_range := 20
	var half_sector_deg := 22.5
	var failures: Array[String] = []
	for facing in FacingDirection.ALL:
		var face_deg := rad_to_deg(atan2(float(facing.y), float(facing.x)))
		for range_tiles in range(1, max_range + 1):
			## Sample bearings across the whole sector, including both edges.
			for sample in range(0, 9):
				var t := float(sample) / 8.0
				var bearing_deg := face_deg + lerpf(-half_sector_deg, half_sector_deg, t)
				var bearing_rad := deg_to_rad(bearing_deg)
				## Place a cell at approximately this range/bearing in grid space.
				var dx := int(round(cos(bearing_rad) * float(range_tiles)))
				var dy := int(round(sin(bearing_rad) * float(range_tiles)))
				if dx == 0 and dy == 0:
					continue
				var target := origin + Vector2i(dx, dy)
				## Only require coverage when the snapped facing for that cell matches —
				## or when the continuous bearing is inside the sector (rounding can nudge
				## edge samples onto a neighbor octant at short range).
				var snapped := FacingDirection.toward_cell(origin, target)
				var cell_bearing := rad_to_deg(atan2(float(dy), float(dx)))
				var delta := absf(wrapf(cell_bearing - face_deg, -180.0, 180.0))
				if snapped != facing and delta > half_sector_deg + 0.5:
					continue
				if not ConeOfFireClass.is_cell_in_cone(origin, facing, target, max_range):
					failures.append(
						"%s r=%d cell=%s bearing=%.1f"
						% [FacingDirection.direction_name(facing), range_tiles, target, bearing_deg]
					)
					if failures.size() >= 12:
						break
			if failures.size() >= 12:
				break
		if failures.size() >= 12:
			break
	_assert(
		"Cone covers full ±22.5° facing sector at ranges 1–20",
		failures.is_empty(),
		"first fails: %s" % ", ".join(failures),
	)


func _test_animation_direction_mapping() -> void:
	var cams: Array[int] = [0, 90, 180, 270]
	var facings := {
		FacingDirection.NORTH: "n",
		FacingDirection.NORTHEAST: "ne",
		FacingDirection.EAST: "e",
		FacingDirection.SOUTHEAST: "se",
		FacingDirection.SOUTH: "s",
		FacingDirection.SOUTHWEST: "sw",
		FacingDirection.WEST: "w",
		FacingDirection.NORTHWEST: "nw",
	}
	for facing in facings.keys():
		var expected_suffix: String = facings[facing]
		_assert(
			"to_anim_suffix %s" % expected_suffix,
			FacingDirection.to_anim_suffix(facing) == expected_suffix,
		)
		## Without X-flip consideration for letter map from logical facing via from_step path:
		## direction_from_step applies X-flip when enabled — still must be one of 8 letters.
		var letter := UsSoldierSpriteFrames.direction_from_step(facing)
		_assert(
			"direction_from_step yields 8-way letter for %s" % expected_suffix,
			letter in ["n", "ne", "e", "se", "s", "sw", "w", "nw"],
			"got %s" % letter,
		)
		for cam in cams:
			var resolved := AnimationDatabase.display_direction(expected_suffix, cam)
			_assert(
				"camera remap %s@%d" % [expected_suffix, cam],
				resolved in ["n", "ne", "e", "se", "s", "sw", "w", "nw"],
				"got %s" % resolved,
			)
