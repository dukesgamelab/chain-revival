class_name SoldierCommandRow
extends HBoxContainer
## One soldier's command row: dot indicator, ammo count, and Run To toggle.

signal run_to_toggled(soldier_id: int, is_pressed: bool)

@export var soldier_id: int = 1
@export var ammo_count: int = 200

@onready var _dots_label: Label = %DotsLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _run_to_button: Button = %RunToButton


func _ready() -> void:
	_dots_label.text = _make_dots(soldier_id)
	_ammo_label.text = str(ammo_count)
	_run_to_button.toggled.connect(_on_run_to_toggled)


func set_run_to_pressed(is_pressed: bool) -> void:
	_run_to_button.set_pressed_no_signal(is_pressed)


func is_run_to_pressed() -> bool:
	return _run_to_button.button_pressed


func _on_run_to_toggled(is_pressed: bool) -> void:
	run_to_toggled.emit(soldier_id, is_pressed)


func _make_dots(count: int) -> String:
	var dots := ""
	for i in range(count):
		if i > 0:
			dots += " "
		dots += "•"
	return dots
