class_name SquadCommandRow
extends HBoxContainer
## Top command row: Fire At and Run To for the whole fireteam at once.

signal fire_at_toggled(is_pressed: bool)
signal run_to_toggled(is_pressed: bool)

@onready var _fire_at_button: Button = %FireAtButton
@onready var _run_to_button: Button = %RunToButton


func _ready() -> void:
	_fire_at_button.toggled.connect(_on_fire_at_toggled)
	_run_to_button.toggled.connect(_on_run_to_toggled)


func set_run_to_pressed(is_pressed: bool) -> void:
	_run_to_button.set_pressed_no_signal(is_pressed)


func set_fire_at_pressed(is_pressed: bool) -> void:
	_fire_at_button.set_pressed_no_signal(is_pressed)
	_update_fire_at_highlight(is_pressed)


func _on_run_to_toggled(is_pressed: bool) -> void:
	run_to_toggled.emit(is_pressed)


func _on_fire_at_toggled(is_pressed: bool) -> void:
	_update_fire_at_highlight(is_pressed)
	fire_at_toggled.emit(is_pressed)


func _update_fire_at_highlight(is_active: bool) -> void:
	_fire_at_button.modulate = Color(1.25, 1.05, 0.45) if is_active else Color.WHITE
