class_name Fireteam
extends RefCounted
## Data container for a 4-man fireteam (selection + soldier states).
##
## Path/facing helpers are called by ActionResolver — not by UI or Soldier views.

const SOLDIER_COUNT := 4
var team_id: int = Team.USA
var soldiers: Array[SoldierState] = []
var selected_soldier_id: int = 1


func _init(team: int = Team.USA, start_cells: Array[Vector2i] = []) -> void:
	team_id = team
	soldiers.clear()
	for i in range(SOLDIER_COUNT):
		var soldier_id := i + 1
		var cell := start_cells[i] if i < start_cells.size() else Vector2i(10, 10)
		soldiers.append(SoldierState.new(soldier_id, cell, team_id))


func get_soldier(soldier_id: int) -> SoldierState:
	for state in soldiers:
		if state.soldier_id == soldier_id:
			return state
	return null


func get_selected() -> SoldierState:
	return get_soldier(selected_soldier_id)


func select_soldier(soldier_id: int) -> void:
	## UI-local selection index (client-side; not replicated as gameplay state).
	var state := get_soldier(soldier_id)
	if state == null or state.is_dead:
		return
	selected_soldier_id = soldier_id


func select_first_alive() -> void:
	for state in soldiers:
		var soldier_state: SoldierState = state
		if soldier_state.is_alive():
			selected_soldier_id = soldier_state.soldier_id
			return


func order_path(soldier_id: int, path: Array[Vector2i]) -> void:
	## Called by ActionResolver.execute_move only.
	var state := get_soldier(soldier_id)
	if state == null or state.is_dead:
		return
	state.assign_path(path)


func on_soldier_reached_tile(soldier_id: int, tile: Vector2i, step_from: Vector2i) -> void:
	## Called by ActionResolver.on_movement_step only.
	var state := get_soldier(soldier_id)
	if state == null or state.is_dead:
		return
	state.grid_position = tile
	if step_from != Vector2i.ZERO:
		state.facing_direction = FacingDirection.from_step(step_from)


func face_toward_tile(soldier_id: int, target_cell: Vector2i) -> bool:
	## Called by ActionResolver (face/fire/combat) only.
	var state := get_soldier(soldier_id)
	if state == null or state.is_dead:
		return false
	if target_cell == state.grid_position:
		return false
	state.facing_direction = FacingDirection.toward_cell(state.grid_position, target_cell)
	return true


func on_soldier_finished_moving(soldier_id: int) -> void:
	var state := get_soldier(soldier_id)
	if state == null:
		return
	state.clear_path()


func to_dict() -> Dictionary:
	var soldier_data: Array = []
	for state in soldiers:
		soldier_data.append(state.to_dict())
	return {
		"team_id": team_id,
		"selected_soldier_id": selected_soldier_id,
		"soldiers": soldier_data,
	}


func load_from_dict(data: Dictionary) -> void:
	team_id = int(data.get("team_id", team_id))
	selected_soldier_id = int(data.get("selected_soldier_id", 1))
	var soldier_data: Array = data.get("soldiers", [])
	for i in range(min(SOLDIER_COUNT, soldier_data.size())):
		var entry: Dictionary = soldier_data[i]
		var state := SoldierState.from_dict(entry)
		state.soldier_id = i + 1
		state.team_id = team_id
		state.clear_path()
		soldiers[i] = state
