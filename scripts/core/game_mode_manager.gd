extends Node
## Autoload: current game mode for offline dev vs local multiplayer connection tests.

var current_mode: int = GameConfig.DEFAULT_GAME_MODE


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
	GameLog.log_system("[GameMode] Switched to %s." % GameMode.display_name(current_mode))


func is_offline_dev() -> bool:
	return current_mode == GameMode.OFFLINE_DEV


func is_local_multiplayer() -> bool:
	return current_mode == GameMode.LOCAL_MULTIPLAYER
