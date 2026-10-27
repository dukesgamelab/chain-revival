extends Node
## Global chat overlay for Chain Revival.
##
## Autoload that places a chat panel on top of every screen via CanvasLayer.
## The panel sits to the right of the main content and is visible whenever
## the player is signed in, except during gameplay.
##
## Uses the chat_messages Supabase table.

const CHAT_PANEL_WIDTH := 260
const CHAT_PANEL_MARGIN_TOP := 80
const CHAT_PANEL_MARGIN_BOTTOM := 20
const CHAT_PANEL_MARGIN_RIGHT := 20
const POLL_INTERVAL := 3.0
const MAX_VISIBLE_MESSAGES := 100

## Scenes where the global chat should be hidden.
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

var _poll_timer: Timer
var _seen_ids: Dictionary = {}
var _is_open: bool = true

var _http_fetch: HTTPRequest
var _http_send: HTTPRequest


func _ready() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	add_child(_canvas_layer)

	_build_ui()
	_setup_http()
	_setup_timer()

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


func _setup_timer() -> void:
	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL
	_poll_timer.timeout.connect(_on_poll)
	add_child(_poll_timer)


# ─────────────────────────────────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root_control = Control.new()
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_root_control)

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
	title_label.add_theme_font_size_override("font_size", 13)
	header_row.add_child(title_label)

	_toggle_button = Button.new()
	_toggle_button.text = "_"
	_toggle_button.custom_minimum_size = Vector2(24, 20)
	_toggle_button.pressed.connect(_on_toggle_pressed)
	header_row.add_child(_toggle_button)

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
	_chat_input.custom_minimum_size = Vector2(0, 26)
	_chat_input.text_submitted.connect(func(_t: String): _submit_chat())
	input_row.add_child(_chat_input)

	_chat_send_button = Button.new()
	_chat_send_button.text = "Send"
	_chat_send_button.custom_minimum_size = Vector2(50, 26)
	_chat_send_button.pressed.connect(_submit_chat)
	input_row.add_child(_chat_send_button)


# ─────────────────────────────────────────────────────────────────────────
# Visibility
# ─────────────────────────────────────────────────────────────────────────

func _is_gameplay_scene() -> bool:
	var current := get_tree().current_scene
	if current == null:
		return false
	var path := current.scene_file_path
	return path in HIDDEN_SCENES


func _update_visibility() -> void:
	var show := SupabaseAuth.is_signed_in and not _is_gameplay_scene()
	_outer_panel.visible = show
	if show:
		_poll_timer.start()
		_fetch_messages()
	else:
		_poll_timer.stop()


func _on_auth_changed(_signed_in: bool) -> void:
	_update_visibility()
	if not SupabaseAuth.is_signed_in:
		_clear_messages()


func _on_tree_changed() -> void:
	# Re-check visibility when scenes change.
	_update_visibility()


func _on_toggle_pressed() -> void:
	_is_open = not _is_open
	_chat_scroll.visible = _is_open
	var vbox := _chat_scroll.get_parent() as VBoxContainer
	if vbox != null:
		var sep := vbox.get_node_or_null("ChatSeparator")
		if sep != null:
			sep.visible = _is_open
		var input_row := vbox.get_node_or_null("ChatInputRow")
		if input_row != null:
			input_row.visible = _is_open
	_toggle_button.text = "_" if _is_open else "+"


# ─────────────────────────────────────────────────────────────────────────
# Chat send / fetch
# ─────────────────────────────────────────────────────────────────────────

func _submit_chat() -> void:
	var msg := _chat_input.text.strip_edges()
	if msg.is_empty():
		return
	if not SupabaseAuth.is_signed_in:
		return
	_chat_input.text = ""
	_chat_input.grab_focus()
	_send_message(msg)
	await get_tree().create_timer(0.3).timeout
	_fetch_messages()


func _send_message(msg: String) -> void:
	var body := JSON.stringify({
		"user_id": SupabaseAuth.user_id,
		"display_name": SupabaseAuth.display_name,
		"message": msg,
		"channel": "global",
	})
	var url := "%s/rest/v1/chat_messages" % SupabaseAuth.SUPABASE_URL
	_http_send.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


func _fetch_messages() -> void:
	if not SupabaseAuth.is_signed_in:
		return
	var url := "%s/rest/v1/chat_messages?channel=eq.global&order=created_at.asc&limit=50" % SupabaseAuth.SUPABASE_URL
	_http_fetch.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


func _on_poll() -> void:
	_fetch_messages()


func _on_send_response(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	pass


func _on_fetch_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed := _parse_body_array(body)
	_apply_messages(parsed)


# ─────────────────────────────────────────────────────────────────────────
# Message rendering
# ─────────────────────────────────────────────────────────────────────────

func _apply_messages(messages: Array) -> void:
	if messages.is_empty():
		return
	var added := false
	for msg_dict in messages:
		var msg: Dictionary = msg_dict
		var msg_id: String = msg.get("id", "")
		if msg_id.is_empty() or _seen_ids.has(msg_id):
			continue
		_seen_ids[msg_id] = true
		added = true

		var sender: String = msg.get("display_name", "???")
		var text: String = msg.get("message", "")
		var timestamp_str: String = msg.get("created_at", "")
		var time_display := _format_chat_time(timestamp_str)

		var line := RichTextLabel.new()
		line.bbcode_enabled = true
		line.fit_content = true
		line.scroll_active = false
		line.add_theme_font_size_override("normal_font_size", 11)

		var msg_user_id: String = msg.get("user_id", "")
		var is_self: bool = (msg_user_id == SupabaseAuth.user_id)
		var name_color: String = "cyan" if is_self else "yellow"

		line.text = "[color=gray]%s[/color] [color=%s][%s][/color] %s" % [
			time_display, name_color, sender, text
		]
		_chat_messages_container.add_child(line)

	if not added:
		return

	while _chat_messages_container.get_child_count() > MAX_VISIBLE_MESSAGES:
		var oldest := _chat_messages_container.get_child(0)
		_chat_messages_container.remove_child(oldest)
		oldest.queue_free()

	await get_tree().process_frame
	_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


func _clear_messages() -> void:
	_seen_ids.clear()
	for child in _chat_messages_container.get_children():
		child.queue_free()


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
