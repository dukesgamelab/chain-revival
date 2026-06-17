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


## Convert a grid cell to the world-space CENTER of that tile.
static func grid_to_world(grid: Vector2i) -> Vector2:
	var half_w := TILE_WIDTH * 0.5
	var half_h := TILE_HEIGHT * 0.5
	var x := (grid.x - grid.y) * half_w
	var y := (grid.x + grid.y) * half_h
	return Vector2(x, y)


## Convert a world position (anywhere on the map) to the grid cell underneath it.
static func world_to_grid(world: Vector2) -> Vector2i:
	var half_w := TILE_WIDTH * 0.5
	var half_h := TILE_HEIGHT * 0.5
	var gx := (world.x / half_w + world.y / half_h) * 0.5
	var gy := (world.y / half_h - world.x / half_w) * 0.5
	return Vector2i(int(floor(gx)), int(floor(gy)))


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
