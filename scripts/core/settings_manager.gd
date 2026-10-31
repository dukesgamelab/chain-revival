extends Node
## Manages display and keybind settings. Persists to user://settings.cfg.

const SETTINGS_PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

const REMAPPABLE_ACTIONS: PackedStringArray = [
	"move_up", "move_down", "move_left", "move_right",
	"rotate_view_left", "rotate_view_right",
]

const ACTION_LABELS := {
	"move_up": "Pan Up",
	"move_down": "Pan Down",
	"move_left": "Pan Left",
	"move_right": "Pan Right",
	"rotate_view_left": "Rotate Left",
	"rotate_view_right": "Rotate Right",
}

const DEFAULT_BINDINGS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"rotate_view_left": [KEY_Q],
	"rotate_view_right": [KEY_E],
}

var fullscreen := false
var vsync := true
var resolution_index := 0
var _keybinds: Dictionary = {}


func _ready() -> void:
	_load_settings()
	_apply_display_settings()
	_apply_keybinds()


func get_bindings(action: String) -> Array:
	if _keybinds.has(action):
		return _keybinds[action]
	if DEFAULT_BINDINGS.has(action):
		return DEFAULT_BINDINGS[action].duplicate()
	return []


func set_binding(action: String, slot: int, keycode: int) -> void:
	var binds: Array = get_bindings(action)
	if slot < binds.size():
		binds[slot] = keycode
	elif slot == binds.size():
		binds.append(keycode)
	_keybinds[action] = binds
	_apply_action_bindings(action)
	save_settings()


func clear_binding(action: String, slot: int) -> void:
	var binds: Array = get_bindings(action)
	if slot < binds.size():
		binds.remove_at(slot)
		_keybinds[action] = binds
		_apply_action_bindings(action)
		save_settings()


func reset_keybinds() -> void:
	_keybinds.clear()
	_apply_keybinds()
	save_settings()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_display_settings()
	save_settings()


func set_vsync(enabled: bool) -> void:
	vsync = enabled
	_apply_display_settings()
	save_settings()


func set_resolution_index(idx: int) -> void:
	resolution_index = clampi(idx, 0, RESOLUTIONS.size() - 1)
	_apply_display_settings()
	save_settings()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "vsync", vsync)
	config.set_value("display", "resolution_index", resolution_index)
	for action in REMAPPABLE_ACTIONS:
		var binds: Array = get_bindings(action)
		var codes: Array[int] = []
		for b in binds:
			codes.append(b as int)
		config.set_value("keybinds", action, codes)
	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	fullscreen = config.get_value("display", "fullscreen", false)
	vsync = config.get_value("display", "vsync", true)
	resolution_index = config.get_value("display", "resolution_index", 0)
	resolution_index = clampi(resolution_index, 0, RESOLUTIONS.size() - 1)
	for action in REMAPPABLE_ACTIONS:
		var saved = config.get_value("keybinds", action, null)
		if saved != null and saved is Array:
			_keybinds[action] = saved


func _apply_display_settings() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var res := RESOLUTIONS[resolution_index]
		DisplayServer.window_set_size(res)
		_center_window()
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _center_window() -> void:
	var screen_size := DisplayServer.screen_get_size()
	var win_size := DisplayServer.window_get_size()
	var pos := (screen_size - win_size) / 2
	DisplayServer.window_set_position(pos)


func _apply_keybinds() -> void:
	for action in REMAPPABLE_ACTIONS:
		_apply_action_bindings(action)


func _apply_action_bindings(action: String) -> void:
	var binds: Array = get_bindings(action)
	InputMap.action_erase_events(action)
	for keycode in binds:
		var ev := InputEventKey.new()
		ev.physical_keycode = keycode as Key
		InputMap.action_add_event(action, ev)


static func key_name(keycode: int) -> String:
	if keycode == 0:
		return "None"
	var k := keycode as Key
	var name := OS.get_keycode_string(k)
	if name != "":
		return name
	return "Key %d" % keycode
