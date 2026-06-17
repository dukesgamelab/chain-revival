class_name SoldierState
extends RefCounted
## Pure gameplay data for one soldier. No rendering references.

const DEFAULT_AMMO_MAX := 200

var soldier_id: int = 1
var team_id: int = Team.BLUE
var grid_position: Vector2i = Vector2i.ZERO
var facing_direction: Vector2i = FacingDirection.NORTH
var current_path: Array[Vector2i] = []
var is_moving: bool = false
var ammo_current: int = DEFAULT_AMMO_MAX
var ammo_max: int = DEFAULT_AMMO_MAX
var is_dead: bool = false


func _init(id: int = 1, start_cell: Vector2i = Vector2i.ZERO, team: int = Team.BLUE) -> void:
	soldier_id = id
	team_id = team
	grid_position = start_cell
	ammo_current = DEFAULT_AMMO_MAX
	ammo_max = DEFAULT_AMMO_MAX


func is_alive() -> bool:
	return not is_dead


func clear_path() -> void:
	current_path.clear()
	is_moving = false


func assign_path(path: Array[Vector2i]) -> void:
	if is_dead:
		return
	current_path = path.duplicate()
	is_moving = current_path.size() > 1


func to_dict() -> Dictionary:
	return {
		"soldier_id": soldier_id,
		"team_id": team_id,
		"grid_x": grid_position.x,
		"grid_y": grid_position.y,
		"facing_x": facing_direction.x,
		"facing_y": facing_direction.y,
		"ammo_current": ammo_current,
		"ammo_max": ammo_max,
		"is_dead": is_dead,
	}


static func from_dict(data: Dictionary) -> SoldierState:
	var state := SoldierState.new(
		int(data.get("soldier_id", 1)),
		Vector2i(int(data.get("grid_x", 0)), int(data.get("grid_y", 0))),
		int(data.get("team_id", Team.BLUE)),
	)
	state.facing_direction = FacingDirection.normalize(
		Vector2i(int(data.get("facing_x", 0)), int(data.get("facing_y", -1))),
	)
	state.ammo_current = int(data.get("ammo_current", DEFAULT_AMMO_MAX))
	state.ammo_max = int(data.get("ammo_max", DEFAULT_AMMO_MAX))
	state.is_dead = bool(data.get("is_dead", false))
	return state
