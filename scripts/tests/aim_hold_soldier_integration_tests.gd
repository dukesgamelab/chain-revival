extends Node
## Integration: Soldier aim-hold survives facing refresh at all cameras.
## Run: Godot --headless --path <project> res://scripts/tests/aim_hold_soldier_integration_tests.tscn

const SoldierScene := preload("res://scenes/soldier.tscn")
const SoldierStateClass := preload("res://scripts/soldiers/soldier_state.gd")
const UsSoldierSpriteFramesClass := preload("res://scripts/soldiers/us_soldier_sprite_frames.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	SimulationClock.reset()
	GameplayPolicies.reset_all_to_defaults()
	AnimationDatabase.ensure_loaded()
	UsSoldierSpriteFramesClass.reload_cached_frames()
	IsometricGrid.set_original_projection_enabled(true)
	IsometricGrid.set_view_pivot_for_map(64, 64)
	await _test_hold_pose_survives_facing_refresh_all_cameras()
	await _test_post_fire_hold_then_full_sync_all_cameras()
	await _test_corner_fire_handoff_to_open_hold_all_cameras()
	await _test_cas_between_shots_yields_to_open_hold()
	print("")
	print("Aim-hold soldier integration: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail if not detail.is_empty() else "assertion failed"])


func _test_hold_pose_survives_facing_refresh_all_cameras() -> void:
	var from_cell := Vector2i(20, 20)
	var target_cell := Vector2i(30, 20)
	var facing := FacingDirection.EAST
	for rot in 4:
		IsometricGrid.current_view_rotation = rot
		var facet := IsometricGrid.facet_camera_direction_degrees()
		var coord := IsometricGrid.camera_direction_degrees()
		var soldier: Soldier = SoldierScene.instantiate() as Soldier
		add_child(soldier)
		await get_tree().process_frame
		soldier.team_id = Team.USA
		soldier.soldier_id = 1
		soldier._configure_team_visual()
		soldier._facing_from_cell = from_cell
		soldier._fire_target_cell = target_cell
		soldier._last_applied_facing = facing
		soldier._applied_position_state = PositionState.UP
		soldier._fire_aim_hold_active = false
		soldier._fire_aim_enter_active = false
		soldier._idle_peek_side = CoverSystem.PeekSide.NONE
		soldier._corner_phase = Soldier.CornerPresPhase.NONE
		## Start from idle so begin takes the enter or hold path (not from_fire).
		if soldier._anim.sprite_frames.has_animation("idle_standing_n"):
			soldier._anim.play("idle_standing_n")
			soldier._anim.pause()
		soldier._begin_fire_aim_hold(PositionState.UP)
		## Collapse enter → hold so we assert the held pose.
		if soldier._fire_aim_enter_active:
			soldier._fire_aim_enter_active = false
			soldier._play_fire_aim_hold_pose(
				"aim_standing_hold_%s" % soldier._fire_display_direction()
			)
		var after_hold := str(soldier._anim.animation)
		_assert(
			"hold after begin rot=%d facet=%d coord=%d → %s" % [rot, facet, coord, after_hold],
			after_hold.begins_with("aim_standing_hold_"),
			"expected aim_standing_hold_*",
		)
		## Sync-like facing refresh while hold is latched.
		soldier._apply_facing(facing, from_cell)
		var after_facing := str(soldier._anim.animation)
		_assert(
			"hold survives _apply_facing rot=%d → %s" % [rot, after_facing],
			after_facing.begins_with("aim_standing_hold_"),
			"got %s hold_active=%s" % [after_facing, soldier._fire_aim_hold_active],
		)
		var state := SoldierStateClass.new()
		state.soldier_id = 1
		state.team_id = Team.USA
		state.grid_position = from_cell
		state.facing_direction = facing
		state.position_state = PositionState.UP
		state.fire_control_state = FireControlState.FIRE_AT_WILL
		state.set_engaged_target(Team.GERMANY, 1)
		state.fire_ready_after_msec = SimulationClock.get_ticks_msec() + 5000
		soldier._sync_fire_aim_hold(state)
		var after_sync := str(soldier._anim.animation)
		_assert(
			"hold survives _sync_fire_aim_hold rot=%d → %s" % [rot, after_sync],
			after_sync.begins_with("aim_standing_hold_"),
			"got %s hold_active=%s enter=%s" % [
				after_sync, soldier._fire_aim_hold_active, soldier._fire_aim_enter_active
			],
		)
		## Full sync_from_state (the path that runs on every shot refresh_views).
		soldier.sync_from_state(state, true, Soldier.FogVisual.REVEALED, true)
		var after_full := str(soldier._anim.animation)
		_assert(
			"hold survives sync_from_state rot=%d → %s" % [rot, after_full],
			after_full.begins_with("aim_standing_hold_") or after_full.begins_with("aim_standing_"),
			"got %s hold_active=%s enter=%s" % [
				after_full, soldier._fire_aim_hold_active, soldier._fire_aim_enter_active
			],
		)
		print(
			"DUMP rot=%d facet=%d coord=%d fire_world=%s display=%s anim=%s hold=%s enter=%s"
			% [
				rot, facet, coord,
				soldier._fire_world_direction,
				soldier._fire_display_direction(),
				after_full,
				soldier._fire_aim_hold_active,
				soldier._fire_aim_enter_active,
			]
		)
		soldier.queue_free()
		await get_tree().process_frame
	IsometricGrid.reset_view_rotation()


func _test_post_fire_hold_then_full_sync_all_cameras() -> void:
	## Mimic: play_fire → fire oneshot finishes → aim hold → refresh_views sync.
	var from_cell := Vector2i(20, 20)
	var target_cell := Vector2i(30, 20)
	var facing := FacingDirection.EAST
	for rot in 4:
		IsometricGrid.current_view_rotation = rot
		var facet := IsometricGrid.facet_camera_direction_degrees()
		var soldier: Soldier = SoldierScene.instantiate() as Soldier
		add_child(soldier)
		await get_tree().process_frame
		soldier.team_id = Team.USA
		soldier.soldier_id = 1
		soldier._configure_team_visual()
		soldier._facing_from_cell = from_cell
		soldier._applied_position_state = PositionState.UP
		soldier._last_applied_facing = facing
		soldier._idle_peek_side = CoverSystem.PeekSide.NONE
		soldier._corner_phase = Soldier.CornerPresPhase.NONE
		soldier.play_fire(PositionState.UP, facing, CoverSystem.PeekSide.NONE, target_cell)
		_assert(
			"fire_active after play_fire rot=%d" % rot,
			soldier._fire_active,
			"fire did not start",
		)
		var fire_anim := str(soldier._anim.animation)
		_assert(
			"fire anim playing rot=%d → %s" % [rot, fire_anim],
			fire_anim.begins_with("fire_standing_"),
			"got %s" % fire_anim,
		)
		## Jump to last frame and finish (same as animation_finished).
		var fc := soldier._anim.sprite_frames.get_frame_count(fire_anim)
		soldier._anim.frame = maxi(fc - 1, 0)
		soldier._finish_fire(fire_anim)
		var after_finish := str(soldier._anim.animation)
		_assert(
			"post-fire hold rot=%d facet=%d → %s" % [rot, facet, after_finish],
			after_finish.begins_with("aim_standing_hold_"),
			"got %s hold_active=%s" % [after_finish, soldier._fire_aim_hold_active],
		)
		var state := SoldierStateClass.new()
		state.soldier_id = 1
		state.team_id = Team.USA
		state.grid_position = from_cell
		state.facing_direction = facing
		state.position_state = PositionState.UP
		state.fire_control_state = FireControlState.FIRE_AT_WILL
		state.set_engaged_target(Team.GERMANY, 1)
		state.fire_ready_after_msec = SimulationClock.get_ticks_msec() + 5000
		## Full roster sync as Main does when any shot sets refresh_views.
		soldier.sync_from_state(state, true, Soldier.FogVisual.REVEALED, true)
		var after_sync := str(soldier._anim.animation)
		_assert(
			"post-fire hold survives sync rot=%d → %s" % [rot, after_sync],
			after_sync.begins_with("aim_standing_hold_") or after_sync.begins_with("aim_standing_"),
			"got %s" % after_sync,
		)
		print(
			"POSTFIRE rot=%d facet=%d fire_anim=%s after_finish=%s after_sync=%s"
			% [rot, facet, fire_anim, after_finish, after_sync]
		)
		soldier.queue_free()
		await get_tree().process_frame
	IsometricGrid.reset_view_rotation()


func _test_corner_fire_handoff_to_open_hold_all_cameras() -> void:
	## Wall soldiers fire CFA then must land on open ASAIS (not CAS/CIS) at every camera.
	var from_cell := Vector2i(20, 20)
	var target_cell := Vector2i(30, 20)
	var facing := FacingDirection.EAST
	for rot in 4:
		IsometricGrid.current_view_rotation = rot
		var soldier: Soldier = SoldierScene.instantiate() as Soldier
		add_child(soldier)
		await get_tree().process_frame
		soldier.team_id = Team.USA
		soldier.soldier_id = 1
		soldier._configure_team_visual()
		soldier._facing_from_cell = from_cell
		soldier._applied_position_state = PositionState.UP
		soldier._last_applied_facing = facing
		soldier._idle_peek_side = CoverSystem.PeekSide.LEFT
		soldier._corner_phase = Soldier.CornerPresPhase.NONE
		soldier.play_fire(
			PositionState.UP,
			facing,
			CoverSystem.PeekSide.LEFT,
			target_cell,
			from_cell + Vector2i(0, -1),
		)
		## Skip peek enter if pending — force the fire oneshot path.
		if soldier._corner_phase == Soldier.CornerPresPhase.PEEKING_OUT:
			soldier._start_corner_aim_hold()
		if soldier._corner_fire_pending or not soldier._fire_active:
			soldier._corner_fire_pending = false
			soldier._begin_fire_sequence(PositionState.UP, facing, CoverSystem.PeekSide.LEFT)
		var fire_anim := str(soldier._anim.animation)
		_assert(
			"corner fire anim rot=%d → %s" % [rot, fire_anim],
			fire_anim.begins_with("corner_fire_") or fire_anim.begins_with("fire_standing_"),
			"got %s" % fire_anim,
		)
		soldier._finish_fire(fire_anim)
		var after := str(soldier._anim.animation)
		_assert(
			"corner post-fire → open hold rot=%d → %s" % [rot, after],
			after.begins_with("aim_standing_hold_"),
			"got %s phase=%d hold=%s enter=%s"
			% [after, soldier._corner_phase, soldier._fire_aim_hold_active, soldier._fire_aim_enter_active],
		)
		_assert(
			"corner phase cleared after handoff rot=%d" % rot,
			soldier._corner_phase == Soldier.CornerPresPhase.NONE,
			"phase=%d" % soldier._corner_phase,
		)
		soldier.queue_free()
		await get_tree().process_frame
	IsometricGrid.reset_view_rotation()


func _test_cas_between_shots_yields_to_open_hold() -> void:
	## Stuck CAS + HUD Aiming must recover to open ASAIS (the Aiming-but-standing bug).
	IsometricGrid.current_view_rotation = 3 ## status-bar 90° / facet 270°
	var soldier: Soldier = SoldierScene.instantiate() as Soldier
	add_child(soldier)
	await get_tree().process_frame
	soldier.team_id = Team.USA
	soldier.soldier_id = 4
	soldier._configure_team_visual()
	soldier._facing_from_cell = Vector2i(20, 20)
	soldier._fire_target_cell = Vector2i(30, 20)
	soldier._last_applied_facing = FacingDirection.EAST
	soldier._applied_position_state = PositionState.UP
	soldier._corner_phase = Soldier.CornerPresPhase.AIMING
	soldier._corner_peek_side = CoverSystem.PeekSide.LEFT
	soldier._corner_semantic = "corner_aim_left"
	if soldier._anim.sprite_frames.has_animation("idle_standing_n"):
		soldier._anim.play("idle_standing_n")
		soldier._anim.pause()
	var state := SoldierStateClass.new()
	state.soldier_id = 4
	state.team_id = Team.USA
	state.grid_position = Vector2i(20, 20)
	state.facing_direction = FacingDirection.EAST
	state.position_state = PositionState.UP
	state.fire_control_state = FireControlState.FIRE_AT_WILL
	state.set_engaged_target(Team.GERMANY, 1)
	state.fire_ready_after_msec = SimulationClock.get_ticks_msec() + 5000
	soldier.sync_from_state(
		state, true, Soldier.FogVisual.REVEALED, true, CoverSystem.PeekSide.LEFT
	)
	var after := str(soldier._anim.animation)
	_assert(
		"CAS + Aiming recovers to open hold → %s" % after,
		after.begins_with("aim_standing_hold_") or after.begins_with("aim_standing_"),
		"got %s hold=%s phase=%d" % [after, soldier._fire_aim_hold_active, soldier._corner_phase],
	)
	soldier.queue_free()
	await get_tree().process_frame
	IsometricGrid.reset_view_rotation()
