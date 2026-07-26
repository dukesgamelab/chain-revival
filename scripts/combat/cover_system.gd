class_name CoverSystem
extends RefCounted
## V1 cover evaluation shared by combat and LOS preview.
##
## Complete-cover walls (wall_straight, etc.) are tactical cover — not opaque vision blockers.
## A wall blocks LOS only when it sits on the fire line and neither the shooter nor the target
## is adjacent to it (using it as cover / peeking over it).

const PositionStateClass := preload("res://scripts/enums/position_state.gd")
const CoverPolicyClass := preload("res://scripts/gameplay_policies/cover_policy.gd")

enum CoverType { NONE, MODERATE, COMPLETE }

enum WallSkipReason { NONE, SHOOTER_PEEK, TARGET_COVER }

## Offensive corner peek lean direction (presentation: PeekLeft / PeekRight).
enum PeekSide { NONE, LEFT, RIGHT }

## Frozen alias of CoverPolicy default for existing call sites.
const MODERATE_HIT_MULTIPLIER := CoverPolicyClass.DEFAULT_MODERATE_HIT_MULT

## When false, prone shooters cannot lean around a tall wall end.
const CORNER_PEEK_WHILE_PRONE := true


const ADJACENT_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1),
]


class CoverResult extends RefCounted:
	var cover_type: int = CoverType.NONE
	var source_type_id: String = ""
	var source_cell: Vector2i = Vector2i(-999, -999)
	## CoverPolicy.Qualifier — CORNER models PseudoCover (not a weaker hit tier).
	var qualifier: int = CoverPolicyClass.Qualifier.NONE
	var qualifying_cells: Array[Vector2i] = []


class BlockResult extends RefCounted:
	var blocked: bool = false
	var blocking_cell: Vector2i = Vector2i(-999, -999)
	var blocking_type_id: String = ""
	## Set when an adjacent wall-end was exempted for offensive corner peek.
	var corner_peek: bool = false
	var peek_side: int = PeekSide.NONE
	var corner_cell: Vector2i = Vector2i(-999, -999)


class CornerPeekResult extends RefCounted:
	var is_corner: bool = false
	var peek_side: int = PeekSide.NONE
	var corner_cell: Vector2i = Vector2i(-999, -999)


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


## True when a map object blocks line of fire (trees, full-height tiles, etc.).
## Complete-cover walls are handled separately — they provide cover, not opaque blocking.
## Prefer terrain_height via MapData.blocks_vision; fall back to legacy blocks_los.
static func blocks_line_of_fire(object_def: MapObjectDef) -> bool:
	if object_def == null:
		return false
	if _is_complete_cover_wall(object_def):
		return false
	return object_def.blocks_los


static func tile_blocks_vision(
	map_data: MapData,
	cell: Vector2i,
	object_def: MapObjectDef,
	observer_prone: bool = false,
	target_prone: bool = false,
) -> bool:
	if map_data == null:
		return false
	if _is_complete_cover_wall(object_def):
		return false
	## Height is the authority for vision obstruction (0/1/2).
	if map_data.has_object(cell):
		return map_data.blocks_vision(cell, observer_prone, target_prone)
	return blocks_line_of_fire(object_def)


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
## Optional `line` avoids rebuilding Bresenham when the caller already has it.
static func evaluate_wall_cover_usage(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	line: Array[Vector2i] = [],
) -> WallCoverUsage:
	var usage := WallCoverUsage.new()
	if map_data == null or from_cell == to_cell:
		return usage

	## Build the line ONCE — previously adjacent checks re-walked the full ray up to 16×.
	var cells: Array[Vector2i] = line if not line.is_empty() else line_cells_between(from_cell, to_cell)
	var line_set: Dictionary = {}
	for cell in cells:
		line_set[cell] = true
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
			if _is_complete_cover_wall(shooter_def) and line_set.has(shooter_adj):
				usage.shooter_using_wall_cover = true
				usage.shooter_cover_cell = shooter_adj

		var target_adj := to_cell + offset
		if map_data.is_in_bounds(target_adj):
			var target_def := map_data.get_object_def(target_adj)
			if _is_complete_cover_wall(target_def) and line_set.has(target_adj):
				usage.target_using_wall_cover = true
				usage.target_cover_cell = target_adj

	return usage


## Tile on the line of fire that completely blocks the shot.
## Set block_soldiers false for spotting visibility (soldiers do not hide each other).
## Optional `line` shares Bresenham with wall-cover evaluation.
##
## Tall / NO_PASS / complete-cover walls hard-block the SHOT unless:
## - climb/moderate "shoot OVER" peek (existing), or
## - offensive corner peek around an adjacent wall END (new), or
## - the target is adjacent to that wall (using it as cover — shot reaches).
static func find_blocking_tile(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	game_state: GameState = null,
	block_soldiers: bool = true,
	line: Array[Vector2i] = [],
) -> BlockResult:
	var result := BlockResult.new()
	if map_data == null:
		result.blocked = true
		return result

	var observer_prone := _cell_occupant_prone(from_cell, game_state)
	var target_prone := _cell_occupant_prone(to_cell, game_state)

	var cells: Array[Vector2i] = line if not line.is_empty() else line_cells_between(from_cell, to_cell)
	var skipped_shooter_side_blocker := false
	var skipped_corner_peek := false
	for cell in cells:
		if block_soldiers and living_standing_soldier_blocks_line(cell, game_state):
			result.blocked = true
			result.blocking_cell = cell
			result.blocking_type_id = "soldier"
			return result

		var object_def := map_data.get_object_def(cell)
		if object_def == null and not map_data.has_object(cell):
			continue

		var is_complete_wall := _is_complete_cover_wall(object_def)
		var vision_blocks := tile_blocks_vision(
			map_data, cell, object_def, observer_prone, target_prone
		)
		## Complete walls are soft in tile_blocks_vision — treat them as hard shot blockers.
		var hard_blocks := is_complete_wall or vision_blocks
		if not hard_blocks:
			continue

		## Height/climb peek OVER a low adjacent wall (separate from corner lean).
		if (
			not is_complete_wall
			and not skipped_shooter_side_blocker
			and can_peek_and_shoot_over(from_cell, to_cell, cell, object_def)
		):
			skipped_shooter_side_blocker = true
			continue

		## Offensive corner peek AROUND an adjacent wall end (one cell only).
		if (
			not skipped_corner_peek
			and (CORNER_PEEK_WHILE_PRONE or not observer_prone)
		):
			var corner := corner_peek_at_cell(from_cell, to_cell, cell, map_data)
			## Bresenham often cuts past the corner tile the shooter is leaning on.
			if not corner.is_corner:
				corner = _remote_corner_peek_for_blocker(from_cell, to_cell, cell, map_data)
			if corner.is_corner:
				skipped_corner_peek = true
				result.corner_peek = true
				result.peek_side = corner.peek_side
				result.corner_cell = corner.corner_cell
				continue

		## Next tile of the same wall run after a corner lean (orthogonal graze only).
		if (
			skipped_corner_peek
			and result.corner_cell.x != -999
			and _is_orthogonal_adjacent(result.corner_cell, cell)
			and _wall_end_peek_side(from_cell, to_cell, cell, map_data) != PeekSide.NONE
		):
			continue

		## Target hugging this hard wall — shot reaches; cover eval applies after.
		if is_complete_wall and _is_adjacent(to_cell, cell):
			continue

		result.blocked = true
		result.blocking_cell = cell
		result.blocking_type_id = object_def.type_id if object_def != null else "terrain"
		return result

	return result


## Spotting LOS: height/terrain blockers; walls never block rays; soldier cells never block.
## Iterates Bresenham without allocating a cell array. Optional prone flags avoid occupancy.
static func find_spotting_blocking_tile(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	game_state: GameState = null,
	line: Array[Vector2i] = [],
	observer_prone: bool = false,
	target_prone: bool = false,
) -> BlockResult:
	var result := BlockResult.new()
	if map_data == null:
		result.blocked = true
		return result

	if game_state != null:
		observer_prone = _cell_occupant_prone(from_cell, game_state)
		target_prone = _cell_occupant_prone(to_cell, game_state)

	var skipped_shooter_side_blocker := false
	if not line.is_empty():
		for cell in line:
			var blocked := _spotting_cell_blocks(
				from_cell, to_cell, cell, map_data,
				observer_prone, target_prone, skipped_shooter_side_blocker, result,
			)
			if blocked < 0:
				continue
			if blocked == 0:
				skipped_shooter_side_blocker = true
				continue
			return result
		return result

	## Inline Bresenham — avoid allocating Array[Vector2i] on every observers×enemies pair.
	var x0 := from_cell.x
	var y0 := from_cell.y
	var x1 := to_cell.x
	var y1 := to_cell.y
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	while true:
		var cell := Vector2i(x0, y0)
		if cell != from_cell and cell != to_cell:
			var blocked := _spotting_cell_blocks(
				from_cell, to_cell, cell, map_data,
				observer_prone, target_prone, skipped_shooter_side_blocker, result,
			)
			if blocked > 0:
				return result
			if blocked == 0:
				skipped_shooter_side_blocker = true
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return result


## Returns 1 = blocked (result filled), 0 = peek-skipped, -1 = clear cell.
static func _spotting_cell_blocks(
	from_cell: Vector2i,
	to_cell: Vector2i,
	cell: Vector2i,
	map_data: MapData,
	observer_prone: bool,
	target_prone: bool,
	skipped_shooter_side_blocker: bool,
	result: BlockResult,
) -> int:
	var object_def := map_data.get_object_def(cell)
	if object_def == null and not map_data.has_object(cell):
		return -1
	if _is_complete_cover_wall(object_def):
		return -1
	if not tile_blocks_vision(map_data, cell, object_def, observer_prone, target_prone):
		return -1
	if (
		not skipped_shooter_side_blocker
		and can_peek_and_shoot_over(from_cell, to_cell, cell, object_def)
	):
		return 0
	result.blocked = true
	result.blocking_cell = cell
	result.blocking_type_id = object_def.type_id if object_def != null else "terrain"
	return 1


static func _cell_occupant_prone(cell: Vector2i, game_state: GameState) -> bool:
	if game_state == null:
		return false
	var soldier := game_state.find_living_soldier_at_cell(cell)
	if soldier == null:
		return false
	return soldier.position_state == PositionStateClass.DOWN


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
			entry.blocks_line = (
				_is_complete_cover_wall(object_def)
				or tile_blocks_vision(map_data, cell, object_def)
			)
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
		elif map_data.has_object(cell) and map_data.blocks_vision(cell):
			entry.type_id = "terrain"
			entry.blocks_los = true
			entry.blocks_line = true
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


## Geometry: shooter adjacent to a tall/NO_PASS wall END on the fire line with an open
## perpendicular edge to lean past. Not a tile property — computed per shot query.
static func shooter_at_corner(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	line: Array[Vector2i] = [],
) -> CornerPeekResult:
	var result := CornerPeekResult.new()
	if map_data == null or from_cell == to_cell:
		return result
	var cells: Array[Vector2i] = line if not line.is_empty() else line_cells_between(from_cell, to_cell)
	for cell in cells:
		var at := corner_peek_at_cell(from_cell, to_cell, cell, map_data)
		if at.is_corner:
			return at
	return result


## True when `wall_cell` on the shot line is an adjacent wall-end the shooter can lean around.
static func corner_peek_at_cell(
	from_cell: Vector2i,
	to_cell: Vector2i,
	wall_cell: Vector2i,
	map_data: MapData,
) -> CornerPeekResult:
	var result := CornerPeekResult.new()
	if map_data == null or not _is_adjacent(from_cell, wall_cell):
		return result
	if not _is_corner_peek_blocker(map_data, wall_cell):
		return result
	var side := _wall_end_peek_side(from_cell, to_cell, wall_cell, map_data)
	if side == PeekSide.NONE:
		return result
	result.is_corner = true
	result.peek_side = side
	result.corner_cell = wall_cell
	return result


## When Bresenham misses the corner tile, the first hard hit is often the next wall cell.
## Allow a lean if the shooter is on an adjacent wall-end and this blocker is not a mid-wall.
static func _remote_corner_peek_for_blocker(
	from_cell: Vector2i,
	to_cell: Vector2i,
	blocking_cell: Vector2i,
	map_data: MapData,
) -> CornerPeekResult:
	var result := CornerPeekResult.new()
	if map_data == null or not _is_corner_peek_blocker(map_data, blocking_cell):
		return result
	## Solid mid-wall (both perps closed) — shooting through, not around.
	if _wall_end_peek_side(from_cell, to_cell, blocking_cell, map_data) == PeekSide.NONE:
		return result
	for offset in ADJACENT_OFFSETS:
		var wall_cell := from_cell + offset
		if wall_cell == blocking_cell or not _is_adjacent(wall_cell, blocking_cell):
			continue
		var at := corner_peek_at_cell(from_cell, to_cell, wall_cell, map_data)
		if at.is_corner:
			return at
	return result


## Presentation helper: standing idle lean at a wall-end beside/ahead of facing.
## Optional `aim_cell` (Face / Fire At target) drives peek geometry; otherwise facing+1.
## Never leans on a wall behind the soldier — that was reading as “facing the wrong way.”
static func corner_idle_at_cell(
	from_cell: Vector2i,
	facing: Vector2i,
	map_data: MapData,
	aim_cell: Vector2i = Vector2i(-999, -999),
) -> CornerPeekResult:
	var result := CornerPeekResult.new()
	if map_data == null:
		return result
	var aim := FacingDirection.normalize(facing)
	if aim == Vector2i.ZERO:
		return result
	var to_cell := aim_cell
	if to_cell.x <= -999 or to_cell == from_cell:
		to_cell = from_cell + aim
	var best_forward := -999
	for offset in ADJACENT_OFFSETS:
		var wall_cell := from_cell + offset
		var at := corner_peek_at_cell(from_cell, to_cell, wall_cell, map_data)
		if not at.is_corner:
			continue
		var to_wall := wall_cell - from_cell
		var forward := to_wall.x * aim.x + to_wall.y * aim.y
		## Behind facing — keep normal standing idle.
		if forward < 0:
			continue
		if not result.is_corner or forward > best_forward:
			result = at
			best_forward = forward
	return result


## Tall / NO_PASS / complete-cover wall cells eligible for corner-peek geometry.
static func _is_corner_peek_blocker(map_data: MapData, cell: Vector2i) -> bool:
	if map_data == null or not map_data.is_in_bounds(cell):
		return false
	if map_data.terrain_class(cell) == MapData.TerrainClass.NO_PASS:
		return true
	var object_def := map_data.get_object_def(cell)
	if _is_complete_cover_wall(object_def):
		return true
	return map_data.obstruction_height(cell) >= 2


## LEFT/RIGHT relative to the shot direction when at least one perpendicular neighbor
## of the wall tile is open (wall does not continue across the line of fire).
static func _wall_end_peek_side(
	from_cell: Vector2i,
	to_cell: Vector2i,
	wall_cell: Vector2i,
	map_data: MapData,
) -> int:
	var shot := to_cell - from_cell
	var dx := signi(shot.x)
	var dy := signi(shot.y)
	if dx == 0 and dy == 0:
		return PeekSide.NONE
	## Looking along the shot: left = (-dy, dx), right = (dy, -dx) in y-down grid space.
	var left_off := Vector2i(-dy, dx)
	var right_off := Vector2i(dy, -dx)
	if left_off == Vector2i.ZERO and right_off == Vector2i.ZERO:
		return PeekSide.NONE
	var left_open := _perp_neighbor_open(map_data, wall_cell + left_off)
	var right_open := _perp_neighbor_open(map_data, wall_cell + right_off)
	if not left_open and not right_open:
		## Wall continues across the fire line — no open edge to lean past.
		return PeekSide.NONE
	if left_open and not right_open:
		return PeekSide.LEFT
	if right_open and not left_open:
		return PeekSide.RIGHT
	## Both open (pillar / single-tile end) — pick side from target relative to wall.
	var to_wall := wall_cell - from_cell
	var cross := to_wall.x * shot.y - to_wall.y * shot.x
	if cross > 0:
		return PeekSide.LEFT
	if cross < 0:
		return PeekSide.RIGHT
	return PeekSide.LEFT


static func _perp_neighbor_open(map_data: MapData, cell: Vector2i) -> bool:
	if not map_data.is_in_bounds(cell):
		return true
	return not _is_corner_peek_blocker(map_data, cell)


static func peek_side_name(side: int) -> String:
	match side:
		PeekSide.LEFT:
			return "left"
		PeekSide.RIGHT:
			return "right"
		_:
			return "none"


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
## Directional geometry (CoverPolicy.cover_check): only shooter-facing obstructions within
## Chebyshev INITCoverRangeLimit of the target. Flanking defeats cover.
static func evaluate_target_cover(
	from_cell: Vector2i,
	target_cell: Vector2i,
	map_data: MapData,
) -> CoverResult:
	var result := CoverResult.new()
	if map_data == null or from_cell == target_cell:
		return result

	var check: CoverPolicyClass.CoverCheckResult = GameplayPolicies.cover.cover_check(
		from_cell,
		target_cell,
		map_data,
	)
	result.qualifying_cells = check.qualifying_cells.duplicate()
	result.qualifier = check.qualifier
	if not check.in_cover:
		return result

	result.cover_type = CoverType.MODERATE
	result.source_cell = check.source_cell
	var object_def := map_data.get_object_def(check.source_cell)
	if object_def != null:
		result.source_type_id = object_def.type_id
		## Preserve COMPLETE label for adjacent hard walls so existing combat messaging stays.
		if (
			_is_complete_cover_wall(object_def)
			and _is_adjacent(target_cell, check.source_cell)
			and is_cell_on_fire_line(from_cell, target_cell, check.source_cell)
		):
			result.cover_type = CoverType.COMPLETE
	else:
		result.source_type_id = "terrain"
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
	return GameplayPolicies.cover.apply_hit_modifier(chance, true)


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
	## Prefer evaluate_wall_cover_usage's line_set path; this remains for rare call sites.
	if cell == from_cell or cell == to_cell:
		return false
	for line_cell in line_cells_between(from_cell, to_cell):
		if line_cell == cell:
			return true
	return false


static func _consider_adjacent_target_cover(
	_from_cell: Vector2i,
	_target_cell: Vector2i,
	_cell: Vector2i,
	_map_data: MapData,
	_result: CoverResult,
) -> void:
	## Retained for call-site compatibility; cover is now CoverPolicy.cover_check.
	pass


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
	return GameplayPolicies.los.is_adjacent(from_cell, to_cell)


static func _is_orthogonal_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


## Hard wall cover defeated by an offensive corner lean (corner + nearby wall-run graze).
static func corner_peek_flanks_cover_cell(corner_cell: Vector2i, cover_cell: Vector2i) -> bool:
	if cover_cell.x == -999 or corner_cell.x == -999:
		return false
	if cover_cell == corner_cell:
		return true
	if _is_orthogonal_adjacent(corner_cell, cover_cell):
		return true
	## Bresenham may credit hard cover on the next tile of the same wall run.
	return maxi(absi(corner_cell.x - cover_cell.x), absi(corner_cell.y - cover_cell.y)) <= 2


static func _manhattan_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
