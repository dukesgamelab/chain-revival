extends Node
## Lobby client for Chain Revival online matchmaking.
##
## Uses Supabase PostgREST API to create, list, join, and manage lobbies.
## NOT an autoload; instantiate it where needed and add_child it.

signal lobbies_listed(lobbies: Array)
signal lobby_created(lobby: Dictionary)
signal lobby_joined(lobby: Dictionary)
signal lobby_deleted()
signal lobby_error(msg: String)
signal chat_messages_received(messages: Array)

var _http_list: HTTPRequest
var _http_create: HTTPRequest
var _http_join: HTTPRequest
var _http_delete: HTTPRequest
var _http_update: HTTPRequest
var _http_chat_send: HTTPRequest
var _http_chat_fetch: HTTPRequest


func _ready() -> void:
	_http_list = _make_http("_on_list_response")
	_http_create = _make_http("_on_create_response")
	_http_join = _make_http("_on_join_response")
	_http_delete = _make_http("_on_delete_response")
	_http_update = _make_http("_on_update_response")
	_http_chat_send = _make_http("_on_chat_send_response")
	_http_chat_fetch = _make_http("_on_chat_fetch_response")


# ─────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────

## List all lobbies with status 'waiting', ordered by newest first.
func list_lobbies() -> void:
	if not _check_auth():
		return
	# Fetch waiting lobbies AND any lobby hosted by the current user (to detect joins).
	var url := "%s/rest/v1/lobbies?or=(status.eq.waiting,host_id.eq.%s)&order=created_at.desc" % [SupabaseAuth.SUPABASE_URL, SupabaseAuth.user_id]
	_http_list.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


## Create a new lobby with the given match name.
func create_lobby(match_name: String, server_url: String = "") -> void:
	if not _check_auth():
		return
	var payload := {
		"host_id": SupabaseAuth.user_id,
		"host_display_name": SupabaseAuth.display_name,
		"match_name": match_name,
		"status": "waiting",
		"current_players": 1,
	}
	if not server_url.is_empty():
		payload["server_url"] = server_url
	var body := JSON.stringify(payload)
	var headers := _bearer_headers_prefer_return()
	var url := "%s/rest/v1/lobbies" % SupabaseAuth.SUPABASE_URL
	_http_create.request(url, headers, HTTPClient.METHOD_POST, body)


## Join an existing lobby by incrementing current_players.
## The caller should check the lobby is still 'waiting' before calling.
func join_lobby(lobby_id: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"current_players": 2,
		"status": "in_progress",
	})
	var headers := _bearer_headers_prefer_return()
	var url := "%s/rest/v1/lobbies?id=eq.%s&status=eq.waiting" % [SupabaseAuth.SUPABASE_URL, lobby_id]
	_http_join.request(url, headers, HTTPClient.METHOD_PATCH, body)


## Update lobby status (e.g. 'in_progress', 'finished').
func update_lobby_status(lobby_id: String, new_status: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({"status": new_status})
	var headers := _bearer_headers_prefer_return()
	var url := "%s/rest/v1/lobbies?id=eq.%s" % [SupabaseAuth.SUPABASE_URL, lobby_id]
	_http_update.request(url, headers, HTTPClient.METHOD_PATCH, body)


## Delete a lobby (host only, enforced by RLS).
func delete_lobby(lobby_id: String) -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/lobbies?id=eq.%s" % [SupabaseAuth.SUPABASE_URL, lobby_id]
	_http_delete.request(url, _bearer_headers(), HTTPClient.METHOD_DELETE)


## Send a chat message to the global lobby chat.
func send_chat_message(msg: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"user_id": SupabaseAuth.user_id,
		"display_name": SupabaseAuth.display_name,
		"message": msg,
	})
	var url := "%s/rest/v1/chat_messages" % SupabaseAuth.SUPABASE_URL
	_http_chat_send.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## Fetch chat messages newer than since_iso (ISO 8601 timestamp).
## Pass an empty string to get the most recent batch.
func fetch_chat_messages(_since_iso: String = "") -> void:
	if not _check_auth():
		return
	# Fetch the last 50 messages. The UI deduplicates by ID.
	var url := "%s/rest/v1/chat_messages?order=created_at.asc&limit=50" % SupabaseAuth.SUPABASE_URL
	_http_chat_fetch.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


# ─────────────────────────────────────────────────────────────────────────
# Response handlers
# ─────────────────────────────────────────────────────────────────────────

func _on_list_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		lobby_error.emit("Failed to fetch lobbies (HTTP %d)" % response_code)
		return
	var parsed := _parse_body_array(body)
	lobbies_listed.emit(parsed)


func _on_create_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or (response_code != 200 and response_code != 201):
		lobby_error.emit("Failed to create lobby (HTTP %d)" % response_code)
		return
	var parsed := _parse_body_array(body)
	if parsed.size() > 0:
		lobby_created.emit(parsed[0])
	else:
		lobby_error.emit("Lobby created but no data returned")


func _on_join_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		lobby_error.emit("Failed to join lobby (HTTP %d)" % response_code)
		return
	var parsed := _parse_body_array(body)
	if parsed.size() > 0:
		lobby_joined.emit(parsed[0])
	else:
		lobby_error.emit("Lobby may have been taken or removed")


func _on_delete_response(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		lobby_error.emit("Failed to delete lobby (HTTP %d)" % response_code)
		return
	lobby_deleted.emit()


func _on_update_response(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	# Fire and forget; the lobby_browser polls anyway.
	pass


func _on_chat_send_response(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	# Fire and forget; the chat poll will pick it up.
	pass


func _on_chat_fetch_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed := _parse_body_array(body)
	chat_messages_received.emit(parsed)


# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

func _check_auth() -> bool:
	if not SupabaseAuth.is_signed_in:
		lobby_error.emit("Not signed in")
		return false
	return true


func _bearer_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % SupabaseAuth.SUPABASE_ANON_KEY,
		"Authorization: Bearer %s" % SupabaseAuth.access_token,
	])


## Same as _bearer_headers but asks PostgREST to return the created/updated row.
func _bearer_headers_prefer_return() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % SupabaseAuth.SUPABASE_ANON_KEY,
		"Authorization: Bearer %s" % SupabaseAuth.access_token,
		"Prefer: return=representation",
	])


func _make_http(callback: String) -> HTTPRequest:
	var req := HTTPRequest.new()
	req.request_completed.connect(Callable(self, callback))
	add_child(req)
	return req


func _parse_body_array(body: PackedByteArray) -> Array:
	var text := body.get_string_from_utf8()
	if text.is_empty():
		return []
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return []
	var data = json.data
	if data is Array:
		return data
	if data is Dictionary:
		return [data]
	return []
