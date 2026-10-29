extends Control
## Online lobby browser for Chain Revival.
##
## Lists waiting lobbies from Supabase, lets the player create or join one.
## Chat is handled by the GlobalChat autoload (always visible on the right).

const MODE_SELECT_SCENE := "res://scenes/mode_select.tscn"
const LOBBY_BROWSER_SCENE := "res://scenes/lobby_browser.tscn"
const SIDE_SELECT_SCENE := "res://scenes/side_select.tscn"
const LEADERBOARD_SCENE := "res://scenes/leaderboard.tscn"
const REGIMENT_SCENE := "res://scenes/regiment_browser.tscn"
const ADMIN_SCENE := "res://scenes/admin_browser.tscn"
const LobbyClientClass := preload("res://scripts/network/lobby_client.gd")
const LeaderboardScript := preload("res://scripts/ui/leaderboard.gd")
const RegimentBrowserScript := preload("res://scripts/ui/regiment_browser.gd")
const AdminBrowserScript := preload("res://scripts/ui/admin_browser.gd")

## Online game server URL (Fly.io).
## Leave empty to fall back to LAN IP detection for local hosting.
const ONLINE_SERVER_URL := "wss://chain-revival-ax0q1g.fly.dev"

var _lobby_client: Node
var _lobby_list_container: VBoxContainer
var _status_label: Label
var _create_button: Button
var _refresh_button: Button
var _leaderboard_button: Button
var _regiments_button: Button
var _admin_button: Button
var _back_button: Button
var _match_name_field: LineEdit
var _create_panel: PanelContainer
var _refresh_timer: Timer

# Hosted game UI
var _hosted_panel: PanelContainer
var _hosted_name_label: Label
var _hosted_status_label: Label
var _hosted_cancel_button: Button
var _waiting_dots := 0

## The lobby we're currently hosting.
var _hosted_lobby_id: String = ""
## The lobby we just joined.
var _joined_lobby: Dictionary = {}


func _ready() -> void:
	CocUiTheme.apply_to(self)
	_lobby_client = LobbyClientClass.new()
	add_child(_lobby_client)
	_build_ui()
	_connect_signals()
	_lobby_client.list_lobbies()

	# Auto-refresh lobbies every 5 seconds.
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 5.0
	_refresh_timer.timeout.connect(_on_auto_refresh)
	add_child(_refresh_timer)
	_refresh_timer.start()


func _exit_tree() -> void:
	if not _hosted_lobby_id.is_empty():
		_lobby_client.delete_lobby(_hosted_lobby_id)


func _process(_delta: float) -> void:
	# Animate waiting dots on the hosted game panel.
	if not _hosted_lobby_id.is_empty() and _hosted_status_label != null:
		var tick := int(Time.get_ticks_msec() / 500) % 4
		if tick != _waiting_dots:
			_waiting_dots = tick
			_hosted_status_label.text = "Waiting for opponent" + ".".repeat(tick)


# ─────────────────────────────────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var outer_panel := PanelContainer.new()
	outer_panel.custom_minimum_size = Vector2(650, 460)
	center.add_child(outer_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	outer_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Online Lobby"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Status
	_status_label = Label.new()
	_status_label.text = "Loading lobbies..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_status_label)

	# ── Hosted game panel (shown when you're hosting) ───────────────────
	_hosted_panel = PanelContainer.new()
	_hosted_panel.visible = false
	vbox.add_child(_hosted_panel)

	var hosted_margin := MarginContainer.new()
	hosted_margin.add_theme_constant_override("margin_left", 12)
	hosted_margin.add_theme_constant_override("margin_top", 8)
	hosted_margin.add_theme_constant_override("margin_right", 12)
	hosted_margin.add_theme_constant_override("margin_bottom", 8)
	_hosted_panel.add_child(hosted_margin)

	var hosted_hbox := HBoxContainer.new()
	hosted_hbox.add_theme_constant_override("separation", 12)
	hosted_margin.add_child(hosted_hbox)

	_hosted_name_label = Label.new()
	_hosted_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hosted_name_label.add_theme_font_size_override("font_size", 14)
	hosted_hbox.add_child(_hosted_name_label)

	_hosted_status_label = Label.new()
	_hosted_status_label.text = "Waiting for opponent..."
	_hosted_status_label.add_theme_font_size_override("font_size", 12)
	_hosted_status_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))
	hosted_hbox.add_child(_hosted_status_label)

	_hosted_cancel_button = Button.new()
	_hosted_cancel_button.text = "Cancel"
	_hosted_cancel_button.custom_minimum_size = Vector2(70, 28)
	_hosted_cancel_button.pressed.connect(_on_cancel_hosted)
	hosted_hbox.add_child(_hosted_cancel_button)

	# ── Lobby list header ───────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var col_name := Label.new()
	col_name.text = "Game"
	col_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_name.add_theme_font_size_override("font_size", 12)
	col_name.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	header.add_child(col_name)

	var col_host := Label.new()
	col_host.text = "Host"
	col_host.custom_minimum_size = Vector2(110, 0)
	col_host.add_theme_font_size_override("font_size", 12)
	col_host.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	header.add_child(col_host)

	var col_players := Label.new()
	col_players.text = "Players"
	col_players.custom_minimum_size = Vector2(60, 0)
	col_players.add_theme_font_size_override("font_size", 12)
	col_players.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	header.add_child(col_players)

	var col_action := Label.new()
	col_action.text = ""
	col_action.custom_minimum_size = Vector2(80, 0)
	header.add_child(col_action)

	# Scrollable lobby list
	var lobby_scroll := ScrollContainer.new()
	lobby_scroll.custom_minimum_size = Vector2(0, 200)
	lobby_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(lobby_scroll)

	_lobby_list_container = VBoxContainer.new()
	_lobby_list_container.add_theme_constant_override("separation", 4)
	_lobby_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_scroll.add_child(_lobby_list_container)

	# ── Create game panel (hidden by default) ───────────────────────────
	_create_panel = PanelContainer.new()
	_create_panel.visible = false
	vbox.add_child(_create_panel)

	var create_margin := MarginContainer.new()
	create_margin.add_theme_constant_override("margin_left", 8)
	create_margin.add_theme_constant_override("margin_top", 8)
	create_margin.add_theme_constant_override("margin_right", 8)
	create_margin.add_theme_constant_override("margin_bottom", 8)
	_create_panel.add_child(create_margin)

	var create_hbox := HBoxContainer.new()
	create_hbox.add_theme_constant_override("separation", 8)
	create_margin.add_child(create_hbox)

	var name_label := Label.new()
	name_label.text = "Game name:"
	name_label.add_theme_font_size_override("font_size", 13)
	create_hbox.add_child(name_label)

	_match_name_field = LineEdit.new()
	_match_name_field.placeholder_text = "%s's Game" % SupabaseAuth.display_name
	_match_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_match_name_field.custom_minimum_size = Vector2(0, 30)
	_match_name_field.add_theme_color_override("font_color", Color.WHITE)
	_match_name_field.add_theme_color_override("font_placeholder_color", Color(0.6, 0.6, 0.6))
	_match_name_field.text_submitted.connect(func(_t: String): _on_confirm_create())
	create_hbox.add_child(_match_name_field)

	var confirm_btn := Button.new()
	confirm_btn.text = "Host"
	confirm_btn.custom_minimum_size = Vector2(60, 30)
	confirm_btn.pressed.connect(_on_confirm_create)
	create_hbox.add_child(confirm_btn)

	var cancel_create_btn := Button.new()
	cancel_create_btn.text = "Cancel"
	cancel_create_btn.custom_minimum_size = Vector2(60, 30)
	cancel_create_btn.pressed.connect(func(): _create_panel.visible = false)
	create_hbox.add_child(cancel_create_btn)

	# ── Bottom buttons ──────────────────────────────────────────────────
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_create_button = Button.new()
	_create_button.text = "Create Game"
	_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_button.custom_minimum_size = Vector2(0, 34)
	btn_row.add_child(_create_button)

	_refresh_button = Button.new()
	_refresh_button.text = "Refresh"
	_refresh_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh_button.custom_minimum_size = Vector2(0, 34)
	btn_row.add_child(_refresh_button)

	_leaderboard_button = Button.new()
	_leaderboard_button.text = "Leaderboard"
	_leaderboard_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leaderboard_button.custom_minimum_size = Vector2(0, 34)
	btn_row.add_child(_leaderboard_button)

	_regiments_button = Button.new()
	_regiments_button.text = "Regiments"
	_regiments_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_regiments_button.custom_minimum_size = Vector2(0, 34)
	btn_row.add_child(_regiments_button)

	# Admin button (only visible for admins)
	if SupabaseAuth.is_admin:
		_admin_button = Button.new()
		_admin_button.text = "Admin"
		_admin_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_admin_button.custom_minimum_size = Vector2(0, 34)
		btn_row.add_child(_admin_button)

	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button.custom_minimum_size = Vector2(0, 34)
	btn_row.add_child(_back_button)


# ─────────────────────────────────────────────────────────────────────────
# Signal wiring
# ─────────────────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	_create_button.pressed.connect(_on_create_pressed)
	_refresh_button.pressed.connect(_on_refresh_pressed)
	_leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	_regiments_button.pressed.connect(_on_regiments_pressed)
	if _admin_button != null:
		_admin_button.pressed.connect(_on_admin_pressed)
	_back_button.pressed.connect(_on_back_pressed)

	_lobby_client.lobbies_listed.connect(_on_lobbies_listed)
	_lobby_client.lobby_created.connect(_on_lobby_created)
	_lobby_client.lobby_joined.connect(_on_lobby_joined)
	_lobby_client.lobby_error.connect(_on_lobby_error)
	_lobby_client.lobby_deleted.connect(_on_lobby_deleted)


# ─────────────────────────────────────────────────────────────────────────
# Lobby button handlers
# ─────────────────────────────────────────────────────────────────────────

func _on_create_pressed() -> void:
	if not _hosted_lobby_id.is_empty():
		_set_status("You already have a game hosted. Cancel it first.", Color.ORANGE)
		return
	_create_panel.visible = true
	_match_name_field.text = ""
	_match_name_field.grab_focus()


func _on_confirm_create() -> void:
	var match_name := _match_name_field.text.strip_edges()
	if match_name.is_empty():
		match_name = "%s's Game" % SupabaseAuth.display_name
	_create_panel.visible = false
	_set_status("Creating lobby...", Color.WHITE)
	var server_url: String
	if ONLINE_SERVER_URL.is_empty():
		# No online server configured; fall back to LAN hosting.
		var lan_ip := _get_lan_ip()
		server_url = "ws://%s:3000" % lan_ip
	else:
		server_url = ONLINE_SERVER_URL
	_lobby_client.create_lobby(match_name, server_url)


func _get_lan_ip() -> String:
	var candidates: Array[String] = []
	for addr in IP.get_local_addresses():
		if ":" in addr:
			continue
		if addr.begins_with("127."):
			continue
		if addr.begins_with("172."):
			continue
		if addr.begins_with("192.168.188.") or addr.begins_with("192.168.228."):
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			candidates.append(addr)
	if not candidates.is_empty():
		return candidates[0]
	return "127.0.0.1"


func _on_refresh_pressed() -> void:
	_set_status("Refreshing...", Color.WHITE)
	_lobby_client.list_lobbies()


func _on_leaderboard_pressed() -> void:
	LeaderboardScript.return_scene = LOBBY_BROWSER_SCENE
	get_tree().change_scene_to_file(LEADERBOARD_SCENE)


func _on_regiments_pressed() -> void:
	RegimentBrowserScript.return_scene = LOBBY_BROWSER_SCENE
	get_tree().change_scene_to_file(REGIMENT_SCENE)


func _on_admin_pressed() -> void:
	AdminBrowserScript.return_scene = LOBBY_BROWSER_SCENE
	get_tree().change_scene_to_file(ADMIN_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MODE_SELECT_SCENE)


func _on_auto_refresh() -> void:
	_lobby_client.list_lobbies()


# ─────────────────────────────────────────────────────────────────────────
# Lobby client callbacks
# ─────────────────────────────────────────────────────────────────────────

func _on_lobbies_listed(lobbies: Array) -> void:
	_clear_lobby_list()

	# If we're hosting, check if someone joined our game.
	if not _hosted_lobby_id.is_empty():
		for lobby_dict in lobbies:
			var lobby: Dictionary = lobby_dict
			if lobby.get("id", "") == _hosted_lobby_id:
				if lobby.get("status", "") == "in_progress":
					_set_status("Opponent joined! Starting match...", Color.GREEN)
					# Use the server_url stored in the lobby record so this
					# works for both LAN (ws://192.168.x.x:3000) and online
					# (wss://railway-host) hosting.
					var host_url: String = lobby.get("server_url", "")
					if host_url.is_empty():
						host_url = "ws://127.0.0.1:3000"
					_start_multiplayer(host_url)
					return

	# Count only waiting lobbies for the status (exclude our own in_progress).
	var waiting_count := 0
	for lobby_dict in lobbies:
		var lobby: Dictionary = lobby_dict
		var status: String = lobby.get("status", "")
		var host_id: String = lobby.get("host_id", "")
		if status == "waiting" and host_id != SupabaseAuth.user_id:
			waiting_count += 1
			_add_lobby_row(lobby)

	if _hosted_lobby_id.is_empty():
		if waiting_count == 0:
			_set_status("No games available. Create one!", Color.WHITE)
		else:
			_set_status("%d game(s) available" % waiting_count, Color.WHITE)


func _on_lobby_created(lobby: Dictionary) -> void:
	_hosted_lobby_id = lobby.get("id", "")
	_set_status("Game created! Waiting for opponent...", Color.GREEN)
	_hosted_panel.visible = true
	_hosted_name_label.text = lobby.get("match_name", "My Game")
	_create_button.disabled = true
	_lobby_client.list_lobbies()


func _on_lobby_joined(lobby: Dictionary) -> void:
	_joined_lobby = lobby
	_set_status("Joined! Starting match...", Color.GREEN)
	var server_url: String = lobby.get("server_url", "")
	if server_url.is_empty():
		server_url = "ws://127.0.0.1:3000"
	_start_multiplayer(server_url)


func _on_lobby_error(msg: String) -> void:
	_set_status(msg, Color.RED)


func _on_lobby_deleted() -> void:
	_hosted_lobby_id = ""
	_hosted_panel.visible = false
	_create_button.disabled = false
	_set_status("Game cancelled.", Color.WHITE)
	_lobby_client.list_lobbies()


func _on_cancel_hosted() -> void:
	if _hosted_lobby_id.is_empty():
		return
	_lobby_client.delete_lobby(_hosted_lobby_id)


# ─────────────────────────────────────────────────────────────────────────
# Lobby list rendering
# ─────────────────────────────────────────────────────────────────────────

func _clear_lobby_list() -> void:
	for child in _lobby_list_container.get_children():
		child.queue_free()


func _add_lobby_row(lobby: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_lobby_list_container.add_child(row)

	var match_name_label := Label.new()
	match_name_label.text = lobby.get("match_name", "Unknown")
	match_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match_name_label.add_theme_font_size_override("font_size", 13)
	row.add_child(match_name_label)

	var host_label := Label.new()
	host_label.text = lobby.get("host_display_name", "???")
	host_label.custom_minimum_size = Vector2(110, 0)
	host_label.add_theme_font_size_override("font_size", 13)
	row.add_child(host_label)

	var current: int = lobby.get("current_players", 1)
	var max_p: int = lobby.get("max_players", 2)
	var players_label := Label.new()
	players_label.text = "%d/%d" % [current, max_p]
	players_label.custom_minimum_size = Vector2(60, 0)
	players_label.add_theme_font_size_override("font_size", 13)
	row.add_child(players_label)

	var lobby_id: String = lobby.get("id", "")
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.custom_minimum_size = Vector2(80, 30)
	join_btn.pressed.connect(_on_join_pressed.bind(lobby_id))
	row.add_child(join_btn)


func _on_join_pressed(lobby_id: String) -> void:
	_set_status("Joining lobby...", Color.WHITE)
	_lobby_client.join_lobby(lobby_id)


# ─────────────────────────────────────────────────────────────────────────
# Game transition
# ─────────────────────────────────────────────────────────────────────────

func _start_multiplayer(server_url: String) -> void:
	_refresh_timer.stop()
	GameModeManager.set_mode(GameMode.LOCAL_MULTIPLAYER)
	NetworkClient.server_url = server_url
	var connected := await NetworkClient.connect_and_wait()
	if not connected:
		_set_status("Could not connect to game server.", Color.RED)
		_refresh_timer.start()
		return
	get_tree().change_scene_to_file(SIDE_SELECT_SCENE)


# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
