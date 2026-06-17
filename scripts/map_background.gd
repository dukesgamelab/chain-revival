extends Node2D
## Full-screen grass fill behind the isometric map so panning never shows black void.
##
## Drawn in world space under the tile grid. Sized large enough to cover the camera
## view at minimum zoom anywhere the clamp allows.

@export var grass_color := Color(0.24, 0.42, 0.19, 1.0)
## Half-width/height of the backdrop rect in world pixels (centered on focus point).
@export var backdrop_half_size := Vector2(6400.0, 6400.0)

var _center_world := Vector2.ZERO


func _ready() -> void:
	queue_redraw()


## Reposition the backdrop when the map loads or the camera focus changes.
func set_center_cell(cell: Vector2i) -> void:
	_center_world = IsometricGrid.grid_to_world(cell)
	queue_redraw()


func _draw() -> void:
	var top_left := _center_world - backdrop_half_size
	var size := backdrop_half_size * 2.0
	draw_rect(Rect2(top_left, size), grass_color)
