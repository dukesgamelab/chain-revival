extends Node
## Headless validation for German stance idles + transitions.
## Run: Godot --headless --path <project> res://scripts/tests/german_stance_frame_check.tscn


const DIRS: Array[String] = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const FAMILY := "german_rifle"
const EXPECTED_FPS := 8.0


func _ready() -> void:
	UsSoldierSpriteFrames.reload_cached_frames()
	var failures: Array[String] = []

	failures.append_array(_validate_anim("idle_standing", "GBRLA", true, 21))
	failures.append_array(_validate_anim("idle_prone", "GPRIS", true, 1))
	failures.append_array(
		_validate_anim("transition_prone_to_standing", "GPRNA", false, 5)
	)
	failures.append_array(
		_validate_anim("transition_standing_to_prone", "GSUPA", false, 24)
	)
	failures.append_array(_validate_runtime())
	failures.append_array(_validate_camera_maps())
	failures.append_array(_validate_usa_has_no_german_transitions())

	print("=== german_stance_frame_check ===")
	if failures.is_empty():
		print("PASS: German stance families OK (GBRLA/GPRIS/GPRNA/GSUPA)")
		get_tree().quit(0)
	else:
		print("FAIL count=%d" % failures.size())
		for line in failures:
			print("FAIL ", line)
		get_tree().quit(1)


func _validate_anim(
	semantic: String,
	expected_source: String,
	expect_loop: bool,
	expected_frames: int,
) -> Array[String]:
	var fails: Array[String] = []
	var anim := AnimationDatabase.get_animation(FAMILY, semantic)
	if anim.is_empty():
		fails.append("%s missing from german_rifle" % semantic)
		return fails
	var meta: Dictionary = anim.get("metadata", {}) if anim.get("metadata", {}) is Dictionary else {}
	if str(meta.get("source_family", "")) != expected_source:
		fails.append(
			"%s source_family=%s expected %s"
			% [semantic, meta.get("source_family", ""), expected_source]
		)
	if bool(anim.get("loop", false)) != expect_loop:
		fails.append("%s loop=%s expected %s" % [semantic, anim.get("loop", false), expect_loop])
	var fps := float(anim.get("fps", 0.0))
	if not is_equal_approx(fps, EXPECTED_FPS):
		fails.append("%s fps=%.1f expected %.1f" % [semantic, fps, EXPECTED_FPS])

	for direction in DIRS:
		var frames := AnimationDatabase.get_direction_frames(FAMILY, semantic, direction)
		if frames.size() != expected_frames:
			fails.append(
				"%s %s: frames=%d expected %d"
				% [semantic, direction, frames.size(), expected_frames]
			)
			continue
		for i in frames.size():
			var path := str(frames[i])
			if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
				fails.append("%s missing file: %s" % [semantic, path])
			var expected_letter := String.chr(ord("A") + i)
			var expected_digit := _digit_for_direction(direction)
			var expected_name := "%s%d%s.png" % [expected_source, expected_digit, expected_letter]
			if path.get_file() != expected_name:
				fails.append(
					"%s %s[%d]: got %s expected %s"
					% [semantic, direction, i, path.get_file(), expected_name]
				)
	return fails


func _validate_runtime() -> Array[String]:
	var fails: Array[String] = []
	var sf := UsSoldierSpriteFrames.get_germany_sprite_frames()
	var checks := {
		"idle_standing": {"frames": 21, "loop": true},
		"idle_prone": {"frames": 1, "loop": true},
		"transition_prone_to_standing": {"frames": 5, "loop": false},
		"transition_standing_to_prone": {"frames": 24, "loop": false},
	}
	for semantic in checks.keys():
		var expect: Dictionary = checks[semantic]
		for direction in DIRS:
			var anim_name := "%s_%s" % [semantic, direction]
			if not sf.has_animation(anim_name):
				fails.append("runtime missing %s" % anim_name)
				continue
			var count := sf.get_frame_count(anim_name)
			var loop := sf.get_animation_loop(anim_name)
			var fps := sf.get_animation_speed(anim_name)
			print(
				"%s frames=%d fps=%.1f loop=%s"
				% [anim_name, count, fps, loop]
			)
			if count != int(expect.frames):
				fails.append("%s frames=%d expected %d" % [anim_name, count, expect.frames])
			if loop != bool(expect.loop):
				fails.append("%s loop=%s expected %s" % [anim_name, loop, expect.loop])
			if not is_equal_approx(fps, EXPECTED_FPS):
				fails.append("%s fps=%.1f expected %.1f" % [anim_name, fps, EXPECTED_FPS])
	return fails


func _validate_camera_maps() -> Array[String]:
	var fails: Array[String] = []
	if AnimationDatabase.display_direction("ne", 0) != "ne":
		fails.append("camera 0° should leave ne as ne")
	if AnimationDatabase.display_direction("w", 180) != "e":
		fails.append("camera 180° should map w → e")
	return fails


func _validate_usa_has_no_german_transitions() -> Array[String]:
	var fails: Array[String] = []
	if not AnimationDatabase.get_animation("us_rifle", "transition_standing_to_prone").is_empty():
		fails.append("USA should not have German standing→prone transition yet")
	if not AnimationDatabase.get_animation("us_rifle", "idle_prone").is_empty():
		fails.append("USA should not have German idle_prone yet")
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
