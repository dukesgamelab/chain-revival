class_name StatusHud
extends PanelContainer
## Top-right status readout (combat messages, mode hints, etc.).

@onready var _status_label: Label = $StatusMargin/StatusLabel


func show_status(text: String) -> void:
	_status_label.text = text
