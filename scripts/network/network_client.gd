extends Node
## WebSocket client for LOCAL_MULTIPLAYER.
##
## Godot does NOT start the Node server. Run it manually first:
##   cd server && npm run dev
## Then choose Multiplayer — this client connects to ws://localhost:3000.

const SERVER_URL := "ws://localhost:3000"
const CLIENT_NAME := "Godot Client"
const DEFAULT_CONNECT_TIMEOUT_SEC := 5.0
const DEFAULT_SIDE_REQUEST_TIMEOUT_SEC := 5.0
const DEFAULT_SNAPSHOT_TIMEOUT_SEC := 5.0
const DEFAULT_MOVE_TIMEOUT_SEC := 3.0
const ActionResultClass := preload("res://scripts/core/action_result.gd")
const MoveCommandClass := preload("res://scripts/commands/move_command.gd")
const AuthoritativeSyncClass := preload("res://scripts/network/authoritative_sync.gd")

signal connection_changed(connected: bool)
signal status_changed(status_text: String)
signal side_assigned(side_name: String)
signal side_denied(reason: String)
signal match_snapshot_received(snapshot: Dictionary)
signal move_result_received(result: ActionResultClass, request_id: String)
signal movement_tick_received(payload: Dictionary)

var _socket := WebSocketPeer.new()
var _connected := false
var _connecting := false
var _connect_failed := false
var _side_request_pending := false
var _side_request_resolved := false
var _side_request_success := false
var client_id: String = ""
var match_id: String = ""
var last_snapshot: Dictionary = {}
var _move_wait_request_id: String = ""
var _move_wait_resolved := false
var _move_wait_result: ActionResultClass = null
var _request_seq := 0


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


func request_side_and_wait(
	side_name: String,
	timeout_sec: float = DEFAULT_SIDE_REQUEST_TIMEOUT_SEC,
) -> bool:
	if not _connected:
		return false

	_side_request_pending = true
	_side_request_resolved = false
	_side_request_success = false
	GameLog.log_system("[NetworkClient] Requested side: %s" % side_name)
	send_json({"type": "request_side", "side": side_name.to_upper()})

	var deadline_msec := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
		if _side_request_resolved:
			return _side_request_success

	_side_request_pending = false
	GameLog.log_system("[NetworkClient] Side request timed out for %s." % side_name)
	return false


func is_connected_to_server() -> bool:
	return _connected


func get_multiplayer_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Mode: LOCAL_MULTIPLAYER")
	lines.append("Connected: %s" % ("Yes" if _connected else "No"))
	if not match_id.is_empty():
		lines.append("Match: %s" % match_id)
	if PlayerSides.has_assignment():
		lines.append("Assigned Side: %s" % PlayerSides.display_side_name())
	return lines


func wait_for_snapshot(timeout_sec: float = DEFAULT_SNAPSHOT_TIMEOUT_SEC) -> Dictionary:
	if not last_snapshot.is_empty():
		return last_snapshot
	var deadline_msec := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
		if not last_snapshot.is_empty():
			return last_snapshot
	return {}


func submit_move_and_wait(
	cmd: MoveCommandClass,
	timeout_sec: float = DEFAULT_MOVE_TIMEOUT_SEC,
) -> ActionResultClass:
	if not _connected or cmd == null:
		return ActionResultClass.fail("Not connected to the match server.")
	_request_seq += 1
	var request_id := "%s-%d" % [client_id if not client_id.is_empty() else "client", _request_seq]
	_move_wait_request_id = request_id
	_move_wait_resolved = false
	_move_wait_result = null
	send_json({
		"type": "move_command",
		"matchId": match_id,
		"requestId": request_id,
		"teamId": cmd.team_id,
		"soldierId": cmd.soldier_id,
		"targetCell": {"x": cmd.target_cell.x, "y": cmd.target_cell.y},
		"scope": int(cmd.scope),
		"movementMode": cmd.movement_mode,
	})
	var deadline_msec := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
		if _move_wait_resolved:
			return _move_wait_result if _move_wait_result != null else ActionResultClass.fail("Empty move result.")
	_move_wait_request_id = ""
	return ActionResultClass.fail("Move request timed out.")


func send_json(data: Dictionary) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(data))


func disconnect_from_server() -> void:
	_reset_socket()
	PlayerSides.clear()
	_emit_status()


func _reset_socket() -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.close()
	_socket = WebSocketPeer.new()
	_connected = false
	_connecting = false
	_connect_failed = false
	_side_request_pending = false
	_side_request_resolved = false
	_side_request_success = false
	client_id = ""
	match_id = ""
	last_snapshot.clear()
	_move_wait_request_id = ""
	_move_wait_resolved = false
	_move_wait_result = null
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
	PlayerSides.clear()
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
			client_id = str(message.get("clientId", ""))
			match_id = str(message.get("matchId", match_id))
			GameLog.log_system(
				"[NetworkClient] Welcome: %s (clientId=%s matchId=%s)"
				% [str(message.get("message", "")), client_id, match_id]
			)
		"match_snapshot":
			_on_match_snapshot(message)
		"pong":
			GameLog.log_system(
				"[NetworkClient] Pong serverTime=%s" % str(message.get("serverTime", ""))
			)
		"side_assigned":
			if message.has("matchId"):
				match_id = str(message.get("matchId", match_id))
			_on_side_assigned(str(message.get("side", "")))
		"side_denied":
			_on_side_denied(str(message.get("reason", "Side denied")))
		"move_result":
			_on_move_result(message)
		"movement_tick":
			movement_tick_received.emit(message)
		_:
			GameLog.log_system("[NetworkClient] Unhandled message type: %s" % msg_type)


func _on_side_assigned(side_name: String) -> void:
	PlayerSides.assign_from_side_name(side_name)
	GameLog.log_system("[NetworkClient] Side assigned: %s" % side_name)
	_side_request_pending = false
	_side_request_resolved = true
	_side_request_success = true
	side_assigned.emit(side_name)
	_emit_status()


func _on_side_denied(reason: String) -> void:
	GameLog.log_system("[NetworkClient] Side denied: %s" % reason)
	_side_request_pending = false
	_side_request_resolved = true
	_side_request_success = false
	side_denied.emit(reason)
	_emit_status()


func _on_match_snapshot(snapshot: Dictionary) -> void:
	last_snapshot = snapshot.duplicate(true)
	if snapshot.has("matchId"):
		match_id = str(snapshot.get("matchId", match_id))
	GameLog.log_system(
		"[NetworkClient] Match snapshot matchId=%s mapId=%s soldiers=%d"
		% [
			str(snapshot.get("matchId", "")),
			str(snapshot.get("mapId", "")),
			(snapshot.get("soldiers", []) as Array).size() if snapshot.get("soldiers", []) is Array else 0,
		]
	)
	match_snapshot_received.emit(last_snapshot)


func _on_move_result(payload: Dictionary) -> void:
	var request_id := str(payload.get("requestId", payload.get("request_id", "")))
	var result: ActionResultClass = AuthoritativeSyncClass.action_result_from_payload(payload)
	if request_id == _move_wait_request_id and not _move_wait_request_id.is_empty():
		_move_wait_result = result
		_move_wait_resolved = true
		_move_wait_request_id = ""
	move_result_received.emit(result, request_id)


func _emit_status() -> void:
	status_changed.emit("")
	if _connected:
		connection_changed.emit(true)
