class_name SquadCommandRow
extends HBoxContainer
## Top command row: squad-wide Fire At, movement, and camera center.

signal fire_at_toggled(is_pressed: bool)
signal move_mode_toggled(movement_mode: int, is_pressed: bool)
signal center_requested

@onready var _fire_at_button: Button = %FireAtButton
@onready var _run_to_button: Button = %RunToButton
@onready var _crawl_to_button: Button = %CrawlToButton
@onready var _center_button: Button = %CenterButton

var _move_buttons: Dictionary = {}


func _ready() -> void:
	_move_buttons = {
		MovementMode.RUN: _run_to_button,
		MovementMode.CRAWL: _crawl_to_button,
	}
	_center_button.tooltip_text = "Center the camera on the active fireteam."
	_fire_at_button.toggled.connect(_on_fire_at_toggled)
	_run_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.RUN))
	_crawl_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.CRAWL))
	_center_button.pressed.connect(_on_center_pressed)


func set_move_mode_pressed(movement_mode: int, is_pressed: bool) -> void:
	var button: Button = _move_buttons.get(movement_mode) as Button
	if button != null:
		button.set_pressed_no_signal(is_pressed)


func clear_move_modes() -> void:
	for button in _move_buttons.values():
		(button as Button).set_pressed_no_signal(false)


func set_fire_at_pressed(is_pressed: bool) -> void:
	_fire_at_button.set_pressed_no_signal(is_pressed)
	_update_fire_at_highlight(is_pressed)


func _on_move_toggled(is_pressed: bool, movement_mode: int) -> void:
	move_mode_toggled.emit(movement_mode, is_pressed)


func _on_fire_at_toggled(is_pressed: bool) -> void:
	_update_fire_at_highlight(is_pressed)
	fire_at_toggled.emit(is_pressed)


func _on_center_pressed() -> void:
	center_requested.emit()


func _update_fire_at_highlight(is_active: bool) -> void:
	_fire_at_button.modulate = Color(1.25, 1.05, 0.45) if is_active else Color.WHITE
