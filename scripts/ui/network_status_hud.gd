class_name NetworkStatusHud
extends PanelContainer
## Top-left readout for game mode, connection, and assigned side.

@onready var _label: Label = $Margin/StatusLabel


func _ready() -> void:
	NetworkClient.connection_changed.connect(_refresh)
	NetworkClient.status_changed.connect(_refresh)
	NetworkClient.side_assigned.connect(_refresh)
	call_deferred("_refresh")


func _refresh(_unused: Variant = null) -> void:
	var lines: PackedStringArray = PackedStringArray()
	if GameModeManager.is_local_multiplayer():
		for line in NetworkClient.get_multiplayer_status_lines():
			lines.append(line)
	else:
		lines.append("Current Mode: %s" % GameMode.display_name(GameModeManager.get_mode()))
	_label.text = "\n".join(lines)
