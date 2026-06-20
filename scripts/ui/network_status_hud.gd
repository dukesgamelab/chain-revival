class_name NetworkStatusHud
extends PanelContainer
## Top-left readout for game mode and WebSocket connection status.

@onready var _label: Label = $Margin/StatusLabel


func _ready() -> void:
	NetworkClient.connection_changed.connect(_refresh)
	NetworkClient.status_changed.connect(_refresh)
	call_deferred("_refresh")


func _refresh(_unused: Variant = null) -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Current Mode: %s" % GameMode.display_name(GameModeManager.get_mode()))
	if GameModeManager.is_local_multiplayer():
		lines.append(NetworkClient.get_server_status_text())
	_label.text = "\n".join(lines)
