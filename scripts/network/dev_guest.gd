class_name DevGuest
extends RefCounted
## Development-only guest identity.
##
## Two Godot processes on one PC share user://supabase_session.json, so both
## restore the same account and the game server kicks one of them. This identity
## is created in memory for a single process and is never written to that file.
##
## It turns on only in the editor when res://dev_guest.txt says "on", or when
## the process was started with --dev-guest. Survival builds never enable it.
## A production game server still rejects the id unless ALLOW_DEV_GUESTS=1.

const MARKER_PATH := "res://dev_guest.txt"
const ID_PATTERN := "^dev-guest-[A-Za-z0-9_-]{6,64}$"

static var _enabled: bool = false
static var _resolved: bool = false
static var player_id: String = ""
static var display_name: String = ""


static func is_enabled() -> bool:
	_resolve()
	return _enabled


static func is_valid_player_id(id: String) -> bool:
	var regex := RegEx.new()
	if regex.compile(ID_PATTERN) != OK:
		return false
	return regex.search(id) != null


static func _resolve() -> void:
	if _resolved:
		return
	_resolved = true
	if BuildConfig.is_survival_playtest():
		return
	var from_command := _command_requested()
	var from_file := OS.has_feature("editor") and _file_requested()
	if not from_command and not from_file:
		return
	_enabled = true
	var pid := OS.get_process_id()
	var suffix := "%08x" % (randi() & 0xffffffff)
	player_id = "dev-guest-%d-%s" % [pid, suffix]
	display_name = "Guest %04d" % (pid % 10000)
	GameLog.log_system("[DevGuest] %s (%s). Production sign-in is not used." % [display_name, player_id])


static func _command_requested() -> bool:
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg == "--dev-guest":
			return true
	return false


static func _file_requested() -> bool:
	if not FileAccess.file_exists(MARKER_PATH):
		return false
	var file := FileAccess.open(MARKER_PATH, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#"):
			continue
		return trimmed.to_lower() == "on"
	return false
