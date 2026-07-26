extends Node
## Headless validation for ABRLA / GBRLA idle_standing + CIS corner idle.
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
	failures.append_array(
		_validate_corner_idle_db("us_rifle", "corner_idle_left", "ALCIS", "USA corner L")
	)
	failures.append_array(
		_validate_corner_idle_db("us_rifle", "corner_idle_right", "ARCIS", "USA corner R")
	)
	failures.append_array(
		_validate_corner_idle_db("german_rifle", "corner_idle_left", "GLCIS", "Germany corner L")
	)
	failures.append_array(
		_validate_corner_idle_db("german_rifle", "corner_idle_right", "GRCIS", "Germany corner R")
	)
	failures.append_array(_validate_no_dupes("us_rifle"))
	failures.append_array(_validate_no_dupes("german_rifle"))
	failures.append_array(_validate_runtime(UsSoldierSpriteFrames.get_usa_sprite_frames(), "USA"))
	failures.append_array(_validate_runtime(UsSoldierSpriteFrames.get_germany_sprite_frames(), "Germany"))
	failures.append_array(_validate_corner_runtime(UsSoldierSpriteFrames.get_usa_sprite_frames(), "USA"))
	failures.append_array(_validate_corner_runtime(UsSoldierSpriteFrames.get_germany_sprite_frames(), "Germany"))
	failures.append_array(_validate_camera_maps())
	failures.append_array(_validate_walk_untouched())
	failures.append_array(_validate_idle_policy())

	print("=== idle_standing_frame_check ===")
	if failures.is_empty():
		print("PASS: ABRLA/GBRLA + corner idle CIS OK")
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
	for direction in DIRS:
		var frames := AnimationDatabase.get_direction_frames(family_id, "idle_standing", direction)
		if frames.size() != EXPECTED_FRAMES:
			fails.append("%s %s: frame count %d expected %d" % [label, direction, frames.size(), EXPECTED_FRAMES])
			continue
		var digit := _digit_for_direction(direction)
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
	return fails


func _validate_corner_idle_db(
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
	if not is_equal_approx(float(anim.get("fps", 0.0)), 4.0):
		fails.append("%s: fps expected 4" % label)
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
	for direction in DIRS:
		var anim_name := "idle_standing_%s" % direction
		if not sf.has_animation(anim_name):
			fails.append("%s runtime missing %s" % [label, anim_name])
			continue
		var count := sf.get_frame_count(anim_name)
		var fps := sf.get_animation_speed(anim_name)
		var loop := sf.get_animation_loop(anim_name)
		if count != EXPECTED_FRAMES:
			fails.append("%s %s frames=%d expected %d" % [label, anim_name, count, EXPECTED_FRAMES])
		if not is_equal_approx(fps, EXPECTED_FPS):
			fails.append("%s %s fps=%.1f expected %.1f" % [label, anim_name, fps, EXPECTED_FPS])
		if not loop:
			fails.append("%s %s must loop" % [label, anim_name])
	return fails


func _validate_corner_runtime(sf: SpriteFrames, label: String) -> Array[String]:
	var fails: Array[String] = []
	for semantic in ["corner_idle_left", "corner_idle_right"]:
		for direction in DIRS:
			var anim_name := "%s_%s" % [semantic, direction]
			if not sf.has_animation(anim_name):
				fails.append("%s runtime missing %s" % [label, anim_name])
				continue
			if sf.get_frame_count(anim_name) != 1:
				fails.append(
					"%s %s frames=%d expected 1" % [label, anim_name, sf.get_frame_count(anim_name)]
				)
			if not sf.get_animation_loop(anim_name):
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


func _validate_idle_policy() -> Array[String]:
	var fails: Array[String] = []
	var policy := GameplayPolicies.idle_anim
	if policy.source_family_for(Team.USA) != "ABRLA":
		fails.append("policy USA open idle → ABRLA")
	if policy.source_family_for(Team.USA, CoverSystem.PeekSide.LEFT) != "ALCIS":
		fails.append("policy USA corner L → ALCIS")
	if policy.source_family_for(Team.USA, CoverSystem.PeekSide.RIGHT) != "ARCIS":
		fails.append("policy USA corner R → ARCIS")
	if policy.source_family_for(Team.GERMANY, CoverSystem.PeekSide.LEFT) != "GLCIS":
		fails.append("policy Germany corner L → GLCIS")
	if policy.source_family_for(Team.GERMANY, CoverSystem.PeekSide.RIGHT) != "GRCIS":
		fails.append("policy Germany corner R → GRCIS")
	if policy.semantic_for(CoverSystem.PeekSide.LEFT) != "corner_idle_left":
		fails.append("semantic corner L")
	if policy.semantic_for(CoverSystem.PeekSide.RIGHT) != "corner_idle_right":
		fails.append("semantic corner R")
	return fails


func _validate_walk_untouched() -> Array[String]:
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
			return 7
