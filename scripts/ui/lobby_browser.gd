extends Control
## Online lobby browser with integrated chat for Chain Revival.
##
## Lists waiting lobbies from Supabase, lets the player create or join one.
## Includes a global chat panel at the bottom.

const MODE_SELECT_SCENE := "res://scenes/mode_select.tscn"
const SIDE_SELECT_SCENE := "res://scenes/side_select.tscn"
const LobbyClientClass := preload("res://scripts/network/lobby_client.gd")

var _lobby_client: Node  # LobbyClientClass instance
var _lobby_list_container: VBoxContainer
var _status_label: Label
var _create_button: Button
var _refresh_button: Button
var _back_button: Button
var _match_name_field: LineEdit
var _create_panel: PanelContainer
var _refresh_timer: Timer

# Chat UI
var _chat_messages_container: VBoxContainer
var _chat_scroll: ScrollContainer
var _chat_input: LineEdit
var _chat_send_button: Button
var _chat_timer: Timer
var _last_chat_timestamp: String = ""
var _seen_chat_ids: Dictionary = {}

## The lobby we're currently hosting (waiting for an opponent).
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
	_lobby_client.fetch_chat_messages()

	# Auto-refresh lobbies every 5 seconds.
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 5.0
	_refresh_timer.timeout.connect(_on_auto_refresh)
	add_child(_refresh_timer)
	_refresh_timer.start()

	# Poll chat every 3 seconds.
	_chat_timer = Timer.new()
	_chat_timer.wait_time = 3.0
	_chat_timer.timeout.connect(_on_chat_poll)
	add_child(_chat_timer)
	_chat_timer.start()


func _exit_tree() -> void:
	# Clean up hosted lobby if we leave without starting.
	if not _hosted_lobby_id.is_empty():
		_lobby_client.delete_lobby(_hosted_lobby_id)


# ─────────────────────────────────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var outer_panel := PanelContainer.new()
	outer_panel.custom_minimum_size = Vector2(600, 520)
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

	# Lobby list header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var col_name := Label.new()
	col_name.text = "Game"
	col_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_name.add_theme_font_size_override("font_size", 12)
	header.add_child(col_name)

	var col_host := Label.new()
	col_host.text = "Host"
	col_host.custom_minimum_size = Vector2(120, 0)
	col_host.add_theme_font_size_override("font_size", 12)
	header.add_child(col_host)

	var col_action := Label.new()
	col_action.text = ""
	col_action.custom_minimum_size = Vector2(80, 0)
	header.add_child(col_action)

	# Scrollable lobby list
	var lobby_scroll := ScrollContainer.new()
	lobby_scroll.custom_minimum_size = Vector2(0, 120)
	lobby_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(lobby_scroll)

	_lobby_list_container = VBoxContainer.new()
	_lobby_list_container.add_theme_constant_override("separation", 4)
	_lobby_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_scroll.add_child(_lobby_list_container)

	# Create game panel (hidden by default)
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
	create_hbox.add_child(_match_name_field)

	var confirm_btn := Button.new()
	confirm_btn.text = "Host"
	confirm_btn.custom_minimum_size = Vector2(60, 30)
	confirm_btn.pressed.connect(_on_confirm_create)
	create_hbox.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(60, 30)
	cancel_btn.pressed.connect(func(): _create_panel.visible = false)
	create_hbox.add_child(cancel_btn)

	# ── Chat panel ──────────────────────────────────────────────────────
	var chat_label := Label.new()
	chat_label.text = "Chat"
	chat_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(chat_label)

	_chat_scroll = ScrollContainer.new()
	_chat_scroll.custom_minimum_size = Vector2(0, 100)
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_chat_scroll)

	_chat_messages_container = VBoxContainer.new()
	_chat_messages_container.add_theme_constant_override("separation", 2)
	_chat_messages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_scroll.add_child(_chat_messages_container)

	var chat_input_row := HBoxContainer.new()
	chat_input_row.add_theme_constant_override("separation", 6)
	vbox.add_child(chat_input_row)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Type a message..."
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.custom_minimum_size = Vector2(0, 28)
	chat_input_row.add_child(_chat_input)

	_chat_send_button = Button.new()
	_chat_send_button.text = "Send"
	_chat_send_button.custom_minimum_size = Vector2(60, 28)
	chat_input_row.add_child(_chat_send_button)

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
	_back_button.pressed.connect(_on_back_pressed)
	_chat_send_button.pressed.connect(_on_chat_send_pressed)
	_chat_input.text_submitted.connect(_on_chat_text_submitted)

	_lobby_client.lobbies_listed.connect(_on_lobbies_listed)
	_lobby_client.lobby_created.connect(_on_lobby_created)
	_lobby_client.lobby_joined.connect(_on_lobby_joined)
	_lobby_client.lobby_error.connect(_on_lobby_error)
	_lobby_client.lobby_deleted.connect(_on_lobby_deleted)
	_lobby_client.chat_messages_received.connect(_on_chat_messages_received)


# ─────────────────────────────────────────────────────────────────────────
# Chat handlers
# ─────────────────────────────────────────────────────────────────────────

func _on_chat_send_pressed() -> void:
	_submit_chat()


func _on_chat_text_submitted(_text: String) -> void:
	_submit_chat()


func _submit_chat() -> void:
	var msg := _chat_input.text.strip_edges()
	if msg.is_empty():
		return
	_chat_input.text = ""
	_chat_input.grab_focus()
	_lobby_client.send_chat_message(msg)
	# Immediately poll to show our own message faster.
	await get_tree().create_timer(0.3).timeout
	_lobby_client.fetch_chat_messages(_last_chat_timestamp)


func _on_chat_poll() -> void:
	_lobby_client.fetch_chat_messages(_last_chat_timestamp)


func _on_chat_messages_received(messages: Array) -> void:
	if messages.is_empty():
		return
	var added := false
	for msg_dict in messages:
		var msg: Dictionary = msg_dict
		var msg_id: String = msg.get("id", "")
		if msg_id.is_empty() or _seen_chat_ids.has(msg_id):
			continue
		_seen_chat_ids[msg_id] = true
		added = true

		var display_name: String = msg.get("display_name", "???")
		var text: String = msg.get("message", "")
		var timestamp: String = msg.get("created_at", "")

		var line := Label.new()
		line.text = "[%s] %s" % [display_name, text]
		line.add_theme_font_size_override("font_size", 12)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_chat_messages_container.add_child(line)

		if not timestamp.is_empty():
			_last_chat_timestamp = timestamp
	if not added:
		return

	# Keep chat from growing forever (cap at 100 messages visible).
	while _chat_messages_container.get_child_count() > 100:
		var oldest := _chat_messages_container.get_child(0)
		_chat_messages_container.remove_child(oldest)
		oldest.queue_free()

	# Auto-scroll to bottom.
	await get_tree().process_frame
	_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


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
	# Detect the host's LAN IP so other players can connect.
	var lan_ip := _get_lan_ip()
	var server_url := "ws://%s:3000" % lan_ip
	_lobby_client.create_lobby(match_name, server_url)


func _get_lan_ip() -> String:
	# Find the LAN IP, skipping virtual adapters (VMware, Hyper-V, etc.).
	# VMware uses 192.168.188.x and 192.168.228.x; Hyper-V uses 172.x.
	var candidates: Array[String] = []
	for addr in IP.get_local_addresses():
		if ":" in addr:
			continue  # skip IPv6
		if addr.begins_with("127."):
			continue
		if addr.begins_with("172."):
			continue  # Hyper-V / Docker
		if addr.begins_with("192.168.188.") or addr.begins_with("192.168.228."):
			continue  # VMware
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			candidates.append(addr)
	if not candidates.is_empty():
		return candidates[0]
	# Fallback to localhost.
	return "127.0.0.1"


func _on_refresh_pressed() -> void:
	_set_status("Refreshing...", Color.WHITE)
	_lobby_client.list_lobbies()


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
					# Host always connects to localhost since the server is on this machine.
					_start_multiplayer("ws://127.0.0.1:3000")
					return

	if lobbies.is_empty():
		_set_status("No games available. Create one!", Color.WHITE)
		return
	_set_status("%d game(s) waiting" % lobbies.size(), Color.WHITE)
	for lobby_dict in lobbies:
		var lobby: Dictionary = lobby_dict
		_add_lobby_row(lobby)


func _on_lobby_created(lobby: Dictionary) -> void:
	_hosted_lobby_id = lobby.get("id", "")
	_set_status("Game created! Waiting for opponent...", Color.GREEN)
	_create_button.text = "Cancel Game"
	_create_button.pressed.disconnect(_on_create_pressed)
	_create_button.pressed.connect(_on_cancel_hosted)
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
	_create_button.text = "Create Game"
	if _create_button.pressed.is_connected(_on_cancel_hosted):
		_create_button.pressed.disconnect(_on_cancel_hosted)
	if not _create_button.pressed.is_connected(_on_create_pressed):
		_create_button.pressed.connect(_on_create_pressed)
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
	host_label.custom_minimum_size = Vector2(120, 0)
	host_label.add_theme_font_size_override("font_size", 13)
	row.add_child(host_label)

	var lobby_id: String = lobby.get("id", "")
	var host_id: String = lobby.get("host_id", "")

	if host_id == SupabaseAuth.user_id:
		var waiting_label := Label.new()
		waiting_label.text = "Waiting..."
		waiting_label.custom_minimum_size = Vector2(80, 0)
		waiting_label.add_theme_font_size_override("font_size", 12)
		waiting_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
		row.add_child(waiting_label)
	else:
		var join_btn := Button.new()
		join_btn.text = "Join"
		join_btn.custom_minimum_size = Vector2(80, 28)
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
	_chat_timer.stop()
	GameModeManager.set_mode(GameMode.LOCAL_MULTIPLAYER)
	NetworkClient.server_url = server_url
	var connected := await NetworkClient.connect_and_wait()
	if not connected:
		_set_status("Could not connect to game server.", Color.RED)
		return
	get_tree().change_scene_to_file(SIDE_SELECT_SCENE)


# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
