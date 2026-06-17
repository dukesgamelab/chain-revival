class_name LineOfFire
extends RefCounted
## Grid line-of-fire checks for combat (trees / blocked tiles block shots).


static func is_blocked(from_cell: Vector2i, to_cell: Vector2i, map_data: MapData) -> bool:
	for cell in grid_line(from_cell, to_cell):
		if cell == from_cell or cell == to_cell:
			continue
		if map_data.is_blocked(cell):
			return true
	return false


## Bresenham line through grid cells from start to end (inclusive).
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
