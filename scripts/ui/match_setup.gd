extends Control
## Match setup: 1v1 / 2v2, Farm Fight, player slot controllers, AI plans.
## Writes MatchConfig → main. Draft AI plans live on MatchConfig slots until match start.

const MatchConfigClass := preload("res://scripts/core/match_config.gd")
const MatchConfigStoreClass := preload("res://scripts/core/match_config_store.gd")
const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const MODE_SELECT_SCENE := "res://scenes/mode_select.tscn"

var _config: MatchConfigClass
var _status: Label
var _usa_list: ItemList
var _ger_list: ItemList
var _type_1v1: Button
var _type_2v2: Button
var _switch_side: Button
var _cycle_controller: Button
var _ai_plans_root: VBoxContainer
## player_id -> OptionButton
var _plan_option_by_player: Dictionary = {}


func _ready() -> void:
	CocUiTheme.apply_to(self)
	var pending_mode := MatchConfigStoreClass.consume_setup_game_mode(
		MatchConfigClass.GameModeKind.SINGLE_PLAYER
	)
	_config = MatchConfigClass.new(pending_mode, MatchConfigClass.MatchType.ONE_V_ONE)
	_build_layout()
	_refresh()


func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.12, 0.18, 0.14, 1)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	CocUiTheme.apply_to(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Match Setup"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)

	var mode_lbl := Label.new()
	mode_lbl.text = MatchConfigClass.game_mode_label(_config.game_mode)
	mode_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(mode_lbl)

	var type_row := HBoxContainer.new()
	type_row.alignment = BoxContainer.ALIGNMENT_CENTER
	type_row.add_theme_constant_override("separation", 8)
	root.add_child(type_row)
	var type_lbl := Label.new()
	type_lbl.text = "Match Type:"
	type_row.add_child(type_lbl)
	_type_1v1 = Button.new()
	_type_1v1.text = "1v1"
	_type_1v1.toggle_mode = true
	_type_1v1.pressed.connect(func() -> void: _set_match_type(MatchConfigClass.MatchType.ONE_V_ONE))
	type_row.add_child(_type_1v1)
	_type_2v2 = Button.new()
	_type_2v2.text = "2v2"
	_type_2v2.toggle_mode = true
	_type_2v2.pressed.connect(func() -> void: _set_match_type(MatchConfigClass.MatchType.TWO_V_TWO))
	type_row.add_child(_type_2v2)

	var map_lbl := Label.new()
	map_lbl.text = "Map: Farm Fight"
	map_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(map_lbl)

	var assign_hdr := Label.new()
	assign_hdr.text = "Player Assignment"
	assign_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(assign_hdr)

	var lists := HBoxContainer.new()
	lists.add_theme_constant_override("separation", 16)
	root.add_child(lists)

	var usa_col := VBoxContainer.new()
	usa_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(usa_col)
	var usa_hdr := Label.new()
	usa_hdr.text = "USA"
	usa_col.add_child(usa_hdr)
	_usa_list = ItemList.new()
	_usa_list.custom_minimum_size = Vector2(220, 100)
	_usa_list.select_mode = ItemList.SELECT_SINGLE
	usa_col.add_child(_usa_list)

	var ger_col := VBoxContainer.new()
	ger_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(ger_col)
	var ger_hdr := Label.new()
	ger_hdr.text = "Germany"
	ger_col.add_child(ger_hdr)
	_ger_list = ItemList.new()
	_ger_list.custom_minimum_size = Vector2(220, 100)
	_ger_list.select_mode = ItemList.SELECT_SINGLE
	ger_col.add_child(_ger_list)

	var tools := HBoxContainer.new()
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	tools.add_theme_constant_override("separation", 8)
	root.add_child(tools)
	_switch_side = Button.new()
	_switch_side.text = "Switch Sides"
	_switch_side.pressed.connect(_on_switch_sides)
	tools.add_child(_switch_side)
	_cycle_controller = Button.new()
	_cycle_controller.text = "Cycle Selected Controller"
	_cycle_controller.pressed.connect(_on_cycle_controller)
	tools.add_child(_cycle_controller)

	var plans_hdr := Label.new()
	plans_hdr.text = "AI Plans (pre-game)"
	plans_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(plans_hdr)
	_ai_plans_root = VBoxContainer.new()
	_ai_plans_root.add_theme_constant_override("separation", 6)
	root.add_child(_ai_plans_root)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 36)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MODE_SELECT_SCENE))
	footer.add_child(back)
	var start := Button.new()
	start.text = "Start Match"
	start.custom_minimum_size = Vector2(160, 36)
	start.pressed.connect(_on_start)
	footer.add_child(start)


func _set_match_type(match_type: int) -> void:
	_config.set_match_type(match_type)
	_refresh()


func _on_switch_sides() -> void:
	_config.switch_human_side()
	_refresh()


func _selected_player_id() -> int:
	for list in [_usa_list, _ger_list]:
		var selected: PackedInt32Array = list.get_selected_items()
		if selected.is_empty():
			continue
		return int(list.get_item_metadata(selected[0]))
	return -1


func _on_cycle_controller() -> void:
	var pid := _selected_player_id()
	if pid <= 0:
		_status.text = "Select a player slot first."
		return
	var current := MatchConfigClass.ControllerType.AI
	for slot in _config.slots:
		if int(slot.get("player_id", -1)) == pid:
			current = int(slot.get("controller", MatchConfigClass.ControllerType.AI))
			break
	var next := current
	## SP and MP: Human ↔ AI. Unused seats stay AI; joining humans replace AI at runtime.
	## OPEN remains valid for legacy lobbies and is filled to AI on Start.
	if current == MatchConfigClass.ControllerType.HUMAN:
		next = MatchConfigClass.ControllerType.AI
	elif current == MatchConfigClass.ControllerType.OPEN:
		next = MatchConfigClass.ControllerType.HUMAN
	else:
		next = MatchConfigClass.ControllerType.HUMAN
	## SP enforces a single Human via set_slot_controller demotion.
	_config.set_slot_controller(pid, next)
	_refresh()


func _on_start() -> void:
	## Unused Open seats become AI so every slot has a controller before GameState.
	_config.fill_open_slots_with_ai()
	var result: Dictionary = _config.validate()
	if not bool(result.get("ok", false)):
		var errs: PackedStringArray = result.get("errors", PackedStringArray())
		_status.text = "\n".join(errs)
		_status.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
		return
	PlayerSides.clear()
	GameModeManager.set_mode(_config.to_runtime_game_mode())
	## Soft side lock for multiplayer: prefer local human team when present.
	for slot in _config.slots:
		if int(slot.get("controller", -1)) == MatchConfigClass.ControllerType.HUMAN:
			PlayerSides.assign_team(int(slot.get("team_id", Team.USA)))
			break
	MatchConfigStoreClass.set_pending(_config)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _refresh() -> void:
	_type_1v1.set_pressed_no_signal(_config.match_type == MatchConfigClass.MatchType.ONE_V_ONE)
	_type_2v2.set_pressed_no_signal(_config.match_type == MatchConfigClass.MatchType.TWO_V_TWO)
	_switch_side.visible = _config.game_mode == MatchConfigClass.GameModeKind.SINGLE_PLAYER
	_fill_team_list(_usa_list, Team.USA)
	_fill_team_list(_ger_list, Team.GERMANY)
	_rebuild_ai_plan_selectors()
	_status.text = "%s · %s · Farm Fight" % [
		MatchConfigClass.game_mode_label(_config.game_mode),
		MatchConfigClass.match_type_label(_config.match_type),
	]
	_status.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2))


func _fill_team_list(list: ItemList, team_id: int) -> void:
	list.clear()
	var team_slots := _config.slots_for_team(team_id)
	for slot in team_slots:
		## 1v1: one row; 2v2: both rows. slots_for_team already filtered.
		if (
			_config.match_type == MatchConfigClass.MatchType.ONE_V_ONE
			and int(slot.get("slot_index", 0)) > 0
		):
			continue
		var label := "Player %d — %s" % [
			int(slot.get("slot_index", 0)) + 1,
			MatchConfigClass.controller_label(int(slot.get("controller", 0))),
		]
		list.add_item(label)
		list.set_item_metadata(list.item_count - 1, int(slot.get("player_id", -1)))


func _rebuild_ai_plan_selectors() -> void:
	## Keep valid existing choices on MatchConfig; only rebuild OptionButtons.
	while _ai_plans_root.get_child_count() > 0:
		var child := _ai_plans_root.get_child(0)
		_ai_plans_root.remove_child(child)
		child.free()
	_plan_option_by_player.clear()

	var ai_slots := _config.ai_slots()
	if ai_slots.is_empty():
		var empty := Label.new()
		empty.text = "No AI players in this match."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ai_plans_root.add_child(empty)
		return

	for slot in ai_slots:
		if (
			_config.match_type == MatchConfigClass.MatchType.ONE_V_ONE
			and int(slot.get("slot_index", 0)) > 0
		):
			continue
		var player_id := int(slot.get("player_id", -1))
		var team_id := int(slot.get("team_id", Team.USA))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_ai_plans_root.add_child(row)

		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.text = "%s · %s · Controller: AI" % [
			str(slot.get("display_name", "Player %d" % player_id)),
			Team.display_name(team_id),
		]
		row.add_child(info)

		var plan_lbl := Label.new()
		plan_lbl.text = "Plan:"
		row.add_child(plan_lbl)

		var option := OptionButton.new()
		option.custom_minimum_size = Vector2(140, 0)
		for plan_id in AiPlanClass.ALL_IDS:
			option.add_item(AiPlanClass.display_name(plan_id))
			option.set_item_metadata(option.item_count - 1, plan_id)
		var selected := AiPlanClass.normalize_id(str(slot.get("selected_ai_plan", "")))
		if not AiPlanClass.is_valid_id(selected):
			selected = AiPlanClass.default_selected_for_slot(
				MatchConfigClass.ControllerType.AI,
				team_id,
				_config.local_human_team_id(),
			)
			_config.set_slot_ai_plan(player_id, selected)
		for i in option.item_count:
			if str(option.get_item_metadata(i)) == selected:
				option.select(i)
				break
		option.item_selected.connect(_on_ai_plan_selected.bind(player_id, option))
		row.add_child(option)
		_plan_option_by_player[player_id] = option


func _on_ai_plan_selected(index: int, player_id: int, option: OptionButton) -> void:
	var plan_id := str(option.get_item_metadata(index))
	if not _config.set_slot_ai_plan(player_id, plan_id):
		_status.text = "Could not set AI plan for player %d." % player_id
		_status.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
