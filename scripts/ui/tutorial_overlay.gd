class_name TutorialOverlay
extends Control

signal skip_requested

var _step_label: Label
var _instruction_label: Label
var _skip_button: Button
var _panel: PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_top = 8.0
	offset_bottom = 120.0

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.offset_left = -310.0
	_panel.offset_right = 310.0
	_panel.custom_minimum_size = Vector2(620, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.92)
	style.border_color = Color(0.35, 0.35, 0.3, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	_step_label = Label.new()
	_step_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	_step_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(_step_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	_skip_button = Button.new()
	_skip_button.text = "Skip Tutorial"
	_skip_button.custom_minimum_size = Vector2(120, 28)
	_skip_button.pressed.connect(func() -> void: skip_requested.emit())
	hbox.add_child(_skip_button)

	_instruction_label = Label.new()
	_instruction_label.add_theme_color_override("font_color", Color.WHITE)
	_instruction_label.add_theme_font_size_override("font_size", 16)
	_instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_instruction_label)


func update_step(step_number: int, total_steps: int, instruction: String) -> void:
	if step_number <= 0 or step_number >= total_steps:
		_step_label.text = ""
	else:
		_step_label.text = "Step %d of %d" % [step_number, total_steps - 2]
	_instruction_label.text = instruction
	_flash_instruction()


func set_visible_overlay(is_visible: bool) -> void:
	visible = is_visible


func _flash_instruction() -> void:
	_instruction_label.modulate = Color(1.0, 1.0, 0.7, 1.0)
	var tween := create_tween()
	tween.tween_property(_instruction_label, "modulate", Color.WHITE, 0.4)
