class_name CommandBar
extends Control
## Bottom command bar inspired by Chain of Command.
## For now it only exposes a "Run To" movement command.

signal run_to_mode_changed(is_active: bool)

@onready var _panel: PanelContainer = $Panel
@onready var _run_to_button: Button = %RunToButton
@onready var _status_label: Label = %StatusLabel

var _run_to_active: bool = false


func _ready() -> void:
	_run_to_button.toggled.connect(_on_run_to_toggled)
	show_status("WASD moves selected soldier.")


func is_run_to_active() -> bool:
	return _run_to_active


## True when the mouse is over the bottom bar (clicks should go to UI, not the map).
func is_pointer_over_bar() -> bool:
	return _panel.get_global_rect().has_point(get_viewport().get_mouse_position())


func set_run_to_active(is_active: bool) -> void:
	_run_to_active = is_active
	_run_to_button.set_pressed_no_signal(is_active)
	run_to_mode_changed.emit(_run_to_active)
	_update_status_for_mode()


func show_status(text: String) -> void:
	_status_label.text = text


func _on_run_to_toggled(toggled_on: bool) -> void:
	_run_to_active = toggled_on
	run_to_mode_changed.emit(_run_to_active)
	_update_status_for_mode()


func _update_status_for_mode() -> void:
	if _run_to_active:
		show_status("Run To: click a destination tile.")
	else:
		show_status("Command mode cleared.")
