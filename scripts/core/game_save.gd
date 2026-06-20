class_name GameSave
extends RefCounted
## JSON save/load for soldier positions during a session (separate from map files).
##
## Load/save is bootstrap persistence, not runtime command flow. A future server would
## restore GameState snapshots rather than call load_from_dict from UI mid-match.

const DEFAULT_PATH := "user://savegame.json"


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
	if not FileAccess.file_exists(file_path):
		push_error("GameSave: no save file at %s" % file_path)
		return false

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("GameSave: invalid JSON in %s" % file_path)
		return false

	var data: Dictionary = parsed
	if data.has("session"):
		session.load_from_dict(data.get("session", {}))
		return true

	# Legacy single-fireteam save format.
	var legacy: Dictionary = data.get("fireteam", {})
	if legacy.is_empty():
		return false
	session.blue_team.load_from_dict(legacy)
	return true
