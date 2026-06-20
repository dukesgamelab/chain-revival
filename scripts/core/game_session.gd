class_name GameSession
extends RefCounted
## Root gameplay container for a match (local dev: both teams on one machine).
##
## Architecture (server-ready):
##   GameSession → fireteams and active team
##   GameState   → session + map_data (authoritative snapshot)
##   ActionResolver → validates/applies Command DTOs against GameState
##
## Presentation (main.gd, Soldier scenes) reads GameState and never mutates it directly.

var blue_team: Fireteam
var red_team: Fireteam
var active_team_id: int = Team.USA


func _init(blue_spawns: Array[Vector2i], red_spawns: Array[Vector2i]) -> void:
	blue_team = Fireteam.new(Team.USA, blue_spawns)
	red_team = Fireteam.new(Team.GERMANY, red_spawns)


func create_game_state(map_data: MapData) -> GameState:
	return GameState.new(self, map_data)


func get_active_fireteam() -> Fireteam:
	return get_fireteam(active_team_id)


func get_fireteam(team_id: int) -> Fireteam:
	if team_id == Team.GERMANY:
		return red_team
	return blue_team


func set_active_team(team_id: int) -> void:
	if team_id == Team.USA or team_id == Team.GERMANY:
		active_team_id = team_id


func all_fireteams() -> Array[Fireteam]:
	return [blue_team, red_team]


func to_dict() -> Dictionary:
	return {
		"active_team_id": active_team_id,
		"blue_team": blue_team.to_dict(),
		"red_team": red_team.to_dict(),
	}


func load_from_dict(data: Dictionary) -> void:
	active_team_id = int(data.get("active_team_id", Team.USA))
	blue_team.load_from_dict(data.get("blue_team", {}))
	red_team.load_from_dict(data.get("red_team", {}))
