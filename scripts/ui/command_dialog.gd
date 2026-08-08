class_name CommandDialog
extends AcceptDialog
## Original-style Command dialog: link/break commander–subordinate relationships.
## Reads GameState; mutates only via CommandRouter.submit_command().

const AssignCommanderCommandClass := preload("res://scripts/commands/assign_commander_command.gd")
const BreakCommandLinkCommandClass := preload("res://scripts/commands/break_command_link_command.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")

signal briefing_requested
signal dialog_closed

var _game_state: GameStateClass = null

var _commanders_list: ItemList
var _unassigned_list: ItemList
var _links_list: ItemList
var _status_label: Label
var _link_button: Button
var _break_button: Button


func _ready() -> void:
	title = "Command"
	ok_button_text = "Close"
	dialog_hide_on_ok = true
	CocUiTheme.apply_to(self)
	_build_layout()
	confirmed.connect(_on_closed)
	canceled.connect(_on_closed)


func bind_game_state(game_state: GameStateClass) -> void:
	_game_state = game_state
	refresh()


func refresh() -> void:
	if _commanders_list == null or _game_state == null or _game_state.command_hierarchy == null:
		return
	var hierarchy := _game_state.command_hierarchy
	## USA only links USA; Germany only links Germany.
	var local_team := hierarchy.get_team_id(_game_state.local_player_id)

	## Left: AI fireteams without a commander (to be assigned under a human).
	_unassigned_list.clear()
	for pid in hierarchy.players_without_commanders():
		if hierarchy.get_team_id(pid) != local_team:
			continue
		if not hierarchy.is_ai_player(pid):
			continue
		_unassigned_list.add_item(hierarchy.list_label(pid))
		_unassigned_list.set_item_metadata(_unassigned_list.item_count - 1, pid)

	## Right: human commanders with openings only — AI is never a commander candidate.
	_commanders_list.clear()
	for pid in hierarchy.commanders_with_openings():
		if hierarchy.get_team_id(pid) != local_team:
			continue
		if hierarchy.is_ai_player(pid):
			continue
		_commanders_list.add_item(hierarchy.list_label(pid))
		_commanders_list.set_item_metadata(_commanders_list.item_count - 1, pid)

	_links_list.clear()
	for link in hierarchy.all_links():
		var cmd_id := int(link.get("commander_id", -1))
		var sub_id := int(link.get("subordinate_id", -1))
		if hierarchy.get_team_id(cmd_id) != local_team:
			continue
		var text := "%s  →  %s" % [hierarchy.list_label(cmd_id), hierarchy.list_label(sub_id)]
		_links_list.add_item(text)
		_links_list.set_item_metadata(_links_list.item_count - 1, sub_id)


func _build_layout() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title_row := Label.new()
	title_row.text = "Command"
	title_row.add_theme_color_override("font_color", Color(0.85, 0.72, 0.2))
	title_row.add_theme_font_size_override("font_size", 16)
	root.add_child(title_row)

	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)

	var left := _make_list_column("Without Commanders\n(AI Fireteams)")
	_unassigned_list = left["list"]
	top.add_child(left["root"])

	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.custom_minimum_size = Vector2(120, 0)
	_link_button = Button.new()
	_link_button.text = "Commanded by ▶▶▶"
	_link_button.pressed.connect(_on_link_pressed)
	mid.add_child(_link_button)
	top.add_child(mid)

	var right := _make_list_column("Commanders with Openings\n(Players)")
	_commanders_list = right["list"]
	top.add_child(right["root"])

	var bottom_header := Label.new()
	bottom_header.text = "Existing Commander-Subordinate Connections"
	root.add_child(bottom_header)
	var hint := Label.new()
	hint.text = "You can break these by selecting and then clicking 'break'"
	hint.add_theme_font_size_override("font_size", 10)
	root.add_child(hint)

	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)

	_links_list = ItemList.new()
	_links_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_links_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_links_list.custom_minimum_size = Vector2(360, 100)
	_links_list.select_mode = ItemList.SELECT_SINGLE
	bottom.add_child(_links_list)

	var break_col := VBoxContainer.new()
	_break_button = Button.new()
	_break_button.text = "Break"
	_break_button.pressed.connect(_on_break_pressed)
	break_col.add_child(_break_button)
	bottom.add_child(break_col)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)
	root.add_child(footer)
	var briefing_btn := Button.new()
	briefing_btn.text = "View Briefing"
	briefing_btn.pressed.connect(_on_briefing_pressed)
	footer.add_child(briefing_btn)


func _make_list_column(header: String) -> Dictionary:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = header
	col.add_child(label)
	var list := ItemList.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(180, 120)
	list.select_mode = ItemList.SELECT_SINGLE
	col.add_child(list)
	return {"root": col, "list": list}


func _selected_meta(list: ItemList) -> int:
	var selected := list.get_selected_items()
	if selected.is_empty():
		return -1
	return int(list.get_item_metadata(selected[0]))


func _on_link_pressed() -> void:
	if _game_state == null:
		return
	## Left = AI subordinate, right = human commander ("Commanded by ▶▶▶").
	var subordinate_id := _selected_meta(_unassigned_list)
	var commander_id := _selected_meta(_commanders_list)
	var hierarchy := _game_state.command_hierarchy
	if hierarchy != null:
		if commander_id > 0 and hierarchy.is_ai_player(commander_id):
			_status_label.text = "Only human players can command AI fireteams."
			_status_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
			return
	var cmd := AssignCommanderCommandClass.new()
	cmd.commander_id = commander_id
	cmd.subordinate_id = subordinate_id
	var result = CommandRouter.submit_command(_game_state, cmd)
	_show_result(result)
	refresh()


func _on_break_pressed() -> void:
	if _game_state == null:
		return
	var subordinate_id := _selected_meta(_links_list)
	var cmd := BreakCommandLinkCommandClass.new()
	cmd.subordinate_id = subordinate_id
	var result = CommandRouter.submit_command(_game_state, cmd)
	_show_result(result)
	refresh()


func _on_briefing_pressed() -> void:
	briefing_requested.emit()
	_status_label.text = (
		"Briefing: select an AI fireteam on the left and a human commander on the right, then Commanded by. "
		+ "Only humans command AI. USA only commands USA; Germany only commands Germany. Visibility flows upward."
	)


func _show_result(result) -> void:
	if result == null:
		_status_label.text = ""
		return
	_status_label.text = str(result.status_message)
	_status_label.add_theme_color_override(
		"font_color",
		Color(0.85, 0.25, 0.2) if not result.success else Color(0.15, 0.55, 0.2),
	)


func _on_closed() -> void:
	## Main decides whether to leave deployment (Offline) or keep the timed countdown (SP/MP).
	dialog_closed.emit()
