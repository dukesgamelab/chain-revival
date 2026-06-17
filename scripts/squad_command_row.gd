class_name SquadCommandRow
extends HBoxContainer
## Top command row: Fire At and move modes for the whole fireteam at once.

signal fire_at_toggled(is_pressed: bool)
signal move_mode_toggled(movement_mode: int, is_pressed: bool)

@onready var _fire_at_button: Button = %FireAtButton
@onready var _run_to_button: Button = %RunToButton
@onready var _walk_to_button: Button = %WalkToButton
@onready var _crawl_to_button: Button = %CrawlToButton

var _move_buttons: Dictionary = {}


func _ready() -> void:
	_move_buttons = {
		MovementMode.RUN: _run_to_button,
		MovementMode.WALK: _walk_to_button,
		MovementMode.CRAWL: _crawl_to_button,
	}
	_fire_at_button.toggled.connect(_on_fire_at_toggled)
	_run_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.RUN))
	_walk_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.WALK))
	_crawl_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.CRAWL))


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


func _update_fire_at_highlight(is_active: bool) -> void:
	_fire_at_button.modulate = Color(1.25, 1.05, 0.45) if is_active else Color.WHITE
