class_name CommandBar
extends Control
## Bottom command bar with one row per soldier (Chain of Command style).

signal soldier_selected(soldier_id: int)
signal run_to_mode_changed(is_active: bool, soldier_id: int)
signal face_direction_mode_changed(is_active: bool, soldier_id: int)
signal save_requested
signal load_requested
signal map_save_requested
signal map_load_requested

@onready var _rows: Array[SoldierCommandRow] = [
	%Row1,
	%Row2,
	%Row3,
	%Row4,
]
@onready var _status_label: Label = %StatusLabel

var _selected_soldier_id: int = 1
var _run_to_soldier_id: int = -1
var _face_direction_soldier_id: int = -1


func _ready() -> void:
	for row in _rows:
		row.run_to_toggled.connect(_on_row_run_to_toggled)
		row.face_direction_toggled.connect(_on_row_face_direction_toggled)

	%SaveButton.pressed.connect(func() -> void: save_requested.emit())
	%LoadButton.pressed.connect(func() -> void: load_requested.emit())
	%MapSaveButton.pressed.connect(func() -> void: map_save_requested.emit())
	%MapLoadButton.pressed.connect(func() -> void: map_load_requested.emit())

	_select_soldier(1, false)


func set_selected_soldier(soldier_id: int) -> void:
	_select_soldier(soldier_id, false)


func clear_run_to_mode() -> void:
	_run_to_soldier_id = -1
	for row in _rows:
		row.set_run_to_pressed(false)
	run_to_mode_changed.emit(false, _selected_soldier_id)
	_update_status()


func clear_face_direction_mode() -> void:
	_face_direction_soldier_id = -1
	for row in _rows:
		row.set_face_direction_pressed(false)
	face_direction_mode_changed.emit(false, _selected_soldier_id)
	_update_status()


func show_status(text: String) -> void:
	_status_label.text = text


func _on_row_run_to_toggled(soldier_id: int, is_pressed: bool) -> void:
	if is_pressed:
		clear_face_direction_mode()
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


func _on_row_face_direction_toggled(soldier_id: int, is_pressed: bool) -> void:
	if is_pressed:
		clear_run_to_mode()
		for row in _rows:
			if row.soldier_id != soldier_id:
				row.set_face_direction_pressed(false)
		_face_direction_soldier_id = soldier_id
		_select_soldier(soldier_id, true)
		face_direction_mode_changed.emit(true, soldier_id)
	else:
		if _face_direction_soldier_id == soldier_id:
			_face_direction_soldier_id = -1
		face_direction_mode_changed.emit(false, soldier_id)

	_update_status()


func _select_soldier(soldier_id: int, from_command: bool) -> void:
	_selected_soldier_id = soldier_id
	soldier_selected.emit(soldier_id)
	if not from_command:
		_update_status()


func _update_status() -> void:
	if _face_direction_soldier_id > 0:
		show_status("Select direction to face (Soldier %d)." % _face_direction_soldier_id)
	elif _run_to_soldier_id > 0:
		show_status("Soldier %d: Run To — click a destination tile." % _run_to_soldier_id)
	else:
		show_status("Soldier %d selected. Run To or click ammo to face." % _selected_soldier_id)
