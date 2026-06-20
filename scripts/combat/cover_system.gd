class_name CoverSystem
extends RefCounted
## V1 cover evaluation shared by combat and LOS preview.

enum CoverType { NONE, MODERATE, COMPLETE }

## Moderate cover halves final hit chance (e.g. 60% -> 30%).
const MODERATE_HIT_MULTIPLIER := 0.5

const ADJACENT_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1),
]


class CoverResult extends RefCounted:
	var cover_type: int = CoverType.NONE
	var source_type_id: String = ""
	var source_cell: Vector2i = Vector2i(-999, -999)


class BlockResult extends RefCounted:
	var blocked: bool = false
	var blocking_cell: Vector2i = Vector2i(-999, -999)
	var blocking_type_id: String = ""


## Tile on the line of fire that completely blocks the shot (wall, tree, etc.).
## The first blocker on the shooter's side of the lane can be fired over (peek-and-shoot).
static func find_blocking_tile(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
) -> BlockResult:
	var result := BlockResult.new()
	if map_data == null:
		result.blocked = true
		return result

	var skipped_shooter_side_blocker := false
	for cell in _line_cells_between(from_cell, to_cell):
		var type_id: String = map_data.get_object_type(cell)
		if type_id.is_empty():
			continue
		var object_def := MapObjectRegistry.get_def(type_id)
		if object_def == null:
			continue
		if object_def.cover_type == CoverType.COMPLETE or object_def.blocks_los:
			if (
				not skipped_shooter_side_blocker
				and is_shooter_side_cover_on_line(from_cell, to_cell, cell)
			):
				skipped_shooter_side_blocker = true
				continue
			result.blocked = true
			result.blocking_cell = cell
			result.blocking_type_id = type_id
			return result

	return result


## Cover on the fire line closer to the shooter than the target — may fire over it.
static func is_shooter_side_cover_on_line(
	from_cell: Vector2i,
	to_cell: Vector2i,
	cover_cell: Vector2i,
) -> bool:
	var dist_shooter := _manhattan_distance(from_cell, cover_cell)
	var dist_past_cover := _manhattan_distance(cover_cell, to_cell)
	return dist_shooter <= dist_past_cover


## Moderate cover affecting the target when the shot is not blocked.
static func evaluate_target_cover(
	from_cell: Vector2i,
	target_cell: Vector2i,
	map_data: MapData,
) -> CoverResult:
	var result := CoverResult.new()
	if map_data == null or from_cell == target_cell:
		return result

	_consider_cover_cell(target_cell, map_data, result)
	for offset in ADJACENT_OFFSETS:
		_consider_cover_cell(target_cell + offset, map_data, result)
	for cell in _line_cells_between(from_cell, target_cell):
		if is_shooter_side_cover_on_line(from_cell, target_cell, cell):
			continue
		_consider_cover_cell(cell, map_data, result)

	return result


static func cover_type_name(cover_type: int) -> String:
	match cover_type:
		CoverType.MODERATE:
			return "moderate"
		CoverType.COMPLETE:
			return "complete"
		_:
			return "none"


static func apply_moderate_cover(chance: float) -> float:
	return chance * MODERATE_HIT_MULTIPLIER


static func _consider_cover_cell(cell: Vector2i, map_data: MapData, result: CoverResult) -> void:
	if not map_data.is_in_bounds(cell):
		return
	var type_id: String = map_data.get_object_type(cell)
	if type_id.is_empty():
		return
	var object_def := MapObjectRegistry.get_def(type_id)
	if object_def == null or not object_def.provides_cover:
		return
	if object_def.cover_type != CoverType.MODERATE:
		return
	result.cover_type = CoverType.MODERATE
	result.source_type_id = type_id
	result.source_cell = cell


static func _line_cells_between(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in IsometricGrid.grid_line(from_cell, to_cell):
		if cell == from_cell or cell == to_cell:
			continue
		cells.append(cell)
	return cells


static func _manhattan_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
