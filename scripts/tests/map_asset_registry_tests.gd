extends Node
## Registry / MapData family-propagation regression tests.
##
## Run:
##   Godot_v4.x_console.exe --headless --path <project> res://scripts/tests/map_asset_registry_tests.tscn

const MapDataClass := preload("res://scripts/map/map_data.gd")
const MapAssetRegistryClass := preload("res://scripts/map/map_asset_registry.gd")
const MapLoaderClass := preload("res://scripts/map/map_loader.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	MapAssetRegistryClass.reload()
	_test_farm_families_registered()
	_test_camera_variants_resolve()
	_test_registry_blocks_movement_propagates()
	_test_registry_climb_propagates()
	_test_camera_rotation_does_not_change_gameplay()
	_test_legacy_baked_flags_are_not_overrides()
	_test_explicit_overrides()
	_test_refresh_gameplay_from_asset_registry()
	_test_save_strips_legacy_source_gameplay()
	_test_legacy_map_loads()
	_print_audit()
	print("")
	print("Map asset registry tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _pass(name: String) -> void:
	_passed += 1
	print("[PASS] %s" % name)


func _fail(name: String, detail: String) -> void:
	_failed += 1
	print("[FAIL] %s — %s" % [name, detail])


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass(name)
	else:
		_fail(name, detail if not detail.is_empty() else "assertion failed")


func _test_farm_families_registered() -> void:
	var audit := MapAssetRegistryClass.audit_farm_fight()
	var missing: Array = audit.get("missing_families", [])
	_assert(
		"every Farm Fight family has registry entry",
		missing.is_empty(),
		"missing=%s" % str(missing),
	)
	_assert(
		"Farm Fight unique family count > 0",
		int(audit.get("farm_unique_families", 0)) > 0,
	)


func _test_camera_variants_resolve() -> void:
	var incomplete: Array = []
	for fam in MapAssetRegistryClass.family_ids():
		for cam in [0, 90, 180, 270]:
			var v := MapAssetRegistryClass.camera_variant(fam, cam)
			if v.is_empty() or str(v.get("facet", "")).is_empty():
				incomplete.append("%s@%d" % [fam, cam])
	_assert(
		"all four camera rotations resolve a visual",
		incomplete.is_empty(),
		"incomplete=%s" % str(incomplete),
	)


func _test_registry_blocks_movement_propagates() -> void:
	var map_data := MapLoaderClass.load_path(MapDataClass.path_for_map("ff_farm"))
	var cells := _cells_for_family(map_data, "WH00")
	_assert("WH00 placements exist", cells.size() > 0, "no WH00 cells")
	if cells.is_empty():
		return
	var original := MapAssetRegistryClass.gameplay_for("WH00")
	MapAssetRegistryClass.set_gameplay("WH00", {"blocks_movement": true, "terrain": "_HG_NoPass", "terrain_height": 2})
	## Reload map so placements re-resolve from registry (no baked overrides).
	map_data = MapLoaderClass.load_path(MapDataClass.path_for_map("ff_farm"))
	var all_blocked := true
	for cell in cells:
		if not map_data.is_blocked(cell):
			all_blocked = false
			break
	_assert("changing WH00 blocks every instance after reload", all_blocked)
	## Restore original gameplay for later tests.
	MapAssetRegistryClass.set_gameplay("WH00", original)


func _test_registry_climb_propagates() -> void:
	var original := MapAssetRegistryClass.gameplay_for("WH00")
	MapAssetRegistryClass.set_gameplay(
		"WH00",
		{
			"terrain": "_HG_Climb",
			"terrain_height": 1,
			"blocks_movement": true,
			"blocks_los": false,
		}
	)
	var map_data := MapLoaderClass.load_path(MapDataClass.path_for_map("ff_farm"))
	var cells := _cells_for_family(map_data, "WH00")
	var ok := true
	for cell in cells:
		if map_data.terrain_class(cell) != MapDataClass.TerrainClass.CLIMB:
			ok = false
			break
		if map_data.obstruction_height(cell) != 1:
			ok = false
			break
	_assert("WH00 climb+height1 updates every instance", ok and cells.size() > 0)
	MapAssetRegistryClass.set_gameplay("WH00", original)


func _test_camera_rotation_does_not_change_gameplay() -> void:
	var map_data := MapLoaderClass.load_path(MapDataClass.path_for_map("ff_farm"))
	var cells := _cells_for_family(map_data, "WWAL")
	if cells.is_empty():
		_fail("camera rotation gameplay invariant", "no WWAL cells")
		return
	var cell: Vector2i = cells[0]
	var before_blocked := map_data.is_blocked(cell)
	var before_height := map_data.obstruction_height(cell)
	var before_terrain := map_data.terrain_class(cell)
	var before_snapshot := _blocked_snapshot(map_data)
	var original_rot := IsometricGrid.current_view_rotation
	IsometricGrid.current_view_rotation = (original_rot + 1) % 4
	var after_blocked := map_data.is_blocked(cell)
	var after_height := map_data.obstruction_height(cell)
	var after_terrain := map_data.terrain_class(cell)
	var after_snapshot := _blocked_snapshot(map_data)
	_assert("camera rotation does not alter blocked", before_blocked == after_blocked)
	_assert("camera rotation does not alter terrain height", before_height == after_height)
	_assert("camera rotation does not alter terrain class", before_terrain == after_terrain)
	_assert(
		"camera rotation does not alter pathfinding solids",
		before_snapshot == after_snapshot,
	)
	IsometricGrid.current_view_rotation = original_rot


func _blocked_snapshot(map_data: MapDataClass) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for cell in map_data.get_object_cells():
		if map_data.is_blocked(cell):
			parts.append("%d,%d" % [cell.x, cell.y])
	parts.sort()
	return ",".join(parts)


func _test_legacy_baked_flags_are_not_overrides() -> void:
	## Top-level baked flags are not overrides. When source has no terrain, registry fills.
	var map_data := MapDataClass.new()
	map_data.width = 10
	map_data.height = 10
	map_data.apply_terrain_gameplay = true
	MapAssetRegistryClass.set_gameplay(
		"WH00",
		{
			"terrain": "_HG_Climb",
			"terrain_height": 1,
			"blocks_movement": true,
			"blocks_los": false,
			"provides_cover": true,
			"cover_type": 1,
		}
	)
	map_data._load_objects_from_json(
		[
			{
				"object_type": "coc_swal",
				"x": 3,
				"y": 3,
				"blocks_movement": false,
				"blocks_los": false,
				"provides_cover": false,
				"cover_type": 0,
				"source": {"image": "WH00", "direction": 0},
			}
		]
	)
	var cell := Vector2i(3, 3)
	_assert("registry fills when source has no terrain", map_data.terrain_class(cell) == MapDataClass.TerrainClass.CLIMB)
	_assert("registry fills when source has no height", map_data.obstruction_height(cell) == 1)
	_assert("legacy top-level flags do not clear climb block", map_data.is_blocked(cell))

	## Legacy source.terrain is ignored — Asset Registry owns shared gameplay.
	map_data._load_objects_from_json(
		[
			{
				"object_type": "coc_swal",
				"x": 4,
				"y": 4,
				"source": {"image": "WH00", "direction": 0, "terrain": "_HG_EVEN", "terrain_height": 0},
			}
		]
	)
	var authored := Vector2i(4, 4)
	_assert(
		"legacy source.terrain does not override registry",
		map_data.terrain_class(authored) == MapDataClass.TerrainClass.CLIMB,
	)
	_assert(
		"legacy source.terrain_height does not override registry",
		map_data.obstruction_height(authored) == 1,
	)
	_assert("registry Climb remains blocked", map_data.is_blocked(authored))


func _test_explicit_overrides() -> void:
	var map_data := MapDataClass.new()
	map_data.width = 10
	map_data.height = 10
	map_data.apply_terrain_gameplay = true
	MapAssetRegistryClass.set_gameplay(
		"WH00",
		{
			"terrain": "_HG_Climb",
			"terrain_height": 1,
			"blocks_movement": true,
			"blocks_los": false,
		}
	)
	map_data._load_objects_from_json(
		[
			{
				"object_type": "coc_swal",
				"x": 4,
				"y": 4,
				"source": {"image": "WH00", "direction": 0},
				"gameplay_overrides": {"terrain": "_HG_EVEN", "terrain_height": 0, "blocks_movement": false},
			}
		]
	)
	var cell := Vector2i(4, 4)
	_assert("explicit override can clear terrain to Even", map_data.terrain_class(cell) == MapDataClass.TerrainClass.EVEN)
	_assert("explicit override height 0", map_data.obstruction_height(cell) == 0)
	_assert("explicit override can clear movement block", not map_data.is_blocked(cell))


func _test_refresh_gameplay_from_asset_registry() -> void:
	## Refresh strips legacy source fields; runtime already ignores them for resolution.
	var map_data := MapDataClass.new()
	map_data.width = 10
	map_data.height = 10
	map_data.apply_terrain_gameplay = true
	var original := MapAssetRegistryClass.gameplay_for("WH00")
	MapAssetRegistryClass.set_gameplay(
		"WH00",
		{
			"terrain": "_HG_Climb",
			"terrain_height": 1,
			"blocks_movement": true,
			"blocks_los": false,
			"provides_cover": true,
			"cover_type": 1,
		}
	)
	map_data._load_objects_from_json(
		[
			{
				"object_type": "coc_swal",
				"x": 2,
				"y": 2,
				"source": {
					"image": "WH00",
					"direction": 90,
					"z": 200,
					"terrain": "_HG_EVEN",
					"terrain_height": 0,
				},
			},
			{
				"object_type": "coc_swal",
				"x": 3,
				"y": 3,
				"source": {
					"image": "WH00",
					"direction": 0,
					"terrain": "_HG_EVEN",
					"terrain_height": 0,
				},
				"gameplay_overrides": {
					"terrain": "_HG_NoPass",
					"terrain_height": 2,
				},
			},
			{
				"object_type": "coc_blocker",
				"x": 4,
				"y": 4,
				"source": {"image": "ZZ_MISSING_FAMILY_XYZ", "direction": 0, "terrain": "_HG_EVEN"},
			},
		]
	)
	var baked := Vector2i(2, 2)
	var overridden := Vector2i(3, 3)
	_assert(
		"legacy source ignored before refresh (registry Climb)",
		map_data.terrain_class(baked) == MapDataClass.TerrainClass.CLIMB,
	)
	_assert("legacy source still present on disk shape", map_data.get_object_source(baked).has("terrain"))
	var summary: Dictionary = map_data.refresh_gameplay_from_asset_registry()
	_assert("refresh inspected all objects", int(summary.get("inspected", 0)) == 3)
	_assert("refresh cleaned objects with legacy fields", int(summary.get("cleaned", 0)) == 2)
	_assert("refresh removed legacy fields", int(summary.get("legacy_fields_removed", 0)) >= 4)
	_assert("refresh preserved override count", int(summary.get("overrides_preserved", 0)) == 1)
	_assert("refresh counts missing families", int(summary.get("missing_definitions", 0)) == 1)
	_assert(
		"after refresh registry Climb still applies",
		map_data.terrain_class(baked) == MapDataClass.TerrainClass.CLIMB,
	)
	_assert(
		"refresh preserves direction",
		int(map_data.get_object_source(baked).get("direction", -1)) == 90,
	)
	_assert(
		"refresh preserves z",
		int(map_data.get_object_source(baked).get("z", -1)) == 200,
	)
	_assert(
		"refresh strips baked terrain from source",
		not map_data.get_object_source(baked).has("terrain"),
	)
	_assert(
		"refresh preserves gameplay_overrides",
		map_data.terrain_class(overridden) == MapDataClass.TerrainClass.NO_PASS,
	)
	_assert(
		"refresh keeps override height",
		map_data.obstruction_height(overridden) == 2,
	)
	MapAssetRegistryClass.set_gameplay("WH00", original)


func _test_save_strips_legacy_source_gameplay() -> void:
	## Serialization must not reintroduce source.terrain / terrain_height.
	var temp_path := "res://maps/_tmp_registry_strip_test.json"
	var original := MapAssetRegistryClass.gameplay_for("WH00")
	MapAssetRegistryClass.set_gameplay(
		"WH00",
		{"terrain": "_HG_NoPass", "terrain_height": 2, "blocks_movement": true},
	)
	var seed_map := MapDataClass.new()
	seed_map.width = 8
	seed_map.height = 8
	seed_map.map_name = "_tmp_registry_strip_test"
	seed_map.apply_terrain_gameplay = true
	seed_map.uses_original_projection = true
	seed_map._load_objects_from_json(
		[
			{
				"object_type": "coc_swal",
				"x": 1,
				"y": 1,
				"source": {
					"image": "WH00",
					"direction": 0,
					"terrain": "_HG_EVEN",
					"terrain_height": 0,
				},
			}
		]
	)
	_assert("seed strip-test map writes", MapDataClass.save_to_file(seed_map, temp_path))
	var reloaded := MapLoaderClass.load_path(temp_path)
	_assert(
		"saved map follows registry NoPass",
		reloaded != null and reloaded.terrain_class(Vector2i(1, 1)) == MapDataClass.TerrainClass.NO_PASS,
	)
	_assert(
		"save stripped legacy source.terrain",
		reloaded != null and not reloaded.get_object_source(Vector2i(1, 1)).has("terrain"),
	)
	_assert(
		"save stripped legacy source.terrain_height",
		reloaded != null and not reloaded.get_object_source(Vector2i(1, 1)).has("terrain_height"),
	)
	MapAssetRegistryClass.set_gameplay("WH00", original)
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	var import_path := temp_path + ".import"
	if FileAccess.file_exists(import_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(import_path))


func _test_legacy_map_loads() -> void:
	var farm := MapLoaderClass.load_path(MapDataClass.path_for_map("ff_farm"))
	_assert("ff_farm loads", farm != null and farm.width > 0)
	var fortress := MapLoaderClass.load_path(MapDataClass.path_for_map("the_fortress"))
	_assert("TheFortress loads", fortress != null and fortress.width > 0)
	var test_map := MapLoaderClass.load_path(MapDataClass.path_for_map("test_map"))
	_assert("test_map loads", test_map != null and test_map.width > 0)


func _print_audit() -> void:
	var audit := MapAssetRegistryClass.audit_farm_fight()
	print("")
	print("--- Registry audit report ---")
	print("Farm Fight unique families: %d" % int(audit.get("farm_unique_families", 0)))
	print("Registered families: %d" % int(audit.get("registered_families", 0)))
	print("Missing families: %s" % str(audit.get("missing_families", [])))
	print("Incomplete camera variants: %s" % str(audit.get("incomplete_camera_variants", [])))
	print("Fallback gameplay: %s" % str(audit.get("fallback_gameplay", [])))


func _cells_for_family(map_data: MapDataClass, family: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var fam := family.to_upper()
	for cell in map_data.get_object_cells():
		if map_data.get_object_family(cell) == fam:
			out.append(cell)
	return out
