class_name MissionDebriefDialog
extends AcceptDialog
## Mission-End Debriefing — layout mirrors the original Close Combat results screen.

signal finished

const ScenarioEndCauseClass := preload("res://scripts/enums/scenario_end_cause.gd")
const ScenarioWinnerClass := preload("res://scripts/enums/scenario_winner.gd")
const ScenarioRulesClass := preload("res://scripts/core/scenario_rules.gd")
const CommandHierarchyClass := preload("res://scripts/core/command_hierarchy.gd")

var _game_state: GameState = null
var _body: VBoxContainer = null
var _close_countdown_sec: float = 23.0
var _countdown_label: Label = null
var _finish_emitted: bool = false


func _ready() -> void:
	title = "Mission-End Debriefing"
	ok_button_text = "Close"
	dialog_hide_on_ok = true
	transient = true
	exclusive = true
	unresizable = true
	CocUiTheme.apply_to(self)
	## Theme blank-button chrome is toolbar-narrow; widen so "Close" is not clipped to "Clos".
	var ok := get_ok_button()
	if ok != null:
		ok.text = "Close"
		ok.clip_text = false
		ok.custom_minimum_size = Vector2(72, CocUiTheme.BUTTON_HEIGHT)
	confirmed.connect(_notify_finished)
	close_requested.connect(_on_close_requested)
	visibility_changed.connect(_on_visibility_changed)
	_build_layout()


func _process(delta: float) -> void:
	if not visible or _countdown_label == null:
		return
	_close_countdown_sec = maxf(0.0, _close_countdown_sec - delta)
	var t := int(_close_countdown_sec)
	_countdown_label.text = "Time Remaining: %02d:%02d" % [t / 60, t % 60]
	if _close_countdown_sec <= 0.0:
		hide()


func bind_game_state(game_state: GameState) -> void:
	_game_state = game_state
	_close_countdown_sec = 23.0
	_finish_emitted = false
	_rebuild_content()


func _on_close_requested() -> void:
	hide()
	_notify_finished()


func _on_visibility_changed() -> void:
	if not visible:
		_notify_finished()


func _notify_finished() -> void:
	if _finish_emitted:
		return
	_finish_emitted = true
	finished.emit()


func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## Content-sized — do not expand to fill a tall window.
	_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(_body)

	## AcceptDialog is a Window — size to content, not a tall forced min height.
	min_size = Vector2(820, 0)


func _rebuild_content() -> void:
	if _body == null or _game_state == null:
		return
	for child in _body.get_children():
		child.queue_free()

	var parchment := _parchment_panel()
	_body.add_child(parchment)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parchment.add_child(root)

	var title := _header("Mission-End Debriefing", 20)
	root.add_child(title)
	root.add_child(_body_label(ScenarioEndCauseClass.display_name(_game_state.end_cause), true))
	root.add_child(_body_label(ScenarioWinnerClass.display_name(_game_state.winner), true))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	## Shrink to content height — EXPAND_FILL was stretching columns off-screen.
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(top)

	top.add_child(_build_fireteam_panel())
	top.add_child(_build_victory_points_panel())

	root.add_child(_build_promotion_panel())

	var footer := HBoxContainer.new()
	_countdown_label = _body_label("Time Remaining: 00:23", false)
	_countdown_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_countdown_label)
	root.add_child(footer)

	## Fit window to content after layout rebuild.
	call_deferred("_fit_window_to_content")


func _fit_window_to_content() -> void:
	if _body == null:
		return
	var content := _body.get_combined_minimum_size()
	var w := maxf(820.0, content.x + 40.0)
	var h := content.y + 96.0
	## Cap so tall monitors don't get a giant empty dialog.
	h = clampf(h, 360.0, 640.0)
	size = Vector2(w, h)
	min_size = Vector2(820, 0)


func _build_fireteam_panel() -> PanelContainer:
	var panel := _inset_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(260, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(col)
	col.add_child(_header("YOU AND YOUR FIRETEAM", 14))

	var local_team := _game_state.local_team_id()
	var ft: Fireteam = _game_state.session.get_fireteam(local_team)
	var local_pid := _game_state.local_player_id
	var any_alive := false
	if ft != null:
		for state in ft.soldiers:
			var s: SoldierState = state
			if s == null:
				continue
			var status := "OK" if not s.is_dead else "Killed"
			if not s.is_dead:
				any_alive = true
			var line := "Soldier #%d:  %s" % [s.soldier_id, status]
			## Mark the first living (or first) soldier as YOU for offline/local.
			if s.soldier_id == 1 or (local_pid > 0 and s.soldier_id == 1):
				if status == "OK":
					line += " – this was YOU."
			col.add_child(_body_label(line, false))

	col.add_child(_spacer(6))
	col.add_child(_body_label("You survived" if any_alive else "You did not survive", true))
	return panel


func _build_victory_points_panel() -> PanelContainer:
	var panel := _inset_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.6
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(420, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(col)
	col.add_child(_header("MISSION VICTORY POINTS", 14))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)

	var headers := ["Side", "Points for Kills", "Points for Terrain Objectives", "Total Points"]
	var header_mins := [88.0, 110.0, 150.0, 90.0]
	for i in headers.size():
		grid.add_child(_table_cell(headers[i], Color(0, 0, 0, 0), header_mins[i], true))

	_add_score_row(grid, "Americans", Team.USA, Color(0.78, 0.88, 0.72, 1.0))
	_add_score_row(grid, "Germans", Team.GERMANY, Color(0.70, 0.82, 0.62, 1.0))
	return panel


func _add_score_row(grid: GridContainer, side: String, team_id: int, tint: Color) -> void:
	var kills := int(_game_state.team_kill_points.get(team_id, 0))
	var terrain := int(_game_state.team_terrain_points.get(team_id, 0))
	var total := ScenarioRulesClass.total_points(_game_state, team_id)
	var mins := [88.0, 110.0, 150.0, 90.0]
	var texts := [side, str(kills), str(terrain), str(total)]
	for i in texts.size():
		grid.add_child(_table_cell(texts[i], tint, mins[i], false))


func _table_cell(text: String, tint: Color, min_width: float, is_header: bool) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(min_width, 0)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = tint if tint.a > 0.0 else Color(0, 0, 0, 0)
	style.set_content_margin_all(4)
	cell.add_theme_stylebox_override("panel", style)
	var lab := Label.new()
	lab.text = text
	## No autowrap — prevents the 1-character-wide vertical stack bug.
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	lab.clip_text = false
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05, 1.0))
	if is_header:
		lab.add_theme_font_size_override("font_size", 11)
	cell.add_child(lab)
	return cell


func _build_promotion_panel() -> PanelContainer:
	var panel := _inset_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(col)
	col.add_child(_header("PROMOTION POINTS (PPs)", 14))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	var pp_headers := [
		"Player",
		"Rank (PPs) at Mission start",
		"Current Rank (+PPs)",
		"PPs required to gain next Rank",
	]
	var pp_mins := [120.0, 170.0, 140.0, 160.0]
	for i in pp_headers.size():
		grid.add_child(_table_cell(pp_headers[i], Color(0, 0, 0, 0), pp_mins[i], true))

	var hierarchy: CommandHierarchyClass = _game_state.command_hierarchy
	var local_pid := _game_state.local_player_id
	var row_texts: Array[String] = ["Commander", "PFC [0]", "PFC [0]", "500"]
	if hierarchy != null and hierarchy.has_player(local_pid):
		var entry := hierarchy.get_entry(local_pid)
		var rank := int(entry.get("rank", 1))
		var pp := int(entry.get("pp", 0))
		var name := str(entry.get("display_name", "Commander"))
		var rank_label: String = str(
			CommandHierarchyClass.RANK_LABELS[
				clampi(rank, 0, CommandHierarchyClass.RANK_LABELS.size() - 1)
			]
		)
		var next_need: int = int(CommandHierarchyClass.PP_TO_NEXT_RANK.get(rank, 500))
		row_texts = [
			name,
			"%s [%d]" % [rank_label, 0],
			"%s [%d]" % [rank_label, pp],
			str(next_need),
		]
	for i in row_texts.size():
		grid.add_child(_table_cell(row_texts[i], Color(0, 0, 0, 0), pp_mins[i], false))

	var subs := PanelContainer.new()
	subs.custom_minimum_size = Vector2(0, 56)
	subs.add_theme_stylebox_override("panel", _green_block_style())
	var subs_label := Label.new()
	subs_label.text = "Subordinates"
	subs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subs_label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	subs.add_child(subs_label)
	col.add_child(subs)
	return panel


func _parchment_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.82, 0.78, 0.62, 1.0)
	style.border_color = Color(0.25, 0.22, 0.16, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _inset_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.76, 0.72, 0.56, 1.0)
	style.border_color = Color(0.35, 0.32, 0.22, 1.0)
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _green_block_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.55, 0.72, 0.45, 1.0)
	style.border_color = Color(0.25, 0.35, 0.18, 1.0)
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _header(text: String, size: int) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05, 1.0))
	return lab


func _body_label(text: String, centered: bool) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	)
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05, 1.0))
	return lab


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
