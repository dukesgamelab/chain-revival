extends Node
## Autoload: current game mode for offline dev vs local multiplayer connection tests.

var current_mode: int = GameConfig.DEFAULT_GAME_MODE
## Host/offline runs AI Commanders. LOCAL_MULTIPLAYER clients never tick AI.
var _ai_authority: bool = true


func _ready() -> void:
	current_mode = GameConfig.startup_game_mode()
	GameLog.log_system(
		"[GameMode] Chain Revival running in %s (mode=%d)."
		% [GameMode.display_name(current_mode), current_mode]
	)


func get_mode() -> int:
	return current_mode


func set_mode(mode: int) -> void:
	if not GameMode.is_valid(mode):
		push_warning("GameModeManager: ignored invalid mode %s" % mode)
		return
	if current_mode == mode:
		return
	current_mode = mode
	## Thin clients never tick AI. Offline / single-player keep host authority.
	_ai_authority = mode != GameMode.LOCAL_MULTIPLAYER
	GameLog.log_system("[GameMode] Switched to %s." % GameMode.display_name(current_mode))


func is_offline_dev() -> bool:
	return current_mode == GameMode.OFFLINE_DEV


func is_local_multiplayer() -> bool:
	return current_mode == GameMode.LOCAL_MULTIPLAYER


## True when this process may execute AI (authoritative host/server).
func is_ai_authority() -> bool:
	return _ai_authority


func set_ai_authority(enabled: bool) -> void:
	_ai_authority = enabled
