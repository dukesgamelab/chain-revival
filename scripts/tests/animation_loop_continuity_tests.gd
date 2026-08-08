extends Node
## Guard: looping clips must wrap on a small pixel-delta step, not a hitch.
##
## Empirical rule (walk): A–G wraps ~0.77× median; A–H wraps ~1.20–1.24× and hitchs.
## Crawl is excluded — its 22-frame cycle deliberately has a large wrap (verified separately).
##
## Threshold note: the prompt's 1.3× does not fail measured A–H ratios (~1.20–1.24).
## This test uses 1.19× and includes a negative control (ASMOA A–H must fail).
##
## Run:
##   Godot_v4.x_console.exe --headless --path <project> res://scripts/tests/animation_loop_continuity_tests.tscn

const DIRECTION := "e"
const PIXEL_TOLERANCE := 8
## Catches A–H hitch; see header. Negative control asserts A–H exceeds this.
const MAX_WRAP_RATIO := 1.19
const MIN_FRAMES := 3

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	AnimationDatabase.reload()
	_test_negative_control_eight_frame_walk_fails()
	_test_looping_anims_wrap_continuity()
	print("")
	print("Animation loop continuity tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail if not detail.is_empty() else "assertion failed"])


func _test_negative_control_eight_frame_walk_fails() -> void:
	## If this passes, the threshold is too loose to catch the bug we care about.
	var paths: Array[String] = []
	for letter in ["A", "B", "C", "D", "E", "F", "G", "H"]:
		paths.append("res://assets/sprites/us_soldier/walk/ASMOA5%s.png" % letter)
	var ratio := _wrap_ratio(paths)
	_assert(
		"negative control: ASMOA A–H wrap ratio exceeds threshold",
		ratio > MAX_WRAP_RATIO,
		"ratio=%.3f threshold=%.2f (guard is too loose if this fails)" % [ratio, MAX_WRAP_RATIO],
	)
	var paths7: Array[String] = []
	for letter in ["A", "B", "C", "D", "E", "F", "G"]:
		paths7.append("res://assets/sprites/us_soldier/walk/ASMOA5%s.png" % letter)
	var ratio7 := _wrap_ratio(paths7)
	_assert(
		"sanity: ASMOA A–G wrap ratio within threshold",
		ratio7 <= MAX_WRAP_RATIO,
		"ratio=%.3f" % ratio7,
	)


func _test_looping_anims_wrap_continuity() -> void:
	var bad: Array[String] = []
	var checked := 0
	var fams := AnimationDatabase.family_ids()
	for fam_id_v in fams:
		var fam_id := str(fam_id_v)
		var fam := AnimationDatabase.get_family(fam_id)
		var anims: Dictionary = fam.get("animations", {})
		for anim_id_v in anims.keys():
			var anim_id := str(anim_id_v)
			if anim_id == "crawl":
				## Verified genuine 22-frame cycle; wrap is large by design.
				continue
			var anim: Dictionary = anims[anim_id_v]
			if not bool(anim.get("loop", false)):
				continue
			var frames := AnimationDatabase.get_direction_frames(fam_id, anim_id, DIRECTION)
			if frames.size() < MIN_FRAMES:
				continue
			checked += 1
			var ratio := _wrap_ratio(frames)
			if ratio > MAX_WRAP_RATIO:
				bad.append(
					"%s/%s wrap_ratio=%.3f (>%.2f) frames=%d"
					% [fam_id, anim_id, ratio, MAX_WRAP_RATIO, frames.size()]
				)
	_assert(
		"looping anims (excl. crawl) wrap within %.2f× median mid-cycle delta" % MAX_WRAP_RATIO,
		bad.is_empty(),
		"checked=%d bad=%s" % [checked, str(bad)],
	)
	print("[INFO] checked %d looping clips on direction %s" % [checked, DIRECTION])


func _wrap_ratio(frame_paths: Array) -> float:
	var images: Array[Image] = []
	for path_v in frame_paths:
		var path := str(path_v)
		var img := _load_image(path)
		if img == null:
			push_error("loop continuity: failed to load %s" % path)
			return 999.0
		images.append(img)
	var deltas: Array[float] = []
	for i in range(images.size() - 1):
		deltas.append(float(_pixel_delta(images[i], images[i + 1])))
	var wrap := float(_pixel_delta(images[images.size() - 1], images[0]))
	var med := _median(deltas)
	if med <= 0.0:
		return 0.0
	return wrap / med


func _load_image(path: String) -> Image:
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return null
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return null
	return tex.get_image()


func _pixel_delta(a: Image, b: Image) -> int:
	var wa := a.get_width()
	var ha := a.get_height()
	var wb := b.get_width()
	var hb := b.get_height()
	var w := maxi(wa, wb)
	var h := maxi(ha, hb)
	var count := 0
	for y in h:
		for x in w:
			var ca := _sample(a, x, y, wa, ha)
			var cb := _sample(b, x, y, wb, hb)
			if (
				absi(int(ca.r8) - int(cb.r8)) > PIXEL_TOLERANCE
				or absi(int(ca.g8) - int(cb.g8)) > PIXEL_TOLERANCE
				or absi(int(ca.b8) - int(cb.b8)) > PIXEL_TOLERANCE
				or absi(int(ca.a8) - int(cb.a8)) > PIXEL_TOLERANCE
			):
				count += 1
	return count


func _sample(img: Image, x: int, y: int, w: int, h: int) -> Color:
	if x < 0 or y < 0 or x >= w or y >= h:
		return Color(0, 0, 0, 0)
	return img.get_pixel(x, y)


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n % 2 == 1:
		return sorted[n / 2]
	return (sorted[n / 2 - 1] + sorted[n / 2]) * 0.5
