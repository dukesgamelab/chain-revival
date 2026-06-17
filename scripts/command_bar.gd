class_name CommandBar
extends Control
## Bottom command bar with a squad row plus one row per soldier (Chain of Command style).

const SQUAD_ID := 0

signal soldier_selected(soldier_id: int)
signal run_to_mode_changed(is_active: bool, soldier_id: int)
signal fire_at_mode_changed(is_active: bool, soldier_id: int)
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
var _run_to_soldier_id: int = -1
var _fire_at_soldier_id: int = -1
var _active_team_id: int = Team.BLUE


func _ready() -> void:
	_squad_row.run_to_toggled.connect(_on_squad_run_to_toggled)
	_squad_row.fire_at_toggled.connect(_on_squad_fire_at_toggled)

	for row in _rows:
		row.run_to_toggled.connect(_on_row_run_to_toggled)
		row.fire_at_toggled.connect(_on_row_fire_at_toggled)

	%SaveButton.pressed.connect(func() -> void: save_requested.emit())
	%LoadButton.pressed.connect(func() -> void: load_requested.emit())
	%MapSaveButton.pressed.connect(func() -> void: map_save_requested.emit())
	%MapLoadButton.pressed.connect(func() -> void: map_load_requested.emit())

	_select_soldier(1, false)


func set_active_team(team_id: int) -> void:
	_active_team_id = team_id
	_team_label.text = Team.display_name(team_id)
	_team_label.add_theme_color_override(
		"font_color",
		Team.COLOR_BLUE if team_id == Team.BLUE else Team.COLOR_RED,
	)
	clear_run_to_mode()
	clear_fire_at_mode()
	_update_status()


func set_selected_soldier(soldier_id: int) -> void:
	_select_soldier(soldier_id, false)


func clear_run_to_mode() -> void:
	_run_to_soldier_id = -1
	_squad_row.set_run_to_pressed(false)
	for row in _rows:
		row.set_run_to_pressed(false)
	run_to_mode_changed.emit(false, _selected_soldier_id)
	_update_status()


func clear_fire_at_mode() -> void:
	_fire_at_soldier_id = -1
	_squad_row.set_fire_at_pressed(false)
	for row in _rows:
		row.set_fire_at_pressed(false)
	fire_at_mode_changed.emit(false, _selected_soldier_id)
	_update_status()


func show_status(text: String) -> void:
	_status_label.text = text


func _on_squad_run_to_toggled(is_pressed: bool) -> void:
	if is_pressed:
		clear_fire_at_mode()
		for row in _rows:
			row.set_run_to_pressed(false)
		_run_to_soldier_id = SQUAD_ID
		run_to_mode_changed.emit(true, SQUAD_ID)
	else:
		if _run_to_soldier_id == SQUAD_ID:
			_run_to_soldier_id = -1
		run_to_mode_changed.emit(false, SQUAD_ID)

	_update_status()


func _on_squad_fire_at_toggled(is_pressed: bool) -> void:
	if is_pressed:
		clear_run_to_mode()
		for row in _rows:
			row.set_fire_at_pressed(false)
		_fire_at_soldier_id = SQUAD_ID
		fire_at_mode_changed.emit(true, SQUAD_ID)
	else:
		if _fire_at_soldier_id == SQUAD_ID:
			_fire_at_soldier_id = -1
		fire_at_mode_changed.emit(false, SQUAD_ID)

	_update_status()


func _on_row_run_to_toggled(soldier_id: int, is_pressed: bool) -> void:
	if is_pressed:
		clear_fire_at_mode()
		_squad_row.set_run_to_pressed(false)
		for row in _rows:
			if row.soldier_id != soldier_id:
				row.set_run_to_pressed(false)
		_run_to_soldier_id = soldier_id
		_select_soldier(soldier_id, true)
		run_to_mode_changed.emit(true, soldier_id)
	else:
		if _run_to_soldier_id == soldier_id:
			_run_to_soldier_id = -1
		run_to_mode_changed.emit(false, soldier_id)

	_update_status()


func _on_row_fire_at_toggled(soldier_id: int, is_pressed: bool) -> void:
	if is_pressed:
		clear_run_to_mode()
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


func _select_soldier(soldier_id: int, from_command: bool) -> void:
	_selected_soldier_id = soldier_id
	soldier_selected.emit(soldier_id)
	if not from_command:
		_update_status()


func _update_status() -> void:
	var team_name := Team.display_name(_active_team_id)
	if _fire_at_soldier_id == SQUAD_ID:
		show_status("%s Fireteam: Fire At — click tiles to aim." % team_name)
	elif _fire_at_soldier_id > 0:
		show_status("%s Fire At — aim Soldier %d." % [team_name, _fire_at_soldier_id])
	elif _run_to_soldier_id == SQUAD_ID:
		show_status("%s Fireteam: Run To — click tiles to move." % team_name)
	elif _run_to_soldier_id > 0:
		show_status("%s Soldier %d: Run To — click tiles to move." % [team_name, _run_to_soldier_id])
	else:
		show_status("%s team — Soldier %d selected. Press 1/2 to switch teams." % [team_name, _selected_soldier_id])
