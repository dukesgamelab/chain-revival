extends RefCounted
## Remembers the multiplayer match this client is in, so a relaunched game can rejoin it.

const PATH := "user://rejoin.cfg"
const SECTION := "match"
## Server holds a disconnected slot for 90s; a record not refreshed for longer is dead.
const STALE_AFTER_SEC := 100
const TOUCH_INTERVAL_SEC := 10

static var _last_touch_unix: int = 0


static func save(lobby_id: String, server_url: String) -> void:
	if lobby_id.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "lobby_id", lobby_id)
	cfg.set_value(SECTION, "server_url", server_url)
	cfg.set_value(SECTION, "user_id", SupabaseAuth.user_id)
	cfg.set_value(SECTION, "last_seen", int(Time.get_unix_time_from_system()))
	cfg.save(PATH)


## Called while connected to a live match so the record stays fresh.
static func touch() -> void:
	var now := int(Time.get_unix_time_from_system())
	if now - _last_touch_unix < TOUCH_INTERVAL_SEC:
		return
	_last_touch_unix = now
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	cfg.set_value(SECTION, "last_seen", now)
	cfg.save(PATH)


## Empty when there is no record, it belongs to another account on this machine, or the
## game has been away longer than the server's reconnect window.
static func load_record() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return {}
	var lobby_id := str(cfg.get_value(SECTION, "lobby_id", ""))
	if lobby_id.is_empty() or str(cfg.get_value(SECTION, "user_id", "")) != SupabaseAuth.user_id:
		return {}
	var last_seen := int(cfg.get_value(SECTION, "last_seen", 0))
	if int(Time.get_unix_time_from_system()) - last_seen > STALE_AFTER_SEC:
		clear()
		return {}
	return {
		"lobby_id": lobby_id,
		"server_url": str(cfg.get_value(SECTION, "server_url", "")),
	}


static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
