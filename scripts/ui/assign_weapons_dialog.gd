class_name AssignWeaponsDialog
extends AcceptDialog
## Original-style Weapons dialog: individual cache items → subordinates / soldiers.
## Layout: pool | Assign to + subordinate players square | soldiers with weapon, ammo.
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
var _subordinates_list: ItemList
var _soldiers_list: ItemList
var _status_label: Label
var _assign_button: Button
var _return_button: Button
var _add_ammo_button: Button


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

	_pool_list.clear()
	## List each physical item individually (4 ammo boxes → 4 rows).
	for entry in cache.get_cache(_player_id):
		var item_id := str(entry.get("item_id", ""))
		var count := int(entry.get("count", 0))
		if item_id.is_empty() or count <= 0:
			continue
		var label := cache.display_name(item_id)
		for _i in count:
			_pool_list.add_item(label)
			_pool_list.set_item_metadata(_pool_list.item_count - 1, item_id)

	_subordinates_list.clear()
	var subs: Array[int] = []
	if hierarchy != null:
		subs = hierarchy.get_subordinates(_player_id)
	for pid in subs:
		var text := hierarchy.get_display_name(pid)
		if hierarchy.is_ai_player(pid):
			text = "%s (AI)" % text
		_subordinates_list.add_item(text)
		_subordinates_list.set_item_metadata(_subordinates_list.item_count - 1, pid)

	_refresh_soldiers_list()


func _refresh_soldiers_list() -> void:
	_soldiers_list.clear()
	if _game_state == null or _game_state.weapon_cache == null:
		return
	var cache: WeaponCacheClass = _game_state.weapon_cache
	var hierarchy = _game_state.command_hierarchy
	var owner_id := _player_id
	var selected_sub := _selected_int_meta(_subordinates_list)
	## Viewing a human subordinate's soldiers; AI fireteams receive gear via the player slot.
	if selected_sub > 0 and hierarchy != null and not hierarchy.is_ai_player(selected_sub):
		owner_id = selected_sub
	var team_id := hierarchy.get_team_id(owner_id) if hierarchy != null else Team.USA
	var soldier_ids: Array[int] = []
	if hierarchy != null:
		soldier_ids = hierarchy.get_soldier_ids(owner_id)
	for sid in soldier_ids:
		var soldier: SoldierState = _game_state.get_soldier(team_id, sid)
		if soldier == null:
			continue
		var weapon_text := cache.display_name(str(soldier.weapon_id))
		var line := "soldier%d   %s, %d" % [sid, weapon_text, soldier.ammo_current]
		_soldiers_list.add_item(line)
		_soldiers_list.set_item_metadata(_soldiers_list.item_count - 1, {
			"soldier_id": sid,
			"owner_player_id": owner_id,
			"team_id": team_id,
		})


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

	## Center: Assign to + black square of subordinate player names (original layout).
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(160, 0)
	mid.add_theme_constant_override("separation", 8)
	_assign_button = Button.new()
	_assign_button.text = "Assign to ▶▶▶"
	_assign_button.pressed.connect(_on_assign_pressed)
	mid.add_child(_assign_button)
	_return_button = Button.new()
	_return_button.text = "Return ◀◀◀"
	_return_button.pressed.connect(_on_return_pressed)
	mid.add_child(_return_button)
	_add_ammo_button = Button.new()
	_add_ammo_button.text = "Add Ammo ▶"
	_add_ammo_button.tooltip_text = "Assign an Ammunition Box to the selected soldier's gun."
	_add_ammo_button.pressed.connect(_on_add_ammo_pressed)
	mid.add_child(_add_ammo_button)

	var sub_hdr := Label.new()
	sub_hdr.text = "Subordinate players"
	sub_hdr.add_theme_font_size_override("font_size", 11)
	mid.add_child(sub_hdr)
	_subordinates_list = ItemList.new()
	_subordinates_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subordinates_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_subordinates_list.custom_minimum_size = Vector2(150, 120)
	_subordinates_list.select_mode = ItemList.SELECT_SINGLE
	_subordinates_list.item_selected.connect(_on_subordinate_selected)
	## Dark panel look matching the original empty black square.
	_subordinates_list.add_theme_color_override("font_color", Color(0.95, 0.9, 0.35))
	_subordinates_list.add_theme_color_override("font_selected_color", Color(1, 1, 0.55))
	_subordinates_list.add_theme_stylebox_override("panel", _dark_list_style())
	mid.add_child(_subordinates_list)
	body.add_child(mid)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)

	var right_header := Label.new()
	right_header.text = "Assign to subordinate players/soldiers"
	right.add_child(right_header)

	_soldiers_list = ItemList.new()
	_soldiers_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_soldiers_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_soldiers_list.custom_minimum_size = Vector2(220, 180)
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


func _dark_list_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 1)
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.25, 0.25, 1)
	style.set_content_margin_all(4)
	return style


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


func _selected_soldier_meta() -> Dictionary:
	var selected := _soldiers_list.get_selected_items()
	if selected.is_empty():
		return {}
	var meta: Variant = _soldiers_list.get_item_metadata(selected[0])
	if meta is Dictionary:
		return meta as Dictionary
	return {}


func _on_subordinate_selected(_index: int) -> void:
	_soldiers_list.deselect_all()
	_refresh_soldiers_list()


func _on_soldier_selected(_index: int) -> void:
	## Keep subordinate selection — soldier rows may belong to that player.
	pass


func _on_assign_pressed() -> void:
	if _game_state == null:
		return
	var item_id := _selected_string_meta(_pool_list)
	var player_target := _selected_int_meta(_subordinates_list)
	var soldier_meta := _selected_soldier_meta()
	var cmd := AssignWeaponCommandClass.new()
	cmd.from_player_id = _player_id
	cmd.item_id = item_id
	if player_target > 0 and soldier_meta.is_empty():
		## Giving gear to a subordinate player's cache (whole AI fireteam / allied player).
		cmd.target_kind = WeaponCacheClass.TargetKind.PLAYER
		cmd.target_id = player_target
	elif not soldier_meta.is_empty():
		cmd.target_kind = WeaponCacheClass.TargetKind.SOLDIER
		cmd.target_id = int(soldier_meta.get("soldier_id", -1))
		cmd.target_team_id = int(soldier_meta.get("team_id", Team.USA))
		## Assignments to another player's soldiers still come from our cache but must be ours.
		var owner_id := int(soldier_meta.get("owner_player_id", _player_id))
		if owner_id != _player_id:
			_status_label.text = "Select your own soldiers, or Assign to the subordinate player."
			_status_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
			return
	else:
		cmd.target_id = -1
	var result = CommandRouter.submit_command(_game_state, cmd)
	_show_result(result)
	refresh()


func _on_add_ammo_pressed() -> void:
	## Convenience: pick an ammo box from the pool (or require one selected) → selected soldier.
	if _game_state == null:
		return
	var soldier_meta := _selected_soldier_meta()
	if soldier_meta.is_empty():
		_status_label.text = "Select a soldier to add ammo to their gun."
		_status_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
		return
	var owner_id := int(soldier_meta.get("owner_player_id", _player_id))
	if owner_id != _player_id:
		_status_label.text = "You can only add ammo to your own soldiers' guns."
		_status_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
		return
	var item_id := _selected_string_meta(_pool_list)
	if item_id.is_empty() or item_id != WeaponCacheClass.ITEM_AMMUNITION_BOX:
		## Auto-select ammo box if any remain.
		if _game_state.weapon_cache.pool_count(_player_id, WeaponCacheClass.ITEM_AMMUNITION_BOX) <= 0:
			_status_label.text = "No Ammunition Box available in your cache."
			_status_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
			return
		item_id = WeaponCacheClass.ITEM_AMMUNITION_BOX
	var cmd := AssignWeaponCommandClass.new()
	cmd.from_player_id = _player_id
	cmd.item_id = item_id
	cmd.target_kind = WeaponCacheClass.TargetKind.SOLDIER
	cmd.target_id = int(soldier_meta.get("soldier_id", -1))
	cmd.target_team_id = int(soldier_meta.get("team_id", Team.USA))
	var result = CommandRouter.submit_command(_game_state, cmd)
	_show_result(result)
	refresh()


func _on_return_pressed() -> void:
	if _game_state == null:
		return
	var soldier_meta := _selected_soldier_meta()
	if soldier_meta.is_empty():
		_status_label.text = "Choose a target for weapon assignment"
		_status_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
		return
	var owner_id := int(soldier_meta.get("owner_player_id", _player_id))
	if owner_id != _player_id:
		_status_label.text = "You can only return weapons from your own soldiers."
		_status_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
		return
	var team_id := int(soldier_meta.get("team_id", Team.USA))
	var soldier_id := int(soldier_meta.get("soldier_id", -1))
	var soldier: SoldierState = _game_state.get_soldier(team_id, soldier_id)
	var cmd := ReturnWeaponCommandClass.new()
	cmd.to_player_id = _player_id
	cmd.team_id = team_id
	cmd.soldier_id = soldier_id
	cmd.item_id = str(soldier.weapon_id) if soldier != null else ""
	var result = CommandRouter.submit_command(_game_state, cmd)
	_show_result(result)
	refresh()


func _on_briefing_pressed() -> void:
	briefing_requested.emit()
	_status_label.text = (
		"Briefing: assign weapons from your cache to your soldiers, "
		+ "or to subordinate players / AI fireteams. Use Add Ammo for ammunition boxes."
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
	dialog_closed.emit()
