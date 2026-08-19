extends Node
## Integration: idle vs combat pose separation (no aim/fire clips while idle).
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
	await _test_engaged_sync_stays_idle_all_cameras()
	await _test_post_fire_returns_idle_all_cameras()
	await _test_stale_fire_frame_cleared_to_idle()
	await _test_corner_fire_returns_corner_idle()
	print("")
	print("Idle vs combat pose integration: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail if not detail.is_empty() else "assertion failed"])


func _is_idle_family_anim(anim: String) -> bool:
	return (
		anim.begins_with("idle_standing_")
		or anim.begins_with("idle_crouch_")
		or anim.begins_with("idle_breathing_")
		or anim.begins_with("idle_rest_")
		or anim.begins_with("corner_idle_")
	)


func _is_aim_family_anim(anim: String) -> bool:
	return (
		anim.begins_with("aim_standing_hold_")
		or anim.begins_with("aim_prone_hold_")
		or (
			anim.begins_with("aim_standing_")
			and not anim.begins_with("aim_standing_hold_")
		)
	)


func _test_engaged_sync_stays_idle_all_cameras() -> void:
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
		soldier._fire_target_cell = target_cell
		soldier._last_applied_facing = facing
		soldier._applied_position_state = PositionState.UP
		soldier._idle_peek_side = CoverSystem.PeekSide.NONE
		soldier._corner_phase = Soldier.CornerPresPhase.NONE
		if soldier._anim.sprite_frames.has_animation("idle_standing_n"):
			soldier._anim.play("idle_standing_n")
			soldier._anim.pause()
		var state := SoldierStateClass.new()
		state.soldier_id = 1
		state.team_id = Team.USA
		state.grid_position = from_cell
		state.facing_direction = facing
		state.position_state = PositionState.UP
		state.fire_control_state = FireControlState.FIRE_AT_WILL
		state.set_engaged_target(Team.GERMANY, 1)
		state.fire_ready_after_msec = SimulationClock.get_ticks_msec() + 5000
		soldier.sync_from_state(state, true, Soldier.FogVisual.REVEALED, true)
		var after := str(soldier._anim.animation)
		_assert(
			"engaged sync → aim hold rot=%d → %s" % [rot, after],
			_is_aim_family_anim(after) and not after.begins_with("fire_"),
			"hold=%s enter=%s" % [soldier._fire_aim_hold_active, soldier._fire_aim_enter_active],
		)
		soldier.queue_free()
		await get_tree().process_frame
	IsometricGrid.reset_view_rotation()


func _test_post_fire_returns_idle_all_cameras() -> void:
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
		soldier._idle_peek_side = CoverSystem.PeekSide.NONE
		soldier._corner_phase = Soldier.CornerPresPhase.NONE
		soldier.play_fire(PositionState.UP, facing, CoverSystem.PeekSide.NONE, target_cell)
		var fire_anim := str(soldier._anim.animation)
		_assert(
			"fire anim playing rot=%d → %s" % [rot, fire_anim],
			fire_anim.begins_with("fire_standing_"),
			"fire did not start",
		)
		var fc := soldier._anim.sprite_frames.get_frame_count(fire_anim)
		soldier._anim.frame = maxi(fc - 1, 0)
		soldier._finish_fire(fire_anim)
		var after_finish := str(soldier._anim.animation)
		_assert(
			"post-fire idle when not engaged rot=%d → %s" % [rot, after_finish],
			_is_idle_family_anim(after_finish),
			"hold=%s" % soldier._fire_aim_hold_active,
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
		soldier.sync_from_state(state, true, Soldier.FogVisual.REVEALED, true)
		var after_sync := str(soldier._anim.animation)
		_assert(
			"post-fire sync engaged → aim hold rot=%d → %s" % [rot, after_sync],
			_is_aim_family_anim(after_sync),
			"got %s" % after_sync,
		)
		soldier.queue_free()
		await get_tree().process_frame
	IsometricGrid.reset_view_rotation()


func _test_stale_fire_frame_cleared_to_idle() -> void:
	var soldier: Soldier = SoldierScene.instantiate() as Soldier
	add_child(soldier)
	await get_tree().process_frame
	soldier.team_id = Team.USA
	soldier.soldier_id = 2
	soldier._configure_team_visual()
	soldier._applied_position_state = PositionState.UP
	soldier._locomotion_direction = "e"
	soldier._fire_active = false
	var fire_anim := "fire_standing_e"
	if soldier._anim.sprite_frames.has_animation(fire_anim):
		soldier._anim.play(fire_anim)
		var fc := soldier._anim.sprite_frames.get_frame_count(fire_anim)
		soldier._anim.frame = maxi(fc - 1, 0)
		soldier._anim.pause()
	soldier._clear_stale_open_fire_pose()
	var after := str(soldier._anim.animation)
	_assert(
		"stale fire_standing last frame → idle (%s)" % after,
		after.begins_with("idle_standing_") or after.begins_with("idle_crouch_"),
		"still on fire clip",
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_corner_fire_returns_corner_idle() -> void:
	IsometricGrid.current_view_rotation = 0
	var from_cell := Vector2i(20, 20)
	var target_cell := Vector2i(30, 20)
	var facing := FacingDirection.EAST
	var soldier: Soldier = SoldierScene.instantiate() as Soldier
	add_child(soldier)
	await get_tree().process_frame
	soldier.team_id = Team.USA
	soldier.soldier_id = 3
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
	if soldier._corner_phase == Soldier.CornerPresPhase.PEEKING_OUT:
		soldier._start_corner_aim_hold()
	if soldier._corner_fire_pending or not soldier._fire_active:
		soldier._corner_fire_pending = false
		soldier._begin_fire_sequence(PositionState.UP, facing, CoverSystem.PeekSide.LEFT)
	var fire_anim := str(soldier._anim.animation)
	soldier._finish_fire(fire_anim)
	var after := str(soldier._anim.animation)
	_assert(
		"corner post-fire → idle family (%s)" % after,
		_is_idle_family_anim(after),
		"phase=%d hold=%s" % [soldier._corner_phase, soldier._fire_aim_hold_active],
	)
	soldier.queue_free()
	await get_tree().process_frame
	IsometricGrid.reset_view_rotation()
