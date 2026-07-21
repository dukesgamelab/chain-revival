class_name StatusHud
extends PanelContainer
## Top-right status readout (combat messages, mode hints, etc.).

@onready var _status_label: Label = $StatusMargin/StatusLabel


func _ready() -> void:
	CocUiTheme.apply_to(self)
	## Message text stays high-contrast red like the original attention line.
	_status_label.add_theme_color_override("font_color", Color("C01010"))
	_status_label.add_theme_font_size_override("font_size", CocUiTheme.FONT_SIZE)


func show_status(text: String) -> void:
	_status_label.text = text
