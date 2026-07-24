class_name CommandHierarchy
extends RefCounted
## Player command tree (commander ↔ subordinates). IDs only — no node refs.
## Applies to players (human or AI), not individual soldiers. Separate from fireteam/squad.
## TODO: order issuing down the chain (OUT OF SCOPE).

## RECOVERED
const MC_PERCENT_PP := 20
const MIN_JOIN_RANK := 0
const MAX_JOIN_RANK := 9
## PP to next rank (RECOVERED thresholds used for ranks 1–3; extend as needed).
const PP_TO_NEXT_RANK := {
	1: 500,
	2: 2000,
	3: 5000,
}
## PP lost on being killed, keyed by victim rank (RECOVERED).
const PP_LOST_ON_KILLED := {
	1: 4,
	2: 8,
	3: 12,
	4: 16,
	5: 20,
	6: 24,
	7: 28,
	8: 32,
}
## Display labels for ranks 0–9 (presentation).
const RANK_LABELS := [
	"PVT", "PFC", "CPL", "SGT", "SSG", "SFC", "MSG", "2LT", "1LT", "CPT",
]

## TUNED, not recovered — original SUBORDINATE_CAP value is unknown.
const SUBORDINATE_CAP := 4

const NO_COMMANDER := -1
const CYCLE_DEPTH_GUARD := 32

## player_id -> entry dictionary
var _players: Dictionary = {}
var _next_player_id: int = 1


func clear() -> void:
	_players.clear()
	_next_player_id = 1


func has_player(player_id: int) -> bool:
	return _players.has(player_id)


func get_entry(player_id: int) -> Dictionary:
	if not _players.has(player_id):
		return {}
	return (_players[player_id] as Dictionary).duplicate(true)


func all_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for key in _players.keys():
		ids.append(int(key))
	ids.sort()
	return ids


## Register a player. Returns assigned player_id.
func register_player(
	display_name: String,
	rank: int,
	team_id: int,
	is_ai: bool = false,
	soldier_ids: Array[int] = [],
	player_id: int = -1,
) -> int:
	var id := player_id if player_id > 0 else _next_player_id
	if player_id <= 0:
		_next_player_id = id + 1
	else:
		_next_player_id = maxi(_next_player_id, id + 1)
	var clamped_rank := clampi(rank, MIN_JOIN_RANK, MAX_JOIN_RANK)
	var owned: Array[int] = []
	for sid in soldier_ids:
		owned.append(int(sid))
	_players[id] = {
		"rank": clamped_rank,
		"commander_id": NO_COMMANDER,
		"subordinates": [] as Array[int],
		"is_mission_commander": false,
		"team_id": team_id,
		"display_name": display_name,
		"is_ai": is_ai,
		"soldier_ids": owned,
		"pp": 0,
	}
	return id


## Default single-player / offline roster: two players per team (commander-capable + lower rank).
## AI players occupy slots so hierarchy works offline — not gated on multiplayer.
func bootstrap_default_match() -> void:
	clear()
	register_player("YOU", 3, Team.USA, false, [1, 2] as Array[int])
	register_player("FTD", 1, Team.USA, true, [3, 4] as Array[int])
	register_player("HANS", 3, Team.GERMANY, true, [1, 2] as Array[int])
	register_player("FRITZ", 1, Team.GERMANY, true, [3, 4] as Array[int])
	## First USA human is Mission Commander by default.
	set_mission_commander(1)


func get_commander(player_id: int) -> int:
	if not _players.has(player_id):
		return NO_COMMANDER
	return int((_players[player_id] as Dictionary).get("commander_id", NO_COMMANDER))


func get_subordinates(player_id: int) -> Array[int]:
	var out: Array[int] = []
	if not _players.has(player_id):
		return out
	var raw: Variant = (_players[player_id] as Dictionary).get("subordinates", [])
	if raw is Array:
		for sid in raw:
			out.append(int(sid))
	return out


func get_rank(player_id: int) -> int:
	if not _players.has(player_id):
		return MIN_JOIN_RANK
	return int((_players[player_id] as Dictionary).get("rank", MIN_JOIN_RANK))


func get_team_id(player_id: int) -> int:
	if not _players.has(player_id):
		return Team.USA
	return int((_players[player_id] as Dictionary).get("team_id", Team.USA))


func get_display_name(player_id: int) -> String:
	if not _players.has(player_id):
		return ""
	return str((_players[player_id] as Dictionary).get("display_name", ""))


func get_soldier_ids(player_id: int) -> Array[int]:
	var out: Array[int] = []
	if not _players.has(player_id):
		return out
	var raw: Variant = (_players[player_id] as Dictionary).get("soldier_ids", [])
	if raw is Array:
		for sid in raw:
			out.append(int(sid))
	return out


func set_soldier_ids(player_id: int, soldier_ids: Array[int]) -> void:
	if not _players.has(player_id):
		return
	var owned: Array[int] = []
	for sid in soldier_ids:
		owned.append(int(sid))
	var entry: Dictionary = _players[player_id]
	entry["soldier_ids"] = owned
	_players[player_id] = entry


func is_mission_commander(player_id: int) -> bool:
	if not _players.has(player_id):
		return false
	return bool((_players[player_id] as Dictionary).get("is_mission_commander", false))


func rank_label(rank: int) -> String:
	var r := clampi(rank, 0, RANK_LABELS.size() - 1)
	return str(RANK_LABELS[r])


func list_label(player_id: int) -> String:
	return "%s   %s" % [rank_label(get_rank(player_id)), get_display_name(player_id)]


func subordinate_count(player_id: int) -> int:
	return get_subordinates(player_id).size()


func has_opening(player_id: int) -> bool:
	return has_player(player_id) and subordinate_count(player_id) < SUBORDINATE_CAP


func commanders_with_openings() -> Array[int]:
	var out: Array[int] = []
	for pid in all_player_ids():
		if has_opening(pid):
			out.append(pid)
	return out


func players_without_commanders() -> Array[int]:
	var out: Array[int] = []
	for pid in all_player_ids():
		if get_commander(pid) == NO_COMMANDER:
			out.append(pid)
	return out


## [{commander_id, subordinate_id}, ...]
func all_links() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pid in all_player_ids():
		var cmd := get_commander(pid)
		if cmd != NO_COMMANDER:
			out.append({"commander_id": cmd, "subordinate_id": pid})
	return out


## All player IDs in the subordinate tree under root (not including root).
func collect_subordinate_tree(root_player_id: int) -> Array[int]:
	var out: Array[int] = []
	var stack: Array[int] = get_subordinates(root_player_id).duplicate()
	var guard := 0
	while not stack.is_empty() and guard < CYCLE_DEPTH_GUARD * 4:
		guard += 1
		var sid := int(stack.pop_back())
		if sid in out:
			continue
		out.append(sid)
		for child in get_subordinates(sid):
			stack.append(child)
	return out


## Soldiers whose spotting feeds this player's shared visibility (self + subordinate tree).
func visibility_soldier_keys(player_id: int) -> Array[Dictionary]:
	var keys: Array[Dictionary] = []
	var players: Array[int] = [player_id]
	players.append_array(collect_subordinate_tree(player_id))
	for pid in players:
		var team_id := get_team_id(pid)
		for soldier_id in get_soldier_ids(pid):
			keys.append({"team_id": team_id, "soldier_id": soldier_id, "player_id": pid})
	return keys


func would_create_cycle(commander_id: int, subordinate_id: int) -> bool:
	## Walk up from proposed commander; fail if subordinate is an ancestor.
	var cursor := commander_id
	var depth := 0
	while cursor != NO_COMMANDER and depth < CYCLE_DEPTH_GUARD:
		if cursor == subordinate_id:
			return true
		cursor = get_commander(cursor)
		depth += 1
	return false


func assign_link(commander_id: int, subordinate_id: int) -> void:
	var sub: Dictionary = _players[subordinate_id]
	var cmd: Dictionary = _players[commander_id]
	sub["commander_id"] = commander_id
	var subs: Array = cmd.get("subordinates", [])
	if subordinate_id not in subs:
		subs.append(subordinate_id)
	cmd["subordinates"] = subs
	_players[subordinate_id] = sub
	_players[commander_id] = cmd


func break_link(subordinate_id: int) -> void:
	if not _players.has(subordinate_id):
		return
	var sub: Dictionary = _players[subordinate_id]
	var commander_id := int(sub.get("commander_id", NO_COMMANDER))
	sub["commander_id"] = NO_COMMANDER
	_players[subordinate_id] = sub
	if commander_id == NO_COMMANDER or not _players.has(commander_id):
		return
	var cmd: Dictionary = _players[commander_id]
	var subs: Array = []
	for sid in cmd.get("subordinates", []):
		if int(sid) != subordinate_id:
			subs.append(int(sid))
	cmd["subordinates"] = subs
	_players[commander_id] = cmd


func set_mission_commander(player_id: int) -> void:
	for pid in all_player_ids():
		var entry: Dictionary = _players[pid]
		entry["is_mission_commander"] = pid == player_id
		_players[pid] = entry


## MC share of a PP award (RECOVERED MC_PERCENT_PP).
func mission_commander_pp_share(total_pp: int) -> int:
	return int(round(float(total_pp) * float(MC_PERCENT_PP) / 100.0))


func add_pp(player_id: int, amount: int) -> void:
	if not _players.has(player_id) or amount == 0:
		return
	var entry: Dictionary = _players[player_id]
	entry["pp"] = int(entry.get("pp", 0)) + amount
	_players[player_id] = entry


func distribute_pp_award(recipient_player_id: int, total_pp: int) -> void:
	## MC receives MC_PERCENT_PP of the award when present; remainder to recipient.
	if total_pp <= 0 or not has_player(recipient_player_id):
		return
	var mc_id := -1
	for pid in all_player_ids():
		if is_mission_commander(pid):
			mc_id = pid
			break
	var mc_share := 0
	if mc_id > 0 and mc_id != recipient_player_id:
		mc_share = mission_commander_pp_share(total_pp)
		add_pp(mc_id, mc_share)
	add_pp(recipient_player_id, total_pp - mc_share)


func pp_to_next_rank(rank: int) -> int:
	return int(PP_TO_NEXT_RANK.get(rank, 0))


func pp_lost_on_killed(rank: int) -> int:
	return int(PP_LOST_ON_KILLED.get(rank, 0))


func to_dict() -> Dictionary:
	return {"players": _players.duplicate(true), "next_player_id": _next_player_id}


func load_from_dict(data: Dictionary) -> void:
	clear()
	var raw: Variant = data.get("players", {})
	if raw is Dictionary:
		for key in raw.keys():
			_players[int(key)] = (raw[key] as Dictionary).duplicate(true)
	_next_player_id = int(data.get("next_player_id", _players.size() + 1))
