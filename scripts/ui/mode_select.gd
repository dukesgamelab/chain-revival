extends Control
## Startup screen: Single Player / Multiplayer / Quit (+ optional Dev tools).

const MAIN_SCENE := "res://scenes/main.tscn"
const MATCH_SETUP_SCENE := "res://scenes/match_setup.tscn"
const EDITOR_SCENE := "res://scenes/editor/map_editor.tscn"
const ASSET_ANIM_EDITOR_SCENE := "res://scenes/editor/asset_animation_editor.tscn"
const SOLDIER_PARITY_SCENE := "res://scenes/debug/soldier_faction_parity_validation.tscn"
const MatchConfigClass := preload("res://scripts/core/match_config.gd")
const MatchConfigStoreClass := preload("res://scripts/core/match_config_store.gd")

const _HINT_DEFAULT := (
	"Single Player and Multiplayer open Match Setup (1v1 / 2v2).\n"
	+ "Dev: Offline Quick Start = human hotseat 1v1 (press 1/2 to switch). AI is Single Player only.\n"
	+ "Survival Mode: 1 v All = US vs recurring German waves on ff_farm_survival."
)
const _HINT_CONNECTING := "Connecting to ws://localhost:3000..."
const _HINT_CONNECT_FAILED := (
	"Could not connect to ws://localhost:3000.\n"
	+ "Start the server in a terminal first:\n"
	+ "  cd server\n"
	+ "  npm run dev"
)

@onready var _single_player_button: Button = $Center/Panel/Margin/VBox/SinglePlayerButton
@onready var _multiplayer_button: Button = $Center/Panel/Margin/VBox/MultiplayerButton
@onready var _quit_button: Button = $Center/Panel/Margin/VBox/QuitButton
@onready var _offline_quick_button: Button = $Center/Panel/Margin/VBox/DevBox/OfflineQuickButton
@onready var _survival_mode_button: Button = $Center/Panel/Margin/VBox/DevBox/SurvivalModeButton
@onready var _editor_button: Button = $Center/Panel/Margin/VBox/DevBox/EditorButton
@onready var _asset_anim_button: Button = $Center/Panel/Margin/VBox/DevBox/AssetAnimEditorButton
@onready var _soldier_parity_button: Button = $Center/Panel/Margin/VBox/DevBox/SoldierParityButton
@onready var _hint: Label = $Center/Panel/Margin/VBox/Hint


func _ready() -> void:
	CocUiTheme.apply_to(self)
	_single_player_button.pressed.connect(_on_single_player_pressed)
	_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_offline_quick_button.pressed.connect(_on_offline_quick_pressed)
	_survival_mode_button.pressed.connect(_on_survival_mode_pressed)
	_editor_button.pressed.connect(_on_editor_pressed)
	_asset_anim_button.pressed.connect(_on_asset_anim_editor_pressed)
	_soldier_parity_button.pressed.connect(_on_soldier_parity_pressed)
	_hint.text = _HINT_DEFAULT


func _on_single_player_pressed() -> void:
	_open_match_setup(MatchConfigClass.GameModeKind.SINGLE_PLAYER)


func _on_multiplayer_pressed() -> void:
	_set_buttons_enabled(false)
	_hint.text = _HINT_CONNECTING
	## Networking not required for Phase 1 config — still attempt connect for existing flow,
	## then open Match Setup (Open slots). Failures fall back to setup anyway.
	GameModeManager.set_mode(GameMode.LOCAL_MULTIPLAYER)
	var connected := await NetworkClient.connect_and_wait()
	if not connected:
		_hint.text = _HINT_CONNECT_FAILED + "\nOpening Match Setup with Open slots anyway."
	_open_match_setup(MatchConfigClass.GameModeKind.MULTIPLAYER)
	_set_buttons_enabled(true)


func _open_match_setup(game_mode_kind: int) -> void:
	PlayerSides.clear()
	MatchConfigStoreClass.set_setup_game_mode(game_mode_kind)
	get_tree().change_scene_to_file(MATCH_SETUP_SCENE)


func _on_offline_quick_pressed() -> void:
	## Dev hotseat: Farm Fight 1v1, both sides human, no AI.
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	MatchConfigStoreClass.set_pending(MatchConfigClass.default_offline_1v1())
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_survival_mode_pressed() -> void:
	## Survival: US human vs recurring GE AI waves on ff_farm_survival.
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	MatchConfigStoreClass.set_pending(MatchConfigClass.default_survival_1v_all())
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_editor_pressed() -> void:
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	MatchConfigStoreClass.clear_pending()
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _on_asset_anim_editor_pressed() -> void:
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	get_tree().change_scene_to_file(ASSET_ANIM_EDITOR_SCENE)


func _on_soldier_parity_pressed() -> void:
	get_tree().change_scene_to_file(SOLDIER_PARITY_SCENE)


func _set_buttons_enabled(enabled: bool) -> void:
	_single_player_button.disabled = not enabled
	_multiplayer_button.disabled = not enabled
	_quit_button.disabled = not enabled
	_offline_quick_button.disabled = not enabled
	_survival_mode_button.disabled = not enabled
	_editor_button.disabled = not enabled
	_asset_anim_button.disabled = not enabled
	_soldier_parity_button.disabled = not enabled
