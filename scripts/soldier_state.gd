class_name SoldierState
extends RefCounted
## Pure gameplay data for one soldier. No rendering references.

var soldier_id: int = 1
var grid_position: Vector2i = Vector2i.ZERO
var facing_direction: Vector2i = FacingDirection.NORTH
var current_path: Array[Vector2i] = []
var is_moving: bool = false


func _init(id: int = 1, start_cell: Vector2i = Vector2i.ZERO) -> void:
	soldier_id = id
	grid_position = start_cell


func clear_path() -> void:
	current_path.clear()
	is_moving = false


func assign_path(path: Array[Vector2i]) -> void:
	current_path = path.duplicate()
	is_moving = current_path.size() > 1


func to_dict() -> Dictionary:
	return {
		"soldier_id": soldier_id,
		"grid_x": grid_position.x,
		"grid_y": grid_position.y,
		"facing_x": facing_direction.x,
		"facing_y": facing_direction.y,
	}


static func from_dict(data: Dictionary) -> SoldierState:
	var state := SoldierState.new(
		int(data.get("soldier_id", 1)),
		Vector2i(int(data.get("grid_x", 0)), int(data.get("grid_y", 0))),
	)
	state.facing_direction = FacingDirection.normalize(
		Vector2i(int(data.get("facing_x", 0)), int(data.get("facing_y", -1))),
	)
	return state
