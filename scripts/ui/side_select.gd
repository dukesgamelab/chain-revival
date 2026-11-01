extends Control
## Choose USA or Germany after connecting to the local multiplayer server.

const MAIN_SCENE := "res://scenes/main.tscn"
const LOBBY_SCENE := "res://scenes/lobby_browser.tscn"
const MatchConfigClass := preload("res://scripts/core/match_config.gd")
const MatchConfigStoreClass := preload("res://scripts/core/match_config_store.gd")

const _HINT_DEFAULT := "Choose your team."
const _HINT_REQUESTING := "Requesting side from server..."
const _HINT_DENIED := "That side is full. Choose the other team."

@onready var _usa_button: Button = $Center/Panel/Margin/VBox/UsaButton
@onready var _germany_button: Button = $Center/Panel/Margin/VBox/GermanyButton
@onready var _back_button: Button = $Center/Panel/Margin/VBox/BackButton
@onready var _hint: Label = $Center/Panel/Margin/VBox/Hint


func _ready() -> void:
	if BuildConfig.is_survival_playtest():
		get_tree().change_scene_to_file("res://scenes/mode_select.tscn")
		return
	PlayerSides.clear()
	_usa_button.pressed.connect(_on_usa_pressed)
	_germany_button.pressed.connect(_on_germany_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	NetworkClient.connection_changed.connect(_on_connection_changed)
	_update_hint_default()
	if not NetworkClient.is_connected_to_server():
		_hint.text = "Disconnected from server."
		_set_buttons_enabled(false)


func _exit_tree() -> void:
	if NetworkClient.connection_changed.is_connected(_on_connection_changed):
		NetworkClient.connection_changed.disconnect(_on_connection_changed)


func _on_usa_pressed() -> void:
	await _request_side("USA")


func _on_germany_pressed() -> void:
	await _request_side("GERMANY")


func _on_back_pressed() -> void:
	NetworkClient.disconnect_from_server()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_connection_changed(connected: bool) -> void:
	if not connected:
		_hint.text = "Disconnected from server. Returning to lobby..."
		_set_buttons_enabled(false)
		_back_button.disabled = true
		await get_tree().create_timer(1.5).timeout
		get_tree().change_scene_to_file(LOBBY_SCENE)


func _request_side(side_name: String) -> void:
	_set_buttons_enabled(false)
	_back_button.disabled = true
	_hint.text = _HINT_REQUESTING

	var assigned := await NetworkClient.request_side_and_wait(side_name)
	if not assigned or not PlayerSides.has_assignment():
		_hint.text = _HINT_DENIED
		_set_buttons_enabled(true)
		_back_button.disabled = false
		return

	# Wait until the server confirms both sides are filled.
	if not NetworkClient.match_ready_received:
		var ts: int = NetworkClient.selected_team_size
		if ts > 1:
			_hint.text = "Waiting for all players to choose sides..."
		else:
			_hint.text = "Waiting for opponent to choose a side..."
		await NetworkClient.match_ready

	var cfg = MatchConfigClass.default_local_multiplayer_1v1()
	cfg.local_player_id = 1 if PlayerSides.assigned_team_id == Team.USA else 2
	MatchConfigStoreClass.set_pending(cfg)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _set_buttons_enabled(enabled: bool) -> void:
	_usa_button.disabled = not enabled
	_germany_button.disabled = not enabled


func _update_hint_default() -> void:
	var ts: int = NetworkClient.selected_team_size
	if ts > 1:
		_hint.text = "Choose your team (%dv%d). Each side needs %d player(s)." % [ts, ts, ts]
	else:
		_hint.text = _HINT_DEFAULT
