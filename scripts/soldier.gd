class_name Soldier
extends Node2D
## A single tactical unit. Knows its grid cell and walks tile-by-tile along a path.

signal movement_finished

## Logical position on the map grid (separate from pixel position).
var grid_pos: Vector2i = Vector2i.ZERO

## Pixels moved per second while walking between tile centers.
@export var move_speed := 140.0

var _path: Array[Vector2i] = []
var _path_index: int = 0
var _move_target_world: Vector2 = Vector2.ZERO
var _is_moving: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _selection_marker: Polygon2D = $SelectionMarker
@onready var _collision: CollisionPolygon2D = $ClickArea/CollisionPolygon2D


func _ready() -> void:
	var hit_shape := IsometricGrid.diamond_corners(Vector2.ZERO)
	_collision.polygon = hit_shape
	_update_selection_visual()


## Snap the soldier to a grid cell (updates both grid_pos and world position).
func set_grid_position(cell: Vector2i) -> void:
	grid_pos = cell
	position = IsometricGrid.grid_to_world(cell)


func set_selected(is_selected: bool) -> void:
	_selection_marker.visible = is_selected
	_sprite.modulate = Color(1.15, 1.15, 1.15) if is_selected else Color.WHITE
	_update_selection_visual()


func is_moving() -> bool:
	return _is_moving


## Walk one tile at a time along the given grid path.
func follow_path(path: Array[Vector2i]) -> void:
	if path.size() <= 1:
		return

	_path = path
	_path_index = 1
	_is_moving = true
	_move_target_world = IsometricGrid.grid_to_world(_path[_path_index])


func _process(delta: float) -> void:
	if not _is_moving:
		return

	var to_target := _move_target_world - position
	var distance := to_target.length()

	if distance < 1.0:
		position = _move_target_world
		grid_pos = _path[_path_index]
		_path_index += 1

		if _path_index >= _path.size():
			_is_moving = false
			movement_finished.emit()
		else:
			_move_target_world = IsometricGrid.grid_to_world(_path[_path_index])
	else:
		position += to_target.normalized() * move_speed * delta


func _update_selection_visual() -> void:
	if _selection_marker == null:
		return
	_selection_marker.polygon = IsometricGrid.diamond_corners(Vector2.ZERO)
