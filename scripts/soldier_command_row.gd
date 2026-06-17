class_name SoldierCommandRow
extends HBoxContainer
## One soldier row: dot indicator, ammo display, Fire At, and Run To.

signal run_to_toggled(soldier_id: int, is_pressed: bool)
signal fire_at_toggled(soldier_id: int, is_pressed: bool)

@export var soldier_id: int = 1
@export var ammo_count: int = 200

@onready var _dots_label: Label = %DotsLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _fire_at_button: Button = %FireAtButton
@onready var _run_to_button: Button = %RunToButton

var _row_enabled: bool = true


func _ready() -> void:
	_dots_label.text = _make_dots(soldier_id)
	_ammo_label.text = str(ammo_count)
	_fire_at_button.tooltip_text = "Enter targeting mode — click an enemy to shoot."
	_fire_at_button.toggled.connect(_on_fire_at_toggled)
	_run_to_button.toggled.connect(_on_run_to_toggled)


func set_run_to_pressed(is_pressed: bool) -> void:
	_run_to_button.set_pressed_no_signal(is_pressed)


func set_fire_at_pressed(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_fire_at_button.set_pressed_no_signal(is_pressed)
	_update_fire_at_highlight(is_pressed)


func set_ammo(ammo_current: int) -> void:
	_ammo_label.text = str(ammo_current)


func set_row_enabled(enabled: bool) -> void:
	_row_enabled = enabled
	_fire_at_button.disabled = not enabled
	_run_to_button.disabled = not enabled
	modulate = Color.WHITE if enabled else Color(0.45, 0.45, 0.45, 1.0)


func is_interactive() -> bool:
	return _row_enabled


func is_run_to_pressed() -> bool:
	return _run_to_button.button_pressed


func is_fire_at_pressed() -> bool:
	return _fire_at_button.button_pressed


func _on_run_to_toggled(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	run_to_toggled.emit(soldier_id, is_pressed)


func _on_fire_at_toggled(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_update_fire_at_highlight(is_pressed)
	fire_at_toggled.emit(soldier_id, is_pressed)


func _update_fire_at_highlight(is_active: bool) -> void:
	_fire_at_button.modulate = Color(1.25, 1.05, 0.45) if is_active else Color.WHITE


func _make_dots(count: int) -> String:
	var dots := ""
	for i in range(count):
		if i > 0:
			dots += " "
		dots += "•"
	return dots
