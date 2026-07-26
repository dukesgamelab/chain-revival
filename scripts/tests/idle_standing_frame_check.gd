extends Node
## Headless validation for ABRLA / GBRLA idle_standing registration.
## Run: Godot --headless --path <project> res://scripts/tests/idle_standing_frame_check.tscn


const DIRS: Array[String] = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const CAM_ROTATIONS: Array[int] = [0, 90, 180, 270]
const EXPECTED_FRAMES := 21
const EXPECTED_FPS := 8.0


func _ready() -> void:
	UsSoldierSpriteFrames.reload_cached_frames()
	var failures: Array[String] = []

	failures.append_array(_validate_db("us_rifle", "ABRLA", "USA"))
	failures.append_array(_validate_db("german_rifle", "GBRLA", "Germany"))
	failures.append_array(_validate_corner_db("us_rifle", "idle_corner_left", "ALCAS", "USA legacy corner L"))
	failures.append_array(_validate_corner_db("us_rifle", "idle_corner_right", "ARCAS", "USA legacy corner R"))
	failures.append_array(
		_validate_corner_db("german_rifle", "idle_corner_left", "GLCAS", "Germany legacy corner L")
	)
	failures.append_array(
		_validate_corner_db("german_rifle", "idle_corner_right", "GRCAS", "Germany legacy corner R")
	)
	failures.append_array(
		_validate_peek_idle_db("us_rifle", "corner_idle_left", "ALPKA", "USA peek L", "A", 4)
	)
	failures.append_array(
		_validate_peek_idle_db("us_rifle", "corner_idle_right", "ARPKA", "USA peek R", "A", 4)
	)
	failures.append_array(
		_validate_peek_idle_db("us_rifle", "corner_idle_kneel", "APKNA", "USA peek kneel", "A", 2)
	)
	failures.append_array(
		_validate_peek_idle_db("german_rifle", "corner_idle_left", "GLPKA", "Germany peek L", "A", 4)
	)
	failures.append_array(
		_validate_peek_idle_db("german_rifle", "corner_idle_right", "GRPKA", "Germany peek R", "A", 4)
	)
	failures.append_array(
		_validate_peek_idle_db("german_rifle", "corner_idle_kneel", "GPKNA", "Germany peek kneel", "A", 2)
	)
	failures.append_array(_validate_runtime(UsSoldierSpriteFrames.get_usa_sprite_frames(), "USA"))
	failures.append_array(_validate_runtime(UsSoldierSpriteFrames.get_germany_sprite_frames(), "Germany"))
	failures.append_array(_validate_corner_runtime(UsSoldierSpriteFrames.get_usa_sprite_frames(), "USA"))
	failures.append_array(_validate_corner_runtime(UsSoldierSpriteFrames.get_germany_sprite_frames(), "Germany"))
	failures.append_array(_validate_camera_maps())
	failures.append_array(_validate_walk_untouched())
	failures.append_array(_validate_idle_policy())

	print("=== idle_standing_frame_check ===")
	if failures.is_empty():
		print("PASS: ABRLA/GBRLA + corner peek idle (ALPKA/ARPKA/APKNA + German) OK")
		get_tree().quit(0)
	else:
		print("FAIL count=%d" % failures.size())
		for line in failures:
			print("FAIL ", line)
		get_tree().quit(1)


func _validate_db(family_id: String, expected_source: String, label: String) -> Array[String]:
	var fails: Array[String] = []
	var anim := AnimationDatabase.get_animation(family_id, "idle_standing")
	if anim.is_empty():
		fails.append("%s: idle_standing missing from AnimationDatabase" % label)
		return fails
	var meta: Dictionary = anim.get("metadata", {}) if anim.get("metadata", {}) is Dictionary else {}
	if str(meta.get("source_family", "")) != expected_source:
		fails.append(
			"%s: source_family=%s expected %s" % [label, meta.get("source_family", ""), expected_source]
		)
	if not bool(anim.get("loop", false)):
		fails.append("%s: idle_standing must loop" % label)
	var fps := float(anim.get("fps", 0.0))
	if not is_equal_approx(fps, EXPECTED_FPS):
		fails.append("%s: fps=%.1f expected %.1f" % [label, fps, EXPECTED_FPS])

	for direction in DIRS:
		var frames := AnimationDatabase.get_direction_frames(family_id, "idle_standing", direction)
		if frames.size() != EXPECTED_FRAMES:
			fails.append(
				"%s %s: frame count %d expected %d"
				% [label, direction, frames.size(), EXPECTED_FRAMES]
			)
		for i in frames.size():
			var path := str(frames[i])
			if path.is_empty():
				fails.append("%s %s[%d]: empty path" % [label, direction, i])
				continue
			if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
				fails.append("%s missing: %s" % [label, path])
			var expected_letter := String.chr(ord("A") + i)
			var expected_digit := _digit_for_direction(direction)
			var expected_name := "%s%d%s.png" % [expected_source, expected_digit, expected_letter]
			if path.get_file() != expected_name:
				fails.append(
					"%s %s[%d]: got %s expected %s"
					% [label, direction, i, path.get_file(), expected_name]
				)
	return fails


func _validate_runtime(sf: SpriteFrames, label: String) -> Array[String]:
	var fails: Array[String] = []
	for direction in DIRS:
		var anim_name := "idle_standing_%s" % direction
		if not sf.has_animation(anim_name):
			fails.append("%s runtime missing %s" % [label, anim_name])
			continue
		var count := sf.get_frame_count(anim_name)
		var fps := sf.get_animation_speed(anim_name)
		var loop := sf.get_animation_loop(anim_name)
		print("%s %s frames=%d fps=%.1f loop=%s" % [label, anim_name, count, fps, loop])
		if count != EXPECTED_FRAMES:
			fails.append("%s %s frames=%d expected %d" % [label, anim_name, count, EXPECTED_FRAMES])
		if not is_equal_approx(fps, EXPECTED_FPS):
			fails.append("%s %s fps=%.1f expected %.1f" % [label, anim_name, fps, EXPECTED_FPS])
		if not loop:
			fails.append("%s %s must loop" % [label, anim_name])
	return fails


func _validate_camera_maps() -> Array[String]:
	var fails: Array[String] = []
	for world in DIRS:
		for cam in CAM_ROTATIONS:
			var resolved := AnimationDatabase.display_direction(world, cam)
			if resolved not in DIRS:
				fails.append("camera map %s@%d → %s invalid" % [world, cam, resolved])
	if AnimationDatabase.display_direction("ne", 0) != "ne":
		fails.append("camera 0° should leave ne as ne")
	if AnimationDatabase.display_direction("w", 180) != "e":
		fails.append("camera 180° should map w → e")
	return fails


func _validate_corner_db(
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
	if not bool(anim.get("loop", false)):
		fails.append("%s: %s must loop" % [label, anim_id])
	for direction in DIRS:
		var frames := AnimationDatabase.get_direction_frames(family_id, anim_id, direction)
		if frames.size() != 1:
			fails.append("%s %s: frame count %d expected 1" % [label, direction, frames.size()])
			continue
		var path := str(frames[0])
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			fails.append("%s missing: %s" % [label, path])
		var expected_name := "%s%dA.png" % [expected_source, _digit_for_direction(direction)]
		if path.get_file() != expected_name:
			fails.append("%s %s: got %s expected %s" % [label, direction, path.get_file(), expected_name])
	return fails


func _validate_peek_idle_db(
	family_id: String,
	anim_id: String,
	expected_source: String,
	label: String,
	start_letter: String,
	expected_count: int,
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
	if not bool(anim.get("loop", false)):
		fails.append("%s: %s must loop" % [label, anim_id])
	var fps := float(anim.get("fps", 0.0))
	if not is_equal_approx(fps, 4.0):
		fails.append("%s: fps=%.1f expected 4.0" % [label, fps])
	var start_ord := ord(start_letter)
	for direction in DIRS:
		var frames := AnimationDatabase.get_direction_frames(family_id, anim_id, direction)
		if frames.size() != expected_count:
			fails.append(
				"%s %s: frame count %d expected %d" % [label, direction, frames.size(), expected_count]
			)
			continue
		var digit := _digit_for_direction(direction)
		for i in frames.size():
			var path := str(frames[i])
			if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
				fails.append("%s missing: %s" % [label, path])
			var expected_name := "%s%d%s.png" % [expected_source, digit, String.chr(start_ord + i)]
			if path.get_file() != expected_name:
				fails.append(
					"%s %s[%d]: got %s expected %s"
					% [label, direction, i, path.get_file(), expected_name]
				)
	return fails


func _validate_corner_runtime(sf: SpriteFrames, label: String) -> Array[String]:
	var fails: Array[String] = []
	for semantic in ["corner_idle_left", "corner_idle_right", "corner_idle_kneel"]:
		for direction in DIRS:
			var anim_name := "%s_%s" % [semantic, direction]
			if not sf.has_animation(anim_name):
				fails.append("%s runtime missing %s" % [label, anim_name])
				continue
			var expected := 2 if semantic == "corner_idle_kneel" else 4
			if sf.get_frame_count(anim_name) != expected:
				fails.append(
					"%s %s frames=%d expected %d"
					% [label, anim_name, sf.get_frame_count(anim_name), expected]
				)
			if not sf.get_animation_loop(anim_name):
				fails.append("%s %s must loop" % [label, anim_name])
	return fails


func _validate_idle_policy() -> Array[String]:
	var fails: Array[String] = []
	var policy := GameplayPolicies.idle_anim
	if policy.source_family_for(Team.USA) != "ABRLA":
		fails.append("policy USA open idle → ABRLA")
	if policy.source_family_for(Team.USA, CoverSystem.PeekSide.LEFT) != "ALPKA":
		fails.append("policy USA corner L → ALPKA")
	if policy.source_family_for(Team.USA, CoverSystem.PeekSide.RIGHT) != "ARPKA":
		fails.append("policy USA corner R → ARPKA")
	if policy.source_family_for(Team.GERMANY, CoverSystem.PeekSide.LEFT) != "GLPKA":
		fails.append("policy Germany corner L → GLPKA")
	if policy.source_family_for(Team.GERMANY, CoverSystem.PeekSide.RIGHT) != "GRPKA":
		fails.append("policy Germany corner R → GRPKA")
	if (
		policy.source_family_for(Team.USA, CoverSystem.PeekSide.LEFT, PositionState.DOWN)
		!= "APKNA"
	):
		fails.append("policy USA corner kneel → APKNA")
	if policy.semantic_for(CoverSystem.PeekSide.LEFT) != "corner_idle_left":
		fails.append("semantic corner L")
	if (
		policy.semantic_for(CoverSystem.PeekSide.RIGHT, PositionState.DOWN)
		!= "corner_idle_kneel"
	):
		fails.append("semantic corner kneel")
	return fails


func _validate_walk_untouched() -> Array[String]:
	## Walking families must remain ASMOA / GSMOA — idle must not replace them.
	var fails: Array[String] = []
	var us_walk := AnimationDatabase.get_direction_frames("us_rifle", "walk", "n")
	var de_walk := AnimationDatabase.get_direction_frames("german_rifle", "walk", "n")
	if us_walk.is_empty() or not str(us_walk[0]).contains("ASMOA"):
		fails.append("USA walk must still use ASMOA (not ABRLA)")
	if de_walk.is_empty() or not str(de_walk[0]).contains("GSMOA"):
		fails.append("Germany walk must still use GSMOA (not GBRLA)")
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
