extends Node
## Headless validation for held ABRLA/GBRLA standing pose + OG idle one-shots.
## Run: Godot --headless --path <project> res://scripts/tests/idle_standing_frame_check.tscn


const DIRS: Array[String] = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const CAM_ROTATIONS: Array[int] = [0, 90, 180, 270]
const USA_FIDGETS := {
	"idle_breathing": {"source": "ABRLA", "letters": "ABCDEFGHIJKLMNOPQRST"},
	"idle_rest_1": {"source": "ASRWA", "letters": "ABCDEFGHIJKLMNOPQRST"},
	"idle_rest_2": {"source": "ASSSA", "letters": "ABCDEFGHIJKLMNOPQRST"},
	"idle_rest_3": {"source": "ASFBA", "letters": "ABCDEFGHIJKL"},
}
const GER_FIDGETS := {
	"idle_breathing": {"source": "GBRLA", "letters": "ABCDEFGHIJKLMNOPQRST"},
	"idle_rest_1": {"source": "GSRWA", "letters": "ABCDEFGHIJKLMNOPQRST"},
	"idle_rest_2": {"source": "GSSSA", "letters": "ABCDEFGHIJKLMNOPQRST"},
	"idle_rest_3": {"source": "GSFBA", "letters": "ABCDEFGHIJKL"},
}


func _ready() -> void:
	UsSoldierSpriteFrames.reload_cached_frames()
	var failures: Array[String] = []

	failures.append_array(_validate_held_pose("usa", "ABRLA", "USA"))
	failures.append_array(_validate_held_pose("germany", "GBRLA", "Germany"))
	failures.append_array(_validate_idle_oneshots("usa", USA_FIDGETS, "USA"))
	failures.append_array(_validate_idle_oneshots("germany", GER_FIDGETS, "Germany"))
	failures.append_array(_validate_idle_crouch_loop("usa", "USA"))
	failures.append_array(_validate_idle_crouch_loop("germany", "Germany"))
	failures.append_array(
		_validate_corner_idle_db("usa", "corner_idle_left", "ALCIS", "USA corner L")
	)
	failures.append_array(
		_validate_corner_idle_db("usa", "corner_idle_right", "ARCIS", "USA corner R")
	)
	failures.append_array(
		_validate_corner_idle_db("germany", "corner_idle_left", "GLCIS", "Germany corner L")
	)
	failures.append_array(
		_validate_corner_idle_db("germany", "corner_idle_right", "GRCIS", "Germany corner R")
	)
	failures.append_array(_validate_runtime(UsSoldierSpriteFrames.get_usa_sprite_frames(), USA_FIDGETS, "USA"))
	failures.append_array(
		_validate_runtime(UsSoldierSpriteFrames.get_germany_sprite_frames(), GER_FIDGETS, "Germany")
	)
	failures.append_array(_validate_corner_runtime(UsSoldierSpriteFrames.get_usa_sprite_frames(), "USA"))
	failures.append_array(_validate_corner_runtime(UsSoldierSpriteFrames.get_germany_sprite_frames(), "Germany"))
	failures.append_array(_validate_camera_maps())
	failures.append_array(_validate_walk_untouched())
	failures.append_array(_validate_idle_policy())

	print("=== idle_standing_frame_check ===")
	if failures.is_empty():
		print("PASS: held standing pose + OG idle one-shots OK")
		get_tree().quit(0)
	else:
		print("FAIL count=%d" % failures.size())
		for line in failures:
			print("FAIL ", line)
		get_tree().quit(1)


func _validate_held_pose(family_id: String, expected_source: String, label: String) -> Array[String]:
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
	if bool(anim.get("loop", true)):
		fails.append("%s: idle_standing must NOT loop (held pose)" % label)
	for direction in DIRS:
		var frames := AnimationDatabase.get_direction_frames(family_id, "idle_standing", direction)
		if frames.size() != 1:
			fails.append("%s %s: frame count %d expected 1 (pose A)" % [label, direction, frames.size()])
			continue
		var digit := AnimationDatabase.source_direction_digit(direction)
		var expected_name := "%s%dA.png" % [expected_source, digit]
		if str(frames[0]).get_file() != expected_name:
			fails.append(
				"%s %s: got %s expected %s" % [label, direction, str(frames[0]).get_file(), expected_name]
			)
		if not ResourceLoader.exists(str(frames[0])) and not FileAccess.file_exists(str(frames[0])):
			fails.append("%s missing: %s" % [label, frames[0]])
	return fails


func _validate_idle_oneshots(
	family_id: String,
	fidgets: Dictionary,
	label: String,
) -> Array[String]:
	var fails: Array[String] = []
	for fidget_id in fidgets.keys():
		var spec: Dictionary = fidgets[fidget_id]
		var expected_source := str(spec.get("source", ""))
		var expected_letters := str(spec.get("letters", ""))
		var anim := AnimationDatabase.get_animation(family_id, fidget_id)
		if anim.is_empty():
			fails.append("%s: %s missing" % [label, fidget_id])
			continue
		if bool(anim.get("loop", true)):
			fails.append("%s: %s must not loop" % [label, fidget_id])
		var meta: Dictionary = anim.get("metadata", {}) if anim.get("metadata", {}) is Dictionary else {}
		if str(meta.get("source_family", "")) != expected_source:
			fails.append(
				"%s %s source_family=%s expected %s"
				% [label, fidget_id, meta.get("source_family", ""), expected_source]
			)
		for direction in DIRS:
			var frames := AnimationDatabase.get_direction_frames(family_id, fidget_id, direction)
			if frames.size() != expected_letters.length():
				fails.append(
					"%s %s %s: frame count %d expected %d"
					% [label, fidget_id, direction, frames.size(), expected_letters.length()]
				)
				continue
			var digit := AnimationDatabase.source_direction_digit(direction)
			for i in frames.size():
				var path := str(frames[i])
				var letter := expected_letters[i]
				var expected_name := "%s%d%s.png" % [expected_source, digit, letter]
				if path.get_file() != expected_name:
					fails.append(
						"%s %s %s[%d]: got %s expected %s"
						% [label, fidget_id, direction, i, path.get_file(), expected_name]
					)
				if letter == "U":
					fails.append("%s %s uses excluded letter U" % [label, fidget_id])
	return fails


func _validate_idle_crouch_loop(family_id: String, label: String) -> Array[String]:
	var fails: Array[String] = []
	var anim := AnimationDatabase.get_animation(family_id, "idle_crouch")
	if anim.is_empty():
		fails.append("%s: idle_crouch missing" % label)
		return fails
	if not bool(anim.get("loop", false)):
		fails.append("%s: idle_crouch should loop (held kneel aim)" % label)
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
	return fails


func _validate_runtime(sf: SpriteFrames, fidgets: Dictionary, label: String) -> Array[String]:
	var fails: Array[String] = []
	if sf == null:
		fails.append("%s: SpriteFrames null" % label)
		return fails
	for direction in DIRS:
		var anim_name := "idle_standing_%s" % direction
		if not sf.has_animation(anim_name):
			fails.append("%s missing runtime %s" % [label, anim_name])
			continue
		if sf.get_animation_loop(anim_name):
			fails.append("%s %s must not loop at runtime" % [label, anim_name])
		if sf.get_frame_count(anim_name) != 1:
			fails.append(
				"%s %s runtime frames %d expected 1"
				% [label, anim_name, sf.get_frame_count(anim_name)]
			)
		for fidget_id in fidgets.keys():
			var fidget_name := "%s_%s" % [fidget_id, direction]
			if not sf.has_animation(fidget_name):
				fails.append("%s missing runtime %s" % [label, fidget_name])
				continue
			if sf.get_animation_loop(fidget_name):
				fails.append("%s %s must not loop" % [label, fidget_name])
			var expected_len: int = str(fidgets[fidget_id].letters).length()
			if sf.get_frame_count(fidget_name) != expected_len:
				fails.append(
					"%s %s frames %d expected %d"
					% [label, fidget_name, sf.get_frame_count(fidget_name), expected_len]
				)
	return fails


func _validate_corner_runtime(sf: SpriteFrames, label: String) -> Array[String]:
	var fails: Array[String] = []
	if sf == null:
		return fails
	for direction in DIRS:
		for semantic in ["corner_idle_left", "corner_idle_right"]:
			var anim_name := "%s_%s" % [semantic, direction]
			if not sf.has_animation(anim_name):
				fails.append("%s missing runtime %s" % [label, anim_name])
	return fails


func _validate_camera_maps() -> Array[String]:
	var fails: Array[String] = []
	for cam in CAM_ROTATIONS:
		var mapped := AnimationDatabase.display_direction("n", cam)
		if mapped.is_empty():
			fails.append("camera map empty for rotation %d" % cam)
	return fails


func _validate_walk_untouched() -> Array[String]:
	var fails: Array[String] = []
	for family_id in ["usa", "germany"]:
		var walk := AnimationDatabase.get_animation(family_id, "walk")
		if walk.is_empty():
			fails.append("%s walk missing after idle patch" % family_id)
	return fails


func _validate_idle_policy() -> Array[String]:
	var fails: Array[String] = []
	var policy := GameplayPolicies.idle_anim
	if policy.source_family_for(Team.USA) != "ABRLA":
		fails.append("idle policy USA source drift")
	if policy.source_family_for(Team.GERMANY) != "GBRLA":
		fails.append("idle policy Germany source drift")
	if policy.semantic_for() != "idle_standing":
		fails.append("idle policy open semantic drift")
	if policy.FIDGET_SEMANTICS.size() != 4:
		fails.append("idle policy fidget count drift")
	for semantic in ["idle_breathing", "idle_rest_1", "idle_rest_2", "idle_rest_3"]:
		if not policy.is_fidget_semantic(semantic):
			fails.append("idle policy missing fidget semantic %s" % semantic)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var delay := policy.random_fidget_delay_sec(rng)
	if delay < policy.fidget_delay_min_sec or delay > policy.fidget_delay_max_sec:
		fails.append("idle policy delay out of range: %s" % delay)
	if policy.fidget_play_chance != IdleAnimPolicy.DEFAULT_FIDGET_PLAY_CHANCE:
		fails.append("idle policy play chance drift")
	if policy.fidget_fps != IdleAnimPolicy.DEFAULT_FIDGET_FPS:
		fails.append("idle policy fidget fps drift")
	for semantic in IdleAnimPolicy.FIDGET_SEMANTICS:
		var expected := float(IdleAnimPolicy.DEFAULT_FIDGET_WEIGHTS.get(semantic, 0.0))
		if float(policy.fidget_weights.get(semantic, -1.0)) != expected:
			fails.append("idle policy weight drift for %s" % semantic)
	rng.seed = 42
	var picks: Dictionary = {}
	for i in 100:
		var picked := policy.pick_fidget_semantic(rng)
		picks[picked] = int(picks.get(picked, 0)) + 1
	if int(picks.get("idle_rest_3", 0)) < 30:
		fails.append("idle policy weighted pick skew: %s" % str(picks))
	return fails
