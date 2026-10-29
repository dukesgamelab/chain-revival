extends Node
## Supabase Realtime WebSocket client for Chain Revival.
##
## Autoload that maintains a persistent WebSocket connection to Supabase
## Realtime. Other scripts subscribe to postgres_changes INSERT events
## on specific table/channel combos and receive callbacks when rows arrive.
##
## Uses the Phoenix channel protocol (v1.0.0).

## Emitted when a new row is inserted into a subscribed table.
## Payload is the full record dictionary from postgres_changes.
signal message_received(table: String, record: Dictionary)

## Emitted when the Realtime connection state changes.
signal connection_state_changed(connected: bool)

const HEARTBEAT_INTERVAL := 20.0
const RECONNECT_DELAYS := [1.0, 2.0, 5.0, 10.0]

var _ws: WebSocketPeer
var _connected: bool = false
var _joining: bool = false
var _joined: bool = false
var _ref_counter: int = 0
var _join_ref: String = ""
var _heartbeat_timer: Timer
var _reconnect_timer: Timer
var _reconnect_attempt: int = 0
var _should_connect: bool = false

## Map of subscription ID (from join reply) to the filter info.
var _subscription_ids: Dictionary = {}

## The channel topic we join. We use one channel for all postgres_changes
## subscriptions and filter client-side by table + channel column.
var _topic: String = "realtime:chat"

## Active filter configs to send on join. Each entry is a Dictionary with
## keys: event, schema, table, and optionally filter.
var _pg_configs: Array[Dictionary] = []

## Listeners: keyed by "<table>:<filter_value>" -> Array of Callables.
var _listeners: Dictionary = {}


func _ready() -> void:
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL
	_heartbeat_timer.timeout.connect(_send_heartbeat)
	add_child(_heartbeat_timer)

	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_attempt_connect)
	add_child(_reconnect_timer)

	SupabaseAuth.auth_state_changed.connect(_on_auth_changed)

	if SupabaseAuth.is_signed_in:
		connect_to_realtime()


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			_reconnect_attempt = 0
			connection_state_changed.emit(true)
			_heartbeat_timer.start()
			_join_channel()
		while _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			_handle_message(pkt.get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		if _connected:
			_connected = false
			_joined = false
			_joining = false
			_heartbeat_timer.stop()
			connection_state_changed.emit(false)
		_ws = null
		if _should_connect and code != 1000:
			_schedule_reconnect()


func _on_auth_changed(signed_in: bool) -> void:
	if signed_in:
		connect_to_realtime()
	else:
		disconnect_from_realtime()


# ─────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────

## Subscribe to INSERT events on a table, optionally filtered by a column
## value (e.g. filter = "channel=eq.global"). The callback receives one
## argument: the record Dictionary.
func subscribe(table: String, filter: String, callback: Callable) -> void:
	var key := "%s:%s" % [table, filter]
	if not _listeners.has(key):
		_listeners[key] = []
	var arr: Array = _listeners[key]
	if callback not in arr:
		arr.append(callback)

	# Build the postgres_changes config entry.
	var config := {
		"event": "INSERT",
		"schema": "public",
		"table": table,
	}
	if filter != "":
		config["filter"] = filter

	# Check if we already have this config.
	for existing in _pg_configs:
		if existing.get("table", "") == table and existing.get("filter", "") == filter:
			return
	_pg_configs.append(config)

	# If already connected, rejoin to pick up the new subscription.
	if _joined:
		_leave_channel()
		_join_channel()


## Remove a specific callback for a table/filter combo.
func unsubscribe(table: String, filter: String, callback: Callable) -> void:
	var key := "%s:%s" % [table, filter]
	if _listeners.has(key):
		var arr: Array = _listeners[key]
		arr.erase(callback)
		if arr.is_empty():
			_listeners.erase(key)

	# Remove the matching pg_config.
	for i in range(_pg_configs.size() - 1, -1, -1):
		var c: Dictionary = _pg_configs[i]
		if c.get("table", "") == table and c.get("filter", "") == filter:
			_pg_configs.remove_at(i)

	# Rejoin if still connected.
	if _joined and _connected:
		_leave_channel()
		if not _pg_configs.is_empty():
			_join_channel()


## Open the WebSocket connection.
func connect_to_realtime() -> void:
	if _ws != null:
		return
	if not SupabaseAuth.is_signed_in:
		return
	_should_connect = true
	_attempt_connect()


## Cleanly close the connection.
func disconnect_from_realtime() -> void:
	_should_connect = false
	_heartbeat_timer.stop()
	_reconnect_timer.stop()
	if _ws != null:
		if _connected:
			_ws.close(1000, "client disconnect")
		else:
			_ws = null
	_connected = false
	_joined = false
	_joining = false
	_subscription_ids.clear()
	connection_state_changed.emit(false)


# ─────────────────────────────────────────────────────────────────────────
# Connection
# ─────────────────────────────────────────────────────────────────────────

func _attempt_connect() -> void:
	if _ws != null:
		return
	if not SupabaseAuth.is_signed_in:
		return

	var project_ref := _extract_project_ref()
	if project_ref.is_empty():
		push_warning("[SupabaseRealtime] Could not extract project ref from SUPABASE_URL")
		return

	var url := "wss://%s.supabase.co/realtime/v1/websocket?apikey=%s&vsn=1.0.0" % [
		project_ref, SupabaseAuth.SUPABASE_ANON_KEY
	]

	_ws = WebSocketPeer.new()
	var tls := TLSOptions.client()
	var err := _ws.connect_to_url(url, tls)
	if err != OK:
		push_warning("[SupabaseRealtime] connect_to_url failed: %d" % err)
		_ws = null
		_schedule_reconnect()


func _extract_project_ref() -> String:
	# SUPABASE_URL is "https://xxxxx.supabase.co"
	var url := SupabaseAuth.SUPABASE_URL
	var start := url.find("://")
	if start < 0:
		return ""
	var host := url.substr(start + 3)
	var dot := host.find(".")
	if dot < 0:
		return ""
	return host.substr(0, dot)


func _schedule_reconnect() -> void:
	if not _should_connect:
		return
	var delay_index := mini(_reconnect_attempt, RECONNECT_DELAYS.size() - 1)
	var delay: float = RECONNECT_DELAYS[delay_index]
	_reconnect_attempt += 1
	_reconnect_timer.start(delay)


# ─────────────────────────────────────────────────────────────────────────
# Phoenix channel protocol (v1.0.0)
# ─────────────────────────────────────────────────────────────────────────

func _next_ref() -> String:
	_ref_counter += 1
	return str(_ref_counter)


func _send_json(data: Dictionary) -> void:
	if _ws == null or not _connected:
		return
	var text := JSON.stringify(data)
	_ws.send_text(text)


func _join_channel() -> void:
	if _joining or _joined:
		return
	if _pg_configs.is_empty():
		return
	_joining = true
	_join_ref = _next_ref()
	var payload := {
		"config": {
			"postgres_changes": _pg_configs,
			"broadcast": {"ack": false, "self": false},
			"presence": {"enabled": false},
			"private": false,
		},
		"access_token": SupabaseAuth.access_token,
	}
	_send_json({
		"topic": _topic,
		"event": "phx_join",
		"payload": payload,
		"ref": _join_ref,
		"join_ref": _join_ref,
	})


func _leave_channel() -> void:
	if not _joined and not _joining:
		return
	_send_json({
		"topic": _topic,
		"event": "phx_leave",
		"payload": {},
		"ref": _next_ref(),
		"join_ref": _join_ref,
	})
	_joined = false
	_joining = false
	_subscription_ids.clear()


func _send_heartbeat() -> void:
	_send_json({
		"topic": "phoenix",
		"event": "heartbeat",
		"payload": {},
		"ref": _next_ref(),
	})


# ─────────────────────────────────────────────────────────────────────────
# Message handling
# ─────────────────────────────────────────────────────────────────────────

func _handle_message(text: String) -> void:
	if text.is_empty():
		return
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return
	var data = json.data
	if data is not Dictionary:
		return
	var event: String = data.get("event", "")

	match event:
		"phx_reply":
			_handle_reply(data)
		"postgres_changes":
			_handle_postgres_changes(data)
		"phx_error":
			_handle_channel_error()
		"phx_close":
			_handle_channel_close()
		"system":
			pass  # Could log system messages if needed.


func _handle_reply(data: Dictionary) -> void:
	var payload: Dictionary = data.get("payload", {})
	var status: String = payload.get("status", "")
	var response: Dictionary = payload.get("response", {})

	if status == "ok" and _joining:
		_joining = false
		_joined = true
		# Store subscription IDs from the join reply.
		var pg_changes: Array = response.get("postgres_changes", [])
		for entry in pg_changes:
			if entry is Dictionary:
				var sub_id = entry.get("id", 0)
				_subscription_ids[sub_id] = {
					"table": entry.get("table", ""),
					"event": entry.get("event", ""),
				}
	elif status == "error":
		push_warning("[SupabaseRealtime] Join error: %s" % str(response.get("reason", "")))
		_joining = false


func _handle_postgres_changes(data: Dictionary) -> void:
	var payload: Dictionary = data.get("payload", {})
	var inner_data: Dictionary = payload.get("data", {})
	var record: Dictionary = inner_data.get("record", {})
	var table: String = inner_data.get("table", "")
	var change_type: String = inner_data.get("type", "")

	if change_type != "INSERT" or record.is_empty():
		return

	# Emit the general signal.
	message_received.emit(table, record)

	# Call specific listeners. Match by table and filter.
	# The filter was something like "channel=eq.global", so check if the
	# record's channel column matches what listeners subscribed to.
	for key in _listeners:
		var parts := (key as String).split(":", true, 1)
		if parts.size() < 2:
			continue
		var listener_table: String = parts[0]
		var listener_filter: String = parts[1]
		if listener_table != table:
			continue

		# Check if the record matches the filter.
		if _record_matches_filter(record, listener_filter):
			var callbacks: Array = _listeners[key]
			for cb: Callable in callbacks:
				if cb.is_valid():
					cb.call(record)


func _record_matches_filter(record: Dictionary, filter: String) -> bool:
	if filter.is_empty():
		return true
	# Parse simple "column=eq.value" filters.
	var eq_pos := filter.find("=eq.")
	if eq_pos < 0:
		return true  # Unknown filter format; pass through.
	var col := filter.substr(0, eq_pos)
	var val := filter.substr(eq_pos + 4)
	var record_val = record.get(col, null)
	if record_val == null:
		return false
	return str(record_val) == val


func _handle_channel_error() -> void:
	# Channel process crashed. Will need to rejoin.
	_joined = false
	_joining = false
	_subscription_ids.clear()
	# The WebSocket itself may still be open; attempt rejoin.
	if _connected and not _pg_configs.is_empty():
		_join_channel()


func _handle_channel_close() -> void:
	_joined = false
	_joining = false
	_subscription_ids.clear()
