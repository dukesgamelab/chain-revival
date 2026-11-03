extends RefCounted
## Remembers the multiplayer match this client is in, so a relaunched game can rejoin it.

const PATH := "user://rejoin.cfg"
const SECTION := "match"


static func save(lobby_id: String, server_url: String) -> void:
	if lobby_id.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "lobby_id", lobby_id)
	cfg.set_value(SECTION, "server_url", server_url)
	cfg.set_value(SECTION, "user_id", SupabaseAuth.user_id)
	cfg.save(PATH)


## Empty when there is no record or it belongs to another account on this machine.
static func load_record() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return {}
	var lobby_id := str(cfg.get_value(SECTION, "lobby_id", ""))
	if lobby_id.is_empty() or str(cfg.get_value(SECTION, "user_id", "")) != SupabaseAuth.user_id:
		return {}
	return {
		"lobby_id": lobby_id,
		"server_url": str(cfg.get_value(SECTION, "server_url", "")),
	}


static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
