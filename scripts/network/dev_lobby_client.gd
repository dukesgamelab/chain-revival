extends Node
## Talks to the development game server's in-memory room list.
## Used only while DevGuest is enabled. It never calls Supabase.

signal lobbies_listed(lobbies: Array)
signal lobby_created(lobby: Dictionary)
signal lobby_joined(lobby: Dictionary)
signal lobby_deleted()
signal lobby_error(msg: String)

const DevGuestScript := preload("res://scripts/network/dev_guest.gd")

var _http_list: HTTPRequest
var _http_host: HTTPRequest
var _http_join: HTTPRequest
var _http_leave: HTTPRequest
var _queued: Array[Dictionary] = []
var _flush_scheduled := false


func _ready() -> void:
	_http_list = _make_http("_on_list_response")
	_http_host = _make_http("_on_host_response")
	_http_join = _make_http("_on_join_response")
	_http_leave = _make_http("_on_leave_response")


func list_rooms() -> void:
	_request(_http_list, HTTPClient.METHOD_GET, "/dev/lobby", "")


func host_room(room_number: int, match_name: String, map_id: String, team_size: int, match_length_sec: int, server_url: String) -> void:
	var body := JSON.stringify({
		"devGuestId": DevGuestScript.player_id,
		"displayName": DevGuestScript.display_name,
		"roomNumber": room_number,
		"matchName": match_name,
		"mapId": map_id,
		"teamSize": team_size,
		"matchLengthSec": match_length_sec,
		"serverUrl": server_url,
	})
	_request(_http_host, HTTPClient.METHOD_POST, "/dev/lobby/host", body)


func join_room(room_number: int) -> void:
	var body := JSON.stringify({
		"devGuestId": DevGuestScript.player_id,
		"displayName": DevGuestScript.display_name,
		"roomNumber": room_number,
	})
	_request(_http_join, HTTPClient.METHOD_POST, "/dev/lobby/join", body)


func leave_room() -> void:
	var body := JSON.stringify({
		"devGuestId": DevGuestScript.player_id,
	})
	_request(_http_leave, HTTPClient.METHOD_POST, "/dev/lobby/leave", body)


func _request(http: HTTPRequest, method: int, path: String, body: String) -> void:
	if not DevGuestScript.is_enabled():
		lobby_error.emit("Dev guest mode is off")
		return
	## The lobby scene calls this during _ready, before HTTPRequest has a client.
	if http == null or not is_node_ready() or not http.is_node_ready():
		_queued.append({"http": http, "method": method, "path": path, "body": body})
		if not _flush_scheduled:
			_flush_scheduled = true
			call_deferred("_flush_queue")
		return
	var url := _http_base() + path
	if http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		http.cancel_request()
	var err := http.request(url, PackedStringArray(["Content-Type: application/json"]), method, body)
	if err != OK:
		lobby_error.emit("Dev lobby request failed to start (%s) %s" % [error_string(err), url])


func _flush_queue() -> void:
	_flush_scheduled = false
	var pending := _queued.duplicate()
	_queued.clear()
	for item in pending:
		_request(item["http"], int(item["method"]), str(item["path"]), str(item["body"]))


func _http_base() -> String:
	var raw := NetworkClient.server_url.strip_edges()
	if raw.begins_with("wss://"):
		return "https://" + raw.substr(6).trim_suffix("/")
	if raw.begins_with("ws://"):
		return "http://" + raw.substr(5).trim_suffix("/")
	return "http://127.0.0.1:3000"


func _on_list_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parsed := _parse_object(result, response_code, body)
	if parsed.is_empty():
		return
	var rooms: Variant = parsed.get("rooms", [])
	lobbies_listed.emit(rooms if rooms is Array else [])


func _on_host_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parsed := _parse_object(result, response_code, body)
	if parsed.is_empty():
		return
	var room: Variant = parsed.get("room", {})
	if room is Dictionary:
		lobby_created.emit(room)


func _on_join_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parsed := _parse_object(result, response_code, body)
	if parsed.is_empty():
		return
	var room: Variant = parsed.get("room", {})
	if room is Dictionary:
		lobby_joined.emit(room)


func _on_leave_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _parse_object(result, response_code, body).is_empty():
		return
	lobby_deleted.emit()


func _parse_object(result: int, response_code: int, body: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		if result == HTTPRequest.RESULT_CANT_CONNECT or result == HTTPRequest.RESULT_CANT_RESOLVE or result == HTTPRequest.RESULT_CONNECTION_ERROR:
			lobby_error.emit("Can't reach %s. Start the server with ALLOW_DEV_GUESTS=1." % _http_base())
		else:
			lobby_error.emit("Dev lobby network error (%d) at %s" % [result, _http_base()])
		return {}
	var text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		lobby_error.emit("Dev lobby returned invalid JSON (HTTP %d)" % response_code)
		return {}
	var data: Dictionary = json.data
	if response_code < 200 or response_code >= 300:
		lobby_error.emit(str(data.get("error", "Dev lobby request failed (HTTP %d)" % response_code)))
		return {}
	return data


func _make_http(callback: String) -> HTTPRequest:
	var req := HTTPRequest.new()
	req.request_completed.connect(Callable(self, callback))
	add_child(req)
	return req
