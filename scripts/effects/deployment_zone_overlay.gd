class_name DeploymentZoneOverlay
extends Node2D
## Tinted diamonds over a team's deployment cells (Phase 48: the enemy's zone is shown
## during the deployment countdown). Map data only, never soldier positions.

const ENEMY_FILL := Color(0.85, 0.18, 0.12, 0.22)
const ENEMY_OUTLINE := Color(0.95, 0.28, 0.2, 0.7)

var _cells: Array[Vector2i] = []


func show_cells(cells: Array[Vector2i]) -> void:
	_cells = cells.duplicate()
	visible = not _cells.is_empty()
	queue_redraw()


func clear() -> void:
	_cells.clear()
	visible = false
	queue_redraw()


func cell_count() -> int:
	return _cells.size()


## Camera rotated: same cells, new projection.
func refresh_view_rotation() -> void:
	queue_redraw()


func _draw() -> void:
	for cell in _cells:
		var corners := IsometricGrid.diamond_corners(IsometricGrid.grid_to_world(cell))
		draw_colored_polygon(corners, ENEMY_FILL)
		var outline := corners.duplicate()
		outline.append(corners[0])
		draw_polyline(outline, ENEMY_OUTLINE, 1.5, true)
