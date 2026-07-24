class_name GameSave
extends RefCounted
## JSON save/load for a session (soldiers + commander hierarchy).
##
## Load/save is bootstrap persistence. Mid-match restore must go through
## CommandRouter.load_saved_session().

const DEFAULT_PATH := "user://savegame.json"


## Preferred: persist session + command hierarchy from GameState (IDs only).
static func save_game_state(game_state, file_path: String = DEFAULT_PATH) -> bool:
	if game_state == null or game_state.session == null or game_state.map_data == null:
		push_error("GameSave: missing game_state")
		return false
	var data := {
		"map_name": game_state.map_data.map_name,
		"session": game_state.session.to_dict(),
		"command_hierarchy": (
			game_state.command_hierarchy.to_dict()
			if game_state.command_hierarchy != null
			else {}
		),
		"match_phase": game_state.match_phase,
		"local_player_id": game_state.local_player_id,
	}
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("GameSave: could not write %s" % file_path)
		return false
	file.store_string(json_text)
	return true


## Legacy signature kept for callers that only have session + map.
static func save_game(session: GameSession, map_data: MapData, file_path: String = DEFAULT_PATH) -> bool:
	var data := {
		"map_name": map_data.map_name,
		"session": session.to_dict(),
	}
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("GameSave: could not write %s" % file_path)
		return false
	file.store_string(json_text)
	return true


static func load_game(session: GameSession, file_path: String = DEFAULT_PATH) -> bool:
	var parsed := _read_json(file_path)
	if parsed.is_empty():
		return false
	if parsed.has("session"):
		session.load_from_dict(parsed.get("session", {}))
		return true

	# Legacy single-fireteam save format.
	var legacy: Dictionary = parsed.get("fireteam", {})
	if legacy.is_empty():
		return false
	session.blue_team.load_from_dict(legacy)
	return true


## Restore session + hierarchy into a live GameState.
static func load_game_state(game_state, file_path: String = DEFAULT_PATH) -> bool:
	if game_state == null or game_state.session == null:
		return false
	var parsed := _read_json(file_path)
	if parsed.is_empty():
		return false
	if parsed.has("session"):
		game_state.session.load_from_dict(parsed.get("session", {}))
	else:
		var legacy: Dictionary = parsed.get("fireteam", {})
		if legacy.is_empty():
			return false
		game_state.session.blue_team.load_from_dict(legacy)
	var hier: Variant = parsed.get("command_hierarchy", {})
	if hier is Dictionary and not (hier as Dictionary).is_empty():
		game_state.load_hierarchy_from_dict(hier as Dictionary)
	if parsed.has("match_phase"):
		game_state.match_phase = int(parsed.get("match_phase", game_state.match_phase))
	if parsed.has("local_player_id"):
		game_state.local_player_id = int(parsed.get("local_player_id", game_state.local_player_id))
	return true


static func _read_json(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		push_error("GameSave: no save file at %s" % file_path)
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("GameSave: invalid JSON in %s" % file_path)
		return {}
	return parsed as Dictionary
