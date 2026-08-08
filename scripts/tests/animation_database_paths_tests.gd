extends Node
## Assert every frame path in animation_database.json resolves on disk.
## Also asserts zero coc_soldiers soldier-art references remain in the DB.
##
## Run:
##   Godot_v4.x_console.exe --headless --path <project> res://scripts/tests/animation_database_paths_tests.tscn

const DB_PATH := "res://assets/data/animation_database.json"

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	AnimationDatabase.reload()
	_test_no_coc_soldiers_in_db()
	_test_every_frame_path_exists()
	_test_no_empty_anims()
	_test_eight_dirs_equal_frame_counts()
	_test_walk_seven_frames()
	_test_sync_from_state_passes_idle_peek()
	print("")
	print("Animation database path tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail if not detail.is_empty() else "assertion failed"])


func _test_no_coc_soldiers_in_db() -> void:
	if not FileAccess.file_exists(DB_PATH):
		_assert("animation_database.json exists", false, "missing %s" % DB_PATH)
		return
	var text := FileAccess.get_file_as_string(DB_PATH)
	var count := text.count("coc_soldiers")
	_assert(
		"animation_database.json has zero coc_soldiers references",
		count == 0,
		"found %d" % count,
	)


func _test_every_frame_path_exists() -> void:
	var missing: Array[String] = []
	var checked := 0
	## Walk via raw JSON so we cover every family/animation even if helpers omit some.
	var file := FileAccess.open(DB_PATH, FileAccess.READ)
	if file == null:
		_assert("open animation_database.json", false, "read failed")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		_assert("parse animation_database.json", false, "invalid JSON")
		return
	var root: Dictionary = parsed
	var fams: Dictionary = root.get("families", {})
	for fam_id in fams.keys():
		var fam: Variant = fams[fam_id]
		if not fam is Dictionary:
			continue
		var anims: Variant = (fam as Dictionary).get("animations", {})
		if not anims is Dictionary:
			continue
		for anim_id in (anims as Dictionary).keys():
			var anim: Variant = (anims as Dictionary)[anim_id]
			if not anim is Dictionary:
				continue
			var dirs: Variant = (anim as Dictionary).get("directions", {})
			if not dirs is Dictionary:
				continue
			for dir_id in (dirs as Dictionary).keys():
				var entry: Variant = (dirs as Dictionary)[dir_id]
				if not entry is Dictionary:
					continue
				var frames: Variant = (entry as Dictionary).get("frames", [])
				if not frames is Array:
					continue
				for path_v in frames:
					var path := str(path_v)
					if path.is_empty():
						continue
					checked += 1
					if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
						missing.append("%s/%s/%s → %s" % [fam_id, anim_id, dir_id, path])
	_assert(
		"every animation_database frame path exists on disk",
		missing.is_empty(),
		"checked=%d missing=%d first=%s" % [
			checked,
			missing.size(),
			str(missing[0]) if not missing.is_empty() else "",
		],
	)
	if not missing.is_empty() and missing.size() <= 20:
		for line in missing:
			print("  MISSING ", line)
	elif missing.size() > 20:
		for i in 20:
			print("  MISSING ", missing[i])
		print("  ... and %d more" % (missing.size() - 20))
	else:
		print("[INFO] checked %d frame paths" % checked)


func _test_no_empty_anims() -> void:
	## Phase 3d: every animation must have frames (empty `fire` slot removed).
	var empty: Array[String] = []
	var file := FileAccess.open(DB_PATH, FileAccess.READ)
	if file == null:
		_assert("open DB for empty-anim check", false, "read failed")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		_assert("parse DB for empty-anim check", false, "invalid JSON")
		return
	var fams: Dictionary = (parsed as Dictionary).get("families", {})
	for fam_id in fams.keys():
		var fam: Variant = fams[fam_id]
		if not fam is Dictionary:
			continue
		var anims: Variant = (fam as Dictionary).get("animations", {})
		if not anims is Dictionary:
			continue
		for anim_id in (anims as Dictionary).keys():
			var anim: Variant = (anims as Dictionary)[anim_id]
			if not anim is Dictionary:
				continue
			var dirs: Variant = (anim as Dictionary).get("directions", {})
			if not dirs is Dictionary:
				continue
			var total := 0
			for dir_id in (dirs as Dictionary).keys():
				var entry: Variant = (dirs as Dictionary)[dir_id]
				if entry is Dictionary:
					var frames: Variant = (entry as Dictionary).get("frames", [])
					if frames is Array:
						total += (frames as Array).size()
			if total == 0:
				empty.append("%s/%s" % [fam_id, anim_id])
	_assert(
		"no family has zero-frame anims",
		empty.is_empty(),
		"empty=%s" % str(empty),
	)


func _test_walk_seven_frames() -> void:
	## Empirical loop boundary: A–G (7). Frame H is on disk but outside the walk loop.
	for fam_id in [
		"us_rifle", "us_smg", "us_bar", "german_rifle", "german_smg", "german_mg42"
	]:
		var ok := true
		var detail := ""
		for direction in ["n", "ne", "e", "se", "s", "sw", "w", "nw"]:
			var frames := AnimationDatabase.get_direction_frames(fam_id, "walk", direction)
			if frames.size() != 7:
				ok = false
				detail = "%s/%s size=%d" % [fam_id, direction, frames.size()]
				break
			var last := str(frames[frames.size() - 1]).get_file().get_basename()
			if not last.ends_with("G"):
				ok = false
				detail = "%s/%s last=%s expected …G" % [fam_id, direction, last]
				break
		_assert("%s walk has 7 frames (A–G) in all 8 directions" % fam_id, ok, detail)


func _test_sync_from_state_passes_idle_peek() -> void:
	## Phase 3c: every sync_from_state call site must pass idle_peek_side (5th arg).
	var path := "res://scripts/core/main.gd"
	if not FileAccess.file_exists(path):
		_assert("main.gd exists for sync_from_state check", false, "missing")
		return
	var text := FileAccess.get_file_as_string(path)
	var bad: Array[String] = []
	var search_from := 0
	while true:
		var idx := text.find("sync_from_state(", search_from)
		if idx < 0:
			break
		var close := text.find(")", idx)
		if close < 0:
			break
		var call := text.substr(idx, close - idx + 1)
		## Count commas outside nested parens roughly — require 4 commas (5 args).
		var commas := call.count(",")
		if commas < 4:
			bad.append(call.replace("\n", " ").strip_edges())
		search_from = close + 1
	_assert(
		"no sync_from_state call site omits idle_peek_side",
		bad.is_empty(),
		"bad=%s" % str(bad),
	)


func _test_eight_dirs_equal_frame_counts() -> void:
	## Phase 2: every animation has all 8 directions; equal frame counts within an anim.
	## Skip us_rifle/fire_standing — intentional 3-vs-4 clip (muzzle-last standing fire).
	var expected_dirs: Array[String] = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
	var bad: Array[String] = []
	var file := FileAccess.open(DB_PATH, FileAccess.READ)
	if file == null:
		_assert("open DB for dir-count check", false, "read failed")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		_assert("parse DB for dir-count check", false, "invalid JSON")
		return
	var fams: Dictionary = (parsed as Dictionary).get("families", {})
	for fam_id in fams.keys():
		var fam: Variant = fams[fam_id]
		if not fam is Dictionary:
			continue
		var anims: Variant = (fam as Dictionary).get("animations", {})
		if not anims is Dictionary:
			continue
		for anim_id in (anims as Dictionary).keys():
			var anim: Variant = (anims as Dictionary)[anim_id]
			if not anim is Dictionary:
				continue
			var dirs: Variant = (anim as Dictionary).get("directions", {})
			if not dirs is Dictionary:
				continue
			var dir_dict: Dictionary = dirs
			var counts: Array[int] = []
			for d in expected_dirs:
				if not dir_dict.has(d):
					bad.append("%s/%s missing dir %s" % [fam_id, anim_id, d])
					continue
				var entry: Variant = dir_dict[d]
				var n := 0
				if entry is Dictionary:
					var frames: Variant = (entry as Dictionary).get("frames", [])
					if frames is Array:
						n = (frames as Array).size()
				counts.append(n)
			if str(fam_id) == "us_rifle" and str(anim_id) == "fire_standing":
				continue
			if counts.size() == expected_dirs.size():
				var first := counts[0]
				for c in counts:
					if c != first:
						bad.append("%s/%s unequal counts %s" % [fam_id, anim_id, str(counts)])
						break
	_assert(
		"every animation has 8 dirs with equal frame counts",
		bad.is_empty(),
		"issues=%d first=%s" % [bad.size(), str(bad[0]) if not bad.is_empty() else ""],
	)
	if not bad.is_empty() and bad.size() <= 15:
		for line in bad:
			print("  BAD ", line)
