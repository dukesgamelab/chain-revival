extends Node
## Headless tests for applying server face / stance / move results on both replicas.
## Run: Godot --headless --path <project> res://scripts/tests/authoritative_sync_tests.tscn

const MapDataClass := preload("res://scripts/map/map_data.gd")
const GameSessionClass := preload("res://scripts/core/game_session.gd")
const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")
const AuthoritativeSyncClass := preload("res://scripts/network/authoritative_sync.gd")
const ActionResultClass := preload("res://scripts/core/action_result.gd")
const PositionStateClass := preload("res://scripts/enums/position_state.gd")
const MovementModeClass := preload("res://scripts/enums/movement_mode.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	SimulationClock.reset()
	GameRandom.reseed(GameRandom.DEFAULT_SEED)
	GameplayPolicies.reset_all_to_defaults()
	_test_face_result_both_replicas()
	_test_position_result_both_replicas()
	_test_move_result_stance_and_mode()
	_test_snapshot_restores_facing_stance_mode()
	_test_fire_control_and_target_both_replicas()
	_test_soldier_sync_applies_state()
	_test_soldier_sync_reports_only_changes()
	_test_soldier_sync_skips_facing_while_moving()
	print("")
	print("Authoritative sync tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail if not detail.is_empty() else "assertion failed"])


func _make_game_state() -> GameState:
	var map_data: MapDataClass = MapDataClass.create_default()
	var session := GameSessionClass.new(
		map_data.team_1_spawn_points,
		map_data.team_2_spawn_points,
	)
	var game_state := session.create_game_state(map_data)
	ActionResolverClass.apply_match_start_setup(game_state)
	return game_state


func _test_face_result_both_replicas() -> void:
	var usa := _make_game_state()
	var germany := _make_game_state()
	var payload := {
		"success": true,
		"statusMessage": "USA Soldier 1 facing EAST.",
		"faceUpdates": [
			{"teamId": Team.USA, "soldierId": 1, "facing": {"x": 1, "y": 0}},
		],
	}
	var result: ActionResultClass = AuthoritativeSyncClass.action_result_from_payload(payload)
	AuthoritativeSyncClass.apply_face_result(usa, result)
	AuthoritativeSyncClass.apply_face_result(germany, result)
	var a: SoldierState = usa.get_soldier(Team.USA, 1)
	var b: SoldierState = germany.get_soldier(Team.USA, 1)
	_assert("face both replicas", a.facing_direction == Vector2i(1, 0) and a.facing_direction == b.facing_direction)


func _test_position_result_both_replicas() -> void:
	var usa := _make_game_state()
	var germany := _make_game_state()
	var payload := {
		"success": true,
		"statusMessage": "Soldier 1 changed to DOWN",
		"soldierUpdates": [
			{
				"teamId": Team.USA,
				"soldierId": 1,
				"facing": {"x": 0, "y": -1},
				"positionState": PositionStateClass.DOWN,
				"movementMode": MovementModeClass.RUN,
			},
		],
		"stanceTransitionOrders": [
			{"teamId": Team.USA, "soldierId": 1, "targetPositionState": PositionStateClass.DOWN},
		],
		"movementHalts": [],
	}
	var result: ActionResultClass = AuthoritativeSyncClass.action_result_from_payload(payload)
	AuthoritativeSyncClass.apply_position_result(usa, result)
	AuthoritativeSyncClass.apply_position_result(germany, result)
	var a: SoldierState = usa.get_soldier(Team.USA, 1)
	var b: SoldierState = germany.get_soldier(Team.USA, 1)
	_assert(
		"stance both replicas",
		a.position_state == PositionStateClass.DOWN
		and b.position_state == PositionStateClass.DOWN
		and a.pending_position_state == PositionStateClass.DOWN
		and b.pending_position_state == PositionStateClass.DOWN,
	)


func _test_move_result_stance_and_mode() -> void:
	var usa := _make_game_state()
	var germany := _make_game_state()
	var start: Vector2i = usa.get_soldier(Team.USA, 1).grid_position
	var dest := start + Vector2i(1, 0)
	var payload := {
		"success": true,
		"statusMessage": "run",
		"moveOrders": [
			{
				"teamId": Team.USA,
				"soldierId": 1,
				"path": [{"x": start.x, "y": start.y}, {"x": dest.x, "y": dest.y}],
				"speedMult": 2.0,
				"movementMode": MovementModeClass.WALK,
				"positionState": PositionStateClass.UP,
			},
		],
		"movementHalts": [],
		"soldierUpdates": [
			{
				"teamId": Team.USA,
				"soldierId": 1,
				"facing": {"x": 1, "y": 0},
				"positionState": PositionStateClass.UP,
				"movementMode": MovementModeClass.WALK,
			},
		],
	}
	var result: ActionResultClass = AuthoritativeSyncClass.action_result_from_payload(payload)
	AuthoritativeSyncClass.apply_move_result(usa, result)
	AuthoritativeSyncClass.apply_move_result(germany, result)
	var a: SoldierState = usa.get_soldier(Team.USA, 1)
	var b: SoldierState = germany.get_soldier(Team.USA, 1)
	_assert(
		"move mode both replicas",
		a.movement_mode == MovementModeClass.WALK
		and b.movement_mode == MovementModeClass.WALK
		and a.position_state == PositionStateClass.UP
		and a.is_moving
		and b.is_moving,
	)


func _test_snapshot_restores_facing_stance_mode() -> void:
	var game_state := _make_game_state()
	var snapshot := {
		"soldiers": [
			{
				"teamId": Team.USA,
				"soldierId": 1,
				"gridPosition": {"x": 3, "y": 4},
				"facing": {"x": -1, "y": 1},
				"positionState": PositionStateClass.DOWN,
				"movementMode": MovementModeClass.CRAWL,
				"isDead": false,
				"isMoving": false,
				"currentPath": [],
				"pathIndex": 0,
				"moveSpeedMult": 0.3,
			},
		],
	}
	AuthoritativeSyncClass.apply_snapshot(game_state, snapshot)
	var soldier: SoldierState = game_state.get_soldier(Team.USA, 1)
	_assert("snapshot facing", soldier.facing_direction == Vector2i(-1, 1))
	_assert("snapshot stance", soldier.position_state == PositionStateClass.DOWN)
	_assert("snapshot movementMode", soldier.movement_mode == MovementModeClass.CRAWL)


func _test_fire_control_and_target_both_replicas() -> void:
	var usa := _make_game_state()
	var germany := _make_game_state()
	var payload := {
		"success": true,
		"statusMessage": "Priority target Germany Soldier 1.",
		"syncFireAtUi": true,
		"targetUpdates": [
			{
				"teamId": Team.USA,
				"soldierId": 1,
				"fireControlState": FireControlState.FIRE_AT_WILL,
				"engagedTargetTeamId": Team.GERMANY,
				"engagedTargetSoldierId": 1,
				"sustainedFire": true,
			},
		],
		"faceUpdates": [],
		"movementHalts": [],
	}
	var result: ActionResultClass = AuthoritativeSyncClass.action_result_from_payload(payload)
	AuthoritativeSyncClass.apply_target_result(usa, result)
	AuthoritativeSyncClass.apply_target_result(germany, result)
	var a: SoldierState = usa.get_soldier(Team.USA, 1)
	var b: SoldierState = germany.get_soldier(Team.USA, 1)
	_assert(
		"fire-at both replicas",
		a.sustained_fire
		and b.sustained_fire
		and a.engaged_target_soldier_id == 1
		and b.engaged_target_soldier_id == 1
		and a.fire_control_state == FireControlState.FIRE_AT_WILL,
	)
	var hold_payload := {
		"success": true,
		"statusMessage": "Hold Fire",
		"syncFireAtUi": true,
		"targetUpdates": [
			{
				"teamId": Team.USA,
				"soldierId": 1,
				"fireControlState": FireControlState.HOLD_FIRE,
				"engagedTargetTeamId": -1,
				"engagedTargetSoldierId": -1,
				"sustainedFire": false,
			},
		],
	}
	var hold: ActionResultClass = AuthoritativeSyncClass.action_result_from_payload(hold_payload)
	AuthoritativeSyncClass.apply_target_result(usa, hold)
	AuthoritativeSyncClass.apply_target_result(germany, hold)
	_assert(
		"hold-fire both replicas",
		a.fire_control_state == FireControlState.HOLD_FIRE
		and b.fire_control_state == FireControlState.HOLD_FIRE
		and not a.is_engaged()
		and not b.is_engaged(),
	)


func _sync_entry(soldier: SoldierState, overrides: Dictionary = {}) -> Dictionary:
	var entry := {
		"teamId": soldier.team_id,
		"soldierId": soldier.soldier_id,
		"positionState": soldier.position_state,
		"movementMode": soldier.movement_mode,
		"facing": {"x": soldier.facing_direction.x, "y": soldier.facing_direction.y},
		"stress": soldier.stress,
		"grenadeCount": soldier.grenade_count,
		"ammoCurrent": soldier.ammo_current,
		"stunnedUntilMsec": soldier.stunned_until_msec,
		"fireControlState": soldier.fire_control_state,
		"engagedTargetTeamId": soldier.engaged_target_team_id,
		"engagedTargetSoldierId": soldier.engaged_target_soldier_id,
		"sustainedFire": soldier.sustained_fire,
	}
	entry.merge(overrides, true)
	return entry


func _test_soldier_sync_applies_state() -> void:
	var game_state := _make_game_state()
	var soldier: SoldierState = game_state.get_soldier(Team.GERMANY, 1)
	var payload := {
		"soldiers": [
			_sync_entry(soldier, {
				"positionState": PositionStateClass.DOWN,
				"movementMode": MovementModeClass.CRAWL,
				"facing": {"x": 1, "y": 0},
				"stress": 42.0,
				"grenadeCount": 2,
				"ammoCurrent": 3,
				"stunnedUntilMsec": 9000,
				"engagedTargetTeamId": Team.USA,
				"engagedTargetSoldierId": 2,
				"sustainedFire": true,
			}),
		],
	}
	var changed := AuthoritativeSyncClass.apply_soldier_sync(game_state, payload)
	_assert("sync stance", soldier.position_state == PositionStateClass.DOWN)
	_assert("sync movementMode", soldier.movement_mode == MovementModeClass.CRAWL)
	_assert("sync facing", soldier.facing_direction == Vector2i(1, 0))
	_assert("sync stress", is_equal_approx(soldier.stress, 42.0))
	_assert("sync grenades", soldier.grenade_count == 2)
	_assert("sync ammo", soldier.ammo_current == 3)
	_assert("sync stun", soldier.stunned_until_msec == 9000)
	_assert(
		"sync fire-at target",
		soldier.sustained_fire and soldier.engaged_target_team_id == Team.USA
		and soldier.engaged_target_soldier_id == 2,
	)
	_assert(
		"sync reports stance change",
		changed.size() == 1 and bool(changed[0].stance_changed) and bool(changed[0].view_changed),
		str(changed),
	)


func _test_soldier_sync_reports_only_changes() -> void:
	var game_state := _make_game_state()
	var soldier: SoldierState = game_state.get_soldier(Team.USA, 1)
	var same := AuthoritativeSyncClass.apply_soldier_sync(game_state, {"soldiers": [_sync_entry(soldier)]})
	_assert("sync unchanged reports nothing", same.is_empty(), str(same))
	var counts := AuthoritativeSyncClass.apply_soldier_sync(
		game_state, {"soldiers": [_sync_entry(soldier, {"grenadeCount": soldier.grenade_count - 1})]}
	)
	_assert(
		"sync grenade-only change skips view refresh",
		counts.size() == 1 and not bool(counts[0].view_changed),
		str(counts),
	)


func _test_soldier_sync_skips_facing_while_moving() -> void:
	var game_state := _make_game_state()
	var soldier: SoldierState = game_state.get_soldier(Team.USA, 1)
	var start := soldier.grid_position
	var path: Array[Vector2i] = [start, start + Vector2i(1, 0)]
	soldier.assign_path(path, 1.0)
	var before := soldier.facing_direction
	var flipped := Vector2i(-before.x, -before.y)
	if flipped == Vector2i.ZERO:
		flipped = Vector2i(1, 0)
	AuthoritativeSyncClass.apply_soldier_sync(
		game_state, {"soldiers": [_sync_entry(soldier, {"facing": {"x": flipped.x, "y": flipped.y}})]}
	)
	_assert("sync leaves moving soldier's facing", soldier.facing_direction == before)
