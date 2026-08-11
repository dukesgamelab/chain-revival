extends Node
## Headless validation for USA/German stance transitions + crawl mappings.
## Run: Godot --headless --path <project> res://scripts/tests/german_stance_frame_check.tscn


const DIRS: Array[String] = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const PRONE_TO_STAND_ORDER: Array[String] = ["E", "A", "B", "C", "D"]
const STAND_TO_PRONE_ORDER: Array[String] = ["D", "C", "B", "A", "E"]
const CRAWL_ORDER: Array[String] = [
	"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K",
	"L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V",
]
const EXPECTED_FPS := 10.0


func _ready() -> void:
	UsSoldierSpriteFrames.reload_cached_frames()
	var failures: Array[String] = []

	failures.append_array(
		_validate_transition(
			"usa",
			"transition_prone_to_standing",
			"APRNA",
			PRONE_TO_STAND_ORDER,
		)
	)
	failures.append_array(
		_validate_transition(
			"germany",
			"transition_prone_to_standing",
			"GPRNA",
			PRONE_TO_STAND_ORDER,
		)
	)
	failures.append_array(
		_validate_transition(
			"usa",
			"transition_standing_to_prone",
			"APRNA",
			STAND_TO_PRONE_ORDER,
		)
	)
	failures.append_array(
		_validate_transition(
			"germany",
			"transition_standing_to_prone",
			"GPRNA",
			STAND_TO_PRONE_ORDER,
		)
	)
	failures.append_array(_validate_crawl("usa", "APMOA"))
	failures.append_array(_validate_crawl("germany", "GPMOA"))
	failures.append_array(_validate_no_forbidden_stance_refs())
	failures.append_array(_validate_runtime_sprite_frames())
	failures.append_array(_validate_camera_maps())
	failures.append_array(_validate_presentation_guards())

	## German idle packs (unchanged by this correction).
	failures.append_array(_validate_german_idles())

	print("=== german_stance_frame_check ===")
	if failures.is_empty():
		print(
			"PASS: stance APRNA/GPRNA EABCD+DCBAE @10fps; crawl APMOA/GPMOA A-V @10fps loop"
		)
		get_tree().quit(0)
	else:
		print("FAIL count=%d" % failures.size())
		for line in failures:
			print("FAIL ", line)
		get_tree().quit(1)


func _validate_transition(
	family_id: String,
	semantic: String,
	expected_source: String,
	letter_order: Array[String],
) -> Array[String]:
	var fails: Array[String] = []
	var anim := AnimationDatabase.get_animation(family_id, semantic)
	if anim.is_empty():
		fails.append("%s/%s missing" % [family_id, semantic])
		return fails
	var meta: Dictionary = (
		anim.get("metadata", {}) if anim.get("metadata", {}) is Dictionary else {}
	)
	if str(meta.get("source_family", "")) != expected_source:
		fails.append(
			"%s/%s source_family=%s expected %s"
			% [family_id, semantic, meta.get("source_family", ""), expected_source]
		)
	if bool(anim.get("loop", true)):
		fails.append("%s/%s loop=true expected false" % [family_id, semantic])
	var fps := float(anim.get("fps", 0.0))
	if not is_equal_approx(fps, EXPECTED_FPS):
		fails.append("%s/%s fps=%.1f expected %.1f" % [family_id, semantic, fps, EXPECTED_FPS])
	for direction in DIRS:
		var frames := AnimationDatabase.get_direction_frames(family_id, semantic, direction)
		if frames.size() != letter_order.size():
			fails.append(
				"%s/%s %s: frames=%d expected %d"
				% [family_id, semantic, direction, frames.size(), letter_order.size()]
			)
			continue
		var digit := _digit_for_direction(direction)
		for i in frames.size():
			var path := str(frames[i])
			if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
				fails.append("%s/%s missing file: %s" % [family_id, semantic, path])
			var expected_name := "%s%d%s.png" % [expected_source, digit, letter_order[i]]
			if path.get_file() != expected_name:
				fails.append(
					"%s/%s %s[%d]: got %s expected %s"
					% [family_id, semantic, direction, i, path.get_file(), expected_name]
				)
			## Forbidden packs must never appear in stance transitions.
			var fname := path.get_file()
			if (
				fname.begins_with("ASUPA")
				or fname.begins_with("GSUPA")
				or fname.begins_with("ASTGA")
				or fname.begins_with("GSPRA")
			):
				fails.append("%s/%s forbidden frame %s" % [family_id, semantic, fname])
	return fails


func _validate_crawl(family_id: String, expected_source: String) -> Array[String]:
	var fails: Array[String] = []
	var anim := AnimationDatabase.get_animation(family_id, "crawl")
	if anim.is_empty():
		fails.append("%s/crawl missing" % family_id)
		return fails
	var meta: Dictionary = (
		anim.get("metadata", {}) if anim.get("metadata", {}) is Dictionary else {}
	)
	if str(meta.get("source_family", "")) != expected_source:
		fails.append(
			"%s/crawl source_family=%s expected %s"
			% [family_id, meta.get("source_family", ""), expected_source]
		)
	if not bool(anim.get("loop", false)):
		fails.append("%s/crawl loop=false expected true" % family_id)
	var fps := float(anim.get("fps", 0.0))
	if not is_equal_approx(fps, EXPECTED_FPS):
		fails.append("%s/crawl fps=%.1f expected %.1f" % [family_id, fps, EXPECTED_FPS])
	for direction in DIRS:
		var frames := AnimationDatabase.get_direction_frames(family_id, "crawl", direction)
		if frames.size() != 22:
			fails.append(
				"%s/crawl %s: frames=%d expected 22" % [family_id, direction, frames.size()]
			)
			continue
		var digit := _digit_for_direction(direction)
		for i in frames.size():
			var path := str(frames[i])
			if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
				fails.append("%s/crawl missing file: %s" % [family_id, path])
			var expected_name := "%s%d%s.png" % [expected_source, digit, CRAWL_ORDER[i]]
			if path.get_file() != expected_name:
				fails.append(
					"%s/crawl %s[%d]: got %s expected %s"
					% [family_id, direction, i, path.get_file(), expected_name]
				)
	return fails


func _validate_no_forbidden_stance_refs() -> Array[String]:
	var fails: Array[String] = []
	for family_id in ["usa", "germany"]:
		for semantic in ["transition_standing_to_prone", "transition_prone_to_standing"]:
			for direction in DIRS:
				for path_v in AnimationDatabase.get_direction_frames(family_id, semantic, direction):
					var fname := str(path_v).get_file()
					if (
						fname.begins_with("ASUPA")
						or fname.begins_with("GSUPA")
						or fname.begins_with("ASTGA")
						or fname.begins_with("GSPRA")
					):
						fails.append("%s/%s still references %s" % [family_id, semantic, fname])
	return fails


func _validate_runtime_sprite_frames() -> Array[String]:
	var fails: Array[String] = []
	var packs := {
		"USA": UsSoldierSpriteFrames.get_usa_sprite_frames(),
		"Germany": UsSoldierSpriteFrames.get_germany_sprite_frames(),
	}
	var checks := {
		"transition_prone_to_standing": {"frames": 5, "loop": false},
		"transition_standing_to_prone": {"frames": 5, "loop": false},
		"crawl": {"frames": 22, "loop": true},
	}
	for label in packs.keys():
		var sf: SpriteFrames = packs[label]
		for semantic in checks.keys():
			var expect: Dictionary = checks[semantic]
			for direction in DIRS:
				var anim_name := "%s_%s" % [semantic, direction]
				if not sf.has_animation(anim_name):
					fails.append("%s runtime missing %s" % [label, anim_name])
					continue
				var count := sf.get_frame_count(anim_name)
				var loop := sf.get_animation_loop(anim_name)
				var fps := sf.get_animation_speed(anim_name)
				if count != int(expect.frames):
					fails.append(
						"%s %s frames=%d expected %d" % [label, anim_name, count, expect.frames]
					)
				if loop != bool(expect.loop):
					fails.append(
						"%s %s loop=%s expected %s" % [label, anim_name, loop, expect.loop]
					)
				if not is_equal_approx(fps, EXPECTED_FPS):
					fails.append(
						"%s %s fps=%.1f expected %.1f" % [label, anim_name, fps, EXPECTED_FPS]
					)
	return fails


func _validate_camera_maps() -> Array[String]:
	var fails: Array[String] = []
	if AnimationDatabase.display_direction("ne", 0) != "ne":
		fails.append("camera 0° should leave ne as ne")
	if AnimationDatabase.display_direction("w", 180) != "e":
		fails.append("camera 180° should map w → e")
	## Stance transitions resolve through the same display_direction remap.
	var usa_ne := AnimationDatabase.resolve_frames(
		"usa", "transition_prone_to_standing", "ne", 0.0
	)
	var usa_ne_rot := AnimationDatabase.resolve_frames(
		"usa", "transition_prone_to_standing", "ne", 180.0
	)
	if usa_ne.is_empty() or usa_ne_rot.is_empty():
		fails.append("resolve_frames returned empty for USA prone→stand")
	elif str(usa_ne[0]).get_file() != "APRNA6E.png":
		fails.append("USA ne@0° first frame=%s expected APRNA6E.png" % str(usa_ne[0]).get_file())
	elif str(usa_ne_rot[0]).get_file() != "APRNA2E.png":
		## ne @ 180° → sw (digit 2)
		fails.append(
			"USA ne@180° first frame=%s expected APRNA2E.png" % str(usa_ne_rot[0]).get_file()
		)
	return fails


func _validate_presentation_guards() -> Array[String]:
	## Guard logic lives on Soldier; assert the locomotion prefix + restart contract.
	var fails: Array[String] = []
	var soldier_script := load("res://scripts/soldiers/soldier.gd") as GDScript
	if soldier_script == null:
		fails.append("could not load soldier.gd")
		return fails
	var source := FileAccess.get_file_as_string("res://scripts/soldiers/soldier.gd")
	if not source.contains("_locomotion_move_prefix"):
		fails.append("soldier.gd missing crawl locomotion prefix helper")
	if not source.contains("Do not restart crawl/walk"):
		fails.append("soldier.gd missing crawl/walk restart preservation comment/guard")
	if not source.contains("if _stance_transition_active:"):
		fails.append("soldier.gd missing stance-transition restart guard")
	if not source.contains("stance_transition_finished.emit"):
		fails.append("soldier.gd missing transition completion signal")
	## ActionResolver: deferred stance + move pause while pending.
	var resolver := FileAccess.get_file_as_string("res://scripts/core/action_resolver.gd")
	if not resolver.contains("Soldier is changing stance"):
		fails.append("action_resolver.gd missing move-pause during pending stance")
	if not resolver.contains("commit_stance_transition"):
		fails.append("action_resolver.gd missing commit_stance_transition")
	return fails


func _validate_german_idles() -> Array[String]:
	var fails: Array[String] = []
	var standing := AnimationDatabase.get_animation("germany", "idle_standing")
	var prone := AnimationDatabase.get_animation("germany", "idle_prone")
	if str(standing.get("metadata", {}).get("source_family", "")) != "GBRLA":
		fails.append("german idle_standing source drift")
	if str(prone.get("metadata", {}).get("source_family", "")) != "GPIDS":
		fails.append("german idle_prone source drift")
	var usa_prone := AnimationDatabase.get_animation("usa", "idle_prone")
	if usa_prone.is_empty():
		fails.append("usa idle_prone (APIDS) missing")
	elif str(usa_prone.get("metadata", {}).get("source_family", "")) != "APIDS":
		fails.append("usa idle_prone source_family expected APIDS")
	else:
		for direction in DIRS:
			var frames := AnimationDatabase.get_direction_frames("usa", "idle_prone", direction)
			if frames.size() != 1:
				fails.append("usa idle_prone %s frames=%d" % [direction, frames.size()])
				continue
			var digit := _digit_for_direction(direction)
			if str(frames[0]).get_file() != "APIDS%dA.png" % digit:
				fails.append(
					"usa idle_prone %s got %s" % [direction, str(frames[0]).get_file()]
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
