extends Node
## Regression assertions for coordinate/direction pipeline (dev-only).
## Run scene: res://scenes/debug/map_handedness_validation.tscn

func _ready() -> void:
	var report := run()
	print(report["summary"])
	for line in report["lines"]:
		print(line)
	if bool(report.get("ok", false)):
		print("MAP HANDEDNESS VALIDATION: PASS")
	else:
		push_error("MAP HANDEDNESS VALIDATION: FAIL")


static func run() -> Dictionary:
	var lines: PackedStringArray = PackedStringArray()
	var ok := true
	MapCoordinateTransform.reset_candidate()
	IsometricGrid.reset_view_rotation()
	IsometricGrid.set_original_projection_enabled(true)
	IsometricGrid.set_view_pivot_for_map(100, 100)

	## 1) Four camera rotations return to the same screen position.
	var cell := Vector2i(35, 92) ## Hundred Acre Woods
	var base := IsometricGrid.grid_to_world(cell)
	for _i in 4:
		IsometricGrid.rotate_view_right()
	var after4 := IsometricGrid.grid_to_world(cell)
	if after4.distance_to(base) > 0.01:
		ok = false
		lines.append("FAIL rotate×4 drift: base=%s after=%s" % [base, after4])
	else:
		lines.append("PASS rotate×4 returns to %s" % base)

	## 2) Left then right is identity.
	IsometricGrid.reset_view_rotation()
	var p0 := IsometricGrid.grid_to_world(cell)
	IsometricGrid.rotate_view_left()
	IsometricGrid.rotate_view_right()
	var p1 := IsometricGrid.grid_to_world(cell)
	if p1.distance_to(p0) > 0.01:
		ok = false
		lines.append("FAIL left+right drift: %s vs %s" % [p0, p1])
	else:
		lines.append("PASS rotate left then right is identity")

	## 3) World direction unchanged by camera (facet changes only).
	var family := "SWAL"
	var world_dir := 90
	var letters: PackedStringArray = PackedStringArray()
	IsometricGrid.reset_view_rotation()
	for cam_i in 4:
		IsometricGrid.current_view_rotation = cam_i
		var letter := CocFacetSelector.select_letter(family, world_dir)
		letters.append(letter)
	IsometricGrid.reset_view_rotation()
	lines.append("SWAL worldDir=90° letters@cams: %s" % ", ".join(letters))
	if letters[0] == letters[1] and letters[0] == letters[2]:
		ok = false
		lines.append("FAIL facets did not change across cameras")
	else:
		lines.append("PASS facets change with camera; worldDir argument unchanged")

	## 4) OG Fortress constraints at cam 0 (Woods left, Hay right of Fort).
	IsometricGrid.reset_view_rotation()
	var woods := IsometricGrid.grid_to_world(Vector2i(35, 92))
	var fort := IsometricGrid.grid_to_world(Vector2i(32, 77))
	var hay := IsometricGrid.grid_to_world(Vector2i(15, 76))
	var west := IsometricGrid.grid_to_world(Vector2i(34, 58))
	if woods.x >= fort.x:
		ok = false
		lines.append("FAIL Woods not left of Fort (woods=%.1f fort=%.1f)" % [woods.x, fort.x])
	else:
		lines.append("PASS Woods left of Fort")
	if hay.x <= fort.x:
		ok = false
		lines.append("FAIL Hay not right of Fort (hay=%.1f fort=%.1f)" % [hay.x, fort.x])
	else:
		lines.append("PASS Hay right of Fort")
	if woods.x >= hay.x:
		ok = false
		lines.append("FAIL Woods not left of Hay")
	else:
		lines.append("PASS Woods left of Hay")
	if west.x <= fort.x:
		ok = false
		lines.append("FAIL Western Approach not right of Fort")
	else:
		lines.append("PASS Western Approach right of Fort")

	## 5) Legacy (no X-flip) must NOT satisfy Hay-right (guards against regressing).
	MapCoordinateTransform.active_candidate = MapCoordinateTransform.Candidate.LEGACY_NO_FLIP
	var hay_legacy := IsometricGrid.grid_to_world(Vector2i(15, 76))
	var fort_legacy := IsometricGrid.grid_to_world(Vector2i(32, 77))
	MapCoordinateTransform.reset_candidate()
	if hay_legacy.x > fort_legacy.x:
		ok = false
		lines.append("FAIL legacy unexpectedly has Hay right of Fort — candidate table broken?")
	else:
		lines.append("PASS legacy_no_flip still has Hay left of Fort (pre-fix mirror)")

	## 6) Reversed camera steps: index 1 → 270° (not 90°).
	IsometricGrid.reset_view_rotation()
	IsometricGrid.rotate_view_right()
	var step1 := IsometricGrid.camera_direction_degrees()
	IsometricGrid.reset_view_rotation()
	if step1 != 270:
		ok = false
		lines.append("FAIL reverse-cam: after rotate_right expected 270°, got %d°" % step1)
	else:
		lines.append("PASS reverse-cam: rotate_right → 270° (OG spin)")

	## 7) X-flip facet offset: world 0° draws as w at cam 0 (not e).
	IsometricGrid.reset_view_rotation()
	MapCoordinateTransform.reset_candidate()
	var letter0 := CocFacetSelector.select_letter("SWAL", 0)
	if letter0 != "w":
		ok = false
		lines.append("FAIL X-flip facet offset: SWAL dir0 @cam0 expected w, got %s" % letter0)
	else:
		lines.append("PASS X-flip facet offset: SWAL dir0 @cam0 → w")
	var letter90 := CocFacetSelector.select_letter("SWAL", 90)
	if letter90 != "n":
		ok = false
		lines.append("FAIL X-flip facet offset: SWAL dir90 @cam0 expected n, got %s" % letter90)
	else:
		lines.append("PASS X-flip facet offset: SWAL dir90 @cam0 → n")

	var summary := "map_handedness_validation ok=%s" % ok
	return {"ok": ok, "lines": lines, "summary": summary}
