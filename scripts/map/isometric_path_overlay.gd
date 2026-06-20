class_name IsometricPathOverlay
extends Node2D
## Draws movement path and destination highlight without redrawing the full map.

@export var path_color := Color(0.95, 0.85, 0.20, 0.55)
@export var target_color := Color(0.90, 0.15, 0.15, 0.75)

var _path_cells: Array[Vector2i] = []
var _target_cell: Vector2i = Vector2i(-999, -999)
var _map_bounds_check: Callable = Callable()


func configure_bounds_check(check: Callable) -> void:
	_map_bounds_check = check


func set_path(cells: Array[Vector2i], target: Vector2i) -> void:
	_path_cells = cells.duplicate()
	_target_cell = target
	queue_redraw()


func clear_path() -> void:
	if _path_cells.is_empty() and _target_cell == Vector2i(-999, -999):
		return
	_path_cells.clear()
	_target_cell = Vector2i(-999, -999)
	queue_redraw()


func _draw() -> void:
	for i in range(_path_cells.size()):
		if i == 0:
			continue
		var cell := _path_cells[i]
		var center := IsometricGrid.grid_to_world(cell)
		draw_colored_polygon(IsometricGrid.diamond_corners(center), path_color)

	if _target_cell != Vector2i(-999, -999) and _map_bounds_check.is_valid() and _map_bounds_check.call(_target_cell):
		var target_center := IsometricGrid.grid_to_world(_target_cell)
		draw_colored_polygon(IsometricGrid.diamond_corners(target_center), target_color)
