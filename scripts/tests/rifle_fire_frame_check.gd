extends Node
## Headless validation for standing / prone / corner rifle fire registration.
## Run: Godot --headless --path <project> res://scripts/tests/rifle_fire_frame_check.tscn


const DIRS: Array[String] = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const CAM_ROTATIONS: Array[int] = [0, 90, 180, 270]
const EXPECTED_FPS := 8.0
const FIRE_SEMANTICS: Array[String] = [
	"fire_standing",
	"fire_prone",
	"fire_corner_left",
	"fire_corner_right",
]


func _ready() -> void:
	UsSoldierSpriteFrames.reload_cached_frames()
	GameplayPolicies.fire_anim.reset_to_defaults()
	var failures: Array[String] = []

	failures.append_array(_validate_db("us_rifle", "fire_standing", "ASFIA", "USA standing", {8: 2}))
	failures.append_array(_validate_db("us_rifle", "fire_prone", "APRFA", "USA prone", {}))
	failures.append_array(_validate_db("us_rifle", "fire_corner_left", "ALCFA", "USA legacy corner L", {}))
	failures.append_array(_validate_db("us_rifle", "fire_corner_right", "ARCFA", "USA legacy corner R", {}))
	failures.append_array(
		_validate_peek_db("us_rifle", "corner_fire_left", "ALPKA", "USA peek L", "E", 12, 12.0, 8)
	)
	failures.append_array(
		_validate_peek_db("us_rifle", "corner_fire_right", "ARPKA", "USA peek R", "E", 12, 12.0, 8)
	)
	failures.append_array(
		_validate_peek_db("us_rifle", "corner_fire_kneel", "APKNA", "USA peek kneel", "C", 6, 12.0, 5)
	)
	failures.append_array(_validate_db("german_rifle", "fire_standing", "GSFIA", "Germany standing", {}))
	failures.append_array(_validate_db("german_rifle", "fire_prone", "GPRFA", "Germany prone", {}))
	failures.append_array(
		_validate_db("german_rifle", "fire_corner_left", "GLCFA", "Germany legacy corner L", {})
	)
	failures.append_array(
		_validate_db("german_rifle", "fire_corner_right", "GRCFA", "Germany legacy corner R", {})
	)
	failures.append_array(
		_validate_peek_db("german_rifle", "corner_fire_left", "GLPKA", "Germany peek L", "E", 12, 12.0, 8, {8: 11})
	)
	failures.append_array(
		_validate_peek_db("german_rifle", "corner_fire_right", "GRPKA", "Germany peek R", "E", 12, 12.0, 8)
	)
	failures.append_array(
		_validate_peek_db(
			"german_rifle", "corner_fire_kneel", "GPKNA", "Germany peek kneel", "C", 6, 12.0, 5
		)
	)
	failures.append_array(_validate_runtime(UsSoldierSpriteFrames.get_usa_sprite_frames(), "USA"))
	failures.append_array(_validate_runtime(UsSoldierSpriteFrames.get_germany_sprite_frames(), "Germany"))
	failures.append_array(_validate_peek_runtime(UsSoldierSpriteFrames.get_usa_sprite_frames(), "USA"))
	failures.append_array(
		_validate_peek_runtime(UsSoldierSpriteFrames.get_germany_sprite_frames(), "Germany")
	)
	failures.append_array(_validate_camera_maps())
	failures.append_array(_validate_policy())
	failures.append_array(_validate_asfia8_exception())

	print("=== rifle_fire_frame_check ===")
	if failures.is_empty():
		print("PASS: standing/prone/corner peek fire anims OK (ASFIA nw=A-B only)")
		get_tree().quit(0)
	else:
		print("FAIL count=%d" % failures.size())
		for line in failures:
			print("FAIL ", line)
		get_tree().quit(1)


func _validate_db(
	family_id: String,
	anim_id: String,
	expected_source: String,
	label: String,
	digit_frame_overrides: Dictionary,
) -> Array[String]:
	var fails: Array[String] = []
	var anim := AnimationDatabase.get_animation(family_id, anim_id)
	if anim.is_empty():
		fails.append("%s: %s missing from AnimationDatabase" % [label, anim_id])
		return fails
	var meta: Dictionary = anim.get("metadata", {}) if anim.get("metadata", {}) is Dictionary else {}
	if str(meta.get("source_family", "")) != expected_source:
		fails.append(
			"%s: source_family=%s expected %s" % [label, meta.get("source_family", ""), expected_source]
		)
	if bool(anim.get("loop", true)):
		fails.append("%s: %s must not loop" % [label, anim_id])
	var fps := float(anim.get("fps", 0.0))
	if not is_equal_approx(fps, EXPECTED_FPS):
		fails.append("%s: fps=%.1f expected %.1f" % [label, fps, EXPECTED_FPS])
	if int(meta.get("visual_shot_frame", -1)) != 1:
		fails.append("%s: visual_shot_frame should be 1 (B)" % label)

	for direction in DIRS:
		var digit := _digit_for_direction(direction)
		var expected_count := 3
		if digit_frame_overrides.has(digit):
			expected_count = int(digit_frame_overrides[digit])
		var frames := AnimationDatabase.get_direction_frames(family_id, anim_id, direction)
		if frames.size() != expected_count:
			fails.append(
				"%s %s: frame count %d expected %d" % [label, direction, frames.size(), expected_count]
			)
		for i in frames.size():
			var path := str(frames[i])
			if path.is_empty():
				fails.append("%s %s[%d]: empty path" % [label, direction, i])
				continue
			if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
				fails.append("%s missing: %s" % [label, path])
			var expected_letter := String.chr(ord("A") + i)
			var expected_name := "%s%d%s.png" % [expected_source, digit, expected_letter]
			if path.get_file() != expected_name:
				fails.append(
					"%s %s[%d]: got %s expected %s"
					% [label, direction, i, path.get_file(), expected_name]
				)
	return fails


func _validate_peek_db(
	family_id: String,
	anim_id: String,
	expected_source: String,
	label: String,
	start_letter: String,
	expected_count: int,
	expected_fps: float,
	muzzle_frame: int,
	digit_frame_overrides: Dictionary = {},
) -> Array[String]:
	var fails: Array[String] = []
	var anim := AnimationDatabase.get_animation(family_id, anim_id)
	if anim.is_empty():
		fails.append("%s: %s missing from AnimationDatabase" % [label, anim_id])
		return fails
	var meta: Dictionary = anim.get("metadata", {}) if anim.get("metadata", {}) is Dictionary else {}
	if str(meta.get("source_family", "")) != expected_source:
		fails.append(
			"%s: source_family=%s expected %s" % [label, meta.get("source_family", ""), expected_source]
		)
	if bool(anim.get("loop", true)):
		fails.append("%s: %s must not loop" % [label, anim_id])
	var fps := float(anim.get("fps", 0.0))
	if not is_equal_approx(fps, expected_fps):
		fails.append("%s: fps=%.1f expected %.1f" % [label, fps, expected_fps])
	if int(meta.get("muzzle_flash_frame", -1)) != muzzle_frame:
		fails.append(
			"%s: muzzle_flash_frame=%s expected %d"
			% [label, meta.get("muzzle_flash_frame", -1), muzzle_frame]
		)
	var start_ord := ord(start_letter)
	for direction in DIRS:
		var digit := _digit_for_direction(direction)
		var count := expected_count
		if digit_frame_overrides.has(digit):
			count = int(digit_frame_overrides[digit])
		var frames := AnimationDatabase.get_direction_frames(family_id, anim_id, direction)
		if frames.size() != count:
			fails.append(
				"%s %s: frame count %d expected %d" % [label, direction, frames.size(), count]
			)
		for i in frames.size():
			var path := str(frames[i])
			if path.is_empty():
				fails.append("%s %s[%d]: empty path" % [label, direction, i])
				continue
			if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
				fails.append("%s missing: %s" % [label, path])
			var expected_letter := String.chr(start_ord + i)
			var expected_name := "%s%d%s.png" % [expected_source, digit, expected_letter]
			if path.get_file() != expected_name:
				fails.append(
					"%s %s[%d]: got %s expected %s"
					% [label, direction, i, path.get_file(), expected_name]
				)
	return fails


func _validate_runtime(sf: SpriteFrames, label: String) -> Array[String]:
	var fails: Array[String] = []
	for semantic in FIRE_SEMANTICS:
		for direction in DIRS:
			var anim_name := "%s_%s" % [semantic, direction]
			if not sf.has_animation(anim_name):
				fails.append("%s runtime missing %s" % [label, anim_name])
				continue
			var count := sf.get_frame_count(anim_name)
			var fps := sf.get_animation_speed(anim_name)
			var loop := sf.get_animation_loop(anim_name)
			print("%s %s frames=%d fps=%.1f loop=%s" % [label, anim_name, count, fps, loop])
			var expected := 2 if (label == "USA" and semantic == "fire_standing" and direction == "nw") else 3
			if count != expected:
				fails.append("%s %s frames=%d expected %d" % [label, anim_name, count, expected])
			if not is_equal_approx(fps, EXPECTED_FPS):
				fails.append("%s %s fps=%.1f expected %.1f" % [label, anim_name, fps, EXPECTED_FPS])
			if loop:
				fails.append("%s %s must not loop" % [label, anim_name])
	return fails


func _validate_peek_runtime(sf: SpriteFrames, label: String) -> Array[String]:
	var fails: Array[String] = []
	var specs := {
		"corner_fire_left": 12,
		"corner_fire_right": 12,
		"corner_fire_kneel": 6,
	}
	for semantic in specs.keys():
		var expected_base: int = int(specs[semantic])
		for direction in DIRS:
			var anim_name := "%s_%s" % [semantic, direction]
			if not sf.has_animation(anim_name):
				fails.append("%s runtime missing %s" % [label, anim_name])
				continue
			var count := sf.get_frame_count(anim_name)
			var fps := sf.get_animation_speed(anim_name)
			var loop := sf.get_animation_loop(anim_name)
			var expected := expected_base
			## Recovered GLPKA NW is missing frame P.
			if label == "Germany" and semantic == "corner_fire_left" and direction == "nw":
				expected = 11
			if count != expected:
				fails.append("%s %s frames=%d expected %d" % [label, anim_name, count, expected])
			if not is_equal_approx(fps, 12.0):
				fails.append("%s %s fps=%.1f expected 12.0" % [label, anim_name, fps])
			if loop:
				fails.append("%s %s must not loop" % [label, anim_name])
	return fails


func _validate_camera_maps() -> Array[String]:
	var fails: Array[String] = []
	for world in DIRS:
		for cam in CAM_ROTATIONS:
			var resolved := AnimationDatabase.display_direction(world, cam)
			if resolved not in DIRS:
				fails.append("camera map %s@%d → %s invalid" % [world, cam, resolved])
	return fails


func _validate_policy() -> Array[String]:
	var fails: Array[String] = []
	var policy := GameplayPolicies.fire_anim
	if policy.source_family_for(Team.USA, PositionState.UP) != "ASFIA":
		fails.append("policy USA standing → ASFIA")
	if policy.source_family_for(Team.USA, PositionState.DOWN) != "APRFA":
		fails.append("policy USA prone → APRFA")
	if policy.source_family_for(Team.GERMANY, PositionState.UP) != "GSFIA":
		fails.append("policy Germany standing → GSFIA")
	if policy.source_family_for(Team.GERMANY, PositionState.DOWN) != "GPRFA":
		fails.append("policy Germany prone → GPRFA")
	if policy.source_family_for(Team.USA, PositionState.UP, CoverSystem.PeekSide.LEFT) != "ALPKA":
		fails.append("policy USA corner L → ALPKA")
	if policy.source_family_for(Team.USA, PositionState.UP, CoverSystem.PeekSide.RIGHT) != "ARPKA":
		fails.append("policy USA corner R → ARPKA")
	if policy.source_family_for(Team.GERMANY, PositionState.UP, CoverSystem.PeekSide.LEFT) != "GLPKA":
		fails.append("policy Germany corner L → GLPKA")
	if policy.source_family_for(Team.GERMANY, PositionState.UP, CoverSystem.PeekSide.RIGHT) != "GRPKA":
		fails.append("policy Germany corner R → GRPKA")
	if policy.source_family_for(Team.USA, PositionState.DOWN, CoverSystem.PeekSide.LEFT) != "APKNA":
		fails.append("policy USA prone+peek → APKNA")
	if policy.semantic_for(PositionState.UP, CoverSystem.PeekSide.LEFT) != "corner_fire_left":
		fails.append("semantic corner L")
	if policy.semantic_for(PositionState.UP, CoverSystem.PeekSide.RIGHT) != "corner_fire_right":
		fails.append("semantic corner R")
	if policy.semantic_for(PositionState.DOWN, CoverSystem.PeekSide.LEFT) != "corner_fire_kneel":
		fails.append("semantic corner kneel")
	if policy.visual_shot_frame_asfia != 1:
		fails.append("ASFIA visual shot frame should be B (1)")
	return fails


func _validate_asfia8_exception() -> Array[String]:
	var fails: Array[String] = []
	var bogus := "res://assets/sprites/us_soldier/fire_standing/ASFIA8C.png"
	if ResourceLoader.exists(bogus) or FileAccess.file_exists(bogus):
		fails.append("ASFIA8C.png must not exist / must not be fabricated")
	var nw := AnimationDatabase.get_direction_frames("us_rifle", "fire_standing", "nw")
	if nw.size() != 2:
		fails.append("ASFIA nw must be exactly 2 frames (A-B), got %d" % nw.size())
	elif nw.size() == 2:
		if not str(nw[0]).ends_with("ASFIA8A.png") or not str(nw[1]).ends_with("ASFIA8B.png"):
			fails.append("ASFIA nw paths must be ASFIA8A then ASFIA8B")
	return fails


func _digit_for_direction(direction: String) -> int:
	match direction:
		"w":
			return 1
		"sw":
			return 2
		"s":
			return 3
		"se":
			return 4
		"e":
			return 5
		"ne":
			return 6
		"n":
			return 7
		"nw":
			return 8
		_:
			return -1
