extends Node
## Aim-hold camera parity: world facing must be camera-invariant; display letter must
## ring-shift by the expected ±2 / +4 steps.
## Run: Godot --headless --path <project> res://scripts/tests/aim_hold_camera_tests.tscn

const UsSoldierSpriteFramesClass := preload("res://scripts/soldiers/us_soldier_sprite_frames.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	SimulationClock.reset()
	GameplayPolicies.reset_all_to_defaults()
	AnimationDatabase.ensure_loaded()
	IsometricGrid.set_original_projection_enabled(true)
	IsometricGrid.set_view_pivot_for_map(64, 64)
	_test_world_facing_invariant_across_cameras()
	_test_display_ring_steps()
	_test_aim_hold_anim_present_all_cameras()
	_dump_aim_hold_resolution_table()
	print("")
	print("Aim-hold camera tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail if not detail.is_empty() else "assertion failed"])


func _test_world_facing_invariant_across_cameras() -> void:
	## Fixed shooter→target bearing must resolve to the same logical step at all cameras.
	var from_cell := Vector2i(20, 20)
	var target_cell := Vector2i(26, 17) ## east-northeast-ish
	var expected := UsSoldierSpriteFramesClass.snap_step_to_eight_way(target_cell - from_cell)
	_assert("expected step non-zero", expected != Vector2i.ZERO, "got %s" % expected)
	for rot in 4:
		IsometricGrid.current_view_rotation = rot
		var got := UsSoldierSpriteFramesClass.snap_step_to_eight_way(target_cell - from_cell)
		_assert(
			"world step invariant at rot_idx=%d facet=%d°" % [
				rot, IsometricGrid.facet_camera_direction_degrees()
			],
			got == expected,
			"got %s expected %s" % [got, expected],
		)
	IsometricGrid.reset_view_rotation()


func _test_display_ring_steps() -> void:
	## Pure world letter 'n' (no X-flip) must ring-shift: 0→n, 90→e, 180→s, 270→w.
	var expected := {"0": "n", "90": "e", "180": "s", "270": "w"}
	for cam_s in expected.keys():
		var cam := int(cam_s)
		var got := AnimationDatabase.display_direction("n", cam)
		_assert(
			"display_direction n@%d → %s" % [cam, expected[cam_s]],
			got == expected[cam_s],
			"got %s" % got,
		)


func _test_aim_hold_anim_present_all_cameras() -> void:
	## For a fixed logical facing, every camera must resolve a hold anim that exists in DB.
	var facing := FacingDirection.EAST
	var sf: SpriteFrames = UsSoldierSpriteFramesClass.get_usa_sprite_frames()
	_assert("usa sprite frames loaded", sf != null)
	for rot in 4:
		IsometricGrid.current_view_rotation = rot
		var letter := UsSoldierSpriteFramesClass.direction_from_step(facing)
		var display := AnimationDatabase.display_direction(
			letter, IsometricGrid.facet_camera_direction_degrees()
		)
		var hold := "aim_standing_hold_%s" % display
		_assert(
			"has %s at rot_idx=%d facet=%d° (letter=%s)" % [
				hold, rot, IsometricGrid.facet_camera_direction_degrees(), letter
			],
			sf.has_animation(hold),
			"missing animation",
		)
	IsometricGrid.reset_view_rotation()


func _dump_aim_hold_resolution_table() -> void:
	## Diagnostic dump for the four rotations — compare even (0/180) vs odd (90/270).
	var from_cell := Vector2i(20, 20)
	var target_cell := Vector2i(30, 20) ## due east
	var hold_facing := UsSoldierSpriteFramesClass.snap_step_to_eight_way(target_cell - from_cell)
	print("")
	print("=== AIM_HOLD resolution dump (shooter=%s target=%s hold_facing=%s) ===" % [
		from_cell, target_cell, hold_facing
	])
	print(
		"rot_idx | facet | coord | pure_world | dir_from_step | display | hold_anim | has"
	)
	var sf: SpriteFrames = UsSoldierSpriteFramesClass.get_usa_sprite_frames()
	for rot in 4:
		IsometricGrid.current_view_rotation = rot
		var facet := IsometricGrid.facet_camera_direction_degrees()
		var coord := IsometricGrid.camera_direction_degrees()
		var pure := FacingDirection.to_anim_suffix(hold_facing)
		var stepped := UsSoldierSpriteFramesClass.direction_from_step(hold_facing)
		var display := AnimationDatabase.display_direction(stepped, facet)
		var hold := "aim_standing_hold_%s" % display
		var has := sf != null and sf.has_animation(hold)
		print(
			"%d | %d | %d | %s | %s | %s | %s | %s"
			% [rot, facet, coord, pure, stepped, display, hold, has]
		)
	IsometricGrid.reset_view_rotation()
