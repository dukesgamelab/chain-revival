class_name MatchConfigStore
extends RefCounted
## Hands a MatchConfig from the menu into gameplay (same pattern as EditorPlaySession).

const MatchConfigScript := preload("res://scripts/core/match_config.gd")
const PENDING_KEY := "pending_match_config"
const SETUP_MODE_KEY := "setup_game_mode_kind"
const STORE_PATH := "user://match_config_session.cfg"


static func set_setup_game_mode(game_mode_kind: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(STORE_PATH)
	cfg.set_value("session", SETUP_MODE_KEY, game_mode_kind)
	cfg.save(STORE_PATH)


static func consume_setup_game_mode(default_kind: int = 0) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(STORE_PATH) != OK:
		return default_kind
	var kind := int(cfg.get_value("session", SETUP_MODE_KEY, default_kind))
	cfg.set_value("session", SETUP_MODE_KEY, default_kind)
	cfg.save(STORE_PATH)
	return kind


static func set_pending(config) -> void:
	var cfg := ConfigFile.new()
	cfg.load(STORE_PATH)
	if config == null:
		cfg.set_value("session", PENDING_KEY, {})
	else:
		cfg.set_value("session", PENDING_KEY, config.to_dict())
	cfg.save(STORE_PATH)


static func peek_pending():
	var cfg := ConfigFile.new()
	if cfg.load(STORE_PATH) != OK:
		return null
	var raw: Variant = cfg.get_value("session", PENDING_KEY, {})
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return null
	return MatchConfigScript.from_dict(raw as Dictionary)


static func consume_pending():
	var pending = peek_pending()
	clear_pending()
	return pending


static func clear_pending() -> void:
	var cfg := ConfigFile.new()
	cfg.load(STORE_PATH)
	cfg.set_value("session", PENDING_KEY, {})
	cfg.save(STORE_PATH)
