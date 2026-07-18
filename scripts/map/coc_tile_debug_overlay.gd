class_name CocTileDebugOverlay
extends Node2D
## Dev-only overlay: inspect the map object under the mouse (F3 to toggle).

var map_data: MapData = null
var enabled: bool = false
var _info: Dictionary = {}


func _ready() -> void:
	z_index = 40


func apply_map_data(data: MapData) -> void:
	map_data = data
	_info.clear()
	queue_redraw()


func set_overlay_enabled(is_on: bool) -> void:
	enabled = is_on
	visible = is_on
	queue_redraw()


func toggle() -> void:
	set_overlay_enabled(not enabled)


func refresh_view_rotation() -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	if not enabled or map_data == null:
		return
	_update_from_mouse()
	queue_redraw()


func _update_from_mouse() -> void:
	var world := get_global_mouse_position()
	var cell := IsometricGrid.world_to_cell_at_point(world)
	_info = {
		"cell": cell,
		"in_bounds": map_data.is_in_bounds(cell),
	}
	if not map_data.is_in_bounds(cell):
		return
	var visual := IsometricGrid.logical_to_visual_cell(cell)
	_info["view"] = visual
	_info["depth"] = visual.x + visual.y
	_info["camera"] = IsometricGrid.camera_direction_degrees()
	## Prefer an object / decoration on this cell; else show floor.
	var best: Dictionary = {}
	for entry in map_data.visual_placements:
		if int(entry.get("x", -1)) != cell.x or int(entry.get("y", -1)) != cell.y:
			continue
		best = entry
		break
	if best.is_empty():
		for entry in map_data.floors:
			if int(entry.get("x", -1)) == cell.x and int(entry.get("y", -1)) == cell.y:
				best = {
					"family": str(entry.get("image", "")).to_upper(),
					"direction": int(entry.get("direction", 0)),
					"layer": "floor",
					"z": 0,
					"image1": "",
				}
				break
	if best.is_empty():
		_info["empty"] = true
		return
	var family := str(best.get("family", "")).to_upper()
	var direction := int(best.get("direction", 0))
	var image1 := str(best.get("image1", ""))
	var draw_info := CocSpriteResolver.resolve_placement(family, direction, image1)
	_info["family"] = family
	_info["direction"] = direction
	_info["display_angle"] = int(draw_info.get("display_angle", CocFacetSelector.display_angle(direction)))
	_info["facet_count"] = int(draw_info.get("facet_count", CocTileCatalog.facet_count(family)))
	_info["letter"] = str(draw_info.get("letter", ""))
	_info["path"] = str(draw_info.get("path", ""))
	_info["hotspot"] = draw_info.get("hotspot", CocTileCatalog.DEFAULT_HOTSPOT)
	_info["z"] = int(best.get("z", 0))
	_info["image1"] = image1
	_info["layer"] = str(best.get("layer", "object"))


func _draw() -> void:
	if not enabled or _info.is_empty():
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("CoC tile debug (F3)")
	var cell: Vector2i = _info.get("cell", Vector2i.ZERO)
	lines.append("map %s" % cell)
	if _info.get("empty", false) or not bool(_info.get("in_bounds", false)):
		lines.append("(no authored tile)")
	else:
		var view: Vector2i = _info.get("view", Vector2i.ZERO)
		lines.append("view %s  depth %s  z %s" % [view, _info.get("depth", 0), _info.get("z", 0)])
		lines.append("family %s  layer %s" % [_info.get("family", ""), _info.get("layer", "")])
		lines.append(
			"worldDir %s  cam %s  display %s"
			% [_info.get("direction", 0), _info.get("camera", 0), _info.get("display_angle", 0)]
		)
		lines.append(
			"facets %s  letter %s"
			% [_info.get("facet_count", 0), _info.get("letter", "")]
		)
		lines.append("path %s" % str(_info.get("path", "")).get_file())
		var hs: Vector2 = _info.get("hotspot", Vector2.ZERO)
		lines.append("hotspot %s" % hs)
		var image1 := str(_info.get("image1", ""))
		if not image1.is_empty():
			lines.append("Image1 %s" % image1)
	var font := ThemeDB.fallback_font
	var pos := get_global_mouse_position() + Vector2(14, 14)
	var y := 0.0
	for line in lines:
		draw_string(font, pos + Vector2(1, y + 1), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.85))
		draw_string(font, pos + Vector2(0, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.95, 0.7, 1))
		y += 14.0
