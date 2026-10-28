extends Control
## Startup screen: Single Player / Multiplayer (+ optional Dev tools).

const MAIN_SCENE := "res://scenes/main.tscn"
const MATCH_SETUP_SCENE := "res://scenes/match_setup.tscn"
const SIDE_SELECT_SCENE := "res://scenes/side_select.tscn"
const EDITOR_SCENE := "res://scenes/editor/map_editor.tscn"
const ASSET_ANIM_EDITOR_SCENE := "res://scenes/editor/asset_animation_editor.tscn"
const AUTH_SCREEN_SCENE := "res://scenes/auth_screen.tscn"
const LOBBY_BROWSER_SCENE := "res://scenes/lobby_browser.tscn"
const LEADERBOARD_SCENE := "res://scenes/leaderboard.tscn"
const LeaderboardScript := preload("res://scripts/ui/leaderboard.gd")
const MatchConfigClass := preload("res://scripts/core/match_config.gd")
const MatchConfigStoreClass := preload("res://scripts/core/match_config_store.gd")

@onready var _single_player_button: Button = $Center/Panel/Margin/VBox/SinglePlayerButton
@onready var _multiplayer_button: Button = $Center/Panel/Margin/VBox/MultiplayerButton
@onready var _offline_quick_button: Button = $Center/Panel/Margin/VBox/DevBox/OfflineQuickButton
@onready var _offline_quick_ai_button: Button = $Center/Panel/Margin/VBox/DevBox/OfflineQuickAiButton
@onready var _survival_mode_button: Button = $Center/Panel/Margin/VBox/SurvivalModeButton
@onready var _how_to_play_button: Button = $Center/Panel/Margin/VBox/HowToPlayButton
@onready var _editor_button: Button = $Center/Panel/Margin/VBox/DevBox/EditorButton
@onready var _asset_anim_button: Button = $Center/Panel/Margin/VBox/DevBox/AssetAnimEditorButton

var _how_to_play_dialog: AcceptDialog


var _sign_in_label: Label

func _ready() -> void:
	CocUiTheme.apply_to(self)
	_single_player_button.pressed.connect(_on_single_player_pressed)
	_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	_offline_quick_button.pressed.connect(_on_offline_quick_pressed)
	_offline_quick_ai_button.pressed.connect(_on_offline_quick_ai_pressed)
	_survival_mode_button.pressed.connect(_on_survival_mode_pressed)
	_how_to_play_button.pressed.connect(_on_how_to_play_pressed)
	_editor_button.pressed.connect(_on_editor_pressed)
	_asset_anim_button.pressed.connect(_on_asset_anim_editor_pressed)
	if BuildConfig.is_survival_playtest():
		_apply_survival_playtest_menu()
	_add_auth_ui()
	_add_lan_button()
	_add_leaderboard_button()


func _add_lan_button() -> void:
	var dev_box := get_node_or_null("Center/Panel/Margin/VBox/DevBox") as VBoxContainer
	if dev_box == null:
		return
	var lan_btn := Button.new()
	lan_btn.text = "LAN Multiplayer"
	lan_btn.pressed.connect(_on_lan_multiplayer_pressed)
	dev_box.add_child(lan_btn)


func _add_leaderboard_button() -> void:
	var vbox := get_node_or_null("Center/Panel/Margin/VBox") as VBoxContainer
	if vbox == null:
		return
	var lb_btn := Button.new()
	lb_btn.text = "Leaderboard"
	lb_btn.pressed.connect(_on_leaderboard_pressed)
	# Insert before the DevBox (second-to-last major element)
	var dev_box := get_node_or_null("Center/Panel/Margin/VBox/DevBox") as Control
	if dev_box != null:
		var dev_idx := dev_box.get_index()
		vbox.add_child(lb_btn)
		vbox.move_child(lb_btn, dev_idx)
	else:
		vbox.add_child(lb_btn)


func _on_leaderboard_pressed() -> void:
	LeaderboardScript.return_scene = "res://scenes/mode_select.tscn"
	get_tree().change_scene_to_file(LEADERBOARD_SCENE)


func _add_auth_ui() -> void:
	var vbox := get_node_or_null("Center/Panel/Margin/VBox") as VBoxContainer
	if vbox == null:
		return
	# Add a sign-in/account label and button at the top of the menu
	var auth_box := HBoxContainer.new()
	auth_box.alignment = BoxContainer.ALIGNMENT_CENTER
	auth_box.add_theme_constant_override("separation", 8)
	vbox.add_child(auth_box)
	vbox.move_child(auth_box, 0)  # Put at the very top

	_sign_in_label = Label.new()
	_sign_in_label.add_theme_font_size_override("font_size", 12)
	auth_box.add_child(_sign_in_label)

	var auth_button := Button.new()
	auth_button.add_theme_font_size_override("font_size", 12)
	auth_box.add_child(auth_button)

	if SupabaseAuth.is_signed_in:
		_sign_in_label.text = "Signed in as %s" % SupabaseAuth.display_name
		auth_button.text = "Sign Out"
		auth_button.pressed.connect(func(): SupabaseAuth.sign_out(); get_tree().reload_current_scene())
	else:
		_sign_in_label.text = "Not signed in"
		auth_button.text = "Sign In"
		auth_button.pressed.connect(func(): get_tree().change_scene_to_file(AUTH_SCREEN_SCENE))

	# If session is being restored asynchronously, refresh the UI when it completes.
	if not SupabaseAuth.auth_state_changed.is_connected(_on_auth_state_changed):
		SupabaseAuth.auth_state_changed.connect(_on_auth_state_changed)


func _on_auth_state_changed(_signed_in: bool) -> void:
	get_tree().reload_current_scene()


func _apply_survival_playtest_menu() -> void:
	## Stay on this menu. Survival is the only playable mode.
	if _single_player_button != null:
		_single_player_button.visible = false
	if _multiplayer_button != null:
		_multiplayer_button.visible = false
	var dev_box := get_node_or_null("Center/Panel/Margin/VBox/DevBox") as Control
	if dev_box != null:
		dev_box.visible = false
	if _survival_mode_button != null:
		_survival_mode_button.text = "Play Survival"
	var subtitle := get_node_or_null("Center/Panel/Margin/VBox/Subtitle") as Label
	if subtitle != null:
		subtitle.text = "Survival Playtest"


func _on_single_player_pressed() -> void:
	if BuildConfig.is_survival_playtest():
		return
	_open_match_setup(MatchConfigClass.GameModeKind.SINGLE_PLAYER)


func _on_multiplayer_pressed() -> void:
	if BuildConfig.is_survival_playtest():
		return
	if SupabaseAuth.is_signed_in:
		get_tree().change_scene_to_file(LOBBY_BROWSER_SCENE)
	else:
		get_tree().change_scene_to_file(AUTH_SCREEN_SCENE)


func _on_lan_multiplayer_pressed() -> void:
	if BuildConfig.is_survival_playtest():
		return
	_set_buttons_enabled(false)
	GameModeManager.set_mode(GameMode.LOCAL_MULTIPLAYER)
	var connected := await NetworkClient.connect_and_wait()
	if not connected:
		GameLog.log_system("[ModeSelect] Local multiplayer server is not running.")
		_set_buttons_enabled(true)
		return
	get_tree().change_scene_to_file(SIDE_SELECT_SCENE)


func _open_match_setup(game_mode_kind: int) -> void:
	if BuildConfig.is_survival_playtest():
		return
	PlayerSides.clear()
	MatchConfigStoreClass.set_setup_game_mode(game_mode_kind)
	get_tree().change_scene_to_file(MATCH_SETUP_SCENE)


func _on_offline_quick_pressed() -> void:
	if BuildConfig.is_survival_playtest():
		return
	## Dev hotseat: Farm Fight 1v1, both sides human, no AI.
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	MatchConfigStoreClass.set_pending(MatchConfigClass.default_offline_1v1())
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_offline_quick_ai_pressed() -> void:
	if BuildConfig.is_survival_playtest():
		return
	## Dev: same one-click start as above, but Germany is AI — the hotseat version has no
	## AI on either side, so use this one when testing commander behaviour.
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	MatchConfigStoreClass.set_pending(MatchConfigClass.default_offline_1v1_vs_ai())
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_survival_mode_pressed() -> void:
	## Survival: US human vs recurring GE AI waves on ff_farm_survival.
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	MatchConfigStoreClass.set_pending(MatchConfigClass.default_survival_1v_all())
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_how_to_play_pressed() -> void:
	_ensure_how_to_play_dialog()
	if _how_to_play_dialog != null:
		_how_to_play_dialog.popup_centered()


func _ensure_how_to_play_dialog() -> void:
	if _how_to_play_dialog != null:
		return
	var dlg := AcceptDialog.new()
	dlg.title = "How to Play"
	dlg.ok_button_text = "Close"
	dlg.unresizable = true
	dlg.min_size = Vector2(580, 480)
	CocUiTheme.apply_to(dlg)
	var paper := _how_to_play_paper_style()
	dlg.add_theme_stylebox_override("panel", paper)
	dlg.add_theme_stylebox_override("embedded_border", paper)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 8)
	dlg.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 370)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.custom_minimum_size.x = 520
	scroll.add_child(page)
	_fill_how_to_play_page(page)

	add_child(dlg)
	_how_to_play_dialog = dlg


func _how_to_play_paper_style() -> StyleBoxFlat:
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.94, 0.92, 0.86)
	paper.border_color = Color(0.55, 0.52, 0.46)
	paper.set_border_width_all(1)
	paper.set_content_margin_all(8)
	return paper


func _fill_how_to_play_page(page: VBoxContainer) -> void:
	_howto_heading(page, "Survival")
	_howto_body(
		page,
		"You command a U.S. fireteam on the farm. German squads keep arriving. Hold the field as long as you can.",
	)
	_howto_body(
		page,
		"After you start, pick a difficulty. That only changes how often a new enemy fireteam deploys:",
	)
	_howto_row(page, "Normal", "New squad every 60 seconds")
	_howto_row(page, "Hard", "New squad every 30 seconds")
	_howto_row(page, "A-town", "New squad every 15 seconds")

	_howto_heading(page, "Camera")
	_howto_row(page, "WASD / arrows", "Pan the map")
	_howto_row(page, "Mouse wheel", "Zoom")
	_howto_row(page, "Right-drag or middle-drag", "Pan")
	_howto_row(page, "Q / E", "Rotate the view (or use Rotate Left / Right)")
	_howto_row(page, "Center", "Jump the camera back to your fireteam")

	_howto_heading(page, "Giving Orders")
	_howto_body(
		page,
		"Click a soldier’s row on the bottom bar to select him. The top row issues orders to the whole fireteam.",
	)
	_howto_body(page, "Click a command, then click the map:")
	_howto_row(page, "Fire at", "Click an enemy or tile to shoot")
	_howto_row(page, "Run To / Crawl To", "Click a tile to move")
	_howto_row(page, "Face…", "Click a tile or enemy to turn that way (no shot)")
	_howto_row(page, "Down / Up", "Drop prone or stand up")
	_howto_row(page, "Grenade", "Click a tile within 7 tiles")
	_howto_row(page, "Fire at Will", "Shoot visible enemies automatically")
	_howto_row(page, "Hold Fire", "Stop automatic fire; use Fire at for aimed shots")
	_howto_row(page, "Right-click", "Cancel Fire at, Face, or Grenade targeting")
	_howto_spacer(page)
	_howto_body(page, "Retreat ends the match and concedes the field.")
	_howto_body(
		page,
		"Tips: crawling and going prone help you survive incoming fire. Use cover, and watch ammo on each soldier’s row.",
	)


func _howto_heading(page: VBoxContainer, title: String) -> void:
	if page.get_child_count() > 0:
		_howto_spacer(page)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.18, 0.16, 0.12))
	page.add_child(label)
	var rule := ColorRect.new()
	rule.color = Color(0.62, 0.58, 0.50)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(rule)


func _howto_body(page: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.16, 0.15, 0.12))
	page.add_child(label)


func _howto_row(page: VBoxContainer, action: String, detail: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var key := Label.new()
	key.text = action
	key.custom_minimum_size = Vector2(168, 0)
	key.add_theme_font_size_override("font_size", 13)
	key.add_theme_color_override("font_color", Color(0.22, 0.20, 0.14))
	row.add_child(key)

	var value := Label.new()
	value.text = detail
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_font_size_override("font_size", 13)
	value.add_theme_color_override("font_color", Color(0.16, 0.15, 0.12))
	row.add_child(value)
	page.add_child(row)


func _howto_spacer(page: VBoxContainer) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	page.add_child(spacer)


func _on_editor_pressed() -> void:
	if BuildConfig.is_survival_playtest():
		return
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	MatchConfigStoreClass.clear_pending()
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _on_asset_anim_editor_pressed() -> void:
	if BuildConfig.is_survival_playtest():
		return
	PlayerSides.clear()
	GameModeManager.set_mode(GameMode.OFFLINE_DEV)
	get_tree().change_scene_to_file(ASSET_ANIM_EDITOR_SCENE)


func _set_buttons_enabled(enabled: bool) -> void:
	_single_player_button.disabled = not enabled
	_multiplayer_button.disabled = not enabled
	_offline_quick_button.disabled = not enabled
	_offline_quick_ai_button.disabled = not enabled
	_survival_mode_button.disabled = not enabled
	if _how_to_play_button != null:
		_how_to_play_button.disabled = not enabled
	_editor_button.disabled = not enabled
	_asset_anim_button.disabled = not enabled
