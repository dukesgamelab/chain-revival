extends Node
## Headless tests: coordinate remap camera vs facet/sprite camera separation.
## Run: Godot --headless --path <project> res://scripts/tests/facet_camera_rotation_tests.tscn

const MapDataClass := preload("res://scripts/map/map_data.gd")
const MapLoaderClass := preload("res://scripts/map/map_loader.gd")

## Interior 4-facet family (no outward +180°) — clean e/n/w/s expectations.
const TEST_FAMILY := "IWWL"
const SHORT_WALL_FAMILIES := ["WH00", "WH01", "WH02", "WH11"]
const SAMPLE_WALL_FAMILIES := [
	"IWCL", "IWCR", "IWWL", "LIHW", "IWDRS7A",
	"WCOR", "WICR", "WWAI", "WWAL", "WWAQ", "WWAR", "WWIN",
	"SCOR", "SICR", "SWAI", "SWAL", "SWAQ", "SWAR",
	"WH00", "WH01", "WH02", "WH11",
]

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	MapCoordinateTransform.reset_candidate()
	IsometricGrid.reset_view_rotation()
	IsometricGrid.set_original_projection_enabled(true)
	IsometricGrid.set_view_pivot_for_map(100, 100)
	CocTileCatalog.ensure_loaded()

	_test_coordinate_remap_steps()
	_test_facet_camera_sequence()
	_test_right_rotations_enws()
	_test_left_rotations_eswn()
	_test_cam0_and_cam180_unchanged_vs_explicit()
	_test_cam90_270_quarter_turn_handedness()
	_test_wwal_exterior_quarter_turns_s_then_n()
	_test_editor_preview_matches_runtime()
	_test_world_direction_unchanged_by_camera()
	_test_maps_not_modified()
	_test_short_walls_four_cameras()
	_test_sample_families_resolve()
	_test_camera_rotation_does_not_alter_gameplay()
	_test_wh02_authored_sprite_square()

	print("")
	print("Facet camera rotation tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s — %s" % [name, detail if not detail.is_empty() else "assertion failed"])


func _test_coordinate_remap_steps() -> void:
	## Coord remap must stay [0, 3, 2, 1].
	var steps: Array[int] = []
	for i in 4:
		steps.append(MapCoordinateTransform.camera_step_for_rotation(i))
	_assert(
		"coordinate remapping still uses [0,3,2,1]",
		steps == [0, 3, 2, 1],
		"got %s" % str(steps),
	)
	IsometricGrid.reset_view_rotation()
	IsometricGrid.rotate_view_right()
	_assert(
		"coord camera after rotate_right is 270°",
		IsometricGrid.camera_direction_degrees() == 270,
		"got %d" % IsometricGrid.camera_direction_degrees(),
	)
	IsometricGrid.reset_view_rotation()


func _test_facet_camera_sequence() -> void:
	var degrees: Array[int] = []
	IsometricGrid.reset_view_rotation()
	for i in 4:
		IsometricGrid.current_view_rotation = i
		degrees.append(IsometricGrid.facet_camera_direction_degrees())
	IsometricGrid.reset_view_rotation()
	_assert(
		"facet camera degrees use [0,1,2,3] → 0/90/180/270",
		degrees == [0, 90, 180, 270],
		"got %s" % str(degrees),
	)
	IsometricGrid.rotate_view_right()
	_assert(
		"CocFacetSelector.camera_degrees uses facet camera (90 after right)",
		CocFacetSelector.camera_degrees() == 90,
		"got %d" % CocFacetSelector.camera_degrees(),
	)
	_assert(
		"facet camera ≠ coord remap camera after rotate_right",
		CocFacetSelector.camera_degrees() != IsometricGrid.camera_direction_degrees(),
		"facet=%d coord=%d"
		% [CocFacetSelector.camera_degrees(), IsometricGrid.camera_direction_degrees()],
	)
	IsometricGrid.reset_view_rotation()


func _letters_for_right_rotations(family: String, world_dir: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	IsometricGrid.reset_view_rotation()
	for _i in 4:
		out.append(CocFacetSelector.select_letter(family, world_dir))
		IsometricGrid.rotate_view_right()
	IsometricGrid.reset_view_rotation()
	return out


func _letters_for_left_rotations(family: String, world_dir: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	IsometricGrid.reset_view_rotation()
	for _i in 4:
		out.append(CocFacetSelector.select_letter(family, world_dir))
		IsometricGrid.rotate_view_left()
	IsometricGrid.reset_view_rotation()
	return out


func _test_right_rotations_enws() -> void:
	var letters := _letters_for_right_rotations(TEST_FAMILY, 0)
	_assert(
		"four right rotations resolve e,n,w,s for dir-0 four-facet family",
		letters == PackedStringArray(["e", "n", "w", "s"]),
		"got %s" % ", ".join(letters),
	)


func _test_left_rotations_eswn() -> void:
	var letters := _letters_for_left_rotations(TEST_FAMILY, 0)
	_assert(
		"four left rotations resolve e,s,w,n for dir-0 four-facet family",
		letters == PackedStringArray(["e", "s", "w", "n"]),
		"got %s" % ", ".join(letters),
	)


func _test_cam0_and_cam180_unchanged_vs_explicit() -> void:
	## Camera 0 and 180 facet picks match explicit angles.
	IsometricGrid.reset_view_rotation()
	var live0 := CocFacetSelector.select_letter(TEST_FAMILY, 0)
	var expl0 := CocFacetSelector.select_letter_at_camera(TEST_FAMILY, 0, 0)
	_assert("camera 0 remains e for IWWL dir0", live0 == "e" and expl0 == "e", "live=%s expl=%s" % [live0, expl0])

	IsometricGrid.current_view_rotation = 2
	var live180 := CocFacetSelector.select_letter(TEST_FAMILY, 0)
	var expl180 := CocFacetSelector.select_letter_at_camera(TEST_FAMILY, 0, 180)
	IsometricGrid.reset_view_rotation()
	_assert(
		"camera 180 remains w for IWWL dir0",
		live180 == "w" and expl180 == "w",
		"live=%s expl=%s" % [live180, expl180],
	)


func _test_cam90_270_quarter_turn_handedness() -> void:
	## Interior (no outward): cam90 → n, cam270 → s.
	IsometricGrid.current_view_rotation = 1
	var at90 := CocFacetSelector.select_letter(TEST_FAMILY, 0)
	IsometricGrid.current_view_rotation = 3
	var at270 := CocFacetSelector.select_letter(TEST_FAMILY, 0)
	IsometricGrid.reset_view_rotation()
	_assert("camera 90 resolves n (interior)", at90 == "n", "got %s" % at90)
	_assert("camera 270 resolves s (interior)", at270 == "s", "got %s" % at270)


func _test_wwal_exterior_quarter_turns_s_then_n() -> void:
	## Relative facet: four Directions stay distinct; paths come from registry by index.
	IsometricGrid.set_original_projection_enabled(true)
	MapAssetRegistry.ensure_loaded()
	for cam in [0, 90, 180, 270]:
		var rels: Dictionary = {}
		for world_dir in [0, 90, 180, 270]:
			var info := CocSpriteResolver.resolve_placement("WWAL", world_dir, "", cam)
			var rel := int(info.get("relative_facet", -1))
			rels[world_dir] = rel
			_assert(
				"WWAL dir=%d cam=%d Direction preserved" % [world_dir, cam],
				int(info.get("world_direction", -1)) == world_dir,
			)
			var variant := MapAssetRegistry.camera_variant("WWAL", rel)
			var want := CocSpriteResolver._registry_path_to_res(str(variant.get("path", "")))
			_assert(
				"WWAL dir=%d cam=%d path matches relative_facet %d" % [world_dir, cam, rel],
				str(info.get("path", "")) == want,
				"got %s" % info.get("path"),
			)
		var unique := {}
		for r in rels.values():
			unique[r] = true
		_assert("WWAL four dirs at cam %d → four relative facets" % cam, unique.size() == 4, str(rels))
	## Facet selector math still available for fallback families.
	_assert(
		"WWAL selector cam90 is s (fallback math unchanged)",
		CocFacetSelector.select_letter_at_camera("WWAL", 0, 90) == "s",
	)
	_assert(
		"WWAL selector cam270 is n (fallback math unchanged)",
		CocFacetSelector.select_letter_at_camera("WWAL", 0, 270) == "n",
	)

func _test_editor_preview_matches_runtime() -> void:
	IsometricGrid.reset_view_rotation()
	for rot in 4:
		IsometricGrid.current_view_rotation = rot
		var preview := CocSpriteResolver.resolve_preview(TEST_FAMILY, 0)
		var runtime := CocSpriteResolver.resolve_placement(TEST_FAMILY, 0)
		var same := (
			str(preview.get("letter", "")) == str(runtime.get("letter", ""))
			and str(preview.get("path", "")) == str(runtime.get("path", ""))
			and int(preview.get("camera_direction", -1)) == int(runtime.get("camera_direction", -2))
		)
		_assert(
			"editor preview == runtime at facet cam %d°" % IsometricGrid.facet_camera_direction_degrees(),
			same,
			"preview=%s runtime=%s" % [preview.get("letter"), runtime.get("letter")],
		)
	IsometricGrid.reset_view_rotation()


func _test_world_direction_unchanged_by_camera() -> void:
	var world_dir := 90
	IsometricGrid.reset_view_rotation()
	for rot in 4:
		IsometricGrid.current_view_rotation = rot
		var info := CocSpriteResolver.resolve_placement(TEST_FAMILY, world_dir)
		_assert(
			"world direction remains %d at rot %d" % [world_dir, rot],
			int(info.get("world_direction", -1)) == world_dir,
			"got %s" % str(info.get("world_direction")),
		)
	IsometricGrid.reset_view_rotation()


func _test_maps_not_modified() -> void:
	## This fix is presentation-only — do not rewrite map JSON.
	var path := MapDataClass.path_for_map("ff_farm")
	if path.is_empty() or not FileAccess.file_exists(path):
		_assert("saved maps not modified (ff_farm present)", false, "missing %s" % path)
		return
	var before := FileAccess.get_md5(path)
	## Rotate cameras and resolve — must not touch disk.
	IsometricGrid.reset_view_rotation()
	for _i in 4:
		CocSpriteResolver.resolve_placement("WWAL", 0)
		IsometricGrid.rotate_view_right()
	IsometricGrid.reset_view_rotation()
	var after := FileAccess.get_md5(path)
	_assert("saved maps are not modified", before == after and not before.is_empty(), "md5 changed")


func _test_short_walls_four_cameras() -> void:
	for fam in SHORT_WALL_FAMILIES:
		var facets := CocTileCatalog.facet_count(fam)
		if facets < 4:
			continue
		var letters := _letters_for_right_rotations(fam, 0)
		## Short field walls are typically exterior-ish; require four distinct cardinals.
		var unique := {}
		for L in letters:
			unique[L] = true
		_assert(
			"short wall %s has changing facets across 4 cams" % fam,
			unique.size() >= 2,
			"letters=%s" % ", ".join(letters),
		)
		## Explicit: rot0 letter equals select_letter_at_camera(..., 0)
		IsometricGrid.reset_view_rotation()
		var live := CocFacetSelector.select_letter(fam, 0)
		var expl := CocFacetSelector.select_letter_at_camera(fam, 0, 0)
		_assert("short wall %s cam0 stable" % fam, live == expl, "%s vs %s" % [live, expl])


func _test_sample_families_resolve() -> void:
	## Smoke: important wall families resolve a non-empty path at all four facet cams.
	for fam in SAMPLE_WALL_FAMILIES:
		for cam in [0, 90, 180, 270]:
			var info := CocSpriteResolver.resolve_placement(fam, 0, "", cam)
			var path := str(info.get("path", ""))
			var letter := str(info.get("letter", ""))
			_assert(
				"%s @ facet cam %d resolves letter+path" % [fam, cam],
				not letter.is_empty() and (not path.is_empty() or bool(info.get("missing", false))),
				"letter=%s path=%s" % [letter, path.get_file()],
			)


func _test_camera_rotation_does_not_alter_gameplay() -> void:
	var map_data := MapLoaderClass.load_path(MapDataClass.path_for_map("ff_farm"))
	if map_data == null:
		_assert("gameplay collision invariant (map load)", false, "ff_farm failed to load")
		return
	var cell := Vector2i(10, 10)
	for c in map_data.get_object_cells():
		if map_data.is_blocked(c):
			cell = c
			break
	var before_blocked := map_data.is_blocked(cell)
	var before_height := map_data.obstruction_height(cell)
	var before_dir := int(map_data.get_visual_at(cell).get("direction", -999))
	IsometricGrid.reset_view_rotation()
	IsometricGrid.rotate_view_right()
	IsometricGrid.rotate_view_right()
	var after_blocked := map_data.is_blocked(cell)
	var after_height := map_data.obstruction_height(cell)
	var after_dir := int(map_data.get_visual_at(cell).get("direction", -999))
	IsometricGrid.reset_view_rotation()
	_assert("camera rotation does not alter blocked/collision", before_blocked == after_blocked)
	_assert("camera rotation does not alter obstruction height", before_height == after_height)
	_assert("camera rotation does not alter world Direction", before_dir == after_dir)


func _test_wh02_authored_sprite_square() -> void:
	## WH02 facet 90/270: s/n (WWAL/WCOR letter order). 0/180 untouched.
	## Each authored sprite appears exactly 4× across 16 pairs.
	MapAssetRegistry.reload()
	var want_by_facet := {
		0: "WH02_E",
		90: "WH02_S",
		180: "WH01S7A_E",
		270: "WH02_N",
	}
	var counts: Dictionary = {}
	for world_dir in [0, 90, 180, 270]:
		for cam in [0, 90, 180, 270]:
			var info := CocSpriteResolver.resolve_placement("WH02", world_dir, "", cam)
			var stem := str(info.get("path", "")).get_file().get_basename().to_upper()
			var rel := int(info.get("relative_facet", -1))
			_assert(
				"WH02 dir=%d cam=%d facet %d → %s" % [world_dir, cam, rel, want_by_facet.get(rel, "?")],
				stem == str(want_by_facet.get(rel, "")),
				"got %s" % stem,
			)
			counts[stem] = int(counts.get(stem, 0)) + 1
	for stem in ["WH02_E", "WH02_S", "WH01S7A_E", "WH02_N"]:
		_assert(
			"WH02 authored %s appears exactly 4 times" % stem,
			int(counts.get(stem, 0)) == 4,
			"got %d counts=%s" % [int(counts.get(stem, 0)), str(counts)],
		)
