extends Node
## Headless tests for Phase 48 fog of war on the client: hidden-enemy snapshots, spotting
## reveals, hidden shooters, last-known markers, the step-by-step enemy chase, and the
## enemy deployment zone overlay. Also compiles main.gd with autoloads present.
## Run: Godot --headless --path <project> res://scripts/tests/fog_of_war_tests.tscn

const MapDataClass := preload("res://scripts/map/map_data.gd")
const GameSessionClass := preload("res://scripts/core/game_session.gd")
const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")
const AuthoritativeSyncClass := preload("res://scripts/network/authoritative_sync.gd")
const PositionStateClass := preload("res://scripts/enums/position_state.gd")
const SoldierScene := preload("res://scenes/soldier.tscn")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	SimulationClock.reset()
	GameRandom.reseed(GameRandom.DEFAULT_SEED)
	GameplayPolicies.reset_all_to_defaults()
	_test_main_compiles()
	_test_hidden_snapshot_keeps_position()
	_test_hidden_dead_snapshot_places_body()
	_test_visible_snapshot_applies()
	_test_revealed_applies_real_state()
	_test_hidden_shooter_cell()
	_test_grenade_kill_body_cell()
	_test_marker_lifecycle()
	_test_remote_chase_holds_and_extends()
	_test_deployment_overlay()
	print("")
	print("Fog of war tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s - %s" % [name, detail if not detail.is_empty() else "assertion failed"])


func _make_game_state() -> GameState:
	var map_data: MapDataClass = MapDataClass.create_default()
	var session := GameSessionClass.new(
		map_data.team_1_spawn_points,
		map_data.team_2_spawn_points,
	)
	var game_state := session.create_game_state(map_data)
	ActionResolverClass.apply_match_start_setup(game_state)
	return game_state


func _cell_dict(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}


func _test_main_compiles() -> void:
	var script: GDScript = load("res://scripts/core/main.gd")
	_assert("main.gd compiles", script != null and script.can_instantiate())


func _test_hidden_snapshot_keeps_position() -> void:
	var gs := _make_game_state()
	var enemy: SoldierState = gs.get_soldier(Team.GERMANY, 1)
	var before := enemy.grid_position
	AuthoritativeSyncClass.apply_snapshot(gs, {
		"simMsec": 0,
		"soldiers": [{"teamId": Team.GERMANY, "soldierId": 1, "weaponId": "", "isDead": false, "known": false}],
	})
	_assert("hidden snapshot leaves the enemy where he was", enemy.grid_position == before and not enemy.is_dead)
	_assert("hidden snapshot clears his route", not enemy.is_moving and enemy.current_path.is_empty())


func _test_hidden_dead_snapshot_places_body() -> void:
	var gs := _make_game_state()
	var enemy: SoldierState = gs.get_soldier(Team.GERMANY, 2)
	AuthoritativeSyncClass.apply_snapshot(gs, {
		"simMsec": 0,
		"soldiers": [{
			"teamId": Team.GERMANY, "soldierId": 2, "weaponId": "", "isDead": true, "known": false,
			"gridPosition": _cell_dict(Vector2i(20, 21)), "facing": _cell_dict(Vector2i(1, 0)),
		}],
	})
	_assert("dead hidden enemy: body placed", enemy.is_dead and enemy.grid_position == Vector2i(20, 21))


func _test_visible_snapshot_applies() -> void:
	var gs := _make_game_state()
	var enemy: SoldierState = gs.get_soldier(Team.GERMANY, 3)
	AuthoritativeSyncClass.apply_snapshot(gs, {
		"simMsec": 0,
		"soldiers": [{
			"teamId": Team.GERMANY, "soldierId": 3, "gridPosition": _cell_dict(Vector2i(12, 13)),
			"facing": _cell_dict(Vector2i(0, 1)), "positionState": PositionStateClass.DOWN,
			"movementMode": MovementMode.RUN, "isDead": false, "isMoving": true, "currentPath": [],
			"pathIndex": 0, "moveSpeedMult": 1.0,
		}],
	})
	_assert(
		"seen enemy in snapshot is placed, path-free",
		enemy.grid_position == Vector2i(12, 13) and enemy.position_state == PositionStateClass.DOWN and not enemy.is_moving,
	)


func _test_revealed_applies_real_state() -> void:
	var gs := _make_game_state()
	var enemy: SoldierState = gs.get_soldier(Team.GERMANY, 1)
	var keys: Array[String] = AuthoritativeSyncClass.apply_revealed(gs, {
		"revealed": [{
			"teamId": Team.GERMANY, "soldierId": 1, "gridPosition": _cell_dict(Vector2i(30, 31)),
			"facing": _cell_dict(Vector2i(-1, 0)), "positionState": PositionStateClass.DOWN,
			"movementMode": MovementMode.RUN, "isMoving": true, "moveSpeedMult": 1.4, "stress": 33.0,
			"stunnedUntilMsec": 0, "fireControlState": 1, "engagedTargetTeamId": Team.USA,
			"engagedTargetSoldierId": 2, "sustainedFire": false, "weaponId": "",
		}],
	})
	_assert("reveal returns the key", keys == ["%d:1" % Team.GERMANY], str(keys))
	_assert("reveal places him", enemy.grid_position == Vector2i(30, 31))
	_assert("reveal stance and stress", enemy.position_state == PositionStateClass.DOWN and is_equal_approx(enemy.stress, 33.0))
	_assert("reveal engaged target", enemy.engaged_target_team_id == Team.USA and enemy.engaged_target_soldier_id == 2)
	_assert("reveal speed kept for the chase", is_equal_approx(enemy.move_speed_mult, 1.4))


func _test_hidden_shooter_cell() -> void:
	var gs := _make_game_state()
	var shooter: SoldierState = gs.get_soldier(Team.GERMANY, 1)
	var ammo_before := shooter.ammo_current
	var facing_before := shooter.facing_direction
	AuthoritativeSyncClass.apply_combat_shots(gs, {
		"simMsec": 0,
		"shots": [{
			"shotId": 1, "shooterTeamId": Team.GERMANY, "shooterId": 1, "targetTeamId": Team.USA,
			"targetId": 1, "fired": true, "hit": false, "killed": false, "tracerCount": 1,
			"facing": {"x": 0, "y": 0}, "shooterHidden": true, "shooterCell": _cell_dict(Vector2i(25, 26)),
			"targetStress": 12.0,
		}],
	})
	_assert("hidden shooter moved to his firing cell", shooter.grid_position == Vector2i(25, 26))
	_assert("hidden shooter ammo / facing untouched", shooter.ammo_current == ammo_before and shooter.facing_direction == facing_before)
	_assert("our target still gets stress", is_equal_approx(gs.get_soldier(Team.USA, 1).stress, 12.0))


func _test_grenade_kill_body_cell() -> void:
	var gs := _make_game_state()
	var victim: SoldierState = gs.get_soldier(Team.GERMANY, 4)
	AuthoritativeSyncClass.apply_grenade_explode(gs, {
		"simMsec": 0,
		"explosionCell": _cell_dict(Vector2i(40, 40)),
		"killed": [{"teamId": Team.GERMANY, "soldierId": 4, "cell": _cell_dict(Vector2i(41, 40))}],
		"stunned": [],
		"messages": [],
	})
	_assert("grenade kill puts the body where he fell", victim.is_dead and victim.grid_position == Vector2i(41, 40))


func _make_view(team_id: int, soldier_id: int, cell: Vector2i) -> Soldier:
	var gs := _make_game_state()
	var state: SoldierState = gs.get_soldier(team_id, soldier_id)
	state.grid_position = cell
	var view: Soldier = SoldierScene.instantiate() as Soldier
	view.soldier_id = soldier_id
	view.team_id = team_id
	add_child(view)
	view.sync_from_state(state, false, Soldier.FogVisual.REVEALED, false)
	return view


func _test_marker_lifecycle() -> void:
	var root := Node2D.new()
	add_child(root)
	var markers := LastKnownMarkers.new()
	add_child(markers)
	markers.setup(root)
	var view := _make_view(Team.GERMANY, 1, Vector2i(10, 10))
	var key := "%d:1" % Team.GERMANY
	markers.drop(key, view, Vector2i(10, 10), 1000)
	_assert("marker dropped", markers.has_marker(key) and markers.count() == 1 and root.get_child_count() == 1)
	_assert("marker cell", markers.marker_cell(key) == Vector2i(10, 10))
	_assert("marker recent for Fire At", markers.is_recent(key, 2500))
	_assert("marker too old for Fire At", not markers.is_recent(key, 3500))
	var ghost: Node2D = root.get_child(0)
	var start_alpha := ghost.modulate.a
	markers.tick(1000 + 1500)
	_assert("marker holds early", is_equal_approx(ghost.modulate.a, start_alpha))
	markers.tick(1000 + 6000)
	_assert("marker fades", ghost.modulate.a < start_alpha and ghost.modulate.a > 0.0)
	markers.tick(1000 + int(LastKnownMarkers.LIFETIME_SEC * 1000.0))
	_assert("marker gone after its lifetime", not markers.has_marker(key))
	markers.drop(key, view, Vector2i(10, 10), 0)
	markers.clear(key)
	_assert("marker cleared on re-spot", not markers.has_marker(key))
	view.queue_free()
	markers.queue_free()
	root.queue_free()


func _test_remote_chase_holds_and_extends() -> void:
	var view := _make_view(Team.GERMANY, 2, Vector2i(10, 10))
	view.chase_remote_step(Vector2i(10, 10), Vector2i(11, 10), 1.0)
	_assert("remote chase starts", view.is_moving() and view.is_remote_chasing())
	## Run well past the cell: the view holds there instead of settling.
	for i in range(120):
		view._process(1.0 / 60.0)
	_assert("remote chase holds at the newest cell", view.is_moving() and view.is_remote_chasing())
	_assert("held at the step's cell", view.position.distance_to(IsometricGrid.grid_to_world(Vector2i(11, 10))) < 1.0)
	view.chase_remote_step(Vector2i(11, 10), Vector2i(12, 10), 1.0)
	_assert("next step extends the chase", view.presentation_destination_cell() == Vector2i(12, 10))
	for i in range(120):
		view._process(1.0 / 60.0)
	view.end_remote_chase()
	_assert("move end settles the view", not view.is_moving() and not view.is_remote_chasing())
	_assert(
		"settled on the last step",
		view.position.distance_to(IsometricGrid.grid_to_world(Vector2i(12, 10))) < 1.0,
	)
	view.queue_free()


func _test_deployment_overlay() -> void:
	var overlay := DeploymentZoneOverlay.new()
	add_child(overlay)
	var cells: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1)]
	overlay.show_cells(cells)
	_assert("overlay shows the enemy cells", overlay.visible and overlay.cell_count() == 2)
	overlay.clear()
	_assert("overlay clears", not overlay.visible and overlay.cell_count() == 0)
	overlay.queue_free()
