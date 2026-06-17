class_name SoldierCommandRow
extends HBoxContainer
## One soldier row: ammo, fire control, Fire At, move modes, Face, and posture.

signal move_mode_toggled(soldier_id: int, movement_mode: int, is_pressed: bool)
signal fire_at_toggled(soldier_id: int, is_pressed: bool)
signal face_toggled(soldier_id: int, is_pressed: bool)
signal position_toggled(soldier_id: int, is_down: bool)
signal fire_control_selected(soldier_id: int, fire_control_state: int)

@export var soldier_id: int = 1
@export var ammo_count: int = 200

@onready var _dots_label: Label = %DotsLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _fire_at_button: Button = %FireAtButton
@onready var _hold_fire_button: Button = %HoldFireButton
@onready var _fire_at_will_button: Button = %FireAtWillButton
@onready var _run_to_button: Button = %RunToButton
@onready var _walk_to_button: Button = %WalkToButton
@onready var _crawl_to_button: Button = %CrawlToButton
@onready var _face_button: Button = %FaceButton
@onready var _position_button: Button = %PositionButton

var _row_enabled: bool = true
var _move_buttons: Dictionary = {}


func _ready() -> void:
	_dots_label.text = _make_dots(soldier_id)
	_ammo_label.text = str(ammo_count)
	_move_buttons = {
		MovementMode.RUN: _run_to_button,
		MovementMode.WALK: _walk_to_button,
		MovementMode.CRAWL: _crawl_to_button,
	}
	_fire_at_button.tooltip_text = "Enter targeting mode — click an enemy to shoot."
	_hold_fire_button.tooltip_text = "Hold Fire — move and face freely, manual Fire At only."
	_fire_at_will_button.tooltip_text = "Fire At Will — automatically engage visible enemies."
	_face_button.tooltip_text = "Face a direction — click a tile."
	_position_button.tooltip_text = "Toggle standing (Up) or prone (Down)."
	_fire_at_button.toggled.connect(_on_fire_at_toggled)
	_hold_fire_button.pressed.connect(_on_hold_fire_pressed)
	_fire_at_will_button.pressed.connect(_on_fire_at_will_pressed)
	_run_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.RUN))
	_walk_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.WALK))
	_crawl_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.CRAWL))
	_face_button.toggled.connect(_on_face_toggled)
	_position_button.toggled.connect(_on_position_toggled)
	set_position_state(PositionState.UP)
	set_fire_control_state(FireControlState.FIRE_AT_WILL)


func set_move_mode_pressed(movement_mode: int, is_pressed: bool) -> void:
	var button: Button = _move_buttons.get(movement_mode) as Button
	if button != null:
		button.set_pressed_no_signal(is_pressed)


func clear_move_modes() -> void:
	for button in _move_buttons.values():
		(button as Button).set_pressed_no_signal(false)


func set_fire_at_pressed(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_fire_at_button.set_pressed_no_signal(is_pressed)
	_update_fire_at_highlight(is_pressed)


func set_face_pressed(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_face_button.set_pressed_no_signal(is_pressed)
	_face_button.modulate = Color(0.75, 1.0, 0.85) if is_pressed else Color.WHITE


func set_ammo(ammo_current: int) -> void:
	_ammo_label.text = str(ammo_current)


func set_row_enabled(enabled: bool) -> void:
	_row_enabled = enabled
	_fire_at_button.disabled = not enabled
	_hold_fire_button.disabled = not enabled
	_fire_at_will_button.disabled = not enabled
	_face_button.disabled = not enabled
	_position_button.disabled = not enabled
	for button in _move_buttons.values():
		(button as Button).disabled = not enabled
	modulate = Color.WHITE if enabled else Color(0.45, 0.45, 0.45, 1.0)


func set_move_button_enabled(movement_mode: int, enabled: bool) -> void:
	var button: Button = _move_buttons.get(movement_mode) as Button
	if button == null:
		return
	button.disabled = not _row_enabled or not enabled
	if not enabled and button.button_pressed:
		button.set_pressed_no_signal(false)


func set_position_state(position_state: int) -> void:
	var is_down := position_state == PositionState.DOWN
	_position_button.set_pressed_no_signal(is_down)
	_position_button.text = "Up" if is_down else "Down"
	_position_button.modulate = Color(1.15, 0.85, 0.55) if is_down else Color.WHITE


func set_fire_control_state(fire_control_state: int) -> void:
	var is_hold := fire_control_state == FireControlState.HOLD_FIRE
	_hold_fire_button.modulate = Color(1.1, 0.85, 0.55) if is_hold else Color.WHITE
	_fire_at_will_button.modulate = Color(1.15, 0.75, 0.55) if not is_hold else Color.WHITE


func is_interactive() -> bool:
	return _row_enabled


func is_move_mode_pressed(movement_mode: int) -> bool:
	var button: Button = _move_buttons.get(movement_mode) as Button
	return button != null and button.button_pressed


func is_fire_at_pressed() -> bool:
	return _fire_at_button.button_pressed


func is_face_pressed() -> bool:
	return _face_button.button_pressed


func _on_move_toggled(is_pressed: bool, movement_mode: int) -> void:
	if not _row_enabled:
		return
	move_mode_toggled.emit(soldier_id, movement_mode, is_pressed)


func _on_fire_at_toggled(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_update_fire_at_highlight(is_pressed)
	fire_at_toggled.emit(soldier_id, is_pressed)


func _on_face_toggled(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_face_button.modulate = Color(0.75, 1.0, 0.85) if is_pressed else Color.WHITE
	face_toggled.emit(soldier_id, is_pressed)


func _on_position_toggled(is_down: bool) -> void:
	if not _row_enabled:
		return
	_position_button.text = "Up" if is_down else "Down"
	_position_button.modulate = Color(1.15, 0.85, 0.55) if is_down else Color.WHITE
	position_toggled.emit(soldier_id, is_down)


func _on_hold_fire_pressed() -> void:
	if not _row_enabled:
		return
	fire_control_selected.emit(soldier_id, FireControlState.HOLD_FIRE)


func _on_fire_at_will_pressed() -> void:
	if not _row_enabled:
		return
	fire_control_selected.emit(soldier_id, FireControlState.FIRE_AT_WILL)


func _update_fire_at_highlight(is_active: bool) -> void:
	_fire_at_button.modulate = Color(1.25, 1.05, 0.45) if is_active else Color.WHITE


func _make_dots(count: int) -> String:
	var dots := ""
	for i in range(count):
		if i > 0:
			dots += " "
		dots += "•"
	return dots
