extends Control
## Admin panel for Chain Revival moderation tools.
##
## Accessible from the lobby browser (admin only).
## Provides player search, ban/unban management, and a list of banned players.

const MODE_SELECT_SCENE := "res://scenes/mode_select.tscn"
const RegimentClientClass := preload("res://scripts/network/regiment_client.gd")
const ONLINE_SERVER_URL := "wss://chain-revival-ax0q1g.fly.dev"

const RANK_LABELS := ["PVT", "PFC", "CPL", "SGT", "SSG", "SFC", "MSG", "2LT", "1LT", "CPT"]

var _regiment_client: Node
var _kick_socket: WebSocketPeer
var _kick_target_id: String = ""
var _kick_reason: String = ""
var _kick_state: String = "" # "", "connecting", "authing", "kicking", "done"
var _status_label: Label
var _search_input: LineEdit
var _reason_input: LineEdit
var _results_container: VBoxContainer
var _tab_bar: TabBar
var _search_section: VBoxContainer
var _banned_section: VBoxContainer
var _banned_container: VBoxContainer

## Which scene to return to.
static var return_scene: String = ""


func _ready() -> void:
	CocUiTheme.apply_to(self)
	if not SupabaseAuth.is_admin:
		get_tree().change_scene_to_file(return_scene if not return_scene.is_empty() else MODE_SELECT_SCENE)
		return

	_regiment_client = RegimentClientClass.new()
	add_child(_regiment_client)

	_regiment_client.player_search_results.connect(_on_player_search_results)
	_regiment_client.player_banned.connect(_on_player_banned)
	_regiment_client.player_unbanned.connect(_on_player_unbanned)
	_regiment_client.banned_list_loaded.connect(_on_banned_list_loaded)
	_regiment_client.regiment_error.connect(_on_error)

	_build_ui()
	_regiment_client.list_banned_players()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 450)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Admin Panel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Status
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	vbox.add_child(_status_label)

	# Tabs
	_tab_bar = TabBar.new()
	_tab_bar.add_tab("Search Players")
	_tab_bar.add_tab("Banned Players")
	_tab_bar.tab_changed.connect(_on_tab_changed)
	vbox.add_child(_tab_bar)

	# Search Players section
	_search_section = VBoxContainer.new()
	_search_section.add_theme_constant_override("separation", 6)
	_search_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_search_section)

	# Search row
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	_search_section.add_child(search_row)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search by player name..."
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.add_theme_font_size_override("font_size", 13)
	_search_input.add_theme_color_override("font_color", Color.WHITE)
	_search_input.text_submitted.connect(func(_t: String): _on_search_pressed())
	search_row.add_child(_search_input)

	var search_btn := Button.new()
	search_btn.text = "Search"
	search_btn.custom_minimum_size = Vector2(70, 0)
	search_btn.pressed.connect(_on_search_pressed)
	search_row.add_child(search_btn)

	# Reason row
	var reason_row := HBoxContainer.new()
	reason_row.add_theme_constant_override("separation", 8)
	_search_section.add_child(reason_row)

	var reason_lbl := Label.new()
	reason_lbl.text = "Ban reason:"
	reason_lbl.custom_minimum_size = Vector2(80, 0)
	reason_lbl.add_theme_font_size_override("font_size", 12)
	reason_row.add_child(reason_lbl)

	_reason_input = LineEdit.new()
	_reason_input.placeholder_text = "Required before banning"
	_reason_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reason_input.add_theme_font_size_override("font_size", 12)
	_reason_input.add_theme_color_override("font_color", Color.WHITE)
	reason_row.add_child(_reason_input)

	# Results scroll
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_search_section.add_child(scroll)

	_results_container = VBoxContainer.new()
	_results_container.add_theme_constant_override("separation", 4)
	_results_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_results_container)

	# Banned Players section (hidden by default)
	_banned_section = VBoxContainer.new()
	_banned_section.add_theme_constant_override("separation", 6)
	_banned_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_banned_section.visible = false
	vbox.add_child(_banned_section)

	var banned_scroll := ScrollContainer.new()
	banned_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	banned_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_banned_section.add_child(banned_scroll)

	_banned_container = VBoxContainer.new()
	_banned_container.add_theme_constant_override("separation", 4)
	_banned_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banned_scroll.add_child(_banned_container)

	# Bottom buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_btn.custom_minimum_size = Vector2(0, 34)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	btn_row.add_child(refresh_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.custom_minimum_size = Vector2(0, 34)
	back_btn.pressed.connect(_on_back_pressed)
	btn_row.add_child(back_btn)


# ─────────────────────────────────────────────────────────────────────────
# Tab switching
# ─────────────────────────────────────────────────────────────────────────

func _on_tab_changed(tab_idx: int) -> void:
	_search_section.visible = (tab_idx == 0)
	_banned_section.visible = (tab_idx == 1)
	if tab_idx == 1:
		_regiment_client.list_banned_players()


# ─────────────────────────────────────────────────────────────────────────
# Search and ban actions
# ─────────────────────────────────────────────────────────────────────────

func _on_search_pressed() -> void:
	var query := _search_input.text.strip_edges()
	if query.is_empty():
		_status_label.text = "Enter a player name to search."
		return
	_status_label.text = "Searching..."
	_regiment_client.search_players(query)


func _on_kick_pressed(player_id: String) -> void:
	if _kick_state != "":
		_status_label.text = "Kick already in progress..."
		return
	var reason := _reason_input.text.strip_edges()
	if reason.is_empty():
		reason = "Kicked by admin"
	_kick_target_id = player_id
	_kick_reason = reason
	_kick_state = "connecting"
	_status_label.text = "Connecting to game server..."

	# Open a temporary WebSocket to the game server
	_kick_socket = WebSocketPeer.new()
	var tls_opts: TLSOptions = null
	if ONLINE_SERVER_URL.begins_with("wss://"):
		tls_opts = TLSOptions.client()
	var err := _kick_socket.connect_to_url(ONLINE_SERVER_URL, tls_opts)
	if err != OK:
		_status_label.text = "Failed to connect to game server."
		_kick_state = ""
		_kick_socket = null
		return
	set_process(true)


func _process(_delta: float) -> void:
	if _kick_socket == null or _kick_state == "":
		set_process(false)
		return

	_kick_socket.poll()
	var state := _kick_socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		# Read any incoming messages
		while _kick_socket.get_available_packet_count() > 0:
			var text := _kick_socket.get_packet().get_string_from_utf8()
			var json := JSON.new()
			if json.parse(text) == OK and json.data is Dictionary:
				var msg: Dictionary = json.data
				if msg.get("type", "") == "welcome" and _kick_state == "authing":
					# Authenticated, now send the kick
					_kick_state = "kicking"
					_kick_socket.send_text(JSON.stringify({
						"type": "kick_player",
						"targetUserId": _kick_target_id,
						"reason": _kick_reason,
					}))
				elif msg.get("type", "") == "kick_result":
					var success: bool = bool(msg.get("success", false))
					if success:
						_status_label.text = "Player kicked."
					else:
						_status_label.text = "Kick failed: %s" % str(msg.get("reason", "unknown"))
					_finish_kick()
					return

		# Send hello on first open
		if _kick_state == "connecting":
			_kick_state = "authing"
			var hello := {
				"type": "hello",
				"clientName": "AdminKick",
				"authToken": SupabaseAuth.access_token,
				"isAdmin": true,
			}
			_kick_socket.send_text(JSON.stringify(hello))

	elif state == WebSocketPeer.STATE_CLOSED or state == WebSocketPeer.STATE_CLOSING:
		if _kick_state != "":
			_status_label.text = "Lost connection to game server."
			_finish_kick()


func _finish_kick() -> void:
	if _kick_socket != null:
		if _kick_socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_kick_socket.close()
		_kick_socket = null
	_kick_state = ""
	_kick_target_id = ""
	_kick_reason = ""
	set_process(false)


func _on_ban_pressed(player_id: String) -> void:
	var reason := _reason_input.text.strip_edges()
	if reason.is_empty():
		_status_label.text = "Enter a ban reason first."
		return
	_status_label.text = "Banning player..."
	_regiment_client.ban_player(player_id, reason)


func _on_unban_pressed(player_id: String) -> void:
	_status_label.text = "Unbanning player..."
	_regiment_client.unban_player(player_id)


# ─────────────────────────────────────────────────────────────────────────
# Data callbacks
# ─────────────────────────────────────────────────────────────────────────

func _on_player_search_results(players: Array) -> void:
	_clear_container(_results_container)

	if players.is_empty():
		_add_empty_label(_results_container, "No players found")
		_status_label.text = ""
		return

	# Header
	_results_container.add_child(_make_player_row("Player", "Rank", "PP", "Status", true))

	for p in players:
		var player_id: String = str(p.get("id", ""))
		var name_text: String = str(p.get("display_name", "???"))
		var player_rank: int = int(p.get("rank", 0))
		var rank_text: String = RANK_LABELS[clampi(player_rank, 0, RANK_LABELS.size() - 1)]
		var pp_text: String = str(int(p.get("prestige_points", 0)))
		var banned: bool = bool(p.get("is_banned", false))
		var player_is_admin: bool = bool(p.get("is_admin", false))
		var match_id_val = p.get("active_match_id", null)
		var in_game: bool = match_id_val != null and str(match_id_val) != "" and str(match_id_val) != "null"
		var status_text := "BANNED" if banned else ("In Game" if in_game else "Online")

		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)

		card.add_child(_make_player_row(name_text, rank_text, pp_text, status_text, false, banned, in_game))

		# Action buttons (no actions on other admins)
		if not player_is_admin:
			var btn_row := HBoxContainer.new()
			btn_row.add_theme_constant_override("separation", 6)
			card.add_child(btn_row)

			if banned:
				var unban_btn := Button.new()
				unban_btn.text = "Unban"
				unban_btn.custom_minimum_size = Vector2(70, 24)
				unban_btn.add_theme_font_size_override("font_size", 11)
				unban_btn.pressed.connect(_on_unban_pressed.bind(player_id))
				btn_row.add_child(unban_btn)
			else:
				var ban_btn := Button.new()
				ban_btn.text = "Ban"
				ban_btn.custom_minimum_size = Vector2(70, 24)
				ban_btn.add_theme_font_size_override("font_size", 11)
				ban_btn.pressed.connect(_on_ban_pressed.bind(player_id))
				btn_row.add_child(ban_btn)

			# Kick button (only shown when player is in a game)
			if in_game:
				var kick_btn := Button.new()
				kick_btn.text = "Kick"
				kick_btn.custom_minimum_size = Vector2(70, 24)
				kick_btn.add_theme_font_size_override("font_size", 11)
				kick_btn.pressed.connect(_on_kick_pressed.bind(player_id))
				btn_row.add_child(kick_btn)

		card.add_child(HSeparator.new())
		_results_container.add_child(card)

	_status_label.text = "%d player(s) found" % players.size()


func _on_banned_list_loaded(players: Array) -> void:
	_clear_container(_banned_container)

	if players.is_empty():
		_add_empty_label(_banned_container, "No banned players")
		return

	_banned_container.add_child(_make_player_row("Player", "Reason", "Banned", "", true))

	for p in players:
		var player_id: String = str(p.get("id", ""))
		var name_text: String = str(p.get("display_name", "???"))
		var reason_text: String = str(p.get("ban_reason", ""))
		var banned_at: String = str(p.get("banned_at", ""))
		var date_text := _format_date(banned_at)

		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)

		card.add_child(_make_player_row(name_text, reason_text, date_text, "", false, true))

		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 6)
		card.add_child(btn_row)

		var unban_btn := Button.new()
		unban_btn.text = "Unban"
		unban_btn.custom_minimum_size = Vector2(70, 24)
		unban_btn.add_theme_font_size_override("font_size", 11)
		unban_btn.pressed.connect(_on_unban_pressed.bind(player_id))
		btn_row.add_child(unban_btn)

		card.add_child(HSeparator.new())
		_banned_container.add_child(card)


func _on_player_banned() -> void:
	_status_label.text = "Player banned."
	_reason_input.text = ""
	if not _search_input.text.strip_edges().is_empty():
		_regiment_client.search_players(_search_input.text.strip_edges())
	else:
		_regiment_client.list_banned_players()


func _on_player_unbanned() -> void:
	_status_label.text = "Player unbanned."
	if not _search_input.text.strip_edges().is_empty():
		_regiment_client.search_players(_search_input.text.strip_edges())
	_regiment_client.list_banned_players()


func _on_error(msg: String) -> void:
	_status_label.text = "Error: %s" % msg


# ─────────────────────────────────────────────────────────────────────────
# Navigation
# ─────────────────────────────────────────────────────────────────────────

func _on_refresh_pressed() -> void:
	if _tab_bar.current_tab == 0 and not _search_input.text.strip_edges().is_empty():
		_regiment_client.search_players(_search_input.text.strip_edges())
	else:
		_regiment_client.list_banned_players()


func _on_back_pressed() -> void:
	var target := return_scene if not return_scene.is_empty() else MODE_SELECT_SCENE
	return_scene = ""
	get_tree().change_scene_to_file(target)


# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

func _make_player_row(col1: String, col2: String, col3: String, col4: String,
		is_header: bool, is_banned: bool = false, is_in_game: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var font_size := 11 if is_header else 12
	var color := Color(0.6, 0.6, 0.6) if is_header else Color.WHITE

	var lbl1 := Label.new()
	lbl1.text = col1
	lbl1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl1.add_theme_font_size_override("font_size", font_size)
	lbl1.add_theme_color_override("font_color", color)
	row.add_child(lbl1)

	var lbl2 := Label.new()
	lbl2.text = col2
	lbl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl2.add_theme_font_size_override("font_size", font_size)
	lbl2.add_theme_color_override("font_color", color)
	row.add_child(lbl2)

	var lbl3 := Label.new()
	lbl3.text = col3
	lbl3.custom_minimum_size = Vector2(60, 0)
	lbl3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl3.add_theme_font_size_override("font_size", font_size)
	lbl3.add_theme_color_override("font_color", color)
	row.add_child(lbl3)

	if col4 != "":
		var lbl4 := Label.new()
		lbl4.text = col4
		lbl4.custom_minimum_size = Vector2(60, 0)
		lbl4.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl4.add_theme_font_size_override("font_size", font_size)
		if not is_header:
			var status_color := Color(0.4, 0.9, 0.4) # Active/Online
			if is_banned:
				status_color = Color(0.9, 0.3, 0.3) # Banned
			elif is_in_game:
				status_color = Color(1.0, 0.85, 0.3) # In Game (yellow)
			lbl4.add_theme_color_override("font_color", status_color)
		else:
			lbl4.add_theme_color_override("font_color", color)
		row.add_child(lbl4)

	return row


func _add_empty_label(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	container.add_child(label)


func _clear_container(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()


func _format_date(iso_str: String) -> String:
	if iso_str.is_empty():
		return "?"
	var date_part := iso_str.left(10)
	var parts := date_part.split("-")
	if parts.size() < 3:
		return date_part
	var month_names := ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var month_idx := int(parts[1])
	if month_idx < 1 or month_idx > 12:
		return date_part
	return "%s %s" % [month_names[month_idx], str(int(parts[2]))]
