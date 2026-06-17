class_name GameState
extends RefCounted
## Authoritative gameplay lookup: session + map. Used by CombatSystem and commands.

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


func enemy_team_id(team_id: int) -> int:
	return Team.RED if team_id == Team.BLUE else Team.BLUE
