class_name IsometricGrid
extends RefCounted
## Converts between logical grid cells and isometric world positions.
##
## Grid coordinates are plain integers (e.g. Vector2i(3, 5)).
## World positions are pixel locations on the 2D plane where the scene is drawn.
##
## We use standard 2:1 isometric math so each cell is a diamond-shaped tile.

## Full width of one tile diamond (left point to right point).
const TILE_WIDTH := 64

## Full height of one tile diamond (top point to bottom point).
const TILE_HEIGHT := 32

## Extra grass rings drawn outside the playable map (visual only, not walkable).
const MAP_VISUAL_BORDER := 12


## Convert a grid cell to the world-space CENTER of that tile.
static func grid_to_world(grid: Vector2i) -> Vector2:
	var half_w := TILE_WIDTH * 0.5
	var half_h := TILE_HEIGHT * 0.5
	var x := (grid.x - grid.y) * half_w
	var y := (grid.x + grid.y) * half_h
	return Vector2(x, y)


## Screen-space direction for a grid facing step (for arrow/sprite visuals only).
static func grid_facing_to_screen(facing: Vector2i) -> Vector2:
	return grid_to_world(facing) - grid_to_world(Vector2i.ZERO)


## Line2D rotation in degrees (local +X arrow) for a grid facing on this isometric map.
static func grid_facing_to_degrees(facing: Vector2i) -> float:
	var screen_dir := grid_facing_to_screen(facing)
	if screen_dir.length_squared() < 0.001:
		return 0.0
	return rad_to_deg(screen_dir.angle())
## Fast approximation — use world_to_cell_at_point() for mouse picking.
static func world_to_grid(world: Vector2) -> Vector2i:
	var half_w := TILE_WIDTH * 0.5
	var half_h := TILE_HEIGHT * 0.5
	var gx := (world.x / half_w + world.y / half_h) * 0.5
	var gy := (world.y / half_h - world.x / half_w) * 0.5
	return Vector2i(int(floor(gx)), int(floor(gy)))


## Pick the tile diamond that actually contains this world point (for mouse clicks).
static func world_to_cell_at_point(world: Vector2) -> Vector2i:
	var approx := world_to_grid(world)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell := Vector2i(approx.x + dx, approx.y + dy)
			if contains_point(cell, world):
				return cell

	# Fallback: nearest tile center (e.g. click on a gap between diamonds).
	var best_cell := approx
	var best_dist := INF
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell := Vector2i(approx.x + dx, approx.y + dy)
			var dist := world.distance_squared_to(grid_to_world(cell))
			if dist < best_dist:
				best_dist = dist
				best_cell = cell
	return best_cell


## True when world lies inside the diamond for this grid cell.
static func contains_point(cell: Vector2i, world: Vector2) -> bool:
	var center := grid_to_world(cell)
	var local := world - center
	var half_w := TILE_WIDTH * 0.5
	var half_h := TILE_HEIGHT * 0.5
	return absf(local.x) / half_w + absf(local.y) / half_h <= 1.0


## Return the four corners of a tile diamond for _draw() or CollisionPolygon2D.
static func diamond_corners(center: Vector2) -> PackedVector2Array:
	var half_w := TILE_WIDTH * 0.5
	var half_h := TILE_HEIGHT * 0.5
	return PackedVector2Array([
		center + Vector2(0.0, -half_h),   # top
		center + Vector2(half_w, 0.0),    # right
		center + Vector2(0.0, half_h),    # bottom
		center + Vector2(-half_w, 0.0),   # left
	])


## World-space bounding box that fully contains every tile on the map.
## Pass border_cells to include decorative grass rings outside the playable grid.
static func get_map_world_bounds(map_width: int, map_height: int, border_cells: int = 0) -> Rect2:
	if map_width <= 0 or map_height <= 0:
		return Rect2()

	var corner_cells := [
		Vector2i(-border_cells, -border_cells),
		Vector2i(map_width - 1 + border_cells, -border_cells),
		Vector2i(-border_cells, map_height - 1 + border_cells),
		Vector2i(map_width - 1 + border_cells, map_height - 1 + border_cells),
	]
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for cell in corner_cells:
		var world := grid_to_world(cell)
		min_x = minf(min_x, world.x)
		max_x = maxf(max_x, world.x)
		min_y = minf(min_y, world.y)
		max_y = maxf(max_y, world.y)

	var half_w := TILE_WIDTH * 0.5
	var half_h := TILE_HEIGHT * 0.5
	return Rect2(
		min_x - half_w,
		min_y - half_h,
		(max_x - min_x) + TILE_WIDTH,
		(max_y - min_y) + TILE_HEIGHT,
	)
