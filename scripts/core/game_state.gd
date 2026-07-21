class_name GameState
extends RefCounted
## Single source of truth for authoritative gameplay data.
##
## Owns the session (soldiers, teams), map (blockers, cover objects, walkability),
## and ObjectRegistry (stable ID → object index). All gameplay mutations go through
## CommandRouter → ActionResolver — never write soldier or map fields from UI,
## Soldier views, or scene scripts.
##
## Authoritative soldier fields (via SoldierState): grid_position, facing_direction,
## is_dead, position_state, movement_mode, fire_control_state, ammo, engagement,
## grenades, stun timers, stress, and weapon assignment.
## Soldier scene nodes are presentation-only and are never stored in the registry.
var session: GameSession
var map_data: MapData
var objects: ObjectRegistry


func _init(game_session: GameSession, map: MapData) -> void:
	session = game_session
	map_data = map
	objects = ObjectRegistry.new()
	objects.rebuild_from(self)


func rebuild_object_registry() -> void:
	objects.rebuild_from(self)


func get_soldier(team_id: int, soldier_id: int) -> SoldierState:
	var from_registry: SoldierState = objects.get_soldier_by_team_slot(team_id, soldier_id)
	if from_registry != null:
		return from_registry
	return session.get_fireteam(team_id).get_soldier(soldier_id)


func get_soldier_by_id(object_id: String) -> SoldierState:
	return objects.get_soldier(object_id)


## First living soldier standing on this tile (any team).
func find_living_soldier_at_cell(cell: Vector2i) -> SoldierState:
	for fireteam in session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.is_dead:
				continue
			if soldier_state.grid_position == cell:
				return soldier_state
	return null


## Any soldier on this tile, including dead or prone.
func find_soldier_at_cell(cell: Vector2i) -> SoldierState:
	for fireteam in session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.grid_position == cell:
				return soldier_state
	return null


func enemy_team_id(team_id: int) -> int:
	return Team.GERMANY if team_id == Team.USA else Team.USA
