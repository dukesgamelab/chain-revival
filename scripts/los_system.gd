class_name LOSSystem
extends RefCounted
## Central line-of-sight / line-of-fire evaluation for combat and UI preview.

enum Status { CLEAR, COVER, BLOCKED }

const COLOR_CLEAR := Color(0.25, 0.95, 0.35, 0.90)
const COLOR_COVER := Color(0.95, 0.88, 0.20, 0.90)
const COLOR_BLOCKED := Color(0.95, 0.18, 0.12, 0.90)


class LossResult extends RefCounted:
	var status: int = Status.CLEAR
	var cover_type: int = CoverSystem.CoverType.NONE
	var cover_source_type: String = ""
	var cover_source_cell: Vector2i = Vector2i(-999, -999)
	var blocking_cell: Vector2i = Vector2i(-999, -999)
	var blocking_type: String = ""


static func evaluate(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
) -> LossResult:
	var result := LossResult.new()
	if map_data == null or not map_data.is_in_bounds(from_cell) or not map_data.is_in_bounds(to_cell):
		result.status = Status.BLOCKED
		return result

	var block := CoverSystem.find_blocking_tile(from_cell, to_cell, map_data)
	if block.blocked:
		result.status = Status.BLOCKED
		result.blocking_cell = block.blocking_cell
		result.blocking_type = block.blocking_type_id
		if result.blocking_type.is_empty():
			result.blocking_type = MapObjectRegistry.DEFAULT_BLOCKED_TYPE
		return result

	var cover := CoverSystem.evaluate_target_cover(from_cell, to_cell, map_data)
	result.cover_type = cover.cover_type
	result.cover_source_type = cover.source_type_id
	result.cover_source_cell = cover.source_cell
	if cover.cover_type == CoverSystem.CoverType.MODERATE:
		result.status = Status.COVER
	else:
		result.status = Status.CLEAR

	return result


static func is_shot_blocked(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
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
			return "Moderate cover"
		Status.BLOCKED:
			return "Blocked"
		_:
			return "Clear"
