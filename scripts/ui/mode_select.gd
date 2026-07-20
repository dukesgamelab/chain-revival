extends Control
## Startup screen: choose offline dev or local multiplayer connection test.
##
## Local Multiplayer does NOT start the Node server — run it manually first:
##   cd server && npm run dev

const MAIN_SCENE := "res://scenes/main.tscn"
const SIDE_SELECT_SCENE := "res://scenes/side_select.tscn"
const EDITOR_SCENE := "res://scenes/editor/map_editor.tscn"
const ASSET_ANIM_EDITOR_SCENE := "res://scenes/editor/asset_animation_editor.tscn"
const SOLDIER_PARITY_SCENE := "res://scenes/debug/soldier_faction_parity_validation.tscn"

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
@onready var _editor_button: Button = $Center/Panel/Margin/VBox/EditorButton
@onready var _asset_anim_button: Button = $Center/Panel/Margin/VBox/AssetAnimEditorButton
@onready var _multiplayer_button: Button = $Center/Panel/Margin/VBox/MultiplayerButton
@onready var _soldier_parity_button: Button = $Center/Panel/Margin/VBox/SoldierParityButton
@onready var _hint: Label = $Center/Panel/Margin/VBox/Hint


func _ready() -> void:
	_offline_button.pressed.connect(_on_offline_pressed)
	_editor_button.pressed.connect(_on_editor_pressed)
	_asset_anim_button.pressed.connect(_on_asset_anim_editor_pressed)
	_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	_soldier_parity_button.pressed.connect(_on_soldier_parity_pressed)
	_hint.text = _HINT_DEFAULT


func _on_offline_pressed() -> void:
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_editor_pressed() -> void:
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _on_asset_anim_editor_pressed() -> void:
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	get_tree().change_scene_to_file(ASSET_ANIM_EDITOR_SCENE)


func _on_soldier_parity_pressed() -> void:
	get_tree().change_scene_to_file(SOLDIER_PARITY_SCENE)


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
	_editor_button.disabled = not enabled
	_asset_anim_button.disabled = not enabled
	_multiplayer_button.disabled = not enabled
	_soldier_parity_button.disabled = not enabled
