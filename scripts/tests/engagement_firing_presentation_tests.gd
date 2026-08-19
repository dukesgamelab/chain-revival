extends Node
## Engagement aim/fire loop + exposed standing → prone presentation.
## Run: Godot --headless --path <project> res://scripts/tests/engagement_firing_presentation_tests.tscn

const SoldierScene := preload("res://scenes/soldier.tscn")
const SoldierStateClass := preload("res://scripts/soldiers/soldier_state.gd")
const MapDataClass := preload("res://scripts/map/map_data.gd")
const MapObjectRegistryClass := preload("res://scripts/map/map_object_registry.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	SimulationClock.reset()
	GameplayPolicies.reset_all_to_defaults()
	AnimationDatabase.ensure_loaded()
	UsSoldierSpriteFrames.reload_cached_frames()
	IsometricGrid.set_original_projection_enabled(true)
	IsometricGrid.set_view_pivot_for_map(64, 64)
	IsometricGrid.current_view_rotation = 0

	await _test_post_fire_returns_aim_hold_when_engaged()
	await _test_fidget_suppressed_during_engagement()
	await _test_exposed_standing_shot_counts_toward_prone()
	await _test_exposed_prone_signal_after_threshold()
	await _test_covered_standing_does_not_signal_prone()
	await _test_stance_finish_returns_prone_aim_when_engaged()
	await _test_hold_fire_clears_aim()
	await _test_fire_at_will_idle_not_aiming()
	print("")
	print("Engagement firing presentation: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail if not detail.is_empty() else "assertion failed"])


func _is_aim_hold_anim(anim: String) -> bool:
	return anim.begins_with("aim_standing_hold_") or anim.begins_with("aim_prone_hold_")


func _is_idle_family_anim(anim: String) -> bool:
	return (
		anim.begins_with("idle_standing_")
		or anim.begins_with("idle_crouch_")
		or anim.begins_with("idle_breathing_")
		or anim.begins_with("idle_rest_")
	)


func _new_soldier() -> Soldier:
	var soldier: Soldier = SoldierScene.instantiate() as Soldier
	add_child(soldier)
	soldier.team_id = Team.USA
	soldier.soldier_id = 1
	soldier._configure_team_visual()
	soldier._facing_from_cell = Vector2i(20, 20)
	soldier._last_applied_facing = FacingDirection.EAST
	soldier._applied_position_state = PositionState.UP
	soldier._idle_peek_side = CoverSystem.PeekSide.NONE
	soldier._corner_phase = Soldier.CornerPresPhase.NONE
	return soldier


func _engaged_state(from_cell: Vector2i, target_cell: Vector2i) -> SoldierState:
	var state := SoldierStateClass.new()
	state.soldier_id = 1
	state.team_id = Team.USA
	state.grid_position = from_cell
	state.facing_direction = FacingDirection.EAST
	state.position_state = PositionState.UP
	state.fire_control_state = FireControlState.FIRE_AT_WILL
	state.set_engaged_target(Team.GERMANY, 1)
	state.fire_ready_after_msec = SimulationClock.get_ticks_msec() + 5000
	return state


func _map_with_wall_cover(stand: Vector2i, threat: Vector2i) -> MapData:
	var map_data := MapDataClass.create_default()
	var wall_cell := stand + Vector2i(-1, 0)
	if threat.x < stand.x:
		wall_cell = stand + Vector2i(1, 0)
	map_data.set_object(wall_cell, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
	return map_data


func _test_post_fire_returns_aim_hold_when_engaged() -> void:
	var from_cell := Vector2i(20, 20)
	var target_cell := Vector2i(30, 20)
	var soldier := _new_soldier()
	await get_tree().process_frame
	soldier._fire_target_cell = target_cell
	soldier._presentation_engaged = true
	soldier._aim_hold_last_target_team_id = Team.GERMANY
	soldier._aim_hold_last_target_soldier_id = 1
	soldier.play_fire(PositionState.UP, FacingDirection.EAST, CoverSystem.PeekSide.NONE, target_cell)
	var fire_anim := str(soldier._anim.animation)
	soldier._finish_fire(fire_anim)
	var after := str(soldier._anim.animation)
	_assert(
		"post-fire engaged → aim hold",
		_is_aim_hold_anim(after) or after.begins_with("aim_standing_"),
		after,
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_fidget_suppressed_during_engagement() -> void:
	var soldier := _new_soldier()
	await get_tree().process_frame
	soldier._presentation_engaged = true
	soldier._aim_hold_last_target_team_id = Team.GERMANY
	soldier._aim_hold_last_target_soldier_id = 1
	soldier._idle_wait_remaining_sec = 0.01
	soldier.set_process(true)
	await get_tree().process_frame
	soldier._tick_standing_idle_wait(1.0)
	_assert(
		"fidget blocked while engaged",
		not soldier._idle_fidget_active and soldier._idle_wait_remaining_sec < 0.0,
		"fidget=%s wait=%s" % [soldier._idle_fidget_active, soldier._idle_wait_remaining_sec],
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_exposed_standing_shot_counts_toward_prone() -> void:
	var soldier := _new_soldier()
	await get_tree().process_frame
	soldier._presentation_engaged = true
	soldier._fire_target_cell = Vector2i(30, 20)
	soldier._presentation_map_data = MapDataClass.create_default()
	soldier._fire_return_prone = false
	soldier._finish_fire("fire_standing_e")
	_assert("exposed shot counted", soldier.debug_exposed_standing_shots_completed() == 1, "")
	soldier.queue_free()
	await get_tree().process_frame


func _test_exposed_prone_signal_after_threshold() -> void:
	var soldier := _new_soldier()
	await get_tree().process_frame
	var signaled := false
	soldier.exposed_engagement_prone_requested.connect(func(_t: int, _s: int) -> void:
		signaled = true
	)
	soldier._presentation_engaged = true
	soldier._fire_target_cell = Vector2i(30, 20)
	soldier._presentation_map_data = MapDataClass.create_default()
	soldier._fire_active = false
	soldier._fire_return_prone = false
	soldier._maybe_request_exposed_prone_after_shot()
	_assert("exposed prone signal at threshold", signaled, "")
	soldier.queue_free()
	await get_tree().process_frame


func _test_covered_standing_does_not_signal_prone() -> void:
	var stand := Vector2i(20, 20)
	var threat := Vector2i(30, 20)
	var soldier := _new_soldier()
	await get_tree().process_frame
	var signaled := false
	soldier.exposed_engagement_prone_requested.connect(func(_t: int, _s: int) -> void:
		signaled = true
	)
	soldier._facing_from_cell = stand
	soldier._presentation_engaged = true
	soldier._fire_target_cell = threat
	soldier._presentation_map_data = _map_with_wall_cover(stand, threat)
	soldier._fire_return_prone = false
	soldier._maybe_request_exposed_prone_after_shot()
	_assert("covered standing no prone signal", not signaled, "")
	soldier.queue_free()
	await get_tree().process_frame


func _test_stance_finish_returns_prone_aim_when_engaged() -> void:
	var soldier := _new_soldier()
	await get_tree().process_frame
	soldier._presentation_engaged = true
	soldier._aim_hold_last_target_team_id = Team.GERMANY
	soldier._aim_hold_last_target_soldier_id = 1
	soldier._stance_transition_active = true
	soldier._stance_transition_target = PositionState.DOWN
	soldier._exposed_prone_pending = true
	soldier._finish_stance_transition("transition_standing_to_prone_e")
	var after := str(soldier._anim.animation)
	_assert(
		"stance finish → prone aim hold",
		_is_aim_hold_anim(after) or after.begins_with("aim_prone_"),
		after,
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_hold_fire_clears_aim() -> void:
	var from_cell := Vector2i(20, 20)
	var soldier := _new_soldier()
	await get_tree().process_frame
	var state := _engaged_state(from_cell, Vector2i(30, 20))
	soldier.sync_from_state(state, false, Soldier.FogVisual.REVEALED, true)
	state.fire_control_state = FireControlState.HOLD_FIRE
	state.clear_engaged_target()
	soldier.sync_from_state(state, false, Soldier.FogVisual.REVEALED, true)
	var after := str(soldier._anim.animation)
	_assert(
		"hold fire exits aim to idle",
		_is_idle_family_anim(after) or after.begins_with("walk_"),
		after,
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_fire_at_will_idle_not_aiming() -> void:
	var soldier := _new_soldier()
	await get_tree().process_frame
	var state := SoldierStateClass.new()
	state.soldier_id = 1
	state.team_id = Team.USA
	state.grid_position = Vector2i(20, 20)
	state.facing_direction = FacingDirection.EAST
	state.position_state = PositionState.UP
	state.fire_control_state = FireControlState.FIRE_AT_WILL
	state.fire_ready_after_msec = SimulationClock.get_ticks_msec() + 5000
	soldier.sync_from_state(state, false, Soldier.FogVisual.REVEALED, true)
	var after := str(soldier._anim.animation)
	_assert(
		"fire at will idle not aiming",
		after.begins_with("idle_standing_") or after.begins_with("idle_crouch_"),
		"hold=%s anim=%s" % [soldier._fire_aim_hold_active, after],
	)
	soldier.queue_free()
	await get_tree().process_frame
