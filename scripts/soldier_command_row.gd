class_name SoldierCommandRow
extends HBoxContainer
## One soldier row: dot indicator, clickable ammo (face direction), and Run To.

signal run_to_toggled(soldier_id: int, is_pressed: bool)
signal face_direction_toggled(soldier_id: int, is_pressed: bool)

@export var soldier_id: int = 1
@export var ammo_count: int = 200

@onready var _dots_label: Label = %DotsLabel
@onready var _ammo_button: Button = %AmmoButton
@onready var _run_to_button: Button = %RunToButton


func _ready() -> void:
	_dots_label.text = _make_dots(soldier_id)
	_ammo_button.text = str(ammo_count)
	_ammo_button.tooltip_text = "Click to face this soldier toward a map tile."
	_ammo_button.toggled.connect(_on_ammo_toggled)
	_run_to_button.toggled.connect(_on_run_to_toggled)


func set_run_to_pressed(is_pressed: bool) -> void:
	_run_to_button.set_pressed_no_signal(is_pressed)


func set_face_direction_pressed(is_pressed: bool) -> void:
	_ammo_button.set_pressed_no_signal(is_pressed)
	_update_ammo_highlight(is_pressed)


func is_run_to_pressed() -> bool:
	return _run_to_button.button_pressed


func is_face_direction_pressed() -> bool:
	return _ammo_button.button_pressed


func _on_run_to_toggled(is_pressed: bool) -> void:
	run_to_toggled.emit(soldier_id, is_pressed)


func _on_ammo_toggled(is_pressed: bool) -> void:
	_update_ammo_highlight(is_pressed)
	face_direction_toggled.emit(soldier_id, is_pressed)


func _update_ammo_highlight(is_active: bool) -> void:
	# Warm highlight while Face Direction mode is armed for this row.
	_ammo_button.modulate = Color(1.25, 1.05, 0.45) if is_active else Color.WHITE


func _make_dots(count: int) -> String:
	var dots := ""
	for i in range(count):
		if i > 0:
			dots += " "
		dots += "•"
	return dots
