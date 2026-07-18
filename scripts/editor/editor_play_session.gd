class_name EditorPlaySession
extends RefCounted
## Hands a map path from the editor into gameplay (and back).

const PENDING_PATH_KEY := "editor_play_map_path"
const RETURN_TO_EDITOR_KEY := "editor_return_after_play"


static func request_play(map_path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", PENDING_PATH_KEY, map_path)
	cfg.set_value("session", RETURN_TO_EDITOR_KEY, true)
	cfg.save("user://editor_play_session.cfg")


static func consume_pending_map_path() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("user://editor_play_session.cfg") != OK:
		return ""
	var path := str(cfg.get_value("session", PENDING_PATH_KEY, ""))
	cfg.set_value("session", PENDING_PATH_KEY, "")
	cfg.save("user://editor_play_session.cfg")
	return path


static func should_return_to_editor() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load("user://editor_play_session.cfg") != OK:
		return false
	return bool(cfg.get_value("session", RETURN_TO_EDITOR_KEY, false))


static func clear_return_flag() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://editor_play_session.cfg")
	cfg.set_value("session", RETURN_TO_EDITOR_KEY, false)
	cfg.save("user://editor_play_session.cfg")
