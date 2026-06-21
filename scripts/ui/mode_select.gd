extends Control
## Startup screen: choose offline dev or local multiplayer connection test.
##
## Local Multiplayer does NOT start the Node server — run it manually first:
##   cd server && npm run dev

const MAIN_SCENE := "res://scenes/main.tscn"
const SIDE_SELECT_SCENE := "res://scenes/side_select.tscn"

const _HINT_DEFAULT := (
	"Local Multiplayer connects to a server you start manually.\n"
	+ "1. Open a terminal: cd server && npm run dev\n"
	+ "2. Then click Local Multiplayer"
)
const _HINT_CONNECTING := "Connecting to ws://localhost:3000..."
const _HINT_CONNECT_FAILED := (
	"Could not connect to ws://localhost:3000.\n"
	+ "Start the server in a terminal first:\n"
	+ "  cd server\n"
	+ "  npm run dev"
)

@onready var _offline_button: Button = $Center/Panel/Margin/VBox/OfflineButton
@onready var _multiplayer_button: Button = $Center/Panel/Margin/VBox/MultiplayerButton
@onready var _hint: Label = $Center/Panel/Margin/VBox/Hint


func _ready() -> void:
	_offline_button.pressed.connect(_on_offline_pressed)
	_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	_hint.text = _HINT_DEFAULT


func _on_offline_pressed() -> void:
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_multiplayer_pressed() -> void:
	_set_buttons_enabled(false)
	GameModeManager.set_mode(GameMode.LOCAL_MULTIPLAYER)
	_hint.text = _HINT_CONNECTING

	var connected := await NetworkClient.connect_and_wait()
	if connected:
		get_tree().change_scene_to_file(SIDE_SELECT_SCENE)
		return

	_hint.text = _HINT_CONNECT_FAILED
	_set_buttons_enabled(true)


func _set_buttons_enabled(enabled: bool) -> void:
	_offline_button.disabled = not enabled
	_multiplayer_button.disabled = not enabled
