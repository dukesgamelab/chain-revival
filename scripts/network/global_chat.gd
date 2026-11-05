extends Node
## Chat overlay for Chain Revival.
##
## Autoload that places a chat panel on top of every screen via CanvasLayer.
## Supports multiple channels: Global (always), Regiment (if in one),
## and custom player-created channels.
## Whispers display across all channel tabs.

const CHAT_PANEL_WIDTH := 420
const CHAT_PANEL_MARGIN_TOP := 80
const CHAT_PANEL_MARGIN_BOTTOM := 20
const CHAT_PANEL_MARGIN_RIGHT := 20
const MAX_VISIBLE_MESSAGES := 100
const MAX_MESSAGE_LENGTH := 200
const SEND_COOLDOWN_SEC := 2.0

const HIDDEN_SCENES := [
	"res://scenes/main.tscn",
	"res://scenes/side_select.tscn",
]

var _canvas_layer: CanvasLayer
var _root_control: Control
var _outer_panel: PanelContainer
var _chat_scroll: ScrollContainer
var _chat_messages_container: VBoxContainer
var _chat_input: LineEdit
var _chat_send_button: Button
var _toggle_button: Button
var _reopen_button: Button
var _channel_tab_row: HBoxContainer

var _is_open: bool = true
var _unread_count: int = 0

var _http_fetch: HTTPRequest
var _http_send: HTTPRequest
var _http_channels: HTTPRequest
var _http_whispers: HTTPRequest
var _http_lookup: HTTPRequest
var _http_batch_lookup: HTTPRequest
var _fetch_busy: bool = false
var _channels_busy: bool = false
var _pending_whisper_msg: String = ""
var _pending_whisper_target: String = ""
var _visibility_check_queued: bool = false
var _subscribed: bool = false
var _send_cooldown: float = 0.0

## Channel data: [{id, name, type}, ...]
var _channels: Array = []
var _active_channel_id: String = ""

## Per-channel message storage: { channel_id: [msg_dict, ...] }
var _channel_messages: Dictionary = {}
## Whisper messages (shown in all tabs)
var _whisper_messages: Array = []
var _seen_ids: Dictionary = {}

## Per-channel unread counts: { channel_id: int }
var _channel_unread: Dictionary = {}

## Tab button references: { channel_id: Button }
var _tab_buttons: Dictionary = {}

## Cache of user_id -> display_name for whisper targets
var _display_name_cache: Dictionary = {}

## All players for whisper suggestions: { user_id: display_name }
var _all_players: Dictionary = {}
var _players_loaded: bool = false
var _http_players: HTTPRequest

var _suggestion_panel: PanelContainer
var _suggestion_list: VBoxContainer

var _http_create_channel: HTTPRequest
var _http_join_channel: HTTPRequest
var _http_leave_channel: HTTPRequest
var _http_list_channels: HTTPRequest
var _http_delete_channel: HTTPRequest
var _channel_dialog: PanelContainer
var _channel_dialog_vbox: VBoxContainer
var _channel_name_input: LineEdit
var _joinable_list: VBoxContainer


func _ready() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	add_child(_canvas_layer)

	_build_ui()
	_setup_http()

	SupabaseAuth.auth_state_changed.connect(_on_auth_changed)
	get_tree().tree_changed.connect(_on_tree_changed)
	_update_visibility()


func _setup_http() -> void:
	_http_fetch = HTTPRequest.new()
	_http_fetch.request_completed.connect(_on_fetch_response)
	add_child(_http_fetch)

	_http_send = HTTPRequest.new()
	_http_send.request_completed.connect(_on_send_response)
	add_child(_http_send)

	_http_channels = HTTPRequest.new()
	_http_channels.request_completed.connect(_on_channels_response)
	add_child(_http_channels)

	_http_whispers = HTTPRequest.new()
	_http_whispers.request_completed.connect(_on_whispers_response)
	add_child(_http_whispers)

	_http_lookup = HTTPRequest.new()
	_http_lookup.request_completed.connect(_on_lookup_response)
	add_child(_http_lookup)

	_http_batch_lookup = HTTPRequest.new()
	_http_batch_lookup.request_completed.connect(_on_batch_lookup_response)
	add_child(_http_batch_lookup)

	_http_players = HTTPRequest.new()
	_http_players.request_completed.connect(_on_players_response)
	add_child(_http_players)

	_http_create_channel = HTTPRequest.new()
	_http_create_channel.request_completed.connect(_on_create_channel_response)
	add_child(_http_create_channel)

	_http_join_channel = HTTPRequest.new()
	_http_join_channel.request_completed.connect(_on_join_channel_response)
	add_child(_http_join_channel)

	_http_leave_channel = HTTPRequest.new()
	_http_leave_channel.request_completed.connect(_on_leave_channel_response)
	add_child(_http_leave_channel)

	_http_list_channels = HTTPRequest.new()
	_http_list_channels.request_completed.connect(_on_list_channels_response)
	add_child(_http_list_channels)

	_http_delete_channel = HTTPRequest.new()
	_http_delete_channel.request_completed.connect(_on_delete_channel_response)
	add_child(_http_delete_channel)


# ─────────────────────────────────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root_control = Control.new()
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_root_control)

	# Small button shown when chat is minimized
	_reopen_button = Button.new()
	_reopen_button.text = "Chat"
	_reopen_button.add_theme_font_size_override("font_size", 18)
	_reopen_button.custom_minimum_size = Vector2(80, 36)
	_reopen_button.anchor_left = 1.0
	_reopen_button.anchor_right = 1.0
	_reopen_button.anchor_top = 0.0
	_reopen_button.offset_left = -(80 + CHAT_PANEL_MARGIN_RIGHT)
	_reopen_button.offset_right = -CHAT_PANEL_MARGIN_RIGHT
	_reopen_button.offset_top = CHAT_PANEL_MARGIN_TOP
	_reopen_button.visible = false
	_reopen_button.pressed.connect(_on_toggle_pressed)
	_root_control.add_child(_reopen_button)

	_outer_panel = PanelContainer.new()
	_outer_panel.anchor_left = 1.0
	_outer_panel.anchor_right = 1.0
	_outer_panel.anchor_top = 0.0
	_outer_panel.anchor_bottom = 1.0
	_outer_panel.offset_left = -(CHAT_PANEL_WIDTH + CHAT_PANEL_MARGIN_RIGHT)
	_outer_panel.offset_right = -CHAT_PANEL_MARGIN_RIGHT
	_outer_panel.offset_top = CHAT_PANEL_MARGIN_TOP
	_outer_panel.offset_bottom = -CHAT_PANEL_MARGIN_BOTTOM
	_root_control.add_child(_outer_panel)

	CocUiTheme.apply_to(_outer_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_outer_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Header row
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 4)
	vbox.add_child(header_row)

	var title_label := Label.new()
	title_label.text = "Chat"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 22)
	header_row.add_child(title_label)

	var add_channel_button := Button.new()
	add_channel_button.text = "+"
	add_channel_button.custom_minimum_size = Vector2(34, 30)
	add_channel_button.pressed.connect(_on_add_channel_pressed)
	header_row.add_child(add_channel_button)

	_toggle_button = Button.new()
	_toggle_button.text = "_"
	_toggle_button.custom_minimum_size = Vector2(34, 30)
	_toggle_button.pressed.connect(_on_toggle_pressed)
	header_row.add_child(_toggle_button)

	# Channel tabs
	_channel_tab_row = HBoxContainer.new()
	_channel_tab_row.name = "ChannelTabs"
	_channel_tab_row.add_theme_constant_override("separation", 4)
	vbox.add_child(_channel_tab_row)

	# Separator
	var sep := HSeparator.new()
	sep.name = "ChatSeparator"
	vbox.add_child(sep)

	# Scrollable message area
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_chat_scroll)

	_chat_messages_container = VBoxContainer.new()
	_chat_messages_container.add_theme_constant_override("separation", 2)
	_chat_messages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_scroll.add_child(_chat_messages_container)

	# Input row
	var input_row := HBoxContainer.new()
	input_row.name = "ChatInputRow"
	input_row.add_theme_constant_override("separation", 4)
	vbox.add_child(input_row)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Say something..."
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.custom_minimum_size = Vector2(0, 38)
	_chat_input.max_length = MAX_MESSAGE_LENGTH
	_chat_input.add_theme_font_size_override("font_size", 18)
	_chat_input.add_theme_color_override("font_color", Color.WHITE)
	_chat_input.text_submitted.connect(func(_t: String): _submit_chat())
	input_row.add_child(_chat_input)

	_chat_send_button = Button.new()
	_chat_send_button.text = "Send"
	_chat_send_button.add_theme_font_size_override("font_size", 18)
	_chat_send_button.custom_minimum_size = Vector2(70, 38)
	_chat_send_button.pressed.connect(_submit_chat)
	input_row.add_child(_chat_send_button)

	_chat_input.text_changed.connect(_on_input_text_changed)

	# Whisper suggestion popup - sits above the input row
	_suggestion_panel = PanelContainer.new()
	_suggestion_panel.visible = false
	_suggestion_panel.custom_minimum_size = Vector2(200, 0)
	vbox.move_child(input_row, -1)
	vbox.add_child(_suggestion_panel)
	vbox.move_child(_suggestion_panel, input_row.get_index())

	var suggestion_margin := MarginContainer.new()
	suggestion_margin.add_theme_constant_override("margin_left", 4)
	suggestion_margin.add_theme_constant_override("margin_top", 4)
	suggestion_margin.add_theme_constant_override("margin_right", 4)
	suggestion_margin.add_theme_constant_override("margin_bottom", 4)
	_suggestion_panel.add_child(suggestion_margin)

	_suggestion_list = VBoxContainer.new()
	_suggestion_list.add_theme_constant_override("separation", 2)
	suggestion_margin.add_child(_suggestion_list)

	# Channel create/join dialog - overlay on top of the chat panel
	_channel_dialog = PanelContainer.new()
	_channel_dialog.visible = false
	_channel_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_channel_dialog.z_index = 10
	_outer_panel.add_child(_channel_dialog)
	CocUiTheme.apply_to(_channel_dialog)

	var dialog_margin := MarginContainer.new()
	dialog_margin.add_theme_constant_override("margin_left", 12)
	dialog_margin.add_theme_constant_override("margin_top", 12)
	dialog_margin.add_theme_constant_override("margin_right", 12)
	dialog_margin.add_theme_constant_override("margin_bottom", 12)
	_channel_dialog.add_child(dialog_margin)

	_channel_dialog_vbox = VBoxContainer.new()
	_channel_dialog_vbox.add_theme_constant_override("separation", 8)
	dialog_margin.add_child(_channel_dialog_vbox)

	var dialog_header := HBoxContainer.new()
	_channel_dialog_vbox.add_child(dialog_header)

	var dialog_title := Label.new()
	dialog_title.text = "Channels"
	dialog_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_title.add_theme_font_size_override("font_size", 20)
	dialog_header.add_child(dialog_title)

	var dialog_close := Button.new()
	dialog_close.text = "X"
	dialog_close.custom_minimum_size = Vector2(34, 30)
	dialog_close.pressed.connect(func(): _channel_dialog.visible = false)
	dialog_header.add_child(dialog_close)

	var create_label := Label.new()
	create_label.text = "Create channel"
	create_label.add_theme_font_size_override("font_size", 16)
	_channel_dialog_vbox.add_child(create_label)

	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 4)
	_channel_dialog_vbox.add_child(create_row)

	_channel_name_input = LineEdit.new()
	_channel_name_input.placeholder_text = "Channel name"
	_channel_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_channel_name_input.custom_minimum_size = Vector2(0, 36)
	_channel_name_input.max_length = 20
	_channel_name_input.add_theme_font_size_override("font_size", 16)
	_channel_name_input.add_theme_color_override("font_color", Color.WHITE)
	create_row.add_child(_channel_name_input)

	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.add_theme_font_size_override("font_size", 16)
	create_btn.custom_minimum_size = Vector2(80, 36)
	create_btn.pressed.connect(_on_create_channel)
	create_row.add_child(create_btn)

	var sep2 := HSeparator.new()
	_channel_dialog_vbox.add_child(sep2)

	var join_label := Label.new()
	join_label.text = "Join a channel"
	join_label.add_theme_font_size_override("font_size", 16)
	_channel_dialog_vbox.add_child(join_label)

	var joinable_scroll := ScrollContainer.new()
	joinable_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	joinable_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_channel_dialog_vbox.add_child(joinable_scroll)

	_joinable_list = VBoxContainer.new()
	_joinable_list.add_theme_constant_override("separation", 4)
	_joinable_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	joinable_scroll.add_child(_joinable_list)


# ─────────────────────────────────────────────────────────────────────────
# Whisper suggestions
# ─────────────────────────────────────────────────────────────────────────

func _on_input_text_changed(new_text: String) -> void:
	if new_text.begins_with("/w "):
		if not _players_loaded:
			_fetch_all_players()
		var partial := new_text.substr(3).strip_edges().to_lower()
		_show_suggestions(partial)
	else:
		_suggestion_panel.visible = false


func _fetch_all_players() -> void:
	if not SupabaseAuth.is_signed_in:
		return
	var url := "%s/rest/v1/player_profiles?select=id,display_name&id=neq.%s&order=display_name" % [SupabaseAuth.SUPABASE_URL, SupabaseAuth.user_id]
	_http_players.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


func _on_players_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		return
	_players_loaded = true
	var parsed := _parse_body_array(body)
	for entry in parsed:
		var uid: String = str(entry.get("id", ""))
		var dname: String = str(entry.get("display_name", ""))
		if not uid.is_empty() and not dname.is_empty():
			_all_players[uid] = dname
	if _chat_input.text.begins_with("/w "):
		var partial := _chat_input.text.substr(3).strip_edges().to_lower()
		_show_suggestions(partial)


func _show_suggestions(partial: String) -> void:
	for child in _suggestion_list.get_children():
		child.queue_free()

	var matches: Array[String] = []
	for uid in _all_players:
		var name: String = _all_players[uid]
		if partial.is_empty() or name.to_lower().begins_with(partial):
			matches.append(name)
	if matches.size() > 8:
		matches.resize(8)

	if matches.is_empty():
		_suggestion_panel.visible = false
		return

	for name in matches:
		var btn := Button.new()
		btn.text = name
		btn.add_theme_font_size_override("font_size", 16)
		btn.custom_minimum_size = Vector2(0, 30)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_suggestion_picked.bind(name))
		_suggestion_list.add_child(btn)

	_suggestion_panel.visible = true


func _on_suggestion_picked(name: String) -> void:
	_chat_input.text = "/w %s " % name
	_chat_input.caret_column = _chat_input.text.length()
	_chat_input.grab_focus()
	_suggestion_panel.visible = false


func _strip_tag(display_name: String) -> String:
	var parts := display_name.split(" ", false, 2)
	if parts.size() >= 2 and parts[0].length() <= 5 and parts[0] == parts[0].to_upper():
		return parts[1]
	return display_name


func _on_name_clicked(meta: Variant) -> void:
	var name_str := str(meta)
	_chat_input.text = "/w %s " % name_str
	_chat_input.caret_column = _chat_input.text.length()
	_chat_input.grab_focus()


# ─────────────────────────────────────────────────────────────────────────
# Channel tabs
# ─────────────────────────────────────────────────────────────────────────

func _rebuild_channel_tabs() -> void:
	for child in _channel_tab_row.get_children():
		child.queue_free()
	_tab_buttons.clear()

	for ch in _channels:
		var ch_id: String = str(ch.get("id", ""))
		var ch_name: String = str(ch.get("name", "???"))
		var ch_type: String = str(ch.get("type", "custom"))
		if ch_type == "regiment":
			ch_name = "[%s]" % ch_name

		if ch_type == "custom":
			var tab_row := HBoxContainer.new()
			tab_row.add_theme_constant_override("separation", 0)
			_channel_tab_row.add_child(tab_row)

			var btn := Button.new()
			btn.text = ch_name
			btn.add_theme_font_size_override("font_size", 18)
			btn.custom_minimum_size = Vector2(0, 36)
			btn.pressed.connect(_on_channel_tab_pressed.bind(ch_id))
			tab_row.add_child(btn)
			_tab_buttons[ch_id] = btn

			var leave_btn := Button.new()
			leave_btn.text = "x"
			leave_btn.add_theme_font_size_override("font_size", 14)
			leave_btn.custom_minimum_size = Vector2(24, 36)
			leave_btn.pressed.connect(_on_leave_channel_tab.bind(ch_id))
			tab_row.add_child(leave_btn)
		else:
			var btn := Button.new()
			btn.text = ch_name
			btn.add_theme_font_size_override("font_size", 18)
			btn.custom_minimum_size = Vector2(0, 36)
			btn.pressed.connect(_on_channel_tab_pressed.bind(ch_id))
			_channel_tab_row.add_child(btn)
			_tab_buttons[ch_id] = btn

	_update_tab_styles()


func _update_tab_styles() -> void:
	for ch_id in _tab_buttons:
		var btn: Button = _tab_buttons[ch_id]
		var is_active: bool = (ch_id == _active_channel_id)
		if is_active:
			btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			btn.remove_theme_color_override("font_color")
		var unread: int = _channel_unread.get(ch_id, 0)
		var base_name := ""
		for ch in _channels:
			if str(ch.get("id", "")) == ch_id:
				var ch_type: String = str(ch.get("type", "custom"))
				base_name = str(ch.get("name", "???"))
				if ch_type == "regiment":
					base_name = "[%s]" % base_name
				break
		if unread > 0 and ch_id != _active_channel_id:
			btn.text = "%s (%d)" % [base_name, unread]
		else:
			btn.text = base_name


func _on_channel_tab_pressed(channel_id: String) -> void:
	if channel_id == _active_channel_id:
		return
	_active_channel_id = channel_id
	_channel_unread[channel_id] = 0
	_update_tab_styles()
	if not _channel_messages.has(channel_id):
		_fetch_history()
	else:
		_refresh_message_display()


# ─────────────────────────────────────────────────────────────────────────
# Channel fetching
# ─────────────────────────────────────────────────────────────────────────

func _fetch_channels() -> void:
	if not SupabaseAuth.is_signed_in:
		return
	if _channels_busy:
		return
	_channels_busy = true
	var url := "%s/rest/v1/chat_channels?select=id,name,type&order=type,name" % SupabaseAuth.SUPABASE_URL
	_http_channels.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


func _on_channels_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_channels_busy = false
	if response_code != 200:
		return
	var parsed := _parse_body_array(body)
	if parsed.is_empty():
		return
	parsed.sort_custom(func(a, b):
		var order := {"global": 0, "regiment": 1, "custom": 2}
		var a_ord: int = order.get(str(a.get("type", "custom")), 2)
		var b_ord: int = order.get(str(b.get("type", "custom")), 2)
		if a_ord != b_ord:
			return a_ord < b_ord
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	_channels = parsed

	var prev_still_exists := false
	if not _active_channel_id.is_empty():
		for ch in _channels:
			if str(ch.get("id", "")) == _active_channel_id:
				prev_still_exists = true
				break

	if not prev_still_exists:
		_active_channel_id = ""
		for ch in _channels:
			if str(ch.get("type", "")) == "global":
				_active_channel_id = str(ch.get("id", ""))
				break
		if _active_channel_id.is_empty() and not _channels.is_empty():
			_active_channel_id = str(_channels[0].get("id", ""))

	_rebuild_channel_tabs()
	_fetch_history()
	_fetch_whisper_history()



# ─────────────────────────────────────────────────────────────────────────
# Visibility
# ─────────────────────────────────────────────────────────────────────────

func _is_gameplay_scene() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var current := tree.current_scene
	if current == null:
		return false
	var path := current.scene_file_path
	return path in HIDDEN_SCENES


func _update_visibility() -> void:
	var show := SupabaseAuth.is_signed_in and not _is_gameplay_scene()
	_outer_panel.visible = show and _is_open
	_reopen_button.visible = show and not _is_open
	if show:
		_ensure_subscribed()
		if _channels.is_empty():
			_fetch_channels()
		var banned := SupabaseAuth.is_banned
		_chat_input.editable = not banned
		_chat_send_button.disabled = banned
		_chat_input.placeholder_text = "You are banned from chat" if banned else "Say something..."
	else:
		_ensure_unsubscribed()


func _on_auth_changed(_signed_in: bool) -> void:
	_update_visibility()
	if not SupabaseAuth.is_signed_in:
		_clear_messages()
		_ensure_unsubscribed()
		_channels.clear()
		_active_channel_id = ""
		_channel_messages.clear()
		_whisper_messages.clear()
		_channel_unread.clear()
	else:
		_fetch_channels()


func _on_tree_changed() -> void:
	if _visibility_check_queued:
		return
	_visibility_check_queued = true
	call_deferred("_deferred_visibility_check")


func _deferred_visibility_check() -> void:
	_visibility_check_queued = false
	_update_visibility()


func _on_toggle_pressed() -> void:
	_is_open = not _is_open
	_outer_panel.visible = _is_open
	_reopen_button.visible = not _is_open
	if _is_open:
		_unread_count = 0
	else:
		_reopen_button.text = "Chat" if _unread_count == 0 else "Chat (%d)" % _unread_count


# ─────────────────────────────────────────────────────────────────────────
# Realtime subscription
# ─────────────────────────────────────────────────────────────────────────

func _ensure_subscribed() -> void:
	if _subscribed:
		return
	_subscribed = true
	SupabaseRealtime.subscribe("chat_messages", "", _on_realtime_message)


func _ensure_unsubscribed() -> void:
	if not _subscribed:
		return
	_subscribed = false
	SupabaseRealtime.unsubscribe("chat_messages", "", _on_realtime_message)


func _on_realtime_message(record: Dictionary) -> void:
	_apply_single_message(record, false)


# ─────────────────────────────────────────────────────────────────────────
# Chat send / initial history fetch
# ─────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _send_cooldown > 0.0:
		_send_cooldown -= delta
		if _send_cooldown <= 0.0:
			_send_cooldown = 0.0
			_chat_send_button.disabled = false


func _submit_chat() -> void:
	var msg := _chat_input.text.strip_edges()
	if msg.is_empty():
		return
	if not SupabaseAuth.is_signed_in:
		return
	if SupabaseAuth.is_banned:
		return
	if _send_cooldown > 0.0:
		return
	_chat_input.text = ""
	_chat_input.grab_focus()

	if msg.begins_with("/w "):
		var parts := msg.substr(3).strip_edges()
		var space_pos := parts.find(" ")
		if space_pos < 1:
			_show_system_message("Usage: /w PlayerName message")
			return
		var target_name := parts.substr(0, space_pos).strip_edges()
		var whisper_text := parts.substr(space_pos + 1).strip_edges()
		if whisper_text.is_empty():
			_show_system_message("Usage: /w PlayerName message")
			return
		_start_whisper(target_name, whisper_text)
	else:
		_send_message(msg)

	_send_cooldown = SEND_COOLDOWN_SEC
	_chat_send_button.disabled = true


func _show_system_message(text: String) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.add_theme_font_size_override("normal_font_size", 18)
	line.text = "[color=red]%s[/color]" % text
	_chat_messages_container.add_child(line)
	_scroll_to_bottom()


func _start_whisper(target_name: String, whisper_text: String) -> void:
	_pending_whisper_target = target_name
	_pending_whisper_msg = whisper_text
	var url := "%s/rest/v1/player_profiles?display_name=eq.%s&select=id,display_name" % [SupabaseAuth.SUPABASE_URL, target_name.uri_encode()]
	_http_lookup.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


func _on_lookup_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		_show_system_message("Could not look up player.")
		return
	var parsed := _parse_body_array(body)
	if parsed.is_empty():
		_show_system_message("Player '%s' not found." % _pending_whisper_target)
		return
	var target_id: String = str(parsed[0].get("id", ""))
	var target_display: String = str(parsed[0].get("display_name", _pending_whisper_target))
	if target_id.is_empty():
		_show_system_message("Player '%s' not found." % _pending_whisper_target)
		return
	if target_id == SupabaseAuth.user_id:
		_show_system_message("You can't whisper to yourself.")
		return
	_display_name_cache[target_id] = target_display
	_send_whisper(target_id, _pending_whisper_msg)
	_pending_whisper_target = ""
	_pending_whisper_msg = ""


func _send_whisper(target_id: String, msg: String) -> void:
	var tagged_name := SupabaseAuth.display_name
	if SupabaseAuth.regiment_tag != "":
		tagged_name = "%s %s" % [SupabaseAuth.regiment_tag, tagged_name]
	var payload := {
		"user_id": SupabaseAuth.user_id,
		"display_name": tagged_name,
		"message": msg,
		"channel": "global",
		"is_whisper": true,
		"whisper_to": target_id,
	}
	if not _active_channel_id.is_empty():
		payload["channel_id"] = _active_channel_id
	var url := "%s/rest/v1/chat_messages" % SupabaseAuth.SUPABASE_URL
	_http_send.request(url, _bearer_headers(), HTTPClient.METHOD_POST, JSON.stringify(payload))


func _send_message(msg: String) -> void:
	var tagged_name := SupabaseAuth.display_name
	if SupabaseAuth.regiment_tag != "":
		tagged_name = "%s %s" % [SupabaseAuth.regiment_tag, tagged_name]
	var payload := {
		"user_id": SupabaseAuth.user_id,
		"display_name": tagged_name,
		"message": msg,
		"channel": "global",
	}
	if not _active_channel_id.is_empty():
		payload["channel_id"] = _active_channel_id
		for ch in _channels:
			if str(ch.get("id", "")) == _active_channel_id:
				var ch_type: String = str(ch.get("type", "global"))
				payload["channel"] = ch_type
				break
	var body := JSON.stringify(payload)
	var url := "%s/rest/v1/chat_messages" % SupabaseAuth.SUPABASE_URL
	_http_send.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


func _fetch_history() -> void:
	if not SupabaseAuth.is_signed_in:
		return
	if _fetch_busy:
		return
	if _active_channel_id.is_empty():
		return
	_fetch_busy = true
	var url := "%s/rest/v1/chat_messages?channel_id=eq.%s&order=created_at.asc&limit=50&select=id,display_name,message,created_at,user_id,channel_id,is_whisper,whisper_to" % [SupabaseAuth.SUPABASE_URL, _active_channel_id]
	_http_fetch.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


func _fetch_whisper_history() -> void:
	if not SupabaseAuth.is_signed_in:
		return
	var url := "%s/rest/v1/chat_messages?is_whisper=eq.true&order=created_at.asc&limit=50&select=id,display_name,message,created_at,user_id,channel_id,is_whisper,whisper_to" % SupabaseAuth.SUPABASE_URL
	_http_whispers.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


func _on_whispers_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		return
	var parsed := _parse_body_array(body)
	var lookup_ids: Array[String] = []
	for msg_dict in parsed:
		_apply_single_message(msg_dict as Dictionary, true)
		var wt: String = str(msg_dict.get("whisper_to", ""))
		var sender_id: String = str(msg_dict.get("user_id", ""))
		if not wt.is_empty() and sender_id == SupabaseAuth.user_id and not _display_name_cache.has(wt):
			if wt not in lookup_ids:
				lookup_ids.append(wt)
	_refresh_message_display()
	if not lookup_ids.is_empty():
		_batch_lookup_names(lookup_ids)


func _batch_lookup_names(ids: Array[String]) -> void:
	var id_list := ",".join(ids)
	var url := "%s/rest/v1/player_profiles?id=in.(%s)&select=id,display_name" % [SupabaseAuth.SUPABASE_URL, id_list]
	_http_batch_lookup.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


func _on_batch_lookup_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		return
	var parsed := _parse_body_array(body)
	for entry in parsed:
		var uid: String = str(entry.get("id", ""))
		var dname: String = str(entry.get("display_name", ""))
		if not uid.is_empty() and not dname.is_empty():
			_display_name_cache[uid] = dname
	_refresh_message_display()


func _on_send_response(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	pass


func _on_fetch_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_fetch_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed := _parse_body_array(body)
	for msg_dict in parsed:
		_apply_single_message(msg_dict as Dictionary, true)
	_refresh_message_display()


# ─────────────────────────────────────────────────────────────────────────
# Message storage and rendering
# ─────────────────────────────────────────────────────────────────────────

func _apply_single_message(msg: Dictionary, is_history: bool) -> void:
	var msg_id: String = msg.get("id", "")
	if msg_id.is_empty():
		var raw_id = msg.get("id", null)
		if raw_id != null:
			msg_id = str(raw_id)
	if msg_id.is_empty() or _seen_ids.has(msg_id):
		return
	_seen_ids[msg_id] = true

	var is_whisper: bool = msg.get("is_whisper", false)
	var ch_id: String = str(msg.get("channel_id", ""))
	if ch_id.is_empty() or ch_id == "null" or ch_id == "<null>":
		ch_id = _active_channel_id

	if is_whisper:
		_whisper_messages.append(msg)
		if _whisper_messages.size() > MAX_VISIBLE_MESSAGES:
			_whisper_messages = _whisper_messages.slice(-MAX_VISIBLE_MESSAGES)
	else:
		if not _channel_messages.has(ch_id):
			_channel_messages[ch_id] = []
		var arr: Array = _channel_messages[ch_id]
		arr.append(msg)
		if arr.size() > MAX_VISIBLE_MESSAGES:
			_channel_messages[ch_id] = arr.slice(-MAX_VISIBLE_MESSAGES)

	if not is_history:
		var msg_user_id: String = str(msg.get("user_id", ""))
		var is_self: bool = (msg_user_id == SupabaseAuth.user_id)

		# Track unread for non-active channels
		if not is_self:
			if ch_id != _active_channel_id or not _is_open:
				_channel_unread[ch_id] = _channel_unread.get(ch_id, 0) + 1
				_update_tab_styles()

			if not _is_open:
				_unread_count += 1
				_reopen_button.text = "Chat (%d)" % _unread_count

		# If message belongs to active channel or is a whisper, show it live
		if ch_id == _active_channel_id or is_whisper:
			_render_message(msg)
			_scroll_to_bottom()


func _refresh_message_display() -> void:
	for child in _chat_messages_container.get_children():
		child.queue_free()

	var channel_msgs: Array = _channel_messages.get(_active_channel_id, [])
	var all_msgs: Array = []
	all_msgs.append_array(channel_msgs)
	all_msgs.append_array(_whisper_messages)
	all_msgs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("created_at", "")) < str(b.get("created_at", ""))
	)

	for msg in all_msgs:
		_render_message(msg)
	_scroll_to_bottom()


func _render_message(msg: Dictionary) -> void:
	var sender: String = TextUtils.escape_bbcode(msg.get("display_name", "???"))
	var text: String = TextUtils.escape_bbcode(msg.get("message", ""))
	var timestamp_str: String = msg.get("created_at", "")
	var time_display := _format_chat_time(timestamp_str)
	var is_whisper: bool = msg.get("is_whisper", false)

	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.add_theme_font_size_override("normal_font_size", 18)

	var msg_user_id: String = str(msg.get("user_id", ""))
	var is_self: bool = (msg_user_id == SupabaseAuth.user_id)

	var click_name := ""
	if is_whisper:
		var whisper_name: String
		if is_self:
			var target_id: String = str(msg.get("whisper_to", ""))
			whisper_name = TextUtils.escape_bbcode(_display_name_cache.get(target_id, target_id))
			line.text = "[color=gray]%s[/color] [color=magenta][whisper to %s][/color] %s" % [
				time_display, whisper_name, text
			]
		else:
			whisper_name = sender
			click_name = _strip_tag(sender)
			line.text = "[color=gray]%s[/color] [color=magenta][whisper from [url=%s]%s[/url]][/color] %s" % [
				time_display, click_name, sender, text
			]
	else:
		var name_color: String = "cyan" if is_self else "yellow"
		if is_self:
			line.text = "[color=gray]%s[/color] [color=%s][%s][/color] %s" % [
				time_display, name_color, sender, text
			]
		else:
			click_name = _strip_tag(sender)
			line.text = "[color=gray]%s[/color] [color=%s][[url=%s]%s[/url]][/color] %s" % [
				time_display, name_color, click_name, sender, text
			]
	if not click_name.is_empty():
		line.meta_clicked.connect(_on_name_clicked)
	_chat_messages_container.add_child(line)


func _scroll_to_bottom() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


func _clear_messages() -> void:
	_seen_ids.clear()
	_unread_count = 0
	_channel_messages.clear()
	_whisper_messages.clear()
	_channel_unread.clear()
	for child in _chat_messages_container.get_children():
		child.queue_free()


# ─────────────────────────────────────────────────────────────────────────
# Custom channels - create / join / leave
# ─────────────────────────────────────────────────────────────────────────

func _on_add_channel_pressed() -> void:
	_channel_dialog.visible = true
	_channel_name_input.text = ""
	_fetch_joinable_channels()


func _fetch_joinable_channels() -> void:
	var url := "%s/rest/v1/rpc/list_custom_channels" % SupabaseAuth.SUPABASE_URL
	_http_list_channels.request(url, _bearer_headers(), HTTPClient.METHOD_POST, "{}")


func _on_list_channels_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	for child in _joinable_list.get_children():
		child.queue_free()

	if response_code != 200:
		var err_label := Label.new()
		err_label.text = "Could not load channels."
		err_label.add_theme_font_size_override("font_size", 14)
		_joinable_list.add_child(err_label)
		return

	var parsed := _parse_body_array(body)
	var my_channel_ids: Array[String] = []
	for ch in _channels:
		my_channel_ids.append(str(ch.get("id", "")))

	var can_delete: bool = SupabaseAuth.is_admin or SupabaseAuth.is_moderator
	var channel_count := 0
	for entry in parsed:
		var ch_id: String = str(entry.get("id", ""))
		var ch_name: String = str(entry.get("name", ""))
		var created_by: String = str(entry.get("created_by", ""))
		var is_mine: bool = (created_by == SupabaseAuth.user_id)
		var already_joined: bool = ch_id in my_channel_ids
		channel_count += 1

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var lbl := Label.new()
		lbl.text = ch_name
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 16)
		if already_joined:
			lbl.add_theme_color_override("font_color", Color.GRAY)
		row.add_child(lbl)

		if not already_joined:
			var join_btn := Button.new()
			join_btn.text = "Join"
			join_btn.add_theme_font_size_override("font_size", 14)
			join_btn.custom_minimum_size = Vector2(60, 30)
			join_btn.pressed.connect(_on_join_channel.bind(ch_id))
			row.add_child(join_btn)

		if is_mine or can_delete:
			var del_btn := Button.new()
			del_btn.text = "Delete"
			del_btn.add_theme_font_size_override("font_size", 14)
			del_btn.custom_minimum_size = Vector2(70, 30)
			del_btn.pressed.connect(_on_delete_channel.bind(ch_id))
			row.add_child(del_btn)

		_joinable_list.add_child(row)

	if channel_count == 0:
		var none_label := Label.new()
		none_label.text = "No custom channels yet."
		none_label.add_theme_font_size_override("font_size", 14)
		none_label.add_theme_color_override("font_color", Color.GRAY)
		_joinable_list.add_child(none_label)


func _on_create_channel() -> void:
	var ch_name := _channel_name_input.text.strip_edges()
	if ch_name.is_empty():
		return
	if not SupabaseAuth.is_signed_in:
		return
	var payload := {"p_name": ch_name}
	var url := "%s/rest/v1/rpc/create_custom_channel" % SupabaseAuth.SUPABASE_URL
	_http_create_channel.request(url, _bearer_headers(), HTTPClient.METHOD_POST, JSON.stringify(payload))


func _on_create_channel_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		var err_text := body.get_string_from_utf8()
		push_warning("Create channel failed (%d): %s" % [response_code, err_text])
		_show_system_message("Could not create channel (%d)." % response_code)
		return
	_channel_dialog.visible = false
	_channel_name_input.text = ""
	_channels_busy = false
	_fetch_channels()


func _on_join_channel(channel_id: String) -> void:
	_join_channel(channel_id)


func _join_channel(channel_id: String) -> void:
	if not SupabaseAuth.is_signed_in:
		return
	var payload := {
		"channel_id": channel_id,
		"user_id": SupabaseAuth.user_id,
	}
	var url := "%s/rest/v1/chat_channel_members" % SupabaseAuth.SUPABASE_URL
	_http_join_channel.request(url, _bearer_headers(), HTTPClient.METHOD_POST, JSON.stringify(payload))


func _on_join_channel_response(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if response_code != 201 and response_code != 200:
		_show_system_message("Could not join channel.")
		return
	_channel_dialog.visible = false
	_channels_busy = false
	_fetch_channels()


func _on_leave_channel_tab(channel_id: String) -> void:
	_leave_channel(channel_id)


func _leave_channel(channel_id: String) -> void:
	var url := "%s/rest/v1/chat_channel_members?channel_id=eq.%s&user_id=eq.%s" % [
		SupabaseAuth.SUPABASE_URL, channel_id, SupabaseAuth.user_id
	]
	_http_leave_channel.request(url, _bearer_headers(), HTTPClient.METHOD_DELETE)


func _on_leave_channel_response(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if response_code != 200 and response_code != 204:
		_show_system_message("Could not leave channel.")
		return
	_channels_busy = false
	_fetch_channels()


func _on_delete_channel(channel_id: String) -> void:
	var payload := {"p_channel_id": channel_id}
	var url := "%s/rest/v1/rpc/delete_custom_channel" % SupabaseAuth.SUPABASE_URL
	_http_delete_channel.request(url, _bearer_headers(), HTTPClient.METHOD_POST, JSON.stringify(payload))


func _on_delete_channel_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200 and response_code != 204:
		var err_text := body.get_string_from_utf8()
		push_warning("Delete channel failed (%d): %s" % [response_code, err_text])
		_show_system_message("Could not delete channel.")
		return
	_channel_dialog.visible = false
	_channels_busy = false
	_fetch_channels()


# ─────────────────────────────────────────────────────────────────────────
# Time formatting
# ─────────────────────────────────────────────────────────────────────────

func _format_chat_time(iso_timestamp: String) -> String:
	if iso_timestamp.is_empty():
		return ""
	var t_pos := iso_timestamp.find("T")
	if t_pos < 0:
		return ""
	var time_part := iso_timestamp.substr(t_pos + 1, 8)
	var parts := time_part.split(":")
	if parts.size() < 2:
		return time_part
	var hour := int(parts[0])
	var minute := int(parts[1])
	var tz_info := Time.get_time_zone_from_system()
	var offset_min: int = tz_info.get("bias", 0)
	var total_min := hour * 60 + minute + offset_min
	if total_min < 0:
		total_min += 1440
	elif total_min >= 1440:
		total_min -= 1440
	@warning_ignore("integer_division")
	hour = total_min / 60
	minute = total_min % 60
	var ampm := "AM" if hour < 12 else "PM"
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, minute, ampm]


# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

func _bearer_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % SupabaseAuth.SUPABASE_ANON_KEY,
		"Authorization: Bearer %s" % SupabaseAuth.access_token,
	])


func _parse_body_array(body: PackedByteArray) -> Array:
	var text := body.get_string_from_utf8()
	if text.is_empty():
		return []
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return []
	var data = json.data
	if data is Array:
		return data
	if data is Dictionary:
		return [data]
	return []
