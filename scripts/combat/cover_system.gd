class_name CoverSystem
extends RefCounted
## V1 cover evaluation shared by combat and LOS preview.
##
## Complete-cover walls (wall_straight, etc.) are tactical cover — not opaque vision blockers.
## A wall blocks LOS only when it sits on the fire line and neither the shooter nor the target
## is adjacent to it (using it as cover / peeking over it).

const PositionStateClass := preload("res://scripts/enums/position_state.gd")

enum CoverType { NONE, MODERATE, COMPLETE }

enum WallSkipReason { NONE, SHOOTER_PEEK, TARGET_COVER }

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


class WallCoverUsage extends RefCounted:
	var shooter_using_wall_cover: bool = false
	var target_using_wall_cover: bool = false
	var shooter_cover_cell: Vector2i = Vector2i(-999, -999)
	var target_cover_cell: Vector2i = Vector2i(-999, -999)


class LineTraceEntry extends RefCounted:
	var cell: Vector2i = Vector2i.ZERO
	var type_id: String = ""
	var blocks_los: bool = false
	var blocks_line: bool = false
	var peek_skipped: bool = false
	var wall_skip_reason: int = WallSkipReason.NONE
	var soldier_blocks: bool = false
	var soldier_pass_through: bool = false


## True when a map object blocks line of fire (trees, etc.).
## Complete-cover walls are handled separately — they provide cover, not opaque blocking.
static func blocks_line_of_fire(object_def: MapObjectDef) -> bool:
	if object_def == null:
		return false
	if _is_complete_cover_wall(object_def):
		return false
	return object_def.blocks_los


## Only low cover beside the shooter may be fired over (haybail).
static func allows_peek_and_shoot_over(object_def: MapObjectDef) -> bool:
	if object_def == null:
		return false
	return (
		object_def.provides_cover
		and object_def.cover_type == CoverType.MODERATE
		and not object_def.blocks_los
	)


## Living standing soldiers block fire; dead and prone soldiers do not.
static func living_standing_soldier_blocks_line(cell: Vector2i, game_state: GameState) -> bool:
	if game_state == null:
		return false
	var soldier := game_state.find_living_soldier_at_cell(cell)
	if soldier == null:
		return false
	if soldier.position_state == PositionStateClass.DOWN:
		return false
	return true


## True when the target is adjacent to a complete-cover wall on the fire line.
static func target_has_hard_cover(
	from_cell: Vector2i,
	target_cell: Vector2i,
	map_data: MapData,
) -> bool:
	return evaluate_wall_cover_usage(from_cell, target_cell, map_data).target_using_wall_cover


## Who is using a complete-cover wall on this fire line (peek / hard cover).
static func evaluate_wall_cover_usage(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
) -> WallCoverUsage:
	var usage := WallCoverUsage.new()
	if map_data == null or from_cell == to_cell:
		return usage

	for cell in line_cells_between(from_cell, to_cell):
		var object_def := map_data.get_object_def(cell)
		if not _is_complete_cover_wall(object_def):
			continue
		if _is_adjacent(from_cell, cell):
			usage.shooter_using_wall_cover = true
			usage.shooter_cover_cell = cell
		if _is_adjacent(to_cell, cell):
			usage.target_using_wall_cover = true
			usage.target_cover_cell = cell

	for offset in ADJACENT_OFFSETS:
		var shooter_adj := from_cell + offset
		if map_data.is_in_bounds(shooter_adj):
			var shooter_def := map_data.get_object_def(shooter_adj)
			if (
				_is_complete_cover_wall(shooter_def)
				and is_cell_on_fire_line(from_cell, to_cell, shooter_adj)
			):
				usage.shooter_using_wall_cover = true
				usage.shooter_cover_cell = shooter_adj

		var target_adj := to_cell + offset
		if map_data.is_in_bounds(target_adj):
			var target_def := map_data.get_object_def(target_adj)
			if (
				_is_complete_cover_wall(target_def)
				and is_cell_on_fire_line(from_cell, to_cell, target_adj)
			):
				usage.target_using_wall_cover = true
				usage.target_cover_cell = target_adj

	return usage


## Tile on the line of fire that completely blocks the shot.
## Set block_soldiers false for spotting visibility (soldiers do not hide each other).
static func find_blocking_tile(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	game_state: GameState = null,
	block_soldiers: bool = true,
) -> BlockResult:
	var result := BlockResult.new()
	if map_data == null:
		result.blocked = true
		return result

	var skipped_shooter_side_blocker := false
	for cell in line_cells_between(from_cell, to_cell):
		if block_soldiers and living_standing_soldier_blocks_line(cell, game_state):
			result.blocked = true
			result.blocking_cell = cell
			result.blocking_type_id = "soldier"
			return result

		var object_def := map_data.get_object_def(cell)
		if object_def == null:
			continue

		if _is_complete_cover_wall(object_def):
			if _is_adjacent(from_cell, cell) or _is_adjacent(to_cell, cell):
				continue
			result.blocked = true
			result.blocking_cell = cell
			result.blocking_type_id = object_def.type_id
			return result

		if not blocks_line_of_fire(object_def):
			continue
		if (
			not skipped_shooter_side_blocker
			and can_peek_and_shoot_over(from_cell, to_cell, cell, object_def)
		):
			skipped_shooter_side_blocker = true
			continue
		result.blocked = true
		result.blocking_cell = cell
		result.blocking_type_id = object_def.type_id
		return result

	return result


## Spotting LOS: trees block; walls never block rays; soldier cells never block.
static func find_spotting_blocking_tile(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	game_state: GameState = null,
) -> BlockResult:
	var result := BlockResult.new()
	if map_data == null:
		result.blocked = true
		return result

	var skipped_shooter_side_blocker := false
	for cell in line_cells_between(from_cell, to_cell):
		if game_state != null and cell != to_cell:
			var occupant := game_state.find_soldier_at_cell(cell)
			if occupant != null:
				continue

		var object_def := map_data.get_object_def(cell)
		if object_def == null:
			continue
		if _is_complete_cover_wall(object_def):
			continue
		if not blocks_line_of_fire(object_def):
			continue
		if (
			not skipped_shooter_side_blocker
			and can_peek_and_shoot_over(from_cell, to_cell, cell, object_def)
		):
			skipped_shooter_side_blocker = true
			continue
		result.blocked = true
		result.blocking_cell = cell
		result.blocking_type_id = object_def.type_id
		return result

	return result


## Deprecated: spotting no longer hides by adjacent wall cover alone (see find_spotting_blocking_tile).
static func is_target_hidden_from_spotting(
	from_cell: Vector2i,
	to_cell: Vector2i,
	_map_data: MapData,
) -> bool:
	return false


## Collect per-tile LOS trace data for debug logging.
static func trace_line_of_sight(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	game_state: GameState = null,
) -> Array[LineTraceEntry]:
	var trace: Array[LineTraceEntry] = []
	if map_data == null:
		return trace

	var skipped_shooter_side_blocker := false
	for cell in line_cells_between(from_cell, to_cell):
		var entry := LineTraceEntry.new()
		entry.cell = cell
		var soldier := game_state.find_soldier_at_cell(cell) if game_state != null else null
		if soldier != null:
			if living_standing_soldier_blocks_line(cell, game_state):
				entry.soldier_blocks = true
				entry.type_id = "soldier"
			else:
				entry.soldier_pass_through = true
				entry.type_id = (
					"soldier_down"
					if soldier.is_dead or soldier.position_state == PositionStateClass.DOWN
					else "soldier"
				)
		var object_def := map_data.get_object_def(cell)
		if object_def != null:
			entry.type_id = object_def.type_id
			entry.blocks_los = object_def.blocks_los
			entry.blocks_line = _is_complete_cover_wall(object_def) or blocks_line_of_fire(object_def)
			if _is_complete_cover_wall(object_def):
				entry.wall_skip_reason = get_wall_skip_reason(
					from_cell,
					to_cell,
					cell,
					object_def,
				)
			elif entry.blocks_line:
				if (
					not skipped_shooter_side_blocker
					and can_peek_and_shoot_over(from_cell, to_cell, cell, object_def)
				):
					entry.peek_skipped = true
					skipped_shooter_side_blocker = true
		trace.append(entry)
	return trace


static func can_peek_and_shoot_over(
	from_cell: Vector2i,
	to_cell: Vector2i,
	cover_cell: Vector2i,
	object_def: MapObjectDef,
) -> bool:
	if not allows_peek_and_shoot_over(object_def):
		return false
	if not _is_adjacent(from_cell, cover_cell):
		return false
	return is_shooter_side_cover_on_line(from_cell, to_cell, cover_cell)


static func get_wall_skip_reason(
	from_cell: Vector2i,
	to_cell: Vector2i,
	wall_cell: Vector2i,
	object_def: MapObjectDef,
) -> int:
	if not _is_complete_cover_wall(object_def):
		return WallSkipReason.NONE
	if not is_cell_on_fire_line(from_cell, to_cell, wall_cell):
		return WallSkipReason.NONE
	if _is_adjacent(from_cell, wall_cell):
		return WallSkipReason.SHOOTER_PEEK
	if _is_adjacent(to_cell, wall_cell):
		return WallSkipReason.TARGET_COVER
	return WallSkipReason.NONE


static func provides_complete_cover_to_target(
	from_cell: Vector2i,
	target_cell: Vector2i,
	cover_cell: Vector2i,
	object_def: MapObjectDef,
) -> bool:
	if get_wall_skip_reason(from_cell, target_cell, cover_cell, object_def) != WallSkipReason.TARGET_COVER:
		return false
	return object_def.provides_cover


static func is_shooter_side_cover_on_line(
	from_cell: Vector2i,
	to_cell: Vector2i,
	cover_cell: Vector2i,
) -> bool:
	var dist_shooter := _manhattan_distance(from_cell, cover_cell)
	var dist_past_cover := _manhattan_distance(cover_cell, to_cell)
	return dist_shooter <= dist_past_cover


## Cover affecting the target when the shot is not blocked.
static func evaluate_target_cover(
	from_cell: Vector2i,
	target_cell: Vector2i,
	map_data: MapData,
) -> CoverResult:
	var result := CoverResult.new()
	if map_data == null or from_cell == target_cell:
		return result

	var wall_usage := evaluate_wall_cover_usage(from_cell, target_cell, map_data)
	if wall_usage.target_using_wall_cover:
		var cover_cell := wall_usage.target_cover_cell
		var object_def := map_data.get_object_def(cover_cell)
		if object_def != null:
			_apply_complete_cover(object_def, cover_cell, result)

	for offset in ADJACENT_OFFSETS:
		_consider_adjacent_target_cover(
			from_cell,
			target_cell,
			target_cell + offset,
			map_data,
			result,
		)
	for cell in line_cells_between(from_cell, target_cell):
		var object_def := map_data.get_object_def(cell)
		if object_def == null:
			continue
		if can_peek_and_shoot_over(from_cell, target_cell, cell, object_def):
			continue
		if get_wall_skip_reason(from_cell, target_cell, cell, object_def) != WallSkipReason.NONE:
			continue
		if object_def.provides_cover and object_def.cover_type == CoverType.MODERATE:
			_apply_moderate_cover(object_def, cell, result)

	return result


static func cover_type_name(cover_type: int) -> String:
	match cover_type:
		CoverType.MODERATE:
			return "moderate"
		CoverType.COMPLETE:
			return "complete"
		_:
			return "none"


static func wall_skip_reason_name(reason: int) -> String:
	match reason:
		WallSkipReason.SHOOTER_PEEK:
			return "shooter_peek"
		WallSkipReason.TARGET_COVER:
			return "target_cover"
		_:
			return "none"


static func apply_moderate_cover(chance: float) -> float:
	return chance * MODERATE_HIT_MULTIPLIER


static func line_cells_between(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in IsometricGrid.grid_line(from_cell, to_cell):
		if cell == from_cell or cell == to_cell:
			continue
		cells.append(cell)
	return cells


static func is_cell_on_fire_line(
	from_cell: Vector2i,
	to_cell: Vector2i,
	cell: Vector2i,
) -> bool:
	for line_cell in line_cells_between(from_cell, to_cell):
		if line_cell == cell:
			return true
	return false


static func _consider_adjacent_target_cover(
	from_cell: Vector2i,
	target_cell: Vector2i,
	cell: Vector2i,
	map_data: MapData,
	result: CoverResult,
) -> void:
	if not map_data.is_in_bounds(cell):
		return
	var object_def := map_data.get_object_def(cell)
	if object_def == null or not object_def.provides_cover:
		return
	if object_def.cover_type == CoverType.MODERATE:
		_apply_moderate_cover(object_def, cell, result)


static func _apply_complete_cover(
	object_def: MapObjectDef,
	cell: Vector2i,
	result: CoverResult,
) -> void:
	result.cover_type = CoverType.COMPLETE
	result.source_type_id = object_def.type_id
	result.source_cell = cell


static func _apply_moderate_cover(
	object_def: MapObjectDef,
	cell: Vector2i,
	result: CoverResult,
) -> void:
	if result.cover_type == CoverType.COMPLETE:
		return
	result.cover_type = CoverType.MODERATE
	result.source_type_id = object_def.type_id
	result.source_cell = cell


static func _is_complete_cover_wall(object_def: MapObjectDef) -> bool:
	return (
		object_def != null
		and object_def.provides_cover
		and object_def.cover_type == CoverType.COMPLETE
	)


static func _is_adjacent(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if from_cell == to_cell:
		return false
	return maxi(absi(from_cell.x - to_cell.x), absi(from_cell.y - to_cell.y)) <= 1


static func _manhattan_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
