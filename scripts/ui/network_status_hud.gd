class_name NetworkStatusHud
extends PanelContainer
## Connection readout for local multiplayer. Hidden in offline play.

@onready var _label: Label = $Margin/StatusLabel


func _ready() -> void:
	NetworkClient.connection_changed.connect(_refresh)
	NetworkClient.status_changed.connect(_refresh)
	NetworkClient.side_assigned.connect(_refresh)
	call_deferred("_refresh")


func _refresh(_unused: Variant = null) -> void:
	visible = false
