class_name GameConfig
extends RefCounted
## Static boot configuration. No networking; mode selection only.

const PROJECT_SETTING_GAME_MODE := "game/mode"
const DEFAULT_GAME_MODE: int = GameMode.OFFLINE_DEV


static func startup_game_mode() -> int:
	if ProjectSettings.has_setting(PROJECT_SETTING_GAME_MODE):
		var configured := int(ProjectSettings.get_setting(PROJECT_SETTING_GAME_MODE))
		if GameMode.is_valid(configured):
			return configured
		push_warning(
			"GameConfig: invalid %s=%s; using OFFLINE_DEV."
			% [PROJECT_SETTING_GAME_MODE, configured]
		)
	return DEFAULT_GAME_MODE
