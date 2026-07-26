extends Node
## Headless validation for standing / prone / corner rifle fire registration.
## Run: Godot --headless --path <project> res://scripts/tests/rifle_fire_frame_check.tscn


const DIRS: Array[String] = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const CAM_ROTATIONS: Array[int] = [0, 90, 180, 270]
const EXPECTED_FPS := 8.0
const FIRE_SEMANTICS: Array[String] = [
	"fire_standing",
	"fire_prone",
]


func _ready() -> void:
	UsSoldierSpriteFrames.reload_cached_frames()
	GameplayPolicies.fire_anim.reset_to_defaults()
	var failures: Array[String] = []

	failures.append_array(_validate_db("us_rifle", "fire_standing", "ASFIA", "USA standing", {8: 2}))
	failures.append_array(_validate_db("us_rifle", "fire_prone", "APRFA", "USA prone", {}))
	failures.append_array(
		_validate_corner_fire_db("us_rifle", "corner_fire_left", "ALCFA", "USA corner L")
	)
	failures.append_array(
		_validate_corner_fire_db("us_rifle", "corner_fire_right", "ARCFA", "USA corner R")
	)
	failures.append_array(_validate_db("german_rifle", "fire_standing", "GSFIA", "Germany standing", {}))
	failures.append_array(_validate_db("german_rifle", "fire_prone", "GPRFA", "Germany prone", {}))
	failures.append_array(
		_validate_corner_fire_db("german_rifle", "corner_fire_left", "GLCFA", "Germany corner L")
	)
	failures.append_array(
		_validate_corner_fire_db("german_rifle", "corner_fire_right", "GRCFA", "Germany corner R")
	)
	failures.append_array(_validate_no_dupes("us_rifle"))
	failures.append_array(_validate_no_dupes("german_rifle"))
	failures.append_array(_validate_runtime(UsSoldierSpriteFrames.get_usa_sprite_frames(), "USA"))
	failures.append_array(_validate_runtime(UsSoldierSpriteFrames.get_germany_sprite_frames(), "Germany"))
	failures.append_array(_validate_corner_runtime(UsSoldierSpriteFrames.get_usa_sprite_frames(), "USA"))
	failures.append_array(
		_validate_corner_runtime(UsSoldierSpriteFrames.get_germany_sprite_frames(), "Germany")
	)
	failures.append_array(_validate_camera_maps())
	failures.append_array(_validate_policy())
	failures.append_array(_validate_asfia8_exception())

	print("=== rifle_fire_frame_check ===")
	if failures.is_empty():
		print("PASS: standing/prone/corner CFA fire anims OK (ASFIA nw=A-B only)")
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


func _validate_corner_fire_db(
	family_id: String,
	anim_id: String,
	expected_source: String,
	label: String,
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
	if not is_equal_approx(float(anim.get("fps", 0.0)), 12.0):
		fails.append("%s: fps expected 12" % label)
	if int(meta.get("muzzle_flash_frame", -1)) != 2:
		fails.append("%s: muzzle_flash_frame expected 2 (C)" % label)
	for direction in DIRS:
		var digit := _digit_for_direction(direction)
		var frames := AnimationDatabase.get_direction_frames(family_id, anim_id, direction)
		if frames.size() != 3:
			fails.append("%s %s: frame count %d expected 3" % [label, direction, frames.size()])
		for i in frames.size():
			var path := str(frames[i])
			if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
				fails.append("%s missing: %s" % [label, path])
			var expected_name := "%s%d%s.png" % [expected_source, digit, String.chr(ord("A") + i)]
			if path.get_file() != expected_name:
				fails.append(
					"%s %s[%d]: got %s expected %s"
					% [label, direction, i, path.get_file(), expected_name]
				)
			## Faction guard: US A*, German G*
			if expected_source.begins_with("A") and path.contains("german_soldier"):
				fails.append("%s cross-faction path: %s" % [label, path])
			if expected_source.begins_with("G") and path.contains("us_soldier"):
				fails.append("%s cross-faction path: %s" % [label, path])
	return fails


func _validate_no_dupes(family_id: String) -> Array[String]:
	var fails: Array[String] = []
	for bad in [
		"fire_corner_left",
		"fire_corner_right",
		"idle_corner_left",
		"idle_corner_right",
		"corner_idle_kneel",
		"corner_fire_kneel",
	]:
		if not AnimationDatabase.get_animation(family_id, bad).is_empty():
			fails.append("%s still has deleted clip %s" % [family_id, bad])
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
			var expected := 2 if (label == "USA" and semantic == "fire_standing" and direction == "nw") else 3
			if count != expected:
				fails.append("%s %s frames=%d expected %d" % [label, anim_name, count, expected])
			if not is_equal_approx(fps, EXPECTED_FPS):
				fails.append("%s %s fps=%.1f expected %.1f" % [label, anim_name, fps, EXPECTED_FPS])
			if loop:
				fails.append("%s %s must not loop" % [label, anim_name])
	return fails


func _validate_corner_runtime(sf: SpriteFrames, label: String) -> Array[String]:
	var fails: Array[String] = []
	for semantic in ["corner_fire_left", "corner_fire_right"]:
		for direction in DIRS:
			var anim_name := "%s_%s" % [semantic, direction]
			if not sf.has_animation(anim_name):
				fails.append("%s runtime missing %s" % [label, anim_name])
				continue
			if sf.get_frame_count(anim_name) != 3:
				fails.append(
					"%s %s frames=%d expected 3" % [label, anim_name, sf.get_frame_count(anim_name)]
				)
			if not is_equal_approx(sf.get_animation_speed(anim_name), 12.0):
				fails.append("%s %s fps expected 12" % [label, anim_name])
			if sf.get_animation_loop(anim_name):
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
	if policy.source_family_for(Team.USA, PositionState.UP, CoverSystem.PeekSide.LEFT) != "ALCFA":
		fails.append("policy USA corner L → ALCFA")
	if policy.source_family_for(Team.USA, PositionState.UP, CoverSystem.PeekSide.RIGHT) != "ARCFA":
		fails.append("policy USA corner R → ARCFA")
	if policy.source_family_for(Team.GERMANY, PositionState.UP, CoverSystem.PeekSide.LEFT) != "GLCFA":
		fails.append("policy Germany corner L → GLCFA")
	if policy.source_family_for(Team.GERMANY, PositionState.UP, CoverSystem.PeekSide.RIGHT) != "GRCFA":
		fails.append("policy Germany corner R → GRCFA")
	if policy.source_family_for(Team.USA, PositionState.DOWN, CoverSystem.PeekSide.LEFT) != "APRFA":
		fails.append("policy USA prone+peek → APRFA")
	if policy.semantic_for(PositionState.UP, CoverSystem.PeekSide.LEFT) != "corner_fire_left":
		fails.append("semantic corner L")
	if policy.semantic_for(PositionState.UP, CoverSystem.PeekSide.RIGHT) != "corner_fire_right":
		fails.append("semantic corner R")
	if policy.semantic_for(PositionState.DOWN, CoverSystem.PeekSide.LEFT) != "fire_prone":
		fails.append("semantic prone+peek")
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
			return 7
