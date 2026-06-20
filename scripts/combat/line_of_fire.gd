class_name LineOfFire
extends RefCounted
## Grid line-of-fire helpers. Blocking checks delegate to CoverSystem / LOSSystem.

static func is_blocked(
	from_cell: Vector2i,
	to_cell: Vector2i,
	map_data: MapData,
	game_state: GameState = null,
) -> bool:
	return CoverSystem.find_blocking_tile(from_cell, to_cell, map_data, game_state).blocked


## Bresenham line through grid cells from start to end (inclusive).
static func grid_line(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	return IsometricGrid.grid_line(from_cell, to_cell)
