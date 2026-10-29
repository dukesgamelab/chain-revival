extends Node
## Regiment client for Chain Revival regiment management.
##
## Uses Supabase PostgREST API and RPC functions to manage regiments,
## membership, applications, and join requests.
## NOT an autoload; instantiate it where needed and add_child it.

signal regiment_loaded(regiment: Dictionary)
signal regiment_members_loaded(members: Array)
signal regiment_error(msg: String)
signal application_submitted()
signal application_list_loaded(applications: Array)
signal application_resolved()
signal join_request_submitted()
signal join_requests_loaded(requests: Array)
signal join_request_resolved()
signal member_kicked()
signal rank_assigned()
signal xo_set()
signal details_updated()
signal my_regiment_loaded(regiment: Dictionary)
signal regiment_list_loaded(regiments: Array)
signal pp_log_loaded(log_entries: Array)
signal player_search_results(players: Array)
signal player_banned()
signal player_unbanned()
signal banned_list_loaded(players: Array)

var _http_load: HTTPRequest
var _http_members: HTTPRequest
var _http_apply: HTTPRequest
var _http_app_list: HTTPRequest
var _http_app_resolve: HTTPRequest
var _http_join_submit: HTTPRequest
var _http_join_list: HTTPRequest
var _http_join_resolve: HTTPRequest
var _http_kick: HTTPRequest
var _http_rank: HTTPRequest
var _http_xo: HTTPRequest
var _http_details: HTTPRequest
var _http_my_regiment: HTTPRequest
var _http_regiment_list: HTTPRequest
var _http_leave: HTTPRequest
var _http_pp_log: HTTPRequest
var _http_player_search: HTTPRequest
var _http_ban: HTTPRequest
var _http_unban: HTTPRequest
var _http_banned_list: HTTPRequest


func _ready() -> void:
	_http_load = _make_http("_on_load_response")
	_http_members = _make_http("_on_members_response")
	_http_apply = _make_http("_on_apply_response")
	_http_app_list = _make_http("_on_app_list_response")
	_http_app_resolve = _make_http("_on_app_resolve_response")
	_http_join_submit = _make_http("_on_join_submit_response")
	_http_join_list = _make_http("_on_join_list_response")
	_http_join_resolve = _make_http("_on_join_resolve_response")
	_http_kick = _make_http("_on_kick_response")
	_http_rank = _make_http("_on_rank_response")
	_http_xo = _make_http("_on_xo_response")
	_http_details = _make_http("_on_details_response")
	_http_my_regiment = _make_http("_on_my_regiment_response")
	_http_regiment_list = _make_http("_on_regiment_list_response")
	_http_leave = _make_http("_on_leave_response")
	_http_pp_log = _make_http("_on_pp_log_response")
	_http_player_search = _make_http("_on_player_search_response")
	_http_ban = _make_http("_on_ban_response")
	_http_unban = _make_http("_on_unban_response")
	_http_banned_list = _make_http("_on_banned_list_response")


# ─────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────

## Load a regiment by ID.
func load_regiment(regiment_id: String) -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/regiments?id=eq.%s" % [SupabaseAuth.SUPABASE_URL, regiment_id]
	_http_load.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


## Load the current user's regiment (from player_profiles.regiment_id).
func load_my_regiment() -> void:
	if not _check_auth():
		return
	# First fetch the player's regiment_id, then load that regiment
	var url := "%s/rest/v1/player_profiles?id=eq.%s&select=regiment_id" % [SupabaseAuth.SUPABASE_URL, SupabaseAuth.user_id]
	_http_my_regiment.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


## List all active regiments.
func list_regiments() -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/regiments?status=eq.active&order=name.asc" % SupabaseAuth.SUPABASE_URL
	_http_regiment_list.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


## List all regiments regardless of status (admin only, RLS enforced).
func list_all_regiments() -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/regiments?order=status.asc,name.asc" % SupabaseAuth.SUPABASE_URL
	_http_regiment_list.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


## Load members of a regiment. Fetches membership rows first, then resolves
## player profiles in a second request (no FK join needed).
func load_members(regiment_id: String) -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/regiment_members?regiment_id=eq.%s&select=player_id,assigned_rank,joined_at" % [SupabaseAuth.SUPABASE_URL, regiment_id]
	_http_members.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


## Submit a regiment creation application.
func apply_create_regiment(regiment_name: String, regiment_tag: String, description: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"type": "create",
		"applicant_id": SupabaseAuth.user_id,
		"regiment_name": regiment_name,
		"regiment_tag": regiment_tag,
		"description": description,
	})
	var url := "%s/rest/v1/regiment_applications" % SupabaseAuth.SUPABASE_URL
	_http_apply.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## Submit a regiment disband application (CO only).
func apply_disband_regiment(regiment_id: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"type": "disband",
		"applicant_id": SupabaseAuth.user_id,
		"regiment_id": regiment_id,
		"description": "Requesting regiment disband",
	})
	var url := "%s/rest/v1/regiment_applications" % SupabaseAuth.SUPABASE_URL
	_http_apply.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## List pending applications (admin only).
func list_pending_applications() -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/regiment_applications?status=eq.pending&order=created_at.asc" % SupabaseAuth.SUPABASE_URL
	_http_app_list.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


## Approve an application (admin only, calls RPC).
func approve_application(application_id: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"p_application_id": application_id,
		"p_admin_id": SupabaseAuth.user_id,
	})
	var url := "%s/rest/v1/rpc/approve_regiment_application" % SupabaseAuth.SUPABASE_URL
	_http_app_resolve.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## Reject an application (admin only, calls RPC).
func reject_application(application_id: String, note: String = "") -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"p_application_id": application_id,
		"p_admin_id": SupabaseAuth.user_id,
		"p_note": note if note != "" else null,
	})
	var url := "%s/rest/v1/rpc/reject_regiment_application" % SupabaseAuth.SUPABASE_URL
	_http_app_resolve.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## Request to join a regiment.
func request_join(regiment_id: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"regiment_id": regiment_id,
		"player_id": SupabaseAuth.user_id,
		"direction": "request",
	})
	var url := "%s/rest/v1/regiment_join_requests" % SupabaseAuth.SUPABASE_URL
	_http_join_submit.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## Invite a player to the regiment (CO/XO only).
func invite_player(regiment_id: String, target_player_id: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"regiment_id": regiment_id,
		"player_id": target_player_id,
		"direction": "invite",
		"invited_by": SupabaseAuth.user_id,
	})
	var url := "%s/rest/v1/regiment_join_requests" % SupabaseAuth.SUPABASE_URL
	_http_join_submit.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## List pending join requests for a regiment (CO/XO view).
func list_join_requests(regiment_id: String) -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/regiment_join_requests?regiment_id=eq.%s&status=eq.pending&order=created_at.asc" % [SupabaseAuth.SUPABASE_URL, regiment_id]
	_http_join_list.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


## List pending invites for the current user.
func list_my_invites() -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/regiment_join_requests?player_id=eq.%s&direction=eq.invite&status=eq.pending&order=created_at.desc" % [SupabaseAuth.SUPABASE_URL, SupabaseAuth.user_id]
	_http_join_list.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


## Accept a join request or invite (calls RPC).
func accept_join(request_id: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"p_request_id": request_id,
		"p_user_id": SupabaseAuth.user_id,
	})
	var url := "%s/rest/v1/rpc/accept_regiment_join" % SupabaseAuth.SUPABASE_URL
	_http_join_resolve.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## Reject a join request (CO/XO) or decline an invite (player).
func reject_join(request_id: String) -> void:
	if not _check_auth():
		return
	# Direct update via REST (RLS handles authorization)
	var body := JSON.stringify({
		"status": "rejected",
		"resolved_by": SupabaseAuth.user_id,
		"resolved_at": Time.get_datetime_string_from_system(true),
	})
	var url := "%s/rest/v1/regiment_join_requests?id=eq.%s&status=eq.pending" % [SupabaseAuth.SUPABASE_URL, request_id]
	_http_join_resolve.request(url, _bearer_headers_prefer_return(), HTTPClient.METHOD_PATCH, body)


## Kick a member (CO/XO, calls RPC).
func kick_member(regiment_id: String, target_id: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"p_regiment_id": regiment_id,
		"p_target_id": target_id,
		"p_caller_id": SupabaseAuth.user_id,
	})
	var url := "%s/rest/v1/rpc/kick_regiment_member" % SupabaseAuth.SUPABASE_URL
	_http_kick.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## Leave the regiment voluntarily.
func leave_regiment(regiment_id: String) -> void:
	if not _check_auth():
		return
	# Delete own membership row (RLS allows this)
	var url := "%s/rest/v1/regiment_members?regiment_id=eq.%s&player_id=eq.%s" % [SupabaseAuth.SUPABASE_URL, regiment_id, SupabaseAuth.user_id]
	_http_leave.request(url, _bearer_headers(), HTTPClient.METHOD_DELETE)


## Assign a rank to a member (CO/XO, calls RPC).
func assign_rank(regiment_id: String, target_id: String, rank_name: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"p_regiment_id": regiment_id,
		"p_target_id": target_id,
		"p_caller_id": SupabaseAuth.user_id,
		"p_rank": rank_name if rank_name != "" else null,
	})
	var url := "%s/rest/v1/rpc/assign_regiment_rank" % SupabaseAuth.SUPABASE_URL
	_http_rank.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## Set or clear the XO (CO only, calls RPC).
func set_xo(regiment_id: String, xo_id: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"p_regiment_id": regiment_id,
		"p_caller_id": SupabaseAuth.user_id,
		"p_xo_id": xo_id if xo_id != "" else null,
	})
	var url := "%s/rest/v1/rpc/set_regiment_xo" % SupabaseAuth.SUPABASE_URL
	_http_xo.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## Update regiment details (CO only, calls RPC).
func update_details(regiment_id: String, description: String, website_url: String) -> void:
	if not _check_auth():
		return
	var body := JSON.stringify({
		"p_regiment_id": regiment_id,
		"p_caller_id": SupabaseAuth.user_id,
		"p_description": description,
		"p_website_url": website_url,
	})
	var url := "%s/rest/v1/rpc/update_regiment_details" % SupabaseAuth.SUPABASE_URL
	_http_details.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body)


## Load PP distribution log for the current user (as recipient).
func load_pp_log() -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/pp_distribution_log?recipient_id=eq.%s&order=created_at.desc&limit=50" % [SupabaseAuth.SUPABASE_URL, SupabaseAuth.user_id]
	_http_pp_log.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


# ─────────────────────────────────────────────────────────────────────────
# Response Handlers
# ─────────────────────────────────────────────────────────────────────────

@warning_ignore("unused_parameter")
func _on_load_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		regiment_error.emit("Failed to load regiment")
		return
	var parsed := _parse_body_array(body)
	if parsed.size() > 0:
		regiment_loaded.emit(parsed[0])
	else:
		regiment_error.emit("Regiment not found")


@warning_ignore("unused_parameter")
func _on_my_regiment_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		regiment_error.emit("Failed to load profile")
		return
	var parsed := _parse_body_array(body)
	if parsed.size() > 0 and parsed[0].get("regiment_id", "") != "":
		# Now load the actual regiment
		load_regiment(parsed[0]["regiment_id"])
		# Signal will come from _on_load_response -> regiment_loaded
	else:
		my_regiment_loaded.emit({})  # No regiment


@warning_ignore("unused_parameter")
func _on_regiment_list_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		regiment_error.emit("Failed to list regiments")
		return
	regiment_list_loaded.emit(_parse_body_array(body))


var _pending_members: Array = []
var _http_member_profiles: HTTPRequest

@warning_ignore("unused_parameter")
func _on_members_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		regiment_error.emit("Failed to load members")
		return
	_pending_members = _parse_body_array(body)
	if _pending_members.is_empty():
		regiment_members_loaded.emit(_pending_members)
		return
	# Fetch profiles for all member player_ids
	var ids: Array[String] = []
	for m in _pending_members:
		var pid: String = str(m.get("player_id", ""))
		if pid != "" and pid not in ids:
			ids.append(pid)
	if _http_member_profiles != null:
		_http_member_profiles.queue_free()
	_http_member_profiles = HTTPRequest.new()
	add_child(_http_member_profiles)
	_http_member_profiles.request_completed.connect(_on_member_profiles_response)
	var id_filter := "(" + ",".join(ids) + ")"
	var url := "%s/rest/v1/player_profiles?id=in.%s&select=id,display_name,rank,prestige_points" % [SupabaseAuth.SUPABASE_URL, id_filter]
	_http_member_profiles.request(url, _bearer_headers(), HTTPClient.METHOD_GET)


@warning_ignore("unused_parameter")
func _on_member_profiles_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		# Emit members without profile data rather than failing
		regiment_members_loaded.emit(_pending_members)
		return
	var profiles := _parse_body_array(body)
	var profile_map: Dictionary = {}
	for p in profiles:
		profile_map[str(p.get("id", ""))] = p
	# Merge profile data into member entries
	for m in _pending_members:
		var pid: String = str(m.get("player_id", ""))
		if profile_map.has(pid):
			m["player_profiles"] = profile_map[pid]
	regiment_members_loaded.emit(_pending_members)


@warning_ignore("unused_parameter")
func _on_apply_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		regiment_error.emit("Failed to submit application")
		return
	application_submitted.emit()


@warning_ignore("unused_parameter")
func _on_app_list_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		regiment_error.emit("Failed to list applications")
		return
	application_list_loaded.emit(_parse_body_array(body))


@warning_ignore("unused_parameter")
func _on_app_resolve_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var text := body.get_string_from_utf8()
		regiment_error.emit("Failed to resolve application: %s" % text)
		return
	application_resolved.emit()


@warning_ignore("unused_parameter")
func _on_join_submit_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		regiment_error.emit("Failed to submit join request")
		return
	join_request_submitted.emit()


@warning_ignore("unused_parameter")
func _on_join_list_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		regiment_error.emit("Failed to list join requests")
		return
	join_requests_loaded.emit(_parse_body_array(body))


@warning_ignore("unused_parameter")
func _on_join_resolve_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var text := body.get_string_from_utf8()
		regiment_error.emit("Failed to resolve join request: %s" % text)
		return
	join_request_resolved.emit()


@warning_ignore("unused_parameter")
func _on_kick_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var text := body.get_string_from_utf8()
		regiment_error.emit("Failed to kick member: %s" % text)
		return
	member_kicked.emit()


@warning_ignore("unused_parameter")
func _on_leave_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		regiment_error.emit("Failed to leave regiment")
		return
	# Clear local regiment_id cache
	# The UI should refresh after this
	join_request_resolved.emit()


@warning_ignore("unused_parameter")
func _on_rank_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var text := body.get_string_from_utf8()
		regiment_error.emit("Failed to assign rank: %s" % text)
		return
	rank_assigned.emit()


@warning_ignore("unused_parameter")
func _on_xo_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var text := body.get_string_from_utf8()
		regiment_error.emit("Failed to set XO: %s" % text)
		return
	xo_set.emit()


@warning_ignore("unused_parameter")
func _on_details_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var text := body.get_string_from_utf8()
		regiment_error.emit("Failed to update details: %s" % text)
		return
	details_updated.emit()


@warning_ignore("unused_parameter")
func _on_pp_log_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		regiment_error.emit("Failed to load PP log")
		return
	pp_log_loaded.emit(_parse_body_array(body))


# ─────────────────────────────────────────────────────────────────────────
# Admin: Ban Management
# ─────────────────────────────────────────────────────────────────────────

## Search players by display name (admin only, RPC enforced).
func search_players(query: String) -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/rpc/search_players" % SupabaseAuth.SUPABASE_URL
	var body_text := JSON.stringify({"p_query": query})
	_http_player_search.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body_text)


@warning_ignore("unused_parameter")
func _on_player_search_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		regiment_error.emit("Player search failed")
		return
	player_search_results.emit(_parse_body_array(body))


## Ban a player (admin only, RPC enforced).
func ban_player(target_id: String, reason: String) -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/rpc/ban_player" % SupabaseAuth.SUPABASE_URL
	var body_text := JSON.stringify({"p_target_id": target_id, "p_reason": reason})
	_http_ban.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body_text)


@warning_ignore("unused_parameter")
func _on_ban_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or (response_code != 200 and response_code != 204):
		regiment_error.emit("Ban failed (HTTP %d)" % response_code)
		return
	player_banned.emit()


## Unban a player (admin only, RPC enforced).
func unban_player(target_id: String) -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/rpc/unban_player" % SupabaseAuth.SUPABASE_URL
	var body_text := JSON.stringify({"p_target_id": target_id})
	_http_unban.request(url, _bearer_headers(), HTTPClient.METHOD_POST, body_text)


@warning_ignore("unused_parameter")
func _on_unban_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or (response_code != 200 and response_code != 204):
		regiment_error.emit("Unban failed (HTTP %d)" % response_code)
		return
	player_unbanned.emit()


## List all currently banned players (admin only, RPC enforced).
func list_banned_players() -> void:
	if not _check_auth():
		return
	var url := "%s/rest/v1/rpc/list_banned_players" % SupabaseAuth.SUPABASE_URL
	_http_banned_list.request(url, _bearer_headers(), HTTPClient.METHOD_POST)


@warning_ignore("unused_parameter")
func _on_banned_list_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		regiment_error.emit("Failed to load banned players")
		return
	banned_list_loaded.emit(_parse_body_array(body))


# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

func _check_auth() -> bool:
	if not SupabaseAuth.is_signed_in:
		regiment_error.emit("Not signed in")
		return false
	return true


func _bearer_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % SupabaseAuth.SUPABASE_ANON_KEY,
		"Authorization: Bearer %s" % SupabaseAuth.access_token,
	])


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
	if json.parse(text) != OK:
		return []
	var data = json.data
	if data is Array:
		return data
	return []
