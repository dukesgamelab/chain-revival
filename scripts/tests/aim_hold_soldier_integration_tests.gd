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
	await _test_idle_facing_corner_peeks()
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
	await _run_corner_fire_case(false)
	await _run_corner_fire_case(true)


## Facing around a corner: rest leaned out on lookout (held scan-peek frame L, gun down), and
## a shot goes straight to the gun-up lean-out. Hugging alongside a wall: hug pose, and every
## few seconds the OG scan peek (PKA) plays once and he tucks back to the hug pose.
func _test_idle_facing_corner_peeks() -> void:
	IsometricGrid.current_view_rotation = 0
	await _run_corner_lookout_case()
	for corner_step in [Vector2i(0, 1)]:
		var soldier := await _make_corner_soldier(corner_step)
		var world_dir := soldier._world_direction_from_step(FacingDirection.EAST)
		soldier._play_idle_standing(world_dir)
		var anim := str(soldier._anim.animation)
		_assert(
			"idle beside wall → hug (%s)" % anim,
			anim.begins_with("corner_idle_left_") and soldier._corner_scan_wait_sec > 0.0,
			"phase=%d scan_wait=%.2f" % [soldier._corner_phase, soldier._corner_scan_wait_sec],
		)
		## Scan timer fires: one-shot peek plays.
		soldier._corner_scan_wait_sec = 0.01
		soldier._tick_corner_scan(0.1)
		anim = str(soldier._anim.animation)
		_assert(
			"corner scan peek plays (%s)" % anim,
			anim.begins_with("corner_peek_left_") and soldier._corner_scan_active,
			"active=%s" % soldier._corner_scan_active,
		)
		## Must be one-shot, or animation_finished never fires to tuck him back in.
		_assert(
			"corner scan peek is one-shot (%s)" % anim,
			not soldier._anim.sprite_frames.get_animation_loop(anim),
		)
		## A sync refresh mid-peek must not cut it short.
		soldier._play_idle_standing(world_dir)
		_assert(
			"sync during scan keeps the peek (%s)" % str(soldier._anim.animation),
			str(soldier._anim.animation).begins_with("corner_peek_left_"),
		)
		## Peek finishes: back to the hug pose with the next scan armed.
		soldier._on_anim_animation_finished()
		anim = str(soldier._anim.animation)
		_assert(
			"after scan → hug again (%s)" % anim,
			anim.begins_with("corner_idle_left_")
			and not soldier._corner_scan_active
			and soldier._corner_scan_wait_sec > 0.0,
			"active=%s scan_wait=%.2f" % [soldier._corner_scan_active, soldier._corner_scan_wait_sec],
		)
		soldier.queue_free()
		await get_tree().process_frame
	IsometricGrid.reset_view_rotation()


func _make_corner_soldier(corner_step: Vector2i) -> Soldier:
	var soldier: Soldier = SoldierScene.instantiate() as Soldier
	add_child(soldier)
	await get_tree().process_frame
	soldier.team_id = Team.USA
	soldier.soldier_id = 2
	soldier._configure_team_visual()
	var from_cell := Vector2i(20, 20)
	soldier._facing_from_cell = from_cell
	soldier._applied_position_state = PositionState.UP
	soldier._last_applied_facing = FacingDirection.EAST
	soldier._idle_peek_side = CoverSystem.PeekSide.LEFT
	soldier._cover_corner_cell = from_cell + corner_step
	return soldier


func _run_corner_lookout_case() -> void:
	var soldier := await _make_corner_soldier(Vector2i(1, 0))
	soldier._play_idle_standing(soldier._world_direction_from_step(FacingDirection.EAST))
	var anim := str(soldier._anim.animation)
	_assert(
		"facing around corner → lookout held (%s frame %d)" % [anim, soldier._anim.frame],
		anim.begins_with("corner_peek_left_")
		and not soldier._anim.is_playing()
		and soldier._anim.frame == Soldier.CORNER_LOOKOUT_FRAME
		and soldier._corner_scan_wait_sec <= 0.0,
		"playing=%s scan_wait=%.2f" % [soldier._anim.is_playing(), soldier._corner_scan_wait_sec],
	)
	## A sync refresh keeps the held lookout frame.
	soldier._play_idle_standing(soldier._world_direction_from_step(FacingDirection.EAST))
	_assert(
		"sync keeps lookout frame (%d)" % soldier._anim.frame,
		soldier._anim.frame == Soldier.CORNER_LOOKOUT_FRAME and not soldier._anim.is_playing(),
	)
	## Enemy engaged: straight to the gun-up lean-out, no tuck-in / peek-enter.
	soldier._request_corner_fire(PositionState.UP, FacingDirection.EAST, CoverSystem.PeekSide.LEFT)
	_assert(
		"lookout → fire skips peek-enter (phase %d)" % soldier._corner_phase,
		soldier._corner_phase != Soldier.CornerPresPhase.PEEKING_OUT
		and (soldier._fire_active or soldier._corner_phase == Soldier.CornerPresPhase.AIMING),
		"anim=%s" % str(soldier._anim.animation),
	)
	## Fight over: lower the gun back to the lookout, no tuck-in.
	soldier._presentation_engaged = false
	if soldier._fire_active:
		soldier._finish_fire(str(soldier._anim.animation))
	else:
		soldier._start_corner_peek_exit()
	var after := str(soldier._anim.animation)
	_assert(
		"lookout fight over → lookout again (%s frame %d)" % [after, soldier._anim.frame],
		after.begins_with("corner_peek_left_") and soldier._anim.frame == Soldier.CORNER_LOOKOUT_FRAME,
		"phase=%d" % soldier._corner_phase,
	)
	soldier.queue_free()
	await get_tree().process_frame


## engaged=false: peek back in (CPA exit) then corner idle. engaged=true: stay peeked out (CAS).
func _run_corner_fire_case(engaged: bool) -> void:
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
	soldier._presentation_engaged = engaged
	var fire_anim := str(soldier._anim.animation)
	soldier._finish_fire(fire_anim)
	var after := str(soldier._anim.animation)
	if engaged:
		_assert(
			"corner post-fire engaged → stays peeked out (%s)" % after,
			after.begins_with("corner_peek_enter_")
			and not soldier._anim.is_playing()
			and soldier._corner_phase == Soldier.CornerPresPhase.AIMING,
			"phase=%d hold=%s" % [soldier._corner_phase, soldier._fire_aim_hold_active],
		)
	else:
		_assert(
			"corner post-fire → peeks back in (%s)" % after,
			after.begins_with("corner_peek_exit_"),
			"phase=%d" % soldier._corner_phase,
		)
		soldier._finish_corner_peek_exit()
		after = str(soldier._anim.animation)
		_assert(
			"corner peek-in → idle family (%s)" % after,
			_is_idle_family_anim(after),
			"phase=%d hold=%s" % [soldier._corner_phase, soldier._fire_aim_hold_active],
		)
	soldier.queue_free()
	await get_tree().process_frame
	IsometricGrid.reset_view_rotation()
