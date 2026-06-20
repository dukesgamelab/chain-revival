class_name GameMode
extends RefCounted
## High-level session type: offline development vs future local multiplayer.

enum Mode { OFFLINE_DEV, LOCAL_MULTIPLAYER }

const OFFLINE_DEV := Mode.OFFLINE_DEV
const LOCAL_MULTIPLAYER := Mode.LOCAL_MULTIPLAYER


static func display_name(mode: int) -> String:
	match mode:
		LOCAL_MULTIPLAYER:
			return "LOCAL_MULTIPLAYER"
		_:
			return "OFFLINE_DEV"


static func is_valid(mode: int) -> bool:
	return mode == OFFLINE_DEV or mode == LOCAL_MULTIPLAYER
