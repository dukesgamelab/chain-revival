class_name GameConfig
extends RefCounted
## Static boot configuration. No networking; mode selection only.

const PROJECT_SETTING_GAME_MODE := "game/mode"
const PROJECT_SETTING_HOTSEAT := "game/hotseat"
const PROJECT_SETTING_AI_VERBOSE := "game/ai_verbose"
const PROJECT_SETTING_COMBAT_VERBOSE := "game/combat_verbose"
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


## Explicit hotseat: both sides human, AI off. Not inferred from OFFLINE_DEV.
## Enable with `--hotseat` on the command line, or project setting `game/hotseat`.
static func hotseat_enabled() -> bool:
	return _cmdline_or_setting_flag("--hotseat", PROJECT_SETTING_HOTSEAT)


## Log every successful AI command (pid, soldier, type, target). Off by default.
static func ai_verbose_enabled() -> bool:
	return _cmdline_or_setting_flag("--ai-verbose", PROJECT_SETTING_AI_VERBOSE)


## Log per-shot hit breakdown (base/cover/move/stress/final/lethality). Off by default.
static func combat_verbose_enabled() -> bool:
	return _cmdline_or_setting_flag("--combat-verbose", PROJECT_SETTING_COMBAT_VERBOSE)


static func _cmdline_or_setting_flag(flag: String, setting_key: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if str(arg) == flag:
			return true
	for arg in OS.get_cmdline_args():
		if str(arg) == flag:
			return true
	if ProjectSettings.has_setting(setting_key):
		return bool(ProjectSettings.get_setting(setting_key))
	return false
