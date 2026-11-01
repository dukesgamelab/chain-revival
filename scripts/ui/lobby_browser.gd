extends Control
## Online lobby browser — persistent 8-room grid.
##
## Players see a fixed list of rooms and click "Join Room" to either
## host (opens a briefing dialog) or join an existing game.
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
const MapDataClass := preload("res://scripts/map/map_data.gd")

const ONLINE_SERVER_URL := "wss://chain-revival-ax0q1g.fly.dev"

const ROOM_CONFIG := [
	{"number": 1, "name": "Open Game", "type": "open"},
	{"number": 2, "name": "Open Game", "type": "open"},
	{"number": 3, "name": "Regimental", "type": "regimental"},
	{"number": 4, "name": "Regimental", "type": "regimental"},
	{"number": 5, "name": "Training", "type": "training"},
	{"number": 6, "name": "Regimental", "type": "regimental"},
	{"number": 7, "name": "Regimental", "type": "regimental"},
	{"number": 8, "name": "Open Game", "type": "open"},
]


var _lobby_client: Node
var _status_label: Label
var _refresh_button: Button
var _leaderboard_button: Button
var _regiments_button: Button
var _admin_button: Button
var _back_button: Button
var _refresh_timer: Timer

# Room grid data — keyed by room number (1-8).
# Each entry: { desc_label, type_label, players_label, action_btn, lobby }
var _room_rows: Dictionary = {}

var _hosted_lobby_id: String = ""
var _joined_lobby_id: String = ""
var _active_room_number: int = 0

# Briefing dialog
var _briefing_dialog: Window
var _briefing_room_label: Label
var _briefing_map_dropdown: OptionButton
var _briefing_size_dropdown: OptionButton
var _briefing_length_dropdown: OptionButton
var _briefing_ai_row: HBoxContainer
var _briefing_ai_dropdown: OptionButton
var _briefing_room_number: int = 0
var _briefing_room_type: String = ""


func _ready() -> void:
	CocUiTheme.apply_to(self)
	_lobby_client = LobbyClientClass.new()
	add_child(_lobby_client)
	_build_ui()
	_connect_signals()
	_lobby_client.list_lobbies()

	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 5.0
	_refresh_timer.timeout.connect(_on_auto_refresh)
	add_child(_refresh_timer)
	_refresh_timer.start()


func _exit_tree() -> void:
	if not _hosted_lobby_id.is_empty():
		_lobby_client.delete_lobby(_hosted_lobby_id)
	_joined_lobby_id = ""




# ─────────────────────────────────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -280
	add_child(center)

	var outer_panel := PanelContainer.new()
	outer_panel.custom_minimum_size = Vector2(780, 520)
	center.add_child(outer_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 16)
	outer_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Game Rooms"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	# Status
	_status_label = Label.new()
	_status_label.text = "Loading rooms..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_status_label)

	# Room grid header
	var header := _build_grid_header()
	vbox.add_child(header)

	# Room rows
	for room_cfg in ROOM_CONFIG:
		var row_panel := _build_room_row(room_cfg)
		vbox.add_child(row_panel)

	# Bottom buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

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

	if SupabaseAuth.is_admin or SupabaseAuth.is_moderator:
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

	# Build briefing dialog (hidden until needed)
	_build_briefing_dialog()


func _build_grid_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)

	var hdr_color := Color(0.85, 0.85, 0.85)

	var col_num := Label.new()
	col_num.text = "Room"
	col_num.custom_minimum_size = Vector2(44, 0)
	col_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col_num.add_theme_font_size_override("font_size", 11)
	col_num.add_theme_color_override("font_color", hdr_color)
	header.add_child(col_num)

	var col_desc := Label.new()
	col_desc.text = "Description"
	col_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_desc.add_theme_font_size_override("font_size", 11)
	col_desc.add_theme_color_override("font_color", hdr_color)
	header.add_child(col_desc)

	var col_type := Label.new()
	col_type.text = "Type"
	col_type.custom_minimum_size = Vector2(80, 0)
	col_type.add_theme_font_size_override("font_size", 11)
	col_type.add_theme_color_override("font_color", hdr_color)
	header.add_child(col_type)

	var col_players := Label.new()
	col_players.text = "Players"
	col_players.custom_minimum_size = Vector2(55, 0)
	col_players.add_theme_font_size_override("font_size", 11)
	col_players.add_theme_color_override("font_color", hdr_color)
	header.add_child(col_players)

	var col_action := Label.new()
	col_action.text = ""
	col_action.custom_minimum_size = Vector2(90, 0)
	header.add_child(col_action)

	return header


func _build_room_row(room_cfg: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 30)

	var margin_wrap := MarginContainer.new()
	margin_wrap.add_theme_constant_override("margin_left", 4)
	margin_wrap.add_theme_constant_override("margin_right", 4)
	margin_wrap.add_theme_constant_override("margin_top", 2)
	margin_wrap.add_theme_constant_override("margin_bottom", 2)
	panel.add_child(margin_wrap)

	var inner_row := HBoxContainer.new()
	inner_row.add_theme_constant_override("separation", 4)
	margin_wrap.add_child(inner_row)

	# Room number
	var num_label := Label.new()
	num_label.text = str(room_cfg["number"])
	num_label.custom_minimum_size = Vector2(44, 0)
	num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_label.add_theme_font_size_override("font_size", 12)
	inner_row.add_child(num_label)

	# Description
	var desc_label := Label.new()
	desc_label.text = room_cfg["name"]
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.add_theme_font_size_override("font_size", 12)
	inner_row.add_child(desc_label)

	# Type
	var type_label := Label.new()
	type_label.text = room_cfg["name"]
	type_label.custom_minimum_size = Vector2(80, 0)
	type_label.add_theme_font_size_override("font_size", 11)
	inner_row.add_child(type_label)

	# Players
	var players_label := Label.new()
	players_label.text = "--"
	players_label.custom_minimum_size = Vector2(55, 0)
	players_label.add_theme_font_size_override("font_size", 12)
	inner_row.add_child(players_label)

	# Action button
	var action_btn := Button.new()
	action_btn.text = "Join Room"
	action_btn.custom_minimum_size = Vector2(90, 26)
	action_btn.pressed.connect(_on_room_action.bind(room_cfg["number"]))
	inner_row.add_child(action_btn)

	var rn: int = room_cfg["number"]
	_room_rows[rn] = {
		"panel": panel,
		"desc_label": desc_label,
		"type_label": type_label,
		"players_label": players_label,
		"action_btn": action_btn,
		"lobby": {},
		"config": room_cfg,
	}

	return panel


# ─────────────────────────────────────────────────────────────────────────
# Briefing dialog
# ─────────────────────────────────────────────────────────────────────────

func _build_briefing_dialog() -> void:
	_briefing_dialog = Window.new()
	_briefing_dialog.title = "Skirmish Briefing"
	_briefing_dialog.size = Vector2i(440, 320)
	_briefing_dialog.unresizable = true
	_briefing_dialog.visible = false
	_briefing_dialog.exclusive = true
	_briefing_dialog.transient = true
	_briefing_dialog.close_requested.connect(_close_briefing)
	add_child(_briefing_dialog)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_briefing_dialog.add_child(panel)
	CocUiTheme.apply_to(panel)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 20)
	outer_margin.add_theme_constant_override("margin_top", 16)
	outer_margin.add_theme_constant_override("margin_right", 20)
	outer_margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(outer_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	outer_margin.add_child(vbox)

	# Room label
	_briefing_room_label = Label.new()
	_briefing_room_label.text = "Room 1 — Open Game"
	_briefing_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_briefing_room_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_briefing_room_label)

	var subtitle := Label.new()
	subtitle.text = "Choose your battlefield and deploy."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(subtitle)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Battlefield row
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 8)
	vbox.add_child(map_row)
	var map_label := Label.new()
	map_label.text = "Battlefield:"
	map_label.custom_minimum_size = Vector2(100, 0)
	map_label.add_theme_font_size_override("font_size", 13)
	map_row.add_child(map_label)
	_briefing_map_dropdown = OptionButton.new()
	_briefing_map_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_briefing_map_dropdown.custom_minimum_size = Vector2(0, 30)
	for entry in MapDataClass.MULTIPLAYER_MAPS:
		_briefing_map_dropdown.add_item("%s (%s)" % [entry["display_name"], entry["team_sizes"]])
	_briefing_map_dropdown.item_selected.connect(_on_briefing_map_selected)
	map_row.add_child(_briefing_map_dropdown)

	# Team size row
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	vbox.add_child(size_row)
	var size_label := Label.new()
	size_label.text = "Team Size:"
	size_label.custom_minimum_size = Vector2(100, 0)
	size_label.add_theme_font_size_override("font_size", 13)
	size_row.add_child(size_label)
	_briefing_size_dropdown = OptionButton.new()
	_briefing_size_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_briefing_size_dropdown.custom_minimum_size = Vector2(0, 30)
	size_row.add_child(_briefing_size_dropdown)
	_populate_briefing_team_sizes()

	# Match length row
	var length_row := HBoxContainer.new()
	length_row.add_theme_constant_override("separation", 8)
	vbox.add_child(length_row)
	var length_label := Label.new()
	length_label.text = "Match Length:"
	length_label.custom_minimum_size = Vector2(100, 0)
	length_label.add_theme_font_size_override("font_size", 13)
	length_row.add_child(length_label)
	_briefing_length_dropdown = OptionButton.new()
	_briefing_length_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_briefing_length_dropdown.custom_minimum_size = Vector2(0, 30)
	_briefing_length_dropdown.add_item("10 minutes")
	_briefing_length_dropdown.add_item("15 minutes")
	_briefing_length_dropdown.add_item("20 minutes")
	_briefing_length_dropdown.select(1)
	length_row.add_child(_briefing_length_dropdown)

	# AI difficulty row (Training rooms only)
	_briefing_ai_row = HBoxContainer.new()
	_briefing_ai_row.add_theme_constant_override("separation", 8)
	_briefing_ai_row.visible = false
	vbox.add_child(_briefing_ai_row)
	var ai_label := Label.new()
	ai_label.text = "AI Difficulty:"
	ai_label.custom_minimum_size = Vector2(100, 0)
	ai_label.add_theme_font_size_override("font_size", 13)
	_briefing_ai_row.add_child(ai_label)
	_briefing_ai_dropdown = OptionButton.new()
	_briefing_ai_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_briefing_ai_dropdown.custom_minimum_size = Vector2(0, 30)
	_briefing_ai_dropdown.add_item("Easy")
	_briefing_ai_dropdown.add_item("Normal")
	_briefing_ai_dropdown.add_item("Hard")
	_briefing_ai_dropdown.select(1)
	_briefing_ai_row.add_child(_briefing_ai_dropdown)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var enter_btn := Button.new()
	enter_btn.text = "Enter Battlefield"
	enter_btn.custom_minimum_size = Vector2(140, 34)
	enter_btn.pressed.connect(_on_briefing_confirm)
	btn_row.add_child(enter_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(80, 34)
	cancel_btn.pressed.connect(_close_briefing)
	btn_row.add_child(cancel_btn)


func _open_briefing(room_number: int) -> void:
	_briefing_room_number = room_number
	var room_cfg: Dictionary = {}
	for cfg in ROOM_CONFIG:
		if cfg["number"] == room_number:
			room_cfg = cfg
			break
	_briefing_room_type = room_cfg.get("type", "open")
	_briefing_room_label.text = "Room %d — %s" % [room_number, room_cfg.get("name", "Game")]
	_briefing_map_dropdown.select(0)
	_populate_briefing_team_sizes()
	_briefing_length_dropdown.select(1)
	_briefing_ai_row.visible = _briefing_room_type == "training"
	if _briefing_ai_row.visible:
		_briefing_ai_dropdown.select(1)
	_briefing_dialog.popup_centered()


func _close_briefing() -> void:
	_briefing_dialog.visible = false
	_briefing_room_number = 0


func _on_briefing_map_selected(_idx: int) -> void:
	_populate_briefing_team_sizes()


func _populate_briefing_team_sizes() -> void:
	_briefing_size_dropdown.clear()
	var map_idx := _briefing_map_dropdown.selected
	if map_idx < 0 or map_idx >= MapDataClass.MULTIPLAYER_MAPS.size():
		_briefing_size_dropdown.add_item("1v1")
		return
	var sizes: Array = MapDataClass.MULTIPLAYER_MAPS[map_idx].get("supported_sizes", [1])
	for s: int in sizes:
		_briefing_size_dropdown.add_item("%dv%d" % [s, s])


func _get_briefing_team_size() -> int:
	var map_idx := _briefing_map_dropdown.selected
	if map_idx < 0 or map_idx >= MapDataClass.MULTIPLAYER_MAPS.size():
		return 1
	var sizes: Array = MapDataClass.MULTIPLAYER_MAPS[map_idx].get("supported_sizes", [1])
	var size_idx := _briefing_size_dropdown.selected
	if size_idx < 0 or size_idx >= sizes.size():
		return 1
	return sizes[size_idx]


func _on_briefing_confirm() -> void:
	var room_number := _briefing_room_number
	var map_idx := _briefing_map_dropdown.selected
	var map_id := "ff_farm"
	if map_idx >= 0 and map_idx < MapDataClass.MULTIPLAYER_MAPS.size():
		map_id = MapDataClass.MULTIPLAYER_MAPS[map_idx]["id"]
	var team_size := _get_briefing_team_size()
	var match_name := "%s's Game" % SupabaseAuth.display_name
	_active_room_number = room_number
	_close_briefing()
	_set_status("Creating game in Room %d..." % room_number, Color.WHITE)
	_lobby_client.create_lobby(match_name, ONLINE_SERVER_URL, map_id, team_size, room_number)


# ─────────────────────────────────────────────────────────────────────────
# Signal wiring
# ─────────────────────────────────────────────────────────────────────────

func _connect_signals() -> void:
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
# Room action handler
# ─────────────────────────────────────────────────────────────────────────

func _on_room_action(room_number: int) -> void:
	var room_data: Dictionary = _room_rows.get(room_number, {})
	var lobby: Dictionary = room_data.get("lobby", {})

	# Check if this is the player's own room — "Leave" action
	if not lobby.is_empty():
		var host_id: String = lobby.get("host_id", "")
		var lobby_id: String = lobby.get("id", "")
		var is_mine := host_id == SupabaseAuth.user_id or lobby_id == _joined_lobby_id
		if is_mine:
			_on_cancel_hosted()
			return

	# Guard: can't join another room while in one
	if not _hosted_lobby_id.is_empty() or not _joined_lobby_id.is_empty():
		_set_status("Leave your current room first.", Color.ORANGE)
		return

	if lobby.is_empty():
		_open_briefing(room_number)
	else:
		var status: String = lobby.get("status", "")
		if status == "waiting":
			var lobby_id: String = lobby.get("id", "")
			_active_room_number = room_number
			_set_status("Joining Room %d..." % room_number, Color.WHITE)
			_lobby_client.join_lobby(lobby_id)
		else:
			_set_status("That room has a match in progress.", Color.ORANGE)


# ─────────────────────────────────────────────────────────────────────────
# Button handlers
# ─────────────────────────────────────────────────────────────────────────

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
	# Recover hosted lobby ID if we lost track (e.g., scene reload, quit while hosting)
	if _hosted_lobby_id.is_empty() and _joined_lobby_id.is_empty():
		for lobby_dict in lobbies:
			var lobby: Dictionary = lobby_dict
			if lobby.get("host_id", "") == SupabaseAuth.user_id and lobby.get("status", "") == "waiting":
				_hosted_lobby_id = lobby.get("id", "")
				var rn_val = lobby.get("room_number", 0)
				_active_room_number = int(rn_val) if rn_val != null else 0
				break

	# Build room_number -> lobby lookup
	var room_to_lobby: Dictionary = {}
	for lobby_dict in lobbies:
		var lobby: Dictionary = lobby_dict
		var rn_val = lobby.get("room_number", 0)
		var rn: int = int(rn_val) if rn_val != null else 0
		if rn >= 1 and rn <= 8:
			room_to_lobby[rn] = lobby

	# Update each room row
	for room_cfg in ROOM_CONFIG:
		var rn: int = room_cfg["number"]
		var lobby: Dictionary = room_to_lobby.get(rn, {})
		_update_room_row(rn, lobby)

	# Check if our hosted/joined lobby transitioned to in_progress
	var my_lobby_id := _hosted_lobby_id if not _hosted_lobby_id.is_empty() else _joined_lobby_id
	if not my_lobby_id.is_empty():
		var found := false
		for lobby_dict in lobbies:
			var lobby: Dictionary = lobby_dict
			if lobby.get("id", "") == my_lobby_id:
				found = true
				var current: int = lobby.get("current_players", 1)
				var max_p: int = lobby.get("max_players", 2)
				if lobby.get("status", "") == "in_progress":
					_set_status("All players joined! Starting match...", Color.GREEN)
					var host_url: String = lobby.get("server_url", "")
					if host_url.is_empty():
						host_url = "ws://127.0.0.1:3000"
					var lobby_map: String = lobby.get("map_id", "")
					var lobby_team_size: int = lobby.get("team_size", 1)
					_start_multiplayer(host_url, lobby_map, lobby_team_size)
					return
				else:
					_set_status("Waiting for players (%d/%d)..." % [current, max_p], Color.GREEN)
				break
		if not found and not _joined_lobby_id.is_empty():
			_joined_lobby_id = ""
			_set_status("The lobby was cancelled by the host.", Color.ORANGE)

	# Update status for empty state
	if _hosted_lobby_id.is_empty() and _joined_lobby_id.is_empty():
		var waiting_count := 0
		for rn: int in _room_rows:
			var lobby: Dictionary = _room_rows[rn].get("lobby", {})
			if not lobby.is_empty() and lobby.get("status", "") == "waiting":
				var host_id: String = lobby.get("host_id", "")
				if host_id != SupabaseAuth.user_id:
					waiting_count += 1
		if waiting_count > 0:
			_set_status("%d room(s) with games waiting" % waiting_count, Color.WHITE)
		else:
			_set_status("All rooms open. Pick a room to start a game.", Color.WHITE)


func _update_room_row(room_number: int, lobby: Dictionary) -> void:
	var row_data: Dictionary = _room_rows.get(room_number, {})
	if row_data.is_empty():
		return

	row_data["lobby"] = lobby
	var desc_label: Label = row_data["desc_label"]
	var type_label: Label = row_data["type_label"]
	var players_label: Label = row_data["players_label"]
	var action_btn: Button = row_data["action_btn"]
	var room_cfg: Dictionary = row_data["config"]

	if lobby.is_empty():
		# Empty room
		desc_label.text = room_cfg["name"]
		type_label.text = room_cfg["name"]
		players_label.text = "--"
		action_btn.text = "Join Room"
		action_btn.disabled = false
	else:
		var status: String = lobby.get("status", "waiting")
		var host_id: String = lobby.get("host_id", "")
		var lobby_id: String = lobby.get("id", "")
		var is_mine: bool = host_id == SupabaseAuth.user_id or lobby_id == _joined_lobby_id
		var current: int = lobby.get("current_players", 1)
		var max_p: int = lobby.get("max_players", 2)
		var ts: int = lobby.get("team_size", 1)

		# Description
		if status == "in_progress":
			desc_label.text = "Match in progress"
		elif is_mine:
			desc_label.text = "%s — %s" % [room_cfg["name"], lobby.get("match_name", "My Game")]
		else:
			desc_label.text = "%s — %s" % [room_cfg["name"], lobby.get("host_display_name", "Waiting")]

		# Type column — show team size format
		type_label.text = "%dv%d" % [ts, ts]

		# Players
		players_label.text = "%d/%d" % [current, max_p]

		# Action button
		if is_mine:
			action_btn.text = "Leave"
			action_btn.disabled = false
		elif status == "waiting":
			action_btn.text = "Join Room"
			action_btn.disabled = false
		else:
			action_btn.text = "In Game"
			action_btn.disabled = true


func _on_lobby_created(lobby: Dictionary) -> void:
	_hosted_lobby_id = lobby.get("id", "")
	var max_p: int = lobby.get("max_players", 2)
	_set_status("Game created! Waiting for players (1/%d)..." % max_p, Color.GREEN)
	_lobby_client.list_lobbies()


func _on_lobby_joined(lobby: Dictionary) -> void:
	var status: String = lobby.get("status", "waiting")
	if status == "in_progress":
		_set_status("Joined! Starting match...", Color.GREEN)
		var server_url: String = lobby.get("server_url", "")
		if server_url.is_empty():
			server_url = "ws://127.0.0.1:3000"
		var lobby_map: String = lobby.get("map_id", "")
		var lobby_team_size: int = lobby.get("team_size", 1)
		_start_multiplayer(server_url, lobby_map, lobby_team_size)
	else:
		_joined_lobby_id = lobby.get("id", "")
		var current: int = lobby.get("current_players", 1)
		var max_p: int = lobby.get("max_players", 2)
		_set_status("Joined! Waiting for players (%d/%d)..." % [current, max_p], Color.GREEN)
		_lobby_client.list_lobbies()


func _on_lobby_error(msg: String) -> void:
	if "409" in msg:
		_set_status("Room already taken! Pick another room.", Color.ORANGE)
	else:
		_set_status(msg, Color.RED)


func _on_lobby_deleted() -> void:
	_hosted_lobby_id = ""
	_active_room_number = 0
	_set_status("Left the room.", Color.WHITE)
	_lobby_client.list_lobbies()


func _on_cancel_hosted() -> void:
	if not _joined_lobby_id.is_empty():
		_joined_lobby_id = ""
		_active_room_number = 0
		_set_status("Left the room.", Color.WHITE)
		_lobby_client.list_lobbies()
		return
	if _hosted_lobby_id.is_empty():
		return
	_lobby_client.delete_lobby(_hosted_lobby_id)


# ─────────────────────────────────────────────────────────────────────────
# Game transition
# ─────────────────────────────────────────────────────────────────────────

func _start_multiplayer(server_url: String, map_id: String = "", team_size: int = 1) -> void:
	_refresh_timer.stop()
	GameModeManager.set_mode(GameMode.LOCAL_MULTIPLAYER)
	NetworkClient.disconnect_from_server()
	NetworkClient.server_url = server_url
	NetworkClient.selected_map_id = map_id
	NetworkClient.selected_team_size = team_size
	var room_type := _get_room_type(_active_room_number)
	NetworkClient.is_training = room_type == "training"
	var connected := await NetworkClient.connect_and_wait()
	if not connected:
		_set_status("Could not connect to game server.", Color.RED)
		_refresh_timer.start()
		return
	get_tree().change_scene_to_file(SIDE_SELECT_SCENE)


# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

func _get_room_type(room_number: int) -> String:
	for cfg in ROOM_CONFIG:
		if cfg["number"] == room_number:
			return cfg["type"]
	return "open"


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


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
