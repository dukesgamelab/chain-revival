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
signal save_requested
signal load_requested
signal map_save_requested
signal map_load_requested

@onready var _squad_row: SquadCommandRow = %SquadRow
@onready var _rows: Array[SoldierCommandRow] = [
	%Row1,
	%Row2,
	%Row3,
	%Row4,
]
@onready var _status_label: Label = %StatusLabel
@onready var _team_label: Label = %TeamLabel

var _selected_soldier_id: int = 1
var _move_target_soldier_id: int = -1
var _active_movement_mode: int = MovementMode.RUN
var _fire_at_soldier_id: int = -1
var _face_soldier_id: int = -1
var _active_team_id: int = Team.USA
var _soldier_weapon_names: Array[String] = ["", "", "", ""]


func _ready() -> void:
	_squad_row.move_mode_toggled.connect(_on_squad_move_mode_toggled)
	_squad_row.fire_at_toggled.connect(_on_squad_fire_at_toggled)

	for row in _rows:
		row.move_mode_toggled.connect(_on_row_move_mode_toggled)
		row.fire_at_toggled.connect(_on_row_fire_at_toggled)
		row.face_toggled.connect(_on_row_face_toggled)
		row.position_toggled.connect(_on_row_position_toggled)
		row.fire_control_selected.connect(_on_row_fire_control_selected)

	%SaveButton.pressed.connect(func() -> void: save_requested.emit())
	%LoadButton.pressed.connect(func() -> void: load_requested.emit())
	%MapSaveButton.pressed.connect(func() -> void: map_save_requested.emit())
	%MapLoadButton.pressed.connect(func() -> void: map_load_requested.emit())

	_select_soldier(1, false, false)


func set_active_team(team_id: int) -> void:
	_active_team_id = team_id
	_team_label.text = Team.display_name(team_id)
	_team_label.add_theme_color_override(
		"font_color",
		Team.COLOR_USA if team_id == Team.USA else Team.COLOR_GERMANY,
	)
	clear_move_targeting()
	clear_fire_at_mode()
	clear_face_mode()
	_update_status()


func set_selected_soldier(soldier_id: int) -> void:
	_select_soldier(soldier_id, false, true)


## Update highlighted soldier without notifying main (programmatic sync).
func sync_selected_soldier(soldier_id: int) -> void:
	_select_soldier(soldier_id, false, false)


## Sync one command row with live soldier gameplay data.
func sync_soldier_row(row_index: int, state: SoldierState) -> void:
	if row_index < 0 or row_index >= _rows.size():
		return
	var row: SoldierCommandRow = _rows[row_index]
	row.set_weapon_info(state)
	row.set_ammo(state.ammo_current, state.ammo_max)
	_soldier_weapon_names[row_index] = state.weapon_name
	row.set_row_enabled(state.is_alive())
	row.set_position_state(state.position_state)
	row.set_fire_control_state(state.fire_control_state)
	row.set_move_button_enabled(MovementMode.RUN, MovementMode.is_allowed(state.position_state, MovementMode.RUN))
	row.set_move_button_enabled(MovementMode.WALK, MovementMode.is_allowed(state.position_state, MovementMode.WALK))
	row.set_move_button_enabled(MovementMode.CRAWL, MovementMode.is_allowed(state.position_state, MovementMode.CRAWL))


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


func clear_face_mode() -> void:
	_face_soldier_id = -1
	for row in _rows:
		row.set_face_pressed(false)
	face_mode_changed.emit(false, _selected_soldier_id)
	_update_status()


func show_status(text: String) -> void:
	_status_label.text = text


func _on_squad_move_mode_toggled(movement_mode: int, is_pressed: bool) -> void:
	if is_pressed:
		clear_fire_at_mode()
		clear_face_mode()
		for row in _rows:
			row.clear_move_modes()
		_squad_row.clear_move_modes()
		_squad_row.set_move_mode_pressed(movement_mode, true)
		_move_target_soldier_id = SQUAD_ID
		_active_movement_mode = movement_mode
		move_targeting_changed.emit(true, SQUAD_ID, movement_mode)
	else:
		if _move_target_soldier_id == SQUAD_ID:
			_move_target_soldier_id = -1
		move_targeting_changed.emit(false, SQUAD_ID, movement_mode)

	_update_status()


func _on_squad_fire_at_toggled(is_pressed: bool) -> void:
	if is_pressed:
		clear_move_targeting()
		clear_face_mode()
		for row in _rows:
			row.set_fire_at_pressed(false)
		_fire_at_soldier_id = SQUAD_ID
		fire_at_mode_changed.emit(true, SQUAD_ID)
	else:
		if _fire_at_soldier_id == SQUAD_ID:
			_fire_at_soldier_id = -1
		fire_at_mode_changed.emit(false, SQUAD_ID)

	_update_status()


func _on_row_move_mode_toggled(soldier_id: int, movement_mode: int, is_pressed: bool) -> void:
	if is_pressed:
		clear_fire_at_mode()
		clear_face_mode()
		_squad_row.clear_move_modes()
		for row in _rows:
			if row.soldier_id != soldier_id:
				row.clear_move_modes()
			else:
				row.set_move_mode_pressed(movement_mode, true)
		_move_target_soldier_id = soldier_id
		_active_movement_mode = movement_mode
		_select_soldier(soldier_id, true)
		move_targeting_changed.emit(true, soldier_id, movement_mode)
	else:
		if _move_target_soldier_id == soldier_id and _active_movement_mode == movement_mode:
			_move_target_soldier_id = -1
		move_targeting_changed.emit(false, soldier_id, movement_mode)

	_update_status()


func _on_row_fire_at_toggled(soldier_id: int, is_pressed: bool) -> void:
	if is_pressed:
		clear_move_targeting()
		clear_face_mode()
		_squad_row.set_fire_at_pressed(false)
		for row in _rows:
			if row.soldier_id != soldier_id:
				row.set_fire_at_pressed(false)
		_fire_at_soldier_id = soldier_id
		_select_soldier(soldier_id, true)
		fire_at_mode_changed.emit(true, soldier_id)
	else:
		if _fire_at_soldier_id == soldier_id:
			_fire_at_soldier_id = -1
		fire_at_mode_changed.emit(false, soldier_id)

	_update_status()


func _on_row_face_toggled(soldier_id: int, is_pressed: bool) -> void:
	if is_pressed:
		clear_move_targeting()
		clear_fire_at_mode()
		for row in _rows:
			if row.soldier_id != soldier_id:
				row.set_face_pressed(false)
		_face_soldier_id = soldier_id
		_select_soldier(soldier_id, true)
		face_mode_changed.emit(true, soldier_id)
	else:
		if _face_soldier_id == soldier_id:
			_face_soldier_id = -1
		face_mode_changed.emit(false, soldier_id)

	_update_status()


func _on_row_fire_control_selected(soldier_id: int, fire_control_state: int) -> void:
	_select_soldier(soldier_id, true)
	fire_control_change_requested.emit(soldier_id, fire_control_state)


func _on_row_position_toggled(soldier_id: int, is_down: bool) -> void:
	_select_soldier(soldier_id, true)
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
		MovementMode.WALK:
			return "Walk To"
		MovementMode.CRAWL:
			return "Crawl To"
		_:
			return "Run To"


func _update_status() -> void:
	var team_name := Team.display_name(_active_team_id)
	if _fire_at_soldier_id == SQUAD_ID:
		show_status("%s Fireteam: Fire At — click enemies or auto-engages. Right-click cancels." % team_name)
	elif _fire_at_soldier_id > 0:
		show_status(
			"%s Soldier %d: Fire At — click enemies or auto-engages. Right-click cancels."
			% [team_name, _fire_at_soldier_id],
		)
	elif _face_soldier_id > 0:
		show_status("%s Soldier %d: Face — click a tile." % [team_name, _face_soldier_id])
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
