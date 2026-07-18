class_name IsometricGrid
extends RefCounted
## Converts between logical grid cells and isometric world positions.
##
## Grid coordinates are plain integers (e.g. Vector2i(3, 5)) and are authoritative for gameplay.
## World positions are pixel locations where the scene is drawn (presentation only).
##
## current_view_rotation remaps logical cells before the normal isometric projection.
## Gameplay grid cells in GameState are never changed.

## Re-exported from TileSizeConfig — single source of truth for tile footprint.
const TILE_WIDTH := TileSizeConfig.TILE_WIDTH

## Re-exported from TileSizeConfig — single source of truth for tile footprint.
const TILE_HEIGHT := TileSizeConfig.TILE_HEIGHT

## Extra grass rings drawn outside the playable map (visual only, not walkable).
const MAP_VISUAL_BORDER := 12

## Presentation-only view rotation: 0-3 = 0, 90, 180, 270 degrees clockwise.
static var current_view_rotation: int = 0

## When true, base projection uses recovered CoC 62×32 pitch (scaled).
static var use_original_projection: bool = false

static var _map_width: int = 0
static var _map_height: int = 0


## Store playable map size used by view-rotation coordinate remaps.
static func set_view_pivot_for_map(map_width: int, map_height: int) -> void:
	_map_width = maxi(map_width, 0)
	_map_height = maxi(map_height, 0)


static func set_original_projection_enabled(enabled: bool) -> void:
	use_original_projection = enabled


static func camera_direction_degrees() -> int:
	return posmod(current_view_rotation, 4) * 90


static func reset_view_rotation() -> void:
	current_view_rotation = 0


static func rotate_view_left() -> void:
	current_view_rotation = (current_view_rotation + 3) % 4


static func rotate_view_right() -> void:
	current_view_rotation = (current_view_rotation + 1) % 4


static func _logical_to_visual(cell: Vector2i) -> Vector2i:
	var x := cell.x
	var y := cell.y
	var w := _map_width
	var h := _map_height
	match current_view_rotation:
		1:
			return Vector2i(y, w - 1 - x)
		2:
			return Vector2i(w - 1 - x, h - 1 - y)
		3:
			return Vector2i(h - 1 - y, x)
		_:
			return cell


## Public alias for presentation remaps (camera rotation only).
static func logical_to_visual_cell(cell: Vector2i) -> Vector2i:
	return _logical_to_visual(cell)


static func _visual_to_logical(cell: Vector2i) -> Vector2i:
	var vx := cell.x
	var vy := cell.y
	var w := _map_width
	var h := _map_height
	match current_view_rotation:
		1:
			return Vector2i(w - 1 - vy, vx)
		2:
			return Vector2i(w - 1 - vx, h - 1 - vy)
		3:
			return Vector2i(vy, h - 1 - vx)
		_:
			return cell


static func _base_grid_to_world(grid: Vector2i) -> Vector2:
	if use_original_projection:
		return OriginalMapProjection.cell_to_world(grid)
	var half_w := TILE_WIDTH * 0.5
	var half_h := TILE_HEIGHT * 0.5
	var x := (grid.x - grid.y) * half_w
	var y := (grid.x + grid.y) * half_h
	return Vector2(x, y)


static func _base_world_to_grid(world: Vector2) -> Vector2i:
	if use_original_projection:
		return OriginalMapProjection.world_to_cell(world)
	var half_w := TILE_WIDTH * 0.5
	var half_h := TILE_HEIGHT * 0.5
	var gx := (world.x / half_w + world.y / half_h) * 0.5
	var gy := (world.y / half_h - world.x / half_w) * 0.5
	return Vector2i(int(floor(gx)), int(floor(gy)))


## Convert a logical grid cell to the world-space CENTER of that tile (presentation).
static func grid_to_world(grid: Vector2i) -> Vector2:
	return _base_grid_to_world(_logical_to_visual(grid))


## World position for soldier aim, tracers, and mouse picking (chest height above tile center).
static func soldier_aim_point(grid: Vector2i) -> Vector2:
	return grid_to_world(grid) + TileSizeConfig.tracer_aim_offset()


## Screen-space direction for a grid facing step (for arrow/sprite visuals only).
static func grid_facing_to_screen(facing: Vector2i, from_cell: Vector2i = Vector2i.ZERO) -> Vector2:
	var visual_from := _logical_to_visual(from_cell)
	var visual_to := _logical_to_visual(from_cell + facing)
	return _base_grid_to_world(visual_to) - _base_grid_to_world(visual_from)


## Line2D rotation in degrees (local +X arrow) for a grid facing on this isometric map.
static func grid_facing_to_degrees(facing: Vector2i, from_cell: Vector2i = Vector2i.ZERO) -> float:
	var screen_dir := grid_facing_to_screen(facing, from_cell)
	if screen_dir.length_squared() < 0.001:
		return 0.0
	return rad_to_deg(screen_dir.angle())


## Isometric screen quadrant for directional unit sprites (ne/nw/se/sw).
static func grid_facing_to_diagonal_quarter(
	facing: Vector2i,
	from_cell: Vector2i = Vector2i.ZERO,
) -> String:
	var screen_dir := grid_facing_to_screen(facing, from_cell)
	if screen_dir.length_squared() < 0.001:
		return "se"
	if screen_dir.x >= 0.0:
		return "ne" if screen_dir.y < 0.0 else "se"
	return "nw" if screen_dir.y < 0.0 else "sw"


## Fast approximation — use world_to_cell_at_point() for mouse picking.
static func world_to_grid(world: Vector2) -> Vector2i:
	return _visual_to_logical(_base_world_to_grid(world))


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
		center + Vector2(0.0, -half_h),
		center + Vector2(half_w, 0.0),
		center + Vector2(0.0, half_h),
		center + Vector2(-half_w, 0.0),
	])


## Bresenham line through grid cells from start to end (inclusive). Gameplay — not rotated.
static func grid_line(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
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
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy

	return points


## World-space bounding box that fully contains every tile on the map (presentation).
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
