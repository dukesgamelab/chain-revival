class_name MapEditHoverOverlay
extends Node2D
## Draws a single hovered-tile highlight for map edit mode (cheap vs redrawing the full map).

var hover_cell: Vector2i = Vector2i(-999, -999)

@export var fill_color := Color(1.0, 0.92, 0.25, 0.38)
@export var outline_color := Color(1.0, 0.82, 0.15, 0.95)


func set_hover_cell(cell: Vector2i) -> void:
	if hover_cell == cell:
		return
	hover_cell = cell
	queue_redraw()


func clear_hover() -> void:
	if hover_cell.x <= -900:
		return
	hover_cell = Vector2i(-999, -999)
	queue_redraw()


func _draw() -> void:
	if hover_cell.x <= -900:
		return
	var center := IsometricGrid.grid_to_world(hover_cell)
	var corners := IsometricGrid.diamond_corners(center)
	draw_colored_polygon(corners, fill_color)
	draw_polyline(corners, outline_color, 2.0, true)
