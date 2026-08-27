extends Node
## Grenade throw presentation sequence (stand/prone → kneel → throw → return).
## Run: Godot --headless --path <project> res://scripts/tests/throw_grenade_sequence_tests.tscn

const SoldierScene := preload("res://scenes/soldier.tscn")

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

	await _test_standing_sequence_order()
	await _test_standing_returns_standing_idle()
	await _test_prone_sequence_order()
	await _test_prone_returns_prone_idle()
	await _test_release_exactly_once()
	await _test_opening_before_throw()
	await _test_exit_after_throw()
	await _test_direction_consistent()
	await _test_death_interrupts()
	await _test_duplicate_request_ignored()
	await _test_human_and_ai_same_path()
	await _test_authoritative_stance_unchanged()

	print("")
	print("Grenade sequence tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail if not detail.is_empty() else "assertion failed"])


func _display_suffix_for_facing(facing: Vector2i) -> String:
	var world := UsSoldierSpriteFrames.direction_from_step(facing)
	return AnimationDatabase.display_direction(world, IsometricGrid.facet_camera_direction_degrees())


func _anim_suffix(anim_name: String) -> String:
	var parts := anim_name.split("_")
	return parts[parts.size() - 1]


func _new_soldier(team_id: int, stance: int, facing: Vector2i) -> Soldier:
	var soldier: Soldier = SoldierScene.instantiate() as Soldier
	add_child(soldier)
	soldier.team_id = team_id
	soldier.soldier_id = 1
	soldier._configure_team_visual()
	soldier._last_applied_facing = facing
	soldier._facing_from_cell = Vector2i(20, 20)
	soldier._applied_position_state = stance
	soldier._idle_peek_side = CoverSystem.PeekSide.NONE
	soldier._corner_phase = Soldier.CornerPresPhase.NONE
	if stance == PositionState.DOWN:
		soldier._anim.scale = soldier._prone_sprite_scale()
		soldier._anim.offset = TileSizeConfig.soldier_prone_sprite_offset()
		if soldier._anim.sprite_frames.has_animation("idle_prone_e"):
			soldier._anim.play("idle_prone_e")
	else:
		soldier._anim.scale = soldier._standing_sprite_scale()
		soldier._anim.offset = TileSizeConfig.soldier_standing_sprite_offset()
		if soldier._anim.sprite_frames.has_animation("idle_standing_e"):
			soldier._anim.play("idle_standing_e")
	return soldier


func _run_throw_sequence(
	soldier: Soldier,
	stance: int,
	facing: Vector2i,
	enter_prefix: String,
	exit_prefix: String,
) -> Dictionary:
	var log: Array[String] = []
	var suffix := _display_suffix_for_facing(facing)
	soldier.play_throw_grenade(stance, facing)
	log.append(str(soldier._anim.animation))
	_assert("enter phase latch", soldier.debug_throw_pres_phase() == Soldier.ThrowPresPhase.ENTER_KNEEL, "")
	_assert("enter anim", str(soldier._anim.animation) == "%s_%s" % [enter_prefix, suffix], str(soldier._anim.animation))

	soldier.debug_simulate_throw_anim_finished()
	log.append(str(soldier._anim.animation))
	_assert("throw phase latch", soldier.debug_throw_pres_phase() == Soldier.ThrowPresPhase.THROW, "")
	_assert("throw anim", str(soldier._anim.animation).begins_with("throw_grenade_"), str(soldier._anim.animation))

	soldier.debug_simulate_throw_anim_finished()
	log.append(str(soldier._anim.animation))
	_assert("exit phase latch", soldier.debug_throw_pres_phase() == Soldier.ThrowPresPhase.EXIT_KNEEL, "")
	_assert("exit anim", str(soldier._anim.animation) == "%s_%s" % [exit_prefix, suffix], str(soldier._anim.animation))

	soldier.debug_simulate_throw_anim_finished()
	log.append(str(soldier._anim.animation))
	_assert("sequence inactive", not soldier._throw_grenade_active, "")
	return {"log": log, "suffix": suffix}


func _test_standing_sequence_order() -> void:
	var soldier := _new_soldier(Team.USA, PositionState.UP, FacingDirection.EAST)
	await get_tree().process_frame
	var result := _run_throw_sequence(
		soldier,
		PositionState.UP,
		FacingDirection.EAST,
		"transition_standing_to_kneel",
		"transition_kneel_to_stand",
	)
	_assert(
		"standing sequence order",
		result.log.size() == 4
		and result.log[0].begins_with("transition_standing_to_kneel_")
		and result.log[1].begins_with("throw_grenade_")
		and result.log[2].begins_with("transition_kneel_to_stand_"),
		"%s" % ", ".join(result.log),
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_standing_returns_standing_idle() -> void:
	var soldier := _new_soldier(Team.USA, PositionState.UP, FacingDirection.EAST)
	await get_tree().process_frame
	_run_throw_sequence(
		soldier,
		PositionState.UP,
		FacingDirection.EAST,
		"transition_standing_to_kneel",
		"transition_kneel_to_stand",
	)
	var after := str(soldier._anim.animation)
	_assert(
		"standing returns standing idle",
		after.begins_with("idle_standing_") or after.begins_with("walk_"),
		after,
	)
	_assert(
		"standing applied stance UP",
		soldier._applied_position_state == PositionState.UP,
		PositionState.display_name(soldier._applied_position_state),
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_prone_sequence_order() -> void:
	var soldier := _new_soldier(Team.USA, PositionState.DOWN, FacingDirection.EAST)
	await get_tree().process_frame
	var result := _run_throw_sequence(
		soldier,
		PositionState.DOWN,
		FacingDirection.EAST,
		"transition_prone_to_kneel",
		"transition_kneel_to_prone",
	)
	_assert(
		"prone sequence order",
		result.log[0].begins_with("transition_prone_to_kneel_")
		and result.log[1].begins_with("throw_grenade_")
		and result.log[2].begins_with("transition_kneel_to_prone_"),
		"%s" % ", ".join(result.log),
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_prone_returns_prone_idle() -> void:
	var soldier := _new_soldier(Team.USA, PositionState.DOWN, FacingDirection.EAST)
	await get_tree().process_frame
	_run_throw_sequence(
		soldier,
		PositionState.DOWN,
		FacingDirection.EAST,
		"transition_prone_to_kneel",
		"transition_kneel_to_prone",
	)
	var after := str(soldier._anim.animation)
	_assert(
		"prone returns prone idle",
		after.begins_with("idle_prone_") or after.begins_with("crawl_"),
		after,
	)
	_assert(
		"prone applied stance DOWN",
		soldier._applied_position_state == PositionState.DOWN,
		PositionState.display_name(soldier._applied_position_state),
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_release_exactly_once() -> void:
	var soldier := _new_soldier(Team.USA, PositionState.UP, FacingDirection.EAST)
	await get_tree().process_frame
	var releases := [0]
	soldier.grenade_release_reached.connect(func(_t: int, _s: int) -> void:
		releases[0] += 1
	)
	GameplayPolicies.grenade.throw_release_frame_usa = 10
	soldier.play_throw_grenade(PositionState.UP, FacingDirection.EAST)
	soldier.debug_simulate_throw_anim_finished()
	var release_frame := GameplayPolicies.grenade.throw_release_frame_for_team(soldier.team_id)
	soldier._anim.frame = maxi(release_frame, 0)
	soldier._on_anim_frame_changed()
	soldier._anim.frame = release_frame + 2
	soldier._on_anim_frame_changed()
	_assert("grenade release once", releases[0] == 1, "releases=%d" % releases[0])
	GameplayPolicies.grenade.throw_release_frame_usa = -1
	soldier.queue_free()
	await get_tree().process_frame


func _test_opening_before_throw() -> void:
	var soldier := _new_soldier(Team.USA, PositionState.UP, FacingDirection.EAST)
	await get_tree().process_frame
	soldier.play_throw_grenade(PositionState.UP, FacingDirection.EAST)
	_assert(
		"throw not during enter",
		not str(soldier._anim.animation).begins_with("throw_grenade_"),
		str(soldier._anim.animation),
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_exit_after_throw() -> void:
	var soldier := _new_soldier(Team.USA, PositionState.UP, FacingDirection.EAST)
	await get_tree().process_frame
	soldier.play_throw_grenade(PositionState.UP, FacingDirection.EAST)
	soldier.debug_simulate_throw_anim_finished()
	_assert(
		"exit not during throw",
		not str(soldier._anim.animation).begins_with("transition_kneel_to_stand_"),
		str(soldier._anim.animation),
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_direction_consistent() -> void:
	var soldier := _new_soldier(Team.GERMANY, PositionState.UP, FacingDirection.NORTH)
	await get_tree().process_frame
	var suffix := _display_suffix_for_facing(FacingDirection.NORTH)
	soldier.play_throw_grenade(PositionState.UP, FacingDirection.NORTH)
	var dirs: Array[String] = [_anim_suffix(str(soldier._anim.animation))]
	soldier.debug_simulate_throw_anim_finished()
	dirs.append(_anim_suffix(str(soldier._anim.animation)))
	soldier.debug_simulate_throw_anim_finished()
	dirs.append(_anim_suffix(str(soldier._anim.animation)))
	soldier.debug_simulate_throw_anim_finished()
	_assert(
		"direction consistent through sequence",
		dirs[0] == suffix and dirs[1] == suffix and dirs[2] == suffix,
		"%s expected %s" % [", ".join(dirs), suffix],
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_death_interrupts() -> void:
	var soldier := _new_soldier(Team.USA, PositionState.UP, FacingDirection.EAST)
	await get_tree().process_frame
	soldier.play_throw_grenade(PositionState.UP, FacingDirection.EAST)
	soldier.play_death_sequence(FacingDirection.WEST, PositionState.UP)
	_assert("death clears throw active", not soldier._throw_grenade_active, "")
	_assert("death clears throw phase", soldier.debug_throw_pres_phase() == Soldier.ThrowPresPhase.NONE, "")
	_assert(
		"death not stuck kneeling scale",
		soldier._applied_position_state == PositionState.UP,
		PositionState.display_name(soldier._applied_position_state),
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_duplicate_request_ignored() -> void:
	var soldier := _new_soldier(Team.USA, PositionState.UP, FacingDirection.EAST)
	await get_tree().process_frame
	soldier.play_throw_grenade(PositionState.UP, FacingDirection.EAST)
	var first := str(soldier._anim.animation)
	var first_phase := soldier.debug_throw_pres_phase()
	soldier.play_throw_grenade(PositionState.UP, FacingDirection.WEST)
	_assert("duplicate keeps first anim", str(soldier._anim.animation) == first, str(soldier._anim.animation))
	_assert("duplicate keeps first phase", soldier.debug_throw_pres_phase() == first_phase, "")
	soldier.queue_free()
	await get_tree().process_frame


func _test_human_and_ai_same_path() -> void:
	## Both gameplay paths call Soldier.play_throw_grenade — verify Germany uses same sequence.
	var soldier := _new_soldier(Team.GERMANY, PositionState.UP, FacingDirection.EAST)
	await get_tree().process_frame
	var result := _run_throw_sequence(
		soldier,
		PositionState.UP,
		FacingDirection.EAST,
		"transition_standing_to_kneel",
		"transition_kneel_to_stand",
	)
	_assert(
		"germany uses kneel throw path",
		result.log[1].begins_with("throw_grenade_"),
		"%s" % ", ".join(result.log),
	)
	soldier.queue_free()
	await get_tree().process_frame


func _test_authoritative_stance_unchanged() -> void:
	var soldier := _new_soldier(Team.USA, PositionState.DOWN, FacingDirection.EAST)
	await get_tree().process_frame
	var stances: Array[int] = []
	soldier.play_throw_grenade(PositionState.DOWN, FacingDirection.EAST)
	stances.append(soldier._applied_position_state)
	soldier.debug_simulate_throw_anim_finished()
	stances.append(soldier._applied_position_state)
	soldier.debug_simulate_throw_anim_finished()
	stances.append(soldier._applied_position_state)
	soldier.debug_simulate_throw_anim_finished()
	stances.append(soldier._applied_position_state)
	soldier.debug_simulate_throw_anim_finished()
	_assert(
		"prone authoritative stance unchanged during sequence",
		stances == [PositionState.DOWN, PositionState.DOWN, PositionState.DOWN, PositionState.DOWN],
		"%s" % stances,
	)
	soldier.queue_free()
	await get_tree().process_frame
