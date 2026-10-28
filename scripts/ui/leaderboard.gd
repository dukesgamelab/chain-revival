extends Control
## Leaderboard screen for Chain Revival.
##
## Fetches player_profiles from Supabase sorted by games_won descending.
## Also shows the current player's recent match history if signed in.

const LOBBY_BROWSER_SCENE := "res://scenes/lobby_browser.tscn"
const MODE_SELECT_SCENE := "res://scenes/mode_select.tscn"

## Supabase REST endpoint
const SUPABASE_URL := "https://tnyaqreedvdmyworvqbw.supabase.co"
const SUPABASE_ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRueWFxcmVlZHZkbXl3b3J2cWJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI5NzA5MzQsImV4cCI6MjEwODU0NjkzNH0.z9P6-W9U-NsJYr5TXxeHsc8Z5_flrDZSOqkNNParqPQ"

var _leaderboard_container: VBoxContainer
var _history_container: VBoxContainer
var _back_button: Button
var _tab_bar: TabBar
var _content_stack: Control  # holds both panels; we show/hide by tab
var _leaderboard_panel: Control
var _history_panel: Control
var _status_label: Label

var _lb_http: HTTPRequest
var _hist_http: HTTPRequest
var _lb_fetch_busy := false
var _hist_fetch_busy := false

## Which scene to return to (set before changing to this scene).
## Falls back to mode_select.
static var return_scene: String = ""


func _ready() -> void:
	CocUiTheme.apply_to(self)
	_build_ui()
	_fetch_leaderboard()
	if SupabaseAuth.is_signed_in:
		_fetch_match_history()


# -----------------------------------------------------------------------
# UI construction
# -----------------------------------------------------------------------

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var outer_panel := PanelContainer.new()
	outer_panel.custom_minimum_size = Vector2(700, 500)
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
	title.text = "Leaderboard"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Status
	_status_label = Label.new()
	_status_label.text = "Loading..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_status_label)

	# Tab bar: Leaderboard / My Matches
	_tab_bar = TabBar.new()
	_tab_bar.add_tab("Leaderboard")
	if SupabaseAuth.is_signed_in:
		_tab_bar.add_tab("My Matches")
	_tab_bar.tab_changed.connect(_on_tab_changed)
	vbox.add_child(_tab_bar)

	# Content area
	_content_stack = Control.new()
	_content_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content_stack)

	# Leaderboard panel
	_leaderboard_panel = _build_leaderboard_panel()
	_content_stack.add_child(_leaderboard_panel)

	# History panel
	_history_panel = _build_history_panel()
	_history_panel.visible = false
	_content_stack.add_child(_history_panel)

	# Bottom buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button.custom_minimum_size = Vector2(0, 34)
	_back_button.pressed.connect(_on_back_pressed)
	btn_row.add_child(_back_button)


func _build_leaderboard_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 2)

	# Header row
	var header := _make_lb_row("#", "Player", "Wins", "Played", "Kills", "Win %", true)
	panel.add_child(header)

	# Scrollable list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_leaderboard_container = VBoxContainer.new()
	_leaderboard_container.add_theme_constant_override("separation", 2)
	_leaderboard_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_leaderboard_container)

	return panel


func _build_history_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 2)

	# Header row
	var header := _make_hist_row("Result", "Team", "Kills", "Score", "Opponent", "Date", true)
	panel.add_child(header)

	# Scrollable list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_history_container = VBoxContainer.new()
	_history_container.add_theme_constant_override("separation", 2)
	_history_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_history_container)

	return panel


func _make_lb_row(rank_text: String, name_text: String, wins_text: String,
		played_text: String, kills_text: String, winrate_text: String, is_header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var font_size := 12 if is_header else 13
	var color := Color(0.7, 0.7, 0.7) if is_header else Color.WHITE

	var rank_label := Label.new()
	rank_label.text = rank_text
	rank_label.custom_minimum_size = Vector2(40, 0)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", font_size)
	rank_label.add_theme_color_override("font_color", color)
	row.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", font_size)
	name_label.add_theme_color_override("font_color", color)
	row.add_child(name_label)

	var wins_label := Label.new()
	wins_label.text = wins_text
	wins_label.custom_minimum_size = Vector2(60, 0)
	wins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wins_label.add_theme_font_size_override("font_size", font_size)
	wins_label.add_theme_color_override("font_color", color)
	row.add_child(wins_label)

	var played_label := Label.new()
	played_label.text = played_text
	played_label.custom_minimum_size = Vector2(60, 0)
	played_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	played_label.add_theme_font_size_override("font_size", font_size)
	played_label.add_theme_color_override("font_color", color)
	row.add_child(played_label)

	var kills_label := Label.new()
	kills_label.text = kills_text
	kills_label.custom_minimum_size = Vector2(50, 0)
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_label.add_theme_font_size_override("font_size", font_size)
	kills_label.add_theme_color_override("font_color", color)
	row.add_child(kills_label)

	var winrate_label := Label.new()
	winrate_label.text = winrate_text
	winrate_label.custom_minimum_size = Vector2(60, 0)
	winrate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winrate_label.add_theme_font_size_override("font_size", font_size)
	winrate_label.add_theme_color_override("font_color", color)
	row.add_child(winrate_label)

	return row


func _make_hist_row(result_text: String, team_text: String, kills_text: String,
		score_text: String, opponent_text: String, date_text: String,
		is_header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var font_size := 12 if is_header else 13

	var result_label := Label.new()
	result_label.text = result_text
	result_label.custom_minimum_size = Vector2(70, 0)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", font_size)
	if is_header:
		result_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	elif result_text == "Win":
		result_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	elif result_text == "Loss":
		result_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	else:
		result_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	row.add_child(result_label)

	var team_label := Label.new()
	team_label.text = team_text
	team_label.custom_minimum_size = Vector2(80, 0)
	team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	team_label.add_theme_font_size_override("font_size", font_size)
	team_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7) if is_header else Color.WHITE)
	row.add_child(team_label)

	var kills_label := Label.new()
	kills_label.text = kills_text
	kills_label.custom_minimum_size = Vector2(50, 0)
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_label.add_theme_font_size_override("font_size", font_size)
	kills_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7) if is_header else Color.WHITE)
	row.add_child(kills_label)

	var score_label := Label.new()
	score_label.text = score_text
	score_label.custom_minimum_size = Vector2(80, 0)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", font_size)
	score_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7) if is_header else Color.WHITE)
	row.add_child(score_label)

	var opponent_label := Label.new()
	opponent_label.text = opponent_text
	opponent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opponent_label.add_theme_font_size_override("font_size", font_size)
	opponent_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7) if is_header else Color.WHITE)
	row.add_child(opponent_label)

	var date_label := Label.new()
	date_label.text = date_text
	date_label.custom_minimum_size = Vector2(100, 0)
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date_label.add_theme_font_size_override("font_size", font_size)
	date_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7) if is_header else Color(0.6, 0.6, 0.6))
	row.add_child(date_label)

	return row


# -----------------------------------------------------------------------
# Tab switching
# -----------------------------------------------------------------------

func _on_tab_changed(tab_idx: int) -> void:
	_leaderboard_panel.visible = (tab_idx == 0)
	_history_panel.visible = (tab_idx == 1)


# -----------------------------------------------------------------------
# Supabase fetch: leaderboard
# -----------------------------------------------------------------------

func _fetch_leaderboard() -> void:
	if _lb_fetch_busy:
		return
	_lb_fetch_busy = true

	if _lb_http != null:
		_lb_http.queue_free()

	_lb_http = HTTPRequest.new()
	add_child(_lb_http)
	_lb_http.request_completed.connect(_on_leaderboard_response)

	# Fetch top 50 players sorted by games_won desc, then by games_played asc (fewer games = better)
	var url := "%s/rest/v1/player_profiles?select=display_name,games_won,games_played,total_kills&order=games_won.desc,games_played.asc&limit=50" % SUPABASE_URL
	var hdrs := PackedStringArray([
		"apikey: %s" % SUPABASE_ANON_KEY,
		"Content-Type: application/json",
	])
	_lb_http.request(url, hdrs, HTTPClient.METHOD_GET)


func _on_leaderboard_response(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_lb_fetch_busy = false

	if response_code != 200:
		_status_label.text = "Failed to load leaderboard (HTTP %d)" % response_code
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_status_label.text = "Failed to parse leaderboard data"
		return

	var players: Array = json.data
	_populate_leaderboard(players)
	_status_label.text = "%d players" % players.size()


func _populate_leaderboard(players: Array) -> void:
	# Clear existing rows
	for child in _leaderboard_container.get_children():
		child.queue_free()

	for i in range(players.size()):
		var p: Dictionary = players[i]
		var display_name: String = p.get("display_name", "???")
		var wins: int = int(p.get("games_won", 0))
		var played: int = int(p.get("games_played", 0))
		var kills: int = int(p.get("total_kills", 0))
		var winrate := 0.0
		if played > 0:
			winrate = float(wins) / float(played) * 100.0

		var row := _make_lb_row(
			str(i + 1),
			display_name,
			str(wins),
			str(played),
			str(kills),
			"%.0f%%" % winrate,
			false
		)

		# Highlight current user's row
		if SupabaseAuth.is_signed_in and display_name == SupabaseAuth.display_name:
			for child in row.get_children():
				if child is Label:
					child.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))

		_leaderboard_container.add_child(row)


# -----------------------------------------------------------------------
# Supabase fetch: match history
# -----------------------------------------------------------------------

func _fetch_match_history() -> void:
	if _hist_fetch_busy or not SupabaseAuth.is_signed_in:
		return
	_hist_fetch_busy = true

	if _hist_http != null:
		_hist_http.queue_free()

	_hist_http = HTTPRequest.new()
	add_child(_hist_http)
	_hist_http.request_completed.connect(_on_history_response)

	# Fetch last 20 matches for the current user
	var url := "%s/rest/v1/match_history?player_id=eq.%s&order=played_at.desc&limit=20" % [
		SUPABASE_URL, SupabaseAuth.user_id
	]
	var hdrs := PackedStringArray([
		"apikey: %s" % SUPABASE_ANON_KEY,
		"Content-Type: application/json",
	])
	_hist_http.request(url, hdrs, HTTPClient.METHOD_GET)


func _on_history_response(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_hist_fetch_busy = false

	if response_code != 200:
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return

	var matches: Array = json.data
	_populate_history(matches)


func _populate_history(matches: Array) -> void:
	for child in _history_container.get_children():
		child.queue_free()

	if matches.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No matches yet"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 13)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_history_container.add_child(empty_label)
		return

	# We need opponent names. For now, show opponent_id truncated.
	# A future improvement could join against player_profiles.
	for m in matches:
		var result_text := "Draw"
		if m.get("won", false):
			result_text = "Win"
		elif not m.get("draw", false):
			result_text = "Loss"

		var team_text: String = m.get("team", "?")
		var match_kills: int = int(m.get("kills", 0))
		var total: int = int(m.get("total_points", 0))
		var score_text := str(total) + " pts"

		# Format the date
		var played_at: String = m.get("played_at", "")
		var date_text := _format_date(played_at)

		# Opponent: for now show "Opponent" placeholder.
		# We'd need a separate fetch to resolve opponent_id to display_name.
		var opponent_text := "Opponent"

		var row := _make_hist_row(result_text, team_text, str(match_kills), score_text, opponent_text, date_text, false)
		_history_container.add_child(row)

	# Now fetch opponent names in bulk
	_fetch_opponent_names(matches)


func _format_date(iso_str: String) -> String:
	if iso_str.is_empty():
		return "?"
	# Parse just the date portion: "2026-10-27T20:30:00+00:00" -> "Oct 27"
	var date_part := iso_str.left(10)  # "2026-10-27"
	var parts := date_part.split("-")
	if parts.size() < 3:
		return date_part
	var month_names := ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var month_idx := int(parts[1])
	if month_idx < 1 or month_idx > 12:
		return date_part
	return "%s %s" % [month_names[month_idx], str(int(parts[2]))]


# -----------------------------------------------------------------------
# Opponent name resolution
# -----------------------------------------------------------------------

var _opponent_http: HTTPRequest

func _fetch_opponent_names(matches: Array) -> void:
	# Collect unique opponent IDs
	var opp_ids: Array[String] = []
	for m in matches:
		var opp_id: String = m.get("opponent_id", "")
		if not opp_id.is_empty() and opp_id not in opp_ids:
			opp_ids.append(opp_id)

	if opp_ids.is_empty():
		return

	if _opponent_http != null:
		_opponent_http.queue_free()

	_opponent_http = HTTPRequest.new()
	add_child(_opponent_http)
	_opponent_http.request_completed.connect(
		_on_opponent_names_response.bind(matches)
	)

	# Fetch display_names for all opponent IDs
	var id_filter := "(" + ",".join(opp_ids) + ")"
	var url := "%s/rest/v1/player_profiles?id=in.%s&select=id,display_name" % [
		SUPABASE_URL, id_filter
	]
	var hdrs := PackedStringArray([
		"apikey: %s" % SUPABASE_ANON_KEY,
		"Content-Type: application/json",
	])
	_opponent_http.request(url, hdrs, HTTPClient.METHOD_GET)


func _on_opponent_names_response(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray,
		matches: Array) -> void:
	if response_code != 200:
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return

	# Build ID -> name lookup
	var name_map: Dictionary = {}
	for profile in json.data:
		name_map[profile.get("id", "")] = profile.get("display_name", "???")

	# Re-populate history with resolved names
	for child in _history_container.get_children():
		child.queue_free()

	for m in matches:
		var result_text := "Draw"
		if m.get("won", false):
			result_text = "Win"
		elif not m.get("draw", false):
			result_text = "Loss"

		var team_text: String = m.get("team", "?")
		var match_kills: int = int(m.get("kills", 0))
		var total: int = int(m.get("total_points", 0))
		var score_text := str(total) + " pts"
		var played_at: String = m.get("played_at", "")
		var date_text := _format_date(played_at)

		var opp_id: String = m.get("opponent_id", "")
		var opponent_text: String = name_map.get(opp_id, "Unknown")

		var row := _make_hist_row(result_text, team_text, str(match_kills), score_text, opponent_text, date_text, false)
		_history_container.add_child(row)


# -----------------------------------------------------------------------
# Navigation
# -----------------------------------------------------------------------

func _on_back_pressed() -> void:
	var target := return_scene if not return_scene.is_empty() else MODE_SELECT_SCENE
	return_scene = ""
	get_tree().change_scene_to_file(target)
