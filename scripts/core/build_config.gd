class_name BuildConfig
extends RefCounted
## Single runtime gate for DEVELOPMENT vs SURVIVAL_PLAYTEST exports.
## Custom feature tag is set only on the Survival Playtest export preset.

const FEATURE_SURVIVAL_PLAYTEST := "survival_playtest"


static func is_survival_playtest() -> bool:
	return OS.has_feature(FEATURE_SURVIVAL_PLAYTEST)


static func is_development() -> bool:
	return not is_survival_playtest()
