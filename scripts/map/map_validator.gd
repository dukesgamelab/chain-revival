class_name MapValidator
extends RefCounted
## One-shot validation for original CoC maps (no per-frame spam).

static func validate_and_log(map_data: MapData) -> Dictionary:
	var report := {
		"errors": [],
		"warnings": [],
		"resolved": 0,
		"skipped_placeholder": 0,
	}
	if map_data == null:
		report["errors"].append("map_data is null")
		return report
	CocTileCatalog.ensure_loaded()
	if map_data.width <= 0 or map_data.height <= 0:
		report["errors"].append("invalid map size")
	_validate_spawns(map_data, report)
	_validate_blocked(map_data, report)
	_validate_placements(map_data, report)
	_validate_floors(map_data, report)
	for err in report["errors"]:
		push_warning("MapValidator ERROR: %s" % err)
	for warn in report["warnings"]:
		push_warning("MapValidator: %s" % warn)
	print(
		"MapValidator: %s resolved=%d placeholder_skips=%d warnings=%d errors=%d"
		% [
			map_data.map_name,
			report["resolved"],
			report["skipped_placeholder"],
			(report["warnings"] as Array).size(),
			(report["errors"] as Array).size(),
		]
	)
	return report


static func _validate_spawns(map_data: MapData, report: Dictionary) -> void:
	for cell in map_data.team_1_spawn_points:
		if not map_data.is_in_bounds(cell):
			report["errors"].append("team_1 spawn out of bounds %s" % cell)
	for cell in map_data.team_2_spawn_points:
		if not map_data.is_in_bounds(cell):
			report["errors"].append("team_2 spawn out of bounds %s" % cell)
	if map_data.team_1_spawn_points.is_empty():
		report["warnings"].append("no team_1 spawn points")
	if map_data.team_2_spawn_points.is_empty():
		report["warnings"].append("no team_2 spawn points")


static func _validate_blocked(map_data: MapData, report: Dictionary) -> void:
	for cell in map_data.blocked_tiles:
		if not map_data.is_in_bounds(cell):
			report["errors"].append("blocked tile out of bounds %s" % cell)


static func _validate_floors(map_data: MapData, report: Dictionary) -> void:
	var seen: Dictionary = {}
	for entry in map_data.floors:
		var fam := str(entry.get("image", "")).to_upper()
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		if not map_data.is_in_bounds(cell):
			report["errors"].append("floor out of bounds %s" % cell)
			continue
		if fam.is_empty():
			report["errors"].append("floor missing family at %s" % cell)
			continue
		if seen.has(fam):
			continue
		seen[fam] = true
		var info := CocRenderRules.resolve_floor_display(fam, int(entry.get("direction", 0)))
		if CocRenderRules.is_unusable_sprite(info):
			report["warnings"].append("floor family unresolved: %s" % fam)
		else:
			report["resolved"] = int(report["resolved"]) + 1


static func _validate_placements(map_data: MapData, report: Dictionary) -> void:
	var family_ok: Dictionary = {}
	var family_bad: Dictionary = {}
	for entry in map_data.visual_placements:
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		if not map_data.is_in_bounds(cell):
			report["errors"].append("object out of bounds %s" % cell)
			continue
		var family := str(entry.get("family", "")).to_upper()
		if family.is_empty() or family == "NEAR":
			continue
		var direction := int(entry.get("direction", 0))
		for cam_deg in [0, 90, 180, 270]:
			var info := CocFacetSelector.resolve_draw_at_camera(family, direction, cam_deg)
			if CocRenderRules.is_unusable_sprite(info):
				if bool(info.get("missing", true)):
					family_bad[family] = true
				else:
					report["skipped_placeholder"] = int(report["skipped_placeholder"]) + 1
			else:
				family_ok[family] = true
				report["resolved"] = int(report["resolved"]) + 1
	for fam in family_bad.keys():
		if not family_ok.has(fam):
			report["warnings"].append("family never resolves usable sprite: %s" % fam)
	## Soft Image1 advisory for wallish cells that neighbour floors but lack Image1.
	var floor_cells: Dictionary = {}
	for entry in map_data.floors:
		floor_cells[Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))] = true
	var missing_image1 := 0
	for entry in map_data.visual_placements:
		var fam := str(entry.get("family", "")).to_upper()
		if not CocRenderRules.is_wallish_family(fam):
			continue
		if not str(entry.get("image1", "")).is_empty():
			continue
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var touches_floor := false
		for nb in CocRenderRules.NEIGHBOR_DIRS:
			if floor_cells.has(cell + nb):
				touches_floor = true
				break
		if touches_floor:
			missing_image1 += 1
	if missing_image1 > 0:
		report["warnings"].append(
			"%d wallish cells touch floors without Image1 (half-diamond underlay used)" % missing_image1
		)
