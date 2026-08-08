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
