extends Node
## Autoload singleton (project.godot: PlayerSides) for server-assigned team side.

var assigned_team_id: int = -1


func clear() -> void:
	assigned_team_id = -1


func assign_team(team_id: int) -> void:
	if team_id == Team.USA or team_id == Team.GERMANY:
		assigned_team_id = team_id


func assign_from_side_name(side_name: String) -> void:
	match side_name.to_upper():
		"USA":
			assign_team(Team.USA)
		"GERMANY":
			assign_team(Team.GERMANY)
		_:
			push_warning("PlayerSideManager: unknown side '%s'" % side_name)


func has_assignment() -> bool:
	return assigned_team_id == Team.USA or assigned_team_id == Team.GERMANY


func can_control_team(team_id: int) -> bool:
	if GameModeManager.is_offline_dev():
		return true
	if not GameModeManager.is_local_multiplayer():
		return true
	return has_assignment() and team_id == assigned_team_id


func display_side_name() -> String:
	if assigned_team_id == Team.GERMANY:
		return "GERMANY"
	if assigned_team_id == Team.USA:
		return "USA"
	return "None"
