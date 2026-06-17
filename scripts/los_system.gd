class_name LOSSystem
extends RefCounted
## Central line-of-sight / line-of-fire evaluation for combat and UI preview.

const MapDataClass := preload("res://scripts/map_data.gd")
const MapObjectRegistryClass := preload("res://scripts/map_object_registry.gd")
const CoverSystemClass := preload("res://scripts/cover_system.gd")
const LineOfFireClass := preload("res://scripts/line_of_fire.gd")

enum Status { CLEAR, COVER, BLOCKED }

const COLOR_CLEAR := Color(0.25, 0.95, 0.35, 0.90)
const COLOR_COVER := Color(0.95, 0.88, 0.20, 0.90)
const COLOR_BLOCKED := Color(0.95, 0.18, 0.12, 0.90)


class LossResult extends RefCounted:
	var status: int = Status.CLEAR
	var cover_value: float = 0.0
	var cover_type: String = ""
	var blocking_cell: Vector2i = Vector2i(-999, -999)
	var blocking_type: String = ""


static func evaluate(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapDataClass,
) -> LossResult:
	var result := LossResult.new()
	if map_data == null or not map_data.is_in_bounds(from_cell) or not map_data.is_in_bounds(to_cell):
		result.status = Status.BLOCKED
		return result

	var blocking_cell := _find_los_blocking_cell(from_cell, to_cell, map_data)
	if blocking_cell != Vector2i(-999, -999):
		result.status = Status.BLOCKED
		result.blocking_cell = blocking_cell
		result.blocking_type = map_data.get_object_type(blocking_cell)
		if result.blocking_type.is_empty():
			result.blocking_type = MapObjectRegistryClass.DEFAULT_BLOCKED_TYPE
		return result

	result.cover_value = CoverSystemClass.get_cover_value(from_cell, to_cell, map_data)
	if result.cover_value > 0.0:
		result.status = Status.COVER
		result.cover_type = CoverSystemClass.get_cover_type(from_cell, to_cell, map_data)
	else:
		result.status = Status.CLEAR

	return result


static func is_shot_blocked(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapDataClass,
) -> bool:
	return evaluate(from_cell, to_cell, map_data).status == Status.BLOCKED


static func status_color(status: int) -> Color:
	match status:
		Status.COVER:
			return COLOR_COVER
		Status.BLOCKED:
			return COLOR_BLOCKED
		_:
			return COLOR_CLEAR


static func status_label(status: int) -> String:
	match status:
		Status.COVER:
			return "Cover"
		Status.BLOCKED:
			return "Blocked"
		_:
			return "Clear"


static func _find_los_blocking_cell(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapDataClass,
) -> Vector2i:
	for cell in LineOfFireClass.grid_line(from_cell, to_cell):
		if cell == from_cell or cell == to_cell:
			continue
		var object_type: String = map_data.get_object_type(cell)
		if object_type.is_empty():
			continue
		var object_def := MapObjectRegistryClass.get_def(object_type)
		if object_def != null and object_def.blocks_los:
			return cell
	return Vector2i(-999, -999)
