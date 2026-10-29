class_name CommandBar
extends Control
## Bottom command bar with a squad row plus one row per soldier (Chain of Command style).

const SQUAD_ID := 0

signal soldier_selected(soldier_id: int)
signal move_targeting_changed(is_active: bool, soldier_id: int, movement_mode: int)
signal fire_at_mode_changed(is_active: bool, soldier_id: int)
signal face_mode_changed(is_active: bool, soldier_id: int)
signal position_change_requested(soldier_id: int, position_state: int)
signal fire_control_change_requested(soldier_id: int, fire_control_state: int)
signal grenade_mode_changed(is_active: bool, soldier_id: int)
signal save_requested
signal load_requested
signal map_save_requested
signal map_load_requested
signal center_camera_requested
signal rotate_view_left_requested
signal rotate_view_right_requested
signal set_commanders_requested
signal assign_weapons_requested
signal ammo_adjust_requested(soldier_id: int, delta: int)
signal retreat_requested

@onready var _squad_row: SquadCommandRow = %SquadRow
@onready var _rows: Array[SoldierCommandRow] = [
	%Row1,
	%Row2,
	%Row3,
	%Row4,
]
@onready var _team_label: Label = %TeamLabel

var _status_hud: StatusHud

# In-game chat
var _chat_http_send: HTTPRequest
var _chat_seen_ids: Dictionary = {}
var _chat_channel: String = ""
var _chat_filter: String = ""
var _chat_subscribed: bool = false
var _ignore_list: Dictionary = {}  # user_id -> true

var _selected_soldier_id: int = 1
var _move_target_soldier_id: int = -1
var _active_movement_mode: int = MovementMode.RUN
var _fire_at_soldier_id: int = -1
var _face_soldier_id: int = -1
var _grenade_soldier_id: int = -1
var _active_team_id: int = Team.USA
var _soldier_weapon_names: Array[String] = ["", "", "", ""]
var _fire_at_engaged: bool = false
var _usa_score_total: int = 0
var _ger_score_total: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	CocUiTheme.apply_to(self)
	_apply_inset_wells()
	_setup_chat_panel()
	_setup_dev_tools()
	var ui := get_parent()
	if ui != null:
		_status_hud = ui.get_node_or_null("StatusHud") as StatusHud
	## Bottom toolbar height follows content (no dead strip under buttons).
	call_deferred("_snap_flush_to_bottom")
	_squad_row.move_mode_toggled.connect(_on_squad_move_mode_toggled)
	_squad_row.fire_at_toggled.connect(_on_squad_fire_at_toggled)
	_squad_row.face_toggled.connect(_on_squad_face_toggled)
	_squad_row.position_toggled.connect(_on_squad_position_toggled)
	_squad_row.grenade_toggled.connect(_on_squad_grenade_toggled)
	_squad_row.fire_control_selected.connect(_on_squad_fire_control_selected)

	for row in _rows:
		row.move_mode_toggled.connect(_on_row_move_mode_toggled)
		row.ammo_adjust_requested.connect(func(sid: int, delta: int) -> void:
			ammo_adjust_requested.emit(sid, delta)
		)
		row.fire_at_toggled.connect(_on_row_fire_at_toggled)
		row.face_toggled.connect(_on_row_face_toggled)
		row.position_toggled.connect(_on_row_position_toggled)
		row.fire_control_selected.connect(_on_row_fire_control_selected)
		row.grenade_toggled.connect(_on_row_grenade_toggled)

	%CenterButton.pressed.connect(func() -> void: center_camera_requested.emit())
	%CenterButton.tooltip_text = "Center the camera on the active fireteam."
	%SaveButton.pressed.connect(func() -> void: save_requested.emit())
	%LoadButton.pressed.connect(func() -> void: load_requested.emit())
	%MapSaveButton.pressed.connect(func() -> void: map_save_requested.emit())
	%MapLoadButton.pressed.connect(func() -> void: map_load_requested.emit())
	%RotateLeftButton.pressed.connect(func() -> void: rotate_view_left_requested.emit())
	%RotateRightButton.pressed.connect(func() -> void: rotate_view_right_requested.emit())
	%SetCommandersButton.pressed.connect(func() -> void: set_commanders_requested.emit())
	%AssignWeaponsButton.pressed.connect(func() -> void: assign_weapons_requested.emit())
	var retreat := %RetreatButton as Button
	if retreat != null:
		retreat.disabled = false
		retreat.tooltip_text = "Retreat — end the scenario and concede the field."
		retreat.pressed.connect(func() -> void: retreat_requested.emit())

	_select_soldier(1, false, false)
	_refresh_deployment_stage_label(true)


func _setup_dev_tools() -> void:
	## Test-only strip (Save / Map Save / …) — top-left, not part of the OG toolbar.
	var score := %ScoreHud as Control
	if score != null:
		score.mouse_filter = Control.MOUSE_FILTER_STOP
		score.add_theme_stylebox_override("panel", CocUiTheme.panel_style())
	var survival := %SurvivalHud as Control
	if survival != null:
		survival.mouse_filter = Control.MOUSE_FILTER_STOP
		survival.add_theme_stylebox_override("panel", CocUiTheme.panel_style())
	var dev := %DevTools as Control
	if dev == null:
		return
	if BuildConfig.is_survival_playtest():
		dev.visible = false
		_fit_dev_tools()
		return
	dev.mouse_filter = Control.MOUSE_FILTER_STOP
	%SaveButton.tooltip_text = "DEV: save game state"
	%LoadButton.tooltip_text = "DEV: load game state"
	%MapSaveButton.tooltip_text = "DEV: save map objects"
	%MapLoadButton.tooltip_text = "DEV: load map objects"
	_fit_dev_tools()


func _fit_dev_tools() -> void:
	call_deferred("_fit_dev_tools_now")


func _fit_dev_tools_now() -> void:
	const PAD := 8.0
	const GAP := 4.0
	var y := PAD
	var score := %ScoreHud as Control
	var survival := %SurvivalHud as Control
	var score_bottom := PAD
	if score != null and is_instance_valid(score):
		var score_min := score.get_combined_minimum_size()
		score.offset_left = PAD
		score.offset_top = y
		score.offset_right = PAD + maxf(score_min.x, 1.0)
		score.offset_bottom = y + maxf(score_min.y, 1.0)
		score_bottom = score.offset_bottom
		if survival != null and is_instance_valid(survival) and survival.visible:
			var surv_min := survival.get_combined_minimum_size()
			survival.offset_left = score.offset_right + GAP
			survival.offset_top = PAD
			survival.offset_right = survival.offset_left + maxf(surv_min.x, 1.0)
			survival.offset_bottom = PAD + maxf(surv_min.y, 1.0)
			score_bottom = maxf(score_bottom, survival.offset_bottom)
		y = score_bottom + GAP
	var dev := %DevTools as Control
	if dev == null or not is_instance_valid(dev) or not dev.visible:
		var ui_early := get_parent()
		if ui_early != null:
			var ann_early := ui_early.get_node_or_null("SurvivalAnnouncementOverlay")
			if ann_early != null and ann_early.has_method("place_under_map_tools"):
				ann_early.place_under_map_tools()
		return
	var min_size := dev.get_combined_minimum_size()
	dev.offset_left = PAD
	dev.offset_top = y
	dev.offset_right = PAD + maxf(min_size.x, 1.0)
	dev.offset_bottom = y + maxf(min_size.y, 1.0)
	var ui := get_parent()
	if ui != null:
		var ann := ui.get_node_or_null("SurvivalAnnouncementOverlay")
		if ann != null and ann.has_method("place_under_map_tools"):
			ann.place_under_map_tools()


## Bounding box of score + survival HUD + map save/load strip (for aligned banners).
func get_top_left_tools_rect() -> Rect2:
	const PAD := 8.0
	var left := PAD
	var top := PAD
	var right := PAD
	var bottom := PAD
	var score := %ScoreHud as Control
	var survival := %SurvivalHud as Control
	var dev := %DevTools as Control
	if score != null and is_instance_valid(score):
		left = minf(left, score.offset_left)
		top = minf(top, score.offset_top)
		right = maxf(right, score.offset_right)
		bottom = maxf(bottom, score.offset_bottom)
	if survival != null and is_instance_valid(survival) and survival.visible:
		left = minf(left, survival.offset_left)
		top = minf(top, survival.offset_top)
		right = maxf(right, survival.offset_right)
		bottom = maxf(bottom, survival.offset_bottom)
	if dev != null and is_instance_valid(dev) and dev.visible:
		left = minf(left, dev.offset_left)
		top = minf(top, dev.offset_top)
		right = maxf(right, dev.offset_right)
		bottom = maxf(bottom, dev.offset_bottom)
	return Rect2(left, top, maxf(right - left, 1.0), maxf(bottom - top, 1.0))


## Pin bottom bar flush; left + chat share one height so their tops align.
func _snap_flush_to_bottom() -> void:
	var host := %BottomHost as Control
	var left := %LeftPanel as Control
	var chat := %ChatSide as Control
	var chat_log := %ChatLog as Control
	if host == null or left == null or chat == null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Keep chat log short enough that ChatSide can match LeftPanel height.
	if chat_log != null:
		chat_log.custom_minimum_size = Vector2(280, 56)
		chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat.custom_minimum_size.y = 0.0
	left.size_flags_vertical = Control.SIZE_FILL
	chat.size_flags_vertical = Control.SIZE_FILL
	var h := maxi(ceili(left.get_combined_minimum_size().y), 1)
	host.set_anchor(SIDE_LEFT, 0.0)
	host.set_anchor(SIDE_TOP, 1.0)
	host.set_anchor(SIDE_RIGHT, 1.0)
	host.set_anchor(SIDE_BOTTOM, 1.0)
	host.offset_left = 0.0
	host.offset_right = 0.0
	host.offset_bottom = 0.0
	host.offset_top = -float(h)
	host.grow_vertical = Control.GROW_DIRECTION_BEGIN
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit_dev_tools()


func set_active_team(team_id: int) -> void:
	_active_team_id = team_id
	_refresh_team_score_label()
	## Keep black text on CoC gray; team identity is the label string.
	_team_label.add_theme_color_override("font_color", CocUiTheme.TEXT_BLACK)
	clear_move_targeting()
	clear_fire_at_mode()
	clear_face_mode()
	clear_grenade_mode()
	_update_status()


func _apply_inset_wells() -> void:
	var inset := CocUiTheme.inset_label_panel()
	for row in _rows:
		row.apply_coc_inset_wells(inset)
	_squad_row.apply_coc_inset_wells(inset)


func set_selected_soldier(soldier_id: int) -> void:
	_select_soldier(soldier_id, false, true)


## Update highlighted soldier without notifying main (programmatic sync).
func sync_selected_soldier(soldier_id: int) -> void:
	_select_soldier(soldier_id, false, false)


## Sync one command row with live soldier gameplay data.
func sync_soldier_row(row_index: int, state: SoldierState, hit_pct: float = -1.0) -> void:
	if row_index < 0 or row_index >= _rows.size():
		return
	var row: SoldierCommandRow = _rows[row_index]
	row.set_weapon_info(state)
	row.set_ammo(state.ammo_current, state.ammo_max)
	_soldier_weapon_names[row_index] = state.weapon_name
	var alive := state.is_alive()
	## Grey the row only on death — stun must not look like a kill.
	row.set_row_enabled(alive)
	row.set_position_state(state.position_state)
	row.set_fire_control_state(state.fire_control_state)
	row.set_activity_status(state.activity_status_label())
	row.set_stress(state.stress)
	row.set_hit_pct(hit_pct)
	row.set_grenade_count(
		state.grenade_count,
		state.has_pending_grenade(),
	)
	var can_move := alive and not state.is_stunned()
	row.set_move_button_enabled(MovementMode.RUN, can_move)
	row.set_move_button_enabled(MovementMode.CRAWL, can_move)


func set_soldier_row_interactive(row_index: int, enabled: bool) -> void:
	if row_index < 0 or row_index >= _rows.size():
		return
	_rows[row_index].set_row_enabled(enabled)


func update_hit_columns(hit_pcts: Array) -> void:
	for i in range(min(_rows.size(), hit_pcts.size())):
		_rows[i].set_hit_pct(float(hit_pcts[i]))


func clear_move_targeting() -> void:
	_move_target_soldier_id = -1
	_active_movement_mode = MovementMode.RUN
	_squad_row.clear_move_modes()
	for row in _rows:
		row.clear_move_modes()
	move_targeting_changed.emit(false, _selected_soldier_id, MovementMode.RUN)
	_update_status()


func clear_fire_at_mode() -> void:
	_fire_at_soldier_id = -1
	_fire_at_engaged = false
	_squad_row.set_fire_at_pressed(false)
	for row in _rows:
		row.set_fire_at_pressed(false)
	fire_at_mode_changed.emit(false, _selected_soldier_id)
	_update_status()


## Keep Fire At button lit after view refresh without re-entering mode.
func affirm_fire_at_pressed(squad: bool, soldier_id: int) -> void:
	if squad:
		_fire_at_soldier_id = SQUAD_ID
		_squad_row.set_fire_at_pressed(true)
		for row in _rows:
			row.set_fire_at_pressed(false)
	else:
		_fire_at_soldier_id = soldier_id
		_squad_row.set_fire_at_pressed(false)
		for row in _rows:
			row.set_fire_at_pressed(row.soldier_id == soldier_id)
	_update_status()


func set_fire_at_engaged(engaged: bool) -> void:
	_fire_at_engaged = engaged
	_update_status()


func clear_face_mode() -> void:
	_face_soldier_id = -1
	_squad_row.set_face_pressed(false)
	for row in _rows:
		row.set_face_pressed(false)
	face_mode_changed.emit(false, _selected_soldier_id)
	_update_status()


func clear_grenade_mode() -> void:
	_grenade_soldier_id = -1
	_squad_row.set_grenade_pressed(false)
	for row in _rows:
		row.set_grenade_pressed(false)
	grenade_mode_changed.emit(false, _selected_soldier_id)
	_update_status()


func sync_squad_position_state(position_state: int) -> void:
	_squad_row.set_position_state(position_state)


func show_status(text: String) -> void:
	if _status_hud != null:
		_status_hud.show_status(text)


func append_chat_system(text: String) -> void:
	_append_chat_system(text)


func set_deployment_phase(is_deployment: bool, remaining_sec: float = 0.0) -> void:
	_refresh_deployment_stage_label(is_deployment, remaining_sec)
	var retreat := %RetreatButton as Button
	if retreat != null:
		retreat.disabled = is_deployment


func set_scenario_clock(remaining_sec: float) -> void:
	var timer := %DeploymentTimerLabel as Label
	if timer == null:
		return
	var total := int(maxi(0, int(ceil(remaining_sec))))
	@warning_ignore("integer_division")
	timer.text = "%02d:%02d" % [total / 60, total % 60]
	timer.add_theme_color_override("font_color", CocUiTheme.TEXT_STATUS_RED)


func set_scenario_scores(
	usa_total: int,
	ger_total: int,
	kill_points: Dictionary,
	terrain_points: Dictionary,
	vp_summary: String,
) -> void:
	_usa_score_total = usa_total
	_ger_score_total = ger_total
	_refresh_team_score_label()
	if _team_label != null:
		var uk := int(kill_points.get(Team.USA, 0))
		var ut := int(terrain_points.get(Team.USA, 0))
		var gk := int(kill_points.get(Team.GERMANY, 0))
		var gt := int(terrain_points.get(Team.GERMANY, 0))
		_team_label.tooltip_text = (
			"USA %d (kills %d + terrain %d)\nGermany %d (kills %d + terrain %d)\nVP: %s"
			% [usa_total, uk, ut, ger_total, gk, gt, vp_summary if not vp_summary.is_empty() else "—"]
		)


@warning_ignore("shadowed_variable_base_class")
func set_survival_hud_visible(is_visible: bool) -> void:
	var survival := %SurvivalHud as Control
	if survival == null:
		return
	survival.visible = is_visible
	_fit_dev_tools()


func set_survival_stats(
	enemy_fireteams: int,
	next_deploy_sec: float,
	enemies_killed: int,
) -> void:
	var fireteams := %SurvivalFireteamsLabel as Label
	var next_deploy := %SurvivalNextDeployLabel as Label
	var kills := %SurvivalKillsLabel as Label
	if fireteams != null:
		fireteams.text = "Enemy fireteams: %d" % enemy_fireteams
	if next_deploy != null:
		if next_deploy_sec < 0.0:
			next_deploy.text = "Next deployment: —"
		else:
			var total := int(maxi(0, int(ceil(next_deploy_sec))))
			@warning_ignore("integer_division")
			next_deploy.text = "Next deployment: %d:%02d" % [total / 60, total % 60]
	if kills != null:
		kills.text = "Enemies killed: %d" % enemies_killed
	_fit_dev_tools()


func _setup_chat_panel() -> void:
	var chat_log := %ChatLog as RichTextLabel
	if chat_log == null:
		return
	chat_log.add_theme_stylebox_override("normal", CocUiTheme.chat_panel_style())
	chat_log.clear()
	chat_log.append_text("[color=#CC0000]ATTENTION: Scenario Running[/color]\n")

	# Enable the chat input field.
	var chat_input := %ChatInput as LineEdit
	if chat_input != null:
		chat_input.editable = true
		chat_input.mouse_filter = Control.MOUSE_FILTER_STOP
		chat_input.focus_mode = Control.FOCUS_ALL
		chat_input.add_theme_color_override("font_color", Color.WHITE)
		chat_input.add_theme_color_override("font_placeholder_color", Color(0.5, 0.5, 0.5))
		chat_input.text_submitted.connect(_on_chat_input_submitted)
		chat_input.focus_entered.connect(_on_chat_focus_entered)
		chat_input.focus_exited.connect(_on_chat_focus_exited)

	# Turn the "[No default]" button into a Send button.
	var default_btn := %ChatDefaultButton as Button
	if default_btn != null:
		default_btn.text = "Send"
		default_btn.disabled = false
		default_btn.pressed.connect(func(): _on_chat_input_submitted(""))

	# Wire up Whisper/Announce/Ignore buttons.
	var whisper_btn := get_node_or_null("%WhisperButton") as Button
	if whisper_btn != null:
		whisper_btn.disabled = true  # Requires player list (Phase 16+)

	var announce_btn := get_node_or_null("%AnnounceButton") as Button
	if announce_btn != null:
		announce_btn.disabled = true  # Team leader only, needs team sizes (Phase 18)

	var ignore_btn := get_node_or_null("%IgnoreButton") as Button
	if ignore_btn != null:
		ignore_btn.disabled = true  # Requires player list (Phase 16+)

	# Set up HTTP for sending messages (receiving uses Realtime).
	_chat_http_send = HTTPRequest.new()
	_chat_http_send.request_completed.connect(_on_chat_send_response)
	add_child(_chat_http_send)


## Call from main.gd after match ID and team assignment are confirmed.
func start_chat_channel() -> void:
	var mid := NetworkClient.match_id
	if mid.is_empty():
		mid = _generate_session_id()
	var team_suffix := "usa" if PlayerSides.assigned_team_id == Team.USA else "germany"
	_chat_channel = "game:%s:%s" % [mid, team_suffix]
	_chat_filter = "channel=eq.%s" % _chat_channel
	if SupabaseAuth.is_signed_in and not _chat_subscribed:
		_chat_subscribed = true
		SupabaseRealtime.subscribe("chat_messages", _chat_filter, _on_chat_realtime_message)


func _append_chat_system(text: String) -> void:
	var chat_log := %ChatLog as RichTextLabel
	if chat_log == null or text.is_empty():
		return
	## Keep the log short; status HUD already shows the live prompt.
	if text.begins_with("USA ") or text.begins_with("Germany "):
		return
	chat_log.append_text("[color=#CC0000]%s[/color]\n" % text)


# ─────────────────────────────────────────────────────────────────────────
# In-game chat (Supabase)
# ─────────────────────────────────────────────────────────────────────────

var _chat_has_focus: bool = false


func _on_chat_focus_entered() -> void:
	_chat_has_focus = true


func _on_chat_focus_exited() -> void:
	_chat_has_focus = false


func _unhandled_input(event: InputEvent) -> void:
	# Block all game input while the chat input is focused.
	if _chat_has_focus and event is InputEventKey:
		get_viewport().set_input_as_handled()


func _on_chat_input_submitted(_text: String = "") -> void:
	var chat_input := %ChatInput as LineEdit
	if chat_input == null:
		return
	var msg := chat_input.text.strip_edges()
	if msg.is_empty() and not _text.is_empty():
		msg = _text.strip_edges()
	if msg.is_empty():
		return
	if not SupabaseAuth.is_signed_in:
		return
	chat_input.text = ""
	chat_input.grab_focus()
	_chat_send_message(msg)
	_echo_local_message(msg)


func _echo_local_message(msg: String) -> void:
	var chat_log := %ChatLog as RichTextLabel
	if chat_log == null:
		return
	var tagged_name := SupabaseAuth.display_name
	if SupabaseAuth.regiment_tag != "":
		tagged_name = "%s %s" % [SupabaseAuth.regiment_tag, tagged_name]
	var now := Time.get_time_dict_from_system()
	var hour: int = now.get("hour", 0)
	var minute: int = now.get("minute", 0)
	var ampm := "AM" if hour < 12 else "PM"
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	var time_display := "%d:%02d %s" % [display_hour, minute, ampm]
	chat_log.append_text("[color=gray]%s[/color] [color=cyan][%s][/color] %s\n" % [
		time_display, tagged_name, msg
	])


func _chat_send_message(msg: String) -> void:
	var tagged_name := SupabaseAuth.display_name
	if SupabaseAuth.regiment_tag != "":
		tagged_name = "%s %s" % [SupabaseAuth.regiment_tag, tagged_name]
	var body := JSON.stringify({
		"user_id": SupabaseAuth.user_id,
		"display_name": tagged_name,
		"message": msg,
		"channel": _chat_channel,
	})
	var url := "%s/rest/v1/chat_messages" % SupabaseAuth.SUPABASE_URL
	_chat_http_send.request(url, _chat_bearer_headers(), HTTPClient.METHOD_POST, body)


func _on_chat_send_response(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	pass


## Called by SupabaseRealtime when a new message arrives on this game channel.
func _on_chat_realtime_message(record: Dictionary) -> void:
	var chat_log := %ChatLog as RichTextLabel
	if chat_log == null:
		return

	var msg_id := str(record.get("id", ""))
	if msg_id.is_empty() or _chat_seen_ids.has(msg_id):
		return
	_chat_seen_ids[msg_id] = true

	var sender_id := str(record.get("user_id", ""))

	# Skip own messages (already echoed locally) and ignored players.
	if sender_id == SupabaseAuth.user_id:
		return
	if _ignore_list.has(sender_id):
		return

	var sender: String = record.get("display_name", "???")
	var text: String = record.get("message", "")
	var timestamp_str: String = record.get("created_at", "")
	var time_display := _chat_format_time(timestamp_str)

	var is_self: bool = (sender_id == SupabaseAuth.user_id)

	var name_color: String = "cyan" if is_self else "yellow"

	chat_log.append_text("[color=gray]%s[/color] [color=%s][%s][/color] %s\n" % [
		time_display, name_color, sender, text
	])

	await get_tree().process_frame
	var chat_scroll := chat_log.get_parent().get_parent() as ScrollContainer
	if chat_scroll != null:
		chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)


## Call this when the match ends to clean up the Realtime subscription.
func cleanup_chat() -> void:
	if _chat_subscribed:
		_chat_subscribed = false
		SupabaseRealtime.unsubscribe("chat_messages", _chat_filter, _on_chat_realtime_message)


func _chat_format_time(iso_timestamp: String) -> String:
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


func _chat_bearer_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % SupabaseAuth.SUPABASE_ANON_KEY,
		"Authorization: Bearer %s" % SupabaseAuth.access_token,
	])




func _generate_session_id() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var id := ""
	for i in 12:
		id += chars[randi() % chars.length()]
	return id


func _refresh_deployment_stage_label(is_deployment: bool, remaining_sec: float = 0.0) -> void:
	var stage := %DeploymentStageLabel as Label
	var timer := %DeploymentTimerLabel as Label
	if stage != null:
		stage.text = "Deployment Stage" if is_deployment else "Scenario Running"
	if timer != null and is_deployment:
		## remaining_sec is the deploy countdown (ceil so 0.1 still shows 00:01).
		var total := int(maxi(0, int(ceil(remaining_sec))))
		@warning_ignore("integer_division")
		timer.text = "%02d:%02d" % [total / 60, total % 60]
		timer.add_theme_color_override("font_color", CocUiTheme.TEXT_STATUS_RED)
	_refresh_team_score_label()


func _refresh_team_score_label() -> void:
	if _team_label == null:
		return
	_team_label.text = "%s  %d|%d" % [
		Team.display_name(_active_team_id),
		_usa_score_total,
		_ger_score_total,
	]
	_team_label.custom_minimum_size = Vector2(96, CocUiTheme.ROW_HEIGHT)


func _on_squad_move_mode_toggled(movement_mode: int, is_pressed: bool) -> void:
	## Action buttons are click-flash only; mode stays until another action clears it.
	if not is_pressed:
		return
	clear_fire_at_mode()
	clear_face_mode()
	clear_grenade_mode()
	for row in _rows:
		row.clear_move_modes()
	_squad_row.clear_move_modes()
	_squad_row.set_move_mode_pressed(movement_mode, true)
	_move_target_soldier_id = SQUAD_ID
	_active_movement_mode = movement_mode
	move_targeting_changed.emit(true, SQUAD_ID, movement_mode)
	_squad_row.flash_move_mode(movement_mode)
	_update_status()


func _on_squad_fire_at_toggled(is_pressed: bool) -> void:
	if not is_pressed:
		return
	clear_move_targeting()
	clear_face_mode()
	clear_grenade_mode()
	for row in _rows:
		row.set_fire_at_pressed(false)
	_fire_at_soldier_id = SQUAD_ID
	fire_at_mode_changed.emit(true, SQUAD_ID)
	_squad_row.flash_fire_at()
	_update_status()


func _on_squad_face_toggled(is_pressed: bool) -> void:
	if not is_pressed:
		return
	clear_move_targeting()
	clear_fire_at_mode()
	clear_grenade_mode()
	for row in _rows:
		row.set_face_pressed(false)
	_face_soldier_id = SQUAD_ID
	face_mode_changed.emit(true, SQUAD_ID)
	_squad_row.flash_face()
	_update_status()


func _on_squad_grenade_toggled(is_pressed: bool) -> void:
	if not is_pressed:
		return
	clear_move_targeting()
	clear_fire_at_mode()
	clear_face_mode()
	for row in _rows:
		row.set_grenade_pressed(false)
	_grenade_soldier_id = SQUAD_ID
	grenade_mode_changed.emit(true, SQUAD_ID)
	_squad_row.flash_grenade()
	_update_status()


func _on_squad_position_toggled(is_down: bool) -> void:
	clear_move_targeting()
	clear_fire_at_mode()
	clear_face_mode()
	clear_grenade_mode()
	position_change_requested.emit(
		SQUAD_ID,
		PositionState.DOWN if is_down else PositionState.UP,
	)


func _on_squad_fire_control_selected(fire_control_state: int) -> void:
	clear_fire_at_mode()
	clear_face_mode()
	clear_grenade_mode()
	fire_control_change_requested.emit(SQUAD_ID, fire_control_state)


func _on_row_move_mode_toggled(soldier_id: int, movement_mode: int, is_pressed: bool) -> void:
	## Action buttons are click-flash only; mode stays until another action clears it.
	if not is_pressed:
		return
	clear_fire_at_mode()
	clear_face_mode()
	clear_grenade_mode()
	_squad_row.clear_move_modes()
	var active_row: SoldierCommandRow = null
	for row in _rows:
		if row.soldier_id != soldier_id:
			row.clear_move_modes()
		else:
			row.clear_move_modes()
			row.set_move_mode_pressed(movement_mode, true)
			active_row = row
	_move_target_soldier_id = soldier_id
	_active_movement_mode = movement_mode
	_select_soldier(soldier_id, true)
	move_targeting_changed.emit(true, soldier_id, movement_mode)
	if active_row != null:
		active_row.flash_move_mode(movement_mode)
	_update_status()


func _on_row_fire_at_toggled(soldier_id: int, is_pressed: bool) -> void:
	if not is_pressed:
		return
	clear_move_targeting()
	clear_face_mode()
	clear_grenade_mode()
	_squad_row.set_fire_at_pressed(false)
	var active_row: SoldierCommandRow = null
	for row in _rows:
		if row.soldier_id != soldier_id:
			row.set_fire_at_pressed(false)
		else:
			active_row = row
	_fire_at_soldier_id = soldier_id
	_select_soldier(soldier_id, true)
	fire_at_mode_changed.emit(true, soldier_id)
	if active_row != null:
		active_row.flash_fire_at()
	_update_status()


func _on_row_face_toggled(soldier_id: int, is_pressed: bool) -> void:
	if not is_pressed:
		return
	clear_move_targeting()
	clear_fire_at_mode()
	clear_grenade_mode()
	_squad_row.set_face_pressed(false)
	var active_row: SoldierCommandRow = null
	for row in _rows:
		if row.soldier_id != soldier_id:
			row.set_face_pressed(false)
		else:
			active_row = row
	_face_soldier_id = soldier_id
	_select_soldier(soldier_id, true)
	face_mode_changed.emit(true, soldier_id)
	if active_row != null:
		active_row.flash_face()
	_update_status()


func _on_row_grenade_toggled(soldier_id: int, is_pressed: bool) -> void:
	if not is_pressed:
		return
	clear_move_targeting()
	clear_fire_at_mode()
	clear_face_mode()
	_squad_row.set_grenade_pressed(false)
	var active_row: SoldierCommandRow = null
	for row in _rows:
		if row.soldier_id != soldier_id:
			row.set_grenade_pressed(false)
		else:
			active_row = row
	_grenade_soldier_id = soldier_id
	_select_soldier(soldier_id, true)
	grenade_mode_changed.emit(true, soldier_id)
	if active_row != null:
		active_row.flash_grenade()
	_update_status()


func _on_row_fire_control_selected(soldier_id: int, fire_control_state: int) -> void:
	clear_fire_at_mode()
	clear_face_mode()
	clear_grenade_mode()
	## Do not notify Main — a full view refresh would wipe the button from stale GameState
	## before the authoritative fire-control result arrives.
	_select_soldier(soldier_id, true, false)
	fire_control_change_requested.emit(soldier_id, fire_control_state)


func _on_row_position_toggled(soldier_id: int, is_down: bool) -> void:
	clear_move_targeting()
	clear_fire_at_mode()
	clear_face_mode()
	clear_grenade_mode()
	_select_soldier(soldier_id, true, false)
	position_change_requested.emit(
		soldier_id,
		PositionState.DOWN if is_down else PositionState.UP,
	)


func _select_soldier(soldier_id: int, from_command: bool, notify: bool = true) -> void:
	var row_index := soldier_id - 1
	if row_index >= 0 and row_index < _rows.size() and not _rows[row_index].is_interactive():
		return
	if _selected_soldier_id == soldier_id:
		if not from_command:
			_update_status()
		return
	_selected_soldier_id = soldier_id
	if notify:
		soldier_selected.emit(soldier_id)
	if not from_command:
		_update_status()


func _movement_label(mode: int) -> String:
	match mode:
		MovementMode.CRAWL:
			return "Crawl To"
		_:
			return "Run To"


func _update_status() -> void:
	var team_name := Team.display_name(_active_team_id)
	if _fire_at_soldier_id == SQUAD_ID:
		show_status(
			"%s Fireteam: Fire At — click a tile or enemy to aim. Right-click cancels."
			% team_name
		)
	elif _fire_at_soldier_id > 0:
		show_status(
			"%s Soldier %d: Fire At — click a tile or enemy to aim. Right-click cancels."
			% [team_name, _fire_at_soldier_id],
		)
	elif _face_soldier_id == SQUAD_ID:
		show_status("%s Fireteam: Face... — click a tile or enemy. Right-click cancels." % team_name)
	elif _face_soldier_id > 0:
		show_status("%s Soldier %d: Face... — click a tile or enemy. Right-click cancels." % [team_name, _face_soldier_id])
	elif _grenade_soldier_id == SQUAD_ID:
		show_status(
			"%s Fireteam: Grenade — click a tile within 7 tiles. All soldiers with grenades throw."
			% team_name,
		)
	elif _grenade_soldier_id > 0:
		show_status(
			"%s Soldier %d: Grenade — click a tile within 7 tiles. Right-click cancels."
			% [team_name, _grenade_soldier_id],
		)
	elif _move_target_soldier_id == SQUAD_ID:
		show_status(
			"%s Fireteam: %s — click tiles to move."
			% [team_name, _movement_label(_active_movement_mode)],
		)
	elif _move_target_soldier_id > 0:
		show_status(
			"%s Soldier %d: %s — click tiles to move."
			% [team_name, _move_target_soldier_id, _movement_label(_active_movement_mode)],
		)
	else:
		var weapon_name := _get_selected_weapon_name()
		if weapon_name.is_empty():
			show_status(
				"%s Soldier %d selected. Press 1/2 to switch teams."
				% [team_name, _selected_soldier_id],
			)
		else:
			show_status(
				"%s Soldier %d — Weapon: %s"
				% [team_name, _selected_soldier_id, weapon_name],
			)


func _get_selected_weapon_name() -> String:
	var row_index := _selected_soldier_id - 1
	if row_index < 0 or row_index >= _soldier_weapon_names.size():
		return ""
	return _soldier_weapon_names[row_index]
