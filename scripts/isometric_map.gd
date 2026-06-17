class_name IsometricMap
extends Node2D
## Draws placeholder isometric tiles and runs AStarGrid2D pathfinding.
##
## Logical grid cells (Vector2i) never change when you move the camera.
## This node only handles map data, tile visuals, and path highlights.

@export var grid_width := 20
@export var grid_height := 20

## Slightly different greens so neighboring tiles are easy to read.
@export var tile_color_a := Color(0.28, 0.48, 0.22, 1.0)
@export var tile_color_b := Color(0.24, 0.42, 0.19, 1.0)
@export var tile_outline := Color(0.12, 0.22, 0.10, 0.6)

@export var path_color := Color(0.95, 0.85, 0.20, 0.55)
@export var target_color := Color(0.90, 0.15, 0.15, 0.75)

var _astar := AStarGrid2D.new()
var _path_cells: Array[Vector2i] = []
var _target_cell: Vector2i = Vector2i(-999, -999)


func _ready() -> void:
	rebuild_pathfinding()
	queue_redraw()


func rebuild_pathfinding() -> void:
	_setup_astar()
	queue_redraw()


func _setup_astar() -> void:
	# AStarGrid2D stores walkability per grid cell.
	_astar.region = Rect2i(0, 0, grid_width, grid_height)
	_astar.cell_size = Vector2(1.0, 1.0)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()
	# All interior cells are walkable by default after update(); no extra setup needed.


func is_in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < grid_width
		and cell.y < grid_height
	)


## Return grid cells from start to goal, inclusive. Empty array means no path.
func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	if not is_in_bounds(from_cell) or not is_in_bounds(to_cell):
		return []
	if _astar.is_point_solid(to_cell):
		return []

	var raw_path := _astar.get_id_path(from_cell, to_cell)
	var path: Array[Vector2i] = []
	for cell in raw_path:
		path.append(Vector2i(cell))
	return path


## Store path/target for visual feedback and trigger a redraw.
func show_path(cells: Array[Vector2i], target: Vector2i) -> void:
	_path_cells = cells.duplicate()
	_target_cell = target
	queue_redraw()


func clear_path() -> void:
	_path_cells.clear()
	_target_cell = Vector2i(-999, -999)
	queue_redraw()


func _draw() -> void:
	_draw_tiles()
	_draw_path_overlay()


func _draw_tiles() -> void:
	for y in range(grid_height):
		for x in range(grid_width):
			var cell := Vector2i(x, y)
			var center := IsometricGrid.grid_to_world(cell)
			var fill := tile_color_a if (x + y) % 2 == 0 else tile_color_b
			var corners := IsometricGrid.diamond_corners(center)
			draw_colored_polygon(corners, fill)
			draw_polyline(corners, tile_outline, 1.0, true)


func _draw_path_overlay() -> void:
	# Draw every step along the planned route (except the starting cell).
	for i in range(_path_cells.size()):
		var cell := _path_cells[i]
		if i == 0:
			continue
		var center := IsometricGrid.grid_to_world(cell)
		var corners := IsometricGrid.diamond_corners(center)
		draw_colored_polygon(corners, path_color)

	# Destination tile gets a stronger highlight (like the red marker in Chain of Command).
	if is_in_bounds(_target_cell):
		var target_center := IsometricGrid.grid_to_world(_target_cell)
		var target_corners := IsometricGrid.diamond_corners(target_center)
		draw_colored_polygon(target_corners, target_color)
