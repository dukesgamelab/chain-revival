extends Node
## Headless validation for ASTGA / GSPRA throw_grenade registration.
## Run: Godot --headless --path <project> res://scripts/tests/throw_grenade_frame_check.tscn


const DIRS: Array[String] = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const CAM_ROTATIONS: Array[int] = [0, 90, 180, 270]
const EXPECTED_FRAMES := 24
const EXPECTED_FPS := 8.0


func _ready() -> void:
	UsSoldierSpriteFrames.reload_cached_frames()
	var failures: Array[String] = []

	failures.append_array(_validate_family("usa", "ASTGA", "USA"))
	failures.append_array(_validate_family("germany", "GSPRA", "Germany"))
	failures.append_array(_validate_sprite_frames(UsSoldierSpriteFrames.get_usa_sprite_frames(), "USA"))
	failures.append_array(_validate_sprite_frames(UsSoldierSpriteFrames.get_germany_sprite_frames(), "Germany"))
	failures.append_array(_validate_camera_maps())
	failures.append_array(_validate_release_policy())

	print("=== throw_grenade_frame_check ===")
	if failures.is_empty():
		print("PASS: ASTGA/GSPRA throw_grenade OK (192+192 frames, 8 FPS, no loop, camera maps)")
		get_tree().quit(0)
	else:
		print("FAIL count=%d" % failures.size())
		for line in failures:
			print("FAIL ", line)
		get_tree().quit(1)


func _validate_family(family_id: String, expected_source: String, label: String) -> Array[String]:
	var fails: Array[String] = []
	var anim := AnimationDatabase.get_animation(family_id, "throw_grenade")
	if anim.is_empty():
		fails.append("%s: throw_grenade missing from AnimationDatabase" % label)
		return fails
	var meta: Dictionary = anim.get("metadata", {}) if anim.get("metadata", {}) is Dictionary else {}
	var source := str(meta.get("source_family", ""))
	if source != expected_source:
		fails.append("%s: source_family=%s expected %s" % [label, source, expected_source])
	if bool(anim.get("loop", true)):
		fails.append("%s: throw_grenade must not loop" % label)
	var fps := float(anim.get("fps", 0.0))
	if not is_equal_approx(fps, EXPECTED_FPS):
		fails.append("%s: fps=%.1f expected %.1f" % [label, fps, EXPECTED_FPS])
	var release_frame := int(meta.get("release_frame", -1))
	if release_frame != -1:
		fails.append("%s: release_frame should be -1 until visually verified (got %d)" % [label, release_frame])

	for direction in DIRS:
		var frames := AnimationDatabase.get_direction_frames(family_id, "throw_grenade", direction)
		if frames.size() != EXPECTED_FRAMES:
			fails.append(
				"%s %s: frame count %d expected %d" % [label, direction, frames.size(), EXPECTED_FRAMES]
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
			var basename := path.get_file()
			var expected_name := "%s%d%s.png" % [expected_source, expected_digit, expected_letter]
			if basename != expected_name:
				fails.append(
					"%s %s[%d]: got %s expected %s" % [label, direction, i, basename, expected_name]
				)
	return fails


func _validate_sprite_frames(sf: SpriteFrames, label: String) -> Array[String]:
	var fails: Array[String] = []
	for direction in DIRS:
		var anim_name := "throw_grenade_%s" % direction
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
	## Spot-check identity and 180° inversion.
	if AnimationDatabase.display_direction("n", 0) != "n":
		fails.append("camera 0° should leave n as n")
	if AnimationDatabase.display_direction("n", 180) != "s":
		fails.append("camera 180° should map n → s")
	return fails


func _validate_release_policy() -> Array[String]:
	var fails: Array[String] = []
	if GameplayPolicies.grenade.is_throw_release_enabled_for_team(Team.USA):
		fails.append("USA throw release should be disabled (-1) until verified")
	if GameplayPolicies.grenade.is_throw_release_enabled_for_team(Team.GERMANY):
		fails.append("Germany throw release should be disabled (-1) until verified")
	if not is_equal_approx(GameplayPolicies.grenade.throw_anim_fps, EXPECTED_FPS):
		fails.append(
			"GrenadePolicy.throw_anim_fps=%.1f expected %.1f"
			% [GameplayPolicies.grenade.throw_anim_fps, EXPECTED_FPS]
		)
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
