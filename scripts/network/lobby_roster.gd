extends RefCounted
## Formats lobby presence and room rosters from server rows.
## The UI does not keep its own membership list.


const FRESH_SEC := 30
const DROP_SEC := 90


static func online_text(players: Array, now_unix: int) -> String:
	var visible := unique_online(players, now_unix)
	if visible.is_empty():
		return "Online — nobody in the lobby"
	var lines: PackedStringArray = PackedStringArray(["Online (%d)" % visible.size()])
	for player in visible:
		lines.append("%s — %s" % [str(player["display_name"]), str(player["status"])])
	return "\n".join(lines)


static func unique_online(players: Array, now_unix: int) -> Array:
	var by_id := {}
	for player in players:
		if not player is Dictionary:
			continue
		var source: Dictionary = player
		var player_id := _player_id(source)
		if player_id.is_empty():
			continue
		var age := _age_sec(source, now_unix)
		if age > DROP_SEC:
			continue
		var status := "Online"
		if source.get("connected", true) == false or (age >= 0 and age > FRESH_SEC):
			status = "Disconnected"
		by_id[player_id] = {"display_name": _display_name(source), "status": status}
	var rows: Array = by_id.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["display_name"]).nocasecmp_to(str(b["display_name"])) < 0
	)
	return rows


static func room_roster(lobby_status: String, members: Array) -> String:
	var playing := lobby_status == "in_progress"
	var by_id := {}
	for member in members:
		if not member is Dictionary:
			continue
		var source: Dictionary = member
		var player_id := _player_id(source)
		if player_id.is_empty() or by_id.has(player_id):
			continue
		by_id[player_id] = _member_line(source, playing)
	var lines: Array = by_id.values()
	lines.sort_custom(func(a: String, b: String) -> bool:
		return a.nocasecmp_to(b) < 0
	)
	return "\n".join(lines)


static func _member_line(member: Dictionary, playing: bool) -> String:
	var name := _display_name(member)
	var side := ""
	var side_value: Variant = member.get("side", null)
	if side_value is String:
		side = side_value
	var place := "waiting"
	if playing and side == "USA":
		place = "USA"
	elif playing and side == "GERMANY":
		place = "Germany"
	elif playing:
		place = "choosing side"
	if member.get("connected", true) == false:
		place += " · disconnected"
	return "%s — %s" % [name, place]


static func _player_id(row: Dictionary) -> String:
	var user_id := str(row.get("user_id", "")).strip_edges()
	if user_id.is_empty() or user_id == "<null>":
		user_id = str(row.get("id", "")).strip_edges()
	if user_id == "<null>":
		return ""
	return user_id


static func _display_name(row: Dictionary) -> String:
	var name := str(row.get("display_name", "")).strip_edges()
	if name.is_empty() or name == "<null>":
		return "Player"
	return name


static func _age_sec(row: Dictionary, now_unix: int) -> int:
	var raw := str(row.get("last_seen", "")).strip_edges()
	if raw.is_empty() or raw == "<null>":
		return -1
	var cleaned := raw
	if cleaned.ends_with("Z"):
		cleaned = cleaned.substr(0, cleaned.length() - 1)
	var plus := cleaned.find("+")
	if plus > 0:
		cleaned = cleaned.substr(0, plus)
	var dot := cleaned.find(".")
	if dot > 0:
		cleaned = cleaned.substr(0, dot)
	cleaned = cleaned.replace("T", " ")
	var seen := int(Time.get_unix_time_from_datetime_string(cleaned))
	if seen <= 0:
		return -1
	return maxi(0, now_unix - seen)
