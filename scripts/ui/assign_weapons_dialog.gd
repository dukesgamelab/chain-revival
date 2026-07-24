class_name AssignWeaponsDialog
extends AcceptDialog
## Original-style Weapons dialog: assign cache items to subordinates / own soldiers.
## Reads GameState; mutates only via CommandRouter.submit_command().

const AssignWeaponCommandClass := preload("res://scripts/commands/assign_weapon_command.gd")
const ReturnWeaponCommandClass := preload("res://scripts/commands/return_weapon_command.gd")
const WeaponCacheClass := preload("res://scripts/core/weapon_cache.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")

signal briefing_requested
signal dialog_closed

var _game_state: GameStateClass = null
var _player_id: int = 1

var _pool_list: ItemList
var _players_header: Label
var _players_list: ItemList
var _players_column: VBoxContainer
var _soldiers_list: ItemList
var _status_label: Label
var _assign_button: Button
var _return_button: Button


func _ready() -> void:
	title = "Weapons"
	ok_button_text = "Close"
	dialog_hide_on_ok = true
	CocUiTheme.apply_to(self)
	_build_layout()
	confirmed.connect(_on_closed)
	canceled.connect(_on_closed)


func bind_game_state(game_state: GameStateClass, player_id: int = -1) -> void:
	_game_state = game_state
	if player_id > 0:
		_player_id = player_id
	elif game_state != null:
		_player_id = game_state.local_player_id
	refresh()


func refresh() -> void:
	if _pool_list == null or _game_state == null or _game_state.weapon_cache == null:
		return
	var cache: WeaponCacheClass = _game_state.weapon_cache
	var hierarchy = _game_state.command_hierarchy
	var team_id := hierarchy.get_team_id(_player_id) if hierarchy != null else Team.USA

	_pool_list.clear()
	for entry in cache.get_cache(_player_id):
		var item_id := str(entry.get("item_id", ""))
		var count := int(entry.get("count", 0))
		if item_id.is_empty() or count <= 0:
			continue
		_pool_list.add_item(cache.pool_line(item_id, count))
		_pool_list.set_item_metadata(_pool_list.item_count - 1, item_id)

	_players_list.clear()
	var subs: Array[int] = []
	if hierarchy != null:
		subs = hierarchy.get_subordinates(_player_id)
	for pid in subs:
		var text := "%s   %s" % [
			hierarchy.get_display_name(pid),
			hierarchy.rank_label(hierarchy.get_rank(pid)),
		]
		_players_list.add_item(text)
		_players_list.set_item_metadata(_players_list.item_count - 1, pid)
	var show_players := not subs.is_empty()
	_players_column.visible = show_players
	_players_header.visible = show_players

	_soldiers_list.clear()
	var soldier_ids: Array[int] = []
	if hierarchy != null:
		soldier_ids = hierarchy.get_soldier_ids(_player_id)
	for sid in soldier_ids:
		var soldier: SoldierState = _game_state.get_soldier(team_id, sid)
		if soldier == null:
			continue
		var weapon_text := cache.display_name(str(soldier.weapon_id))
		var line := "soldier%d   %s, %d" % [sid, weapon_text, soldier.ammo_current]
		_soldiers_list.add_item(line)
		_soldiers_list.set_item_metadata(_soldiers_list.item_count - 1, sid)


func _build_layout() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title_row := Label.new()
	title_row.text = "Weapons"
	title_row.add_theme_color_override("font_color", Color(0.85, 0.72, 0.2))
	title_row.add_theme_font_size_override("font_size", 16)
	root.add_child(title_row)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)

	var left := _make_list_column("Weapons/Equipment to be assigned")
	_pool_list = left["list"]
	body.add_child(left["root"])

	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.custom_minimum_size = Vector2(140, 0)
	mid.add_theme_constant_override("separation", 8)
	_assign_button = Button.new()
	_assign_button.text = "Assign to ▶▶▶"
	_assign_button.pressed.connect(_on_assign_pressed)
	mid.add_child(_assign_button)
	_return_button = Button.new()
	_return_button.text = "Return ◀◀◀"
	_return_button.pressed.connect(_on_return_pressed)
	mid.add_child(_return_button)
	body.add_child(mid)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)

	var right_header := Label.new()
	right_header.text = "Assign to subordinate players/soldiers"
	right.add_child(right_header)

	_players_column = VBoxContainer.new()
	_players_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_players_header = Label.new()
	_players_header.text = "Players"
	_players_column.add_child(_players_header)
	_players_list = ItemList.new()
	_players_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_players_list.custom_minimum_size = Vector2(200, 72)
	_players_list.select_mode = ItemList.SELECT_SINGLE
	_players_list.item_selected.connect(_on_player_selected)
	_players_column.add_child(_players_list)
	right.add_child(_players_column)

	var soldiers_header := Label.new()
	soldiers_header.text = "Soldiers"
	right.add_child(soldiers_header)
	_soldiers_list = ItemList.new()
	_soldiers_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_soldiers_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_soldiers_list.custom_minimum_size = Vector2(200, 100)
	_soldiers_list.select_mode = ItemList.SELECT_SINGLE
	_soldiers_list.item_selected.connect(_on_soldier_selected)
	right.add_child(_soldiers_list)

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
	list.custom_minimum_size = Vector2(200, 180)
	list.select_mode = ItemList.SELECT_SINGLE
	col.add_child(list)
	return {"root": col, "list": list}


func _selected_string_meta(list: ItemList) -> String:
	var selected := list.get_selected_items()
	if selected.is_empty():
		return ""
	return str(list.get_item_metadata(selected[0]))


func _selected_int_meta(list: ItemList) -> int:
	var selected := list.get_selected_items()
	if selected.is_empty():
		return -1
	return int(list.get_item_metadata(selected[0]))


func _on_player_selected(_index: int) -> void:
	_soldiers_list.deselect_all()


func _on_soldier_selected(_index: int) -> void:
	_players_list.deselect_all()


func _on_assign_pressed() -> void:
	if _game_state == null:
		return
	var item_id := _selected_string_meta(_pool_list)
	var player_target := _selected_int_meta(_players_list)
	var soldier_target := _selected_int_meta(_soldiers_list)
	var cmd := AssignWeaponCommandClass.new()
	cmd.from_player_id = _player_id
	cmd.item_id = item_id
	if player_target > 0:
		cmd.target_kind = WeaponCacheClass.TargetKind.PLAYER
		cmd.target_id = player_target
	elif soldier_target > 0:
		cmd.target_kind = WeaponCacheClass.TargetKind.SOLDIER
		cmd.target_id = soldier_target
		if _game_state.command_hierarchy != null:
			cmd.target_team_id = _game_state.command_hierarchy.get_team_id(_player_id)
	else:
		cmd.target_id = -1
	var result = CommandRouter.submit_command(_game_state, cmd)
	_show_result(result)
	refresh()


func _on_return_pressed() -> void:
	if _game_state == null:
		return
	var soldier_target := _selected_int_meta(_soldiers_list)
	if soldier_target <= 0:
		_status_label.text = "Choose a target for weapon assignment"
		_status_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
		return
	var team_id := Team.USA
	if _game_state.command_hierarchy != null:
		team_id = _game_state.command_hierarchy.get_team_id(_player_id)
	var soldier: SoldierState = _game_state.get_soldier(team_id, soldier_target)
	var cmd := ReturnWeaponCommandClass.new()
	cmd.to_player_id = _player_id
	cmd.team_id = team_id
	cmd.soldier_id = soldier_target
	cmd.item_id = str(soldier.weapon_id) if soldier != null else ""
	var result = CommandRouter.submit_command(_game_state, cmd)
	_show_result(result)
	refresh()


func _on_briefing_pressed() -> void:
	briefing_requested.emit()
	_status_label.text = "Briefing: assign weapons from your cache to soldiers or subordinates."


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
	dialog_closed.emit()
