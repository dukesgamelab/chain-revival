extends Node
## WebSocket client for LOCAL_MULTIPLAYER connection tests only.
##
## Godot does NOT start the Node server. Run it manually first:
##   cd server && npm run dev
## Then choose Local Multiplayer — this client connects to ws://localhost:3000.

const SERVER_URL := "ws://localhost:3000"
const CLIENT_NAME := "Godot Client"
const DEFAULT_CONNECT_TIMEOUT_SEC := 5.0

signal connection_changed(connected: bool)
signal status_changed(status_text: String)

var _socket := WebSocketPeer.new()
var _connected := false
var _connecting := false
var _connect_failed := false


func _ready() -> void:
	set_process(false)


func connect_for_local_multiplayer() -> void:
	if not GameModeManager.is_local_multiplayer():
		GameLog.log_system("[NetworkClient] Skipped — not in LOCAL_MULTIPLAYER mode.")
		return
	if _connected or _connecting:
		return

	_connect_failed = false
	_connecting = true
	_emit_status()
	var err := _socket.connect_to_url(SERVER_URL)
	if err != OK:
		_connecting = false
		_connect_failed = true
		_emit_status()
		GameLog.log_system(
			"[NetworkClient] Connection failed to start: %s" % error_string(err)
		)
		return

	set_process(true)
	GameLog.log_system("[NetworkClient] Connecting to %s..." % SERVER_URL)


## Wait until connected or timeout. Call after setting LOCAL_MULTIPLAYER mode.
func connect_and_wait(timeout_sec: float = DEFAULT_CONNECT_TIMEOUT_SEC) -> bool:
	if not GameModeManager.is_local_multiplayer():
		return false
	if _connected:
		return true

	connect_for_local_multiplayer()
	var deadline_msec := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
		if _connected:
			return true
		if _connect_failed or (not _connecting and not _connected):
			break

	if _connected:
		return true

	_reset_socket()
	GameLog.log_system(
		"[NetworkClient] Connection failed — start the server first: cd server && npm run dev"
	)
	return false


func is_connected_to_server() -> bool:
	return _connected


func get_server_status_text() -> String:
	if not GameModeManager.is_local_multiplayer():
		return ""
	if _connected:
		return "Server: Connected"
	if _connecting:
		return "Server: Connecting..."
	return "Server: Disconnected"


func send_json(data: Dictionary) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(data))


func disconnect_from_server() -> void:
	_reset_socket()
	_emit_status()


func _reset_socket() -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.close()
	_socket = WebSocketPeer.new()
	_connected = false
	_connecting = false
	_connect_failed = false
	set_process(false)


func _process(_delta: float) -> void:
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_on_connected()
			_receive_packets()
		WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED:
			if _connected or _connecting:
				_on_disconnected()
			set_process(false)


func _on_connected() -> void:
	_connected = true
	_connecting = false
	GameLog.log_system("[NetworkClient] Connected to server.")
	_emit_status()
	_send_hello()


func _on_disconnected() -> void:
	var was_connected := _connected
	var was_connecting := _connecting
	_connected = false
	_connecting = false
	if was_connected:
		GameLog.log_system("[NetworkClient] Disconnected from server.")
	elif was_connecting:
		_connect_failed = true
		GameLog.log_system(
			"[NetworkClient] Could not reach server at %s — is it running?" % SERVER_URL
		)
	_emit_status()
	connection_changed.emit(false)


func _send_hello() -> void:
	send_json({"type": "hello", "clientName": CLIENT_NAME})
	GameLog.log_system("[NetworkClient] Sent hello to server.")


func _receive_packets() -> void:
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var text := packet.get_string_from_utf8()
		GameLog.log_system("[NetworkClient] Received: %s" % text)
		var parsed: Variant = _parse_json_object(text)
		if parsed == null:
			GameLog.log_system("[NetworkClient] Message is not valid JSON object.")
			continue
		_handle_message(parsed as Dictionary)


func _parse_json_object(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		return null
	return json.data


func _handle_message(message: Dictionary) -> void:
	var msg_type: String = str(message.get("type", ""))
	match msg_type:
		"welcome":
			GameLog.log_system(
				"[NetworkClient] Welcome: %s (clientId=%s)"
				% [str(message.get("message", "")), str(message.get("clientId", ""))]
			)
		"pong":
			GameLog.log_system(
				"[NetworkClient] Pong serverTime=%s" % str(message.get("serverTime", ""))
			)
		_:
			GameLog.log_system("[NetworkClient] Unhandled message type: %s" % msg_type)


func _emit_status() -> void:
	status_changed.emit(get_server_status_text())
	if _connected:
		connection_changed.emit(true)
