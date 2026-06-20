class_name GameState
extends RefCounted
## Single source of truth for authoritative gameplay data.
##
## Owns the session (soldiers, teams) and map (blockers, cover objects, walkability).
## All gameplay mutations go through CommandRouter → ActionResolver — never write
## soldier or map fields from UI, Soldier views, or scene scripts.
##
## Authoritative soldier fields (via SoldierState): grid_position, facing_direction,
## is_dead, position_state, movement_mode, fire_control_state, ammo, engagement,
## grenades, stun timers, stress, and weapon assignment.
var session: GameSession
var map_data: MapData


func _init(game_session: GameSession, map: MapData) -> void:
	session = game_session
	map_data = map


func get_soldier(team_id: int, soldier_id: int) -> SoldierState:
	return session.get_fireteam(team_id).get_soldier(soldier_id)


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
