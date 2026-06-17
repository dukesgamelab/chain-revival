class_name Soldier
extends Node2D
## Visual representation of one soldier. Reads gameplay data from SoldierState via sync_from_state().

signal movement_step_reached(team_id: int, soldier_id: int, tile: Vector2i, step_delta: Vector2i)
signal movement_finished(team_id: int, soldier_id: int)

var soldier_id: int = 1
var team_id: int = Team.BLUE

@export var move_speed := 95.0

var _path: Array[Vector2i] = []
var _path_index: int = 0
var _move_target_world: Vector2 = Vector2.ZERO
var _is_moving: bool = false
var _previous_grid_pos: Vector2i = Vector2i.ZERO

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _selection_marker: Polygon2D = $SelectionMarker
@onready var _facing_arrow: Line2D = $FacingArrow


## Apply authoritative gameplay state to this sprite (position, facing, selection).
func sync_from_state(state: SoldierState, is_selected: bool) -> void:
	soldier_id = state.soldier_id
	team_id = state.team_id
	if not _is_moving:
		position = IsometricGrid.grid_to_world(state.grid_position)
	_apply_facing(state.facing_direction)
	set_selected(is_selected)
	_apply_team_color(is_selected)


func set_selected(is_selected: bool) -> void:
	_selection_marker.visible = is_selected
	_selection_marker.polygon = IsometricGrid.diamond_corners(Vector2.ZERO)
	_apply_team_color(is_selected)


func _apply_team_color(is_selected: bool) -> void:
	_sprite.modulate = Team.soldier_color(team_id, is_selected)


func is_moving() -> bool:
	return _is_moving


func stop_movement() -> void:
	_is_moving = false
	_path.clear()
	_path_index = 0


func follow_path(path: Array[Vector2i]) -> void:
	if path.size() <= 1:
		return

	_path = path
	_path_index = 1
	_is_moving = true
	_previous_grid_pos = _path[0]
	position = IsometricGrid.grid_to_world(_path[0])
	_move_target_world = IsometricGrid.grid_to_world(_path[_path_index])


func _process(delta: float) -> void:
	if not _is_moving:
		return

	var to_target := _move_target_world - position
	var distance := to_target.length()
	var step_delta := _path[_path_index] - _previous_grid_pos
	_apply_facing(FacingDirection.from_step(step_delta))

	if distance <= 0.001:
		_advance_path_step()
		return

	var move_amount := move_speed * delta
	if move_amount >= distance:
		position = _move_target_world
		_advance_path_step()
	else:
		position += to_target.normalized() * move_amount


func _advance_path_step() -> void:
	var step_delta := _path[_path_index] - _previous_grid_pos
	position = _move_target_world
	movement_step_reached.emit(team_id, soldier_id, _path[_path_index], step_delta)
	_previous_grid_pos = _path[_path_index]
	_path_index += 1

	if _path_index >= _path.size():
		_is_moving = false
		movement_finished.emit(team_id, soldier_id)
	else:
		_move_target_world = IsometricGrid.grid_to_world(_path[_path_index])


## Point the placeholder arrow along the isometric screen direction for grid facing.
func _apply_facing(facing: Vector2i) -> void:
	if _facing_arrow == null:
		return
	_facing_arrow.rotation_degrees = IsometricGrid.grid_facing_to_degrees(facing)
