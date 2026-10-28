class_name CommandHierarchy
extends RefCounted
## Player command tree (commander ↔ subordinates). IDs only — no node refs.
## Applies to players (human or AI), not individual soldiers. Separate from fireteam/squad.
## TODO: order issuing down the chain (OUT OF SCOPE).

const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const AiOrderClass := preload("res://scripts/ai/ai_order.gd")

## RECOVERED
const MC_PERCENT_PP := 20
const MIN_JOIN_RANK := 0
const MAX_JOIN_RANK := 9
## Cumulative PP thresholds for each rank (index = rank). Rank 0 (PVT) is free.
const RANK_PP_THRESHOLDS := [0, 500, 2500, 7500, 17500, 35500, 65500, 115500, 195500, 315500]
## PP to next rank: how many PP above the current threshold to reach the next one.
## Used by the in-match hierarchy (local PP tracking). Kept for compatibility.
const PP_TO_NEXT_RANK := {
	1: 500,
	2: 2000,
	3: 5000,
	4: 10000,
	5: 18000,
	6: 30000,
	7: 50000,
	8: 80000,
	9: 120000,
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
## Display labels for ranks 0â€“9 (presentation).
const RANK_LABELS := [
	"PVT", "PFC", "CPL", "SGT", "SSG", "SFC", "MSG", "2LT", "1LT", "CPT",
]

## TUNED, not recovered â€” original SUBORDINATE_CAP value is unknown.
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
		"player_id": id,
		"rank": clamped_rank,
		"commander_id": NO_COMMANDER,
		## subordinate_ids (stored as subordinates for compatibility)
		"subordinates": [] as Array[int],
		"subordinate_ids": [] as Array[int],
		"is_mission_commander": false,
		"team_id": team_id,
		"display_name": display_name,
		"is_ai": is_ai,
		"soldier_ids": owned,
		"pp": 0,
		## Phase 3 AI plans (stable string ids). Empty for humans.
		"selected_ai_plan": "",
		"active_ai_plan": "",
		## Stashed when Human claims an AI slot — restored on leave → AI.
		"stashed_selected_ai_plan": "",
		"stashed_active_ai_plan": "",
		## Phase 4–6 human order currently applied to this AI player.
		"active_ai_order": "none",
		"active_ai_order_cell": {"x": -999, "y": -999},
	}
	return id


## Default single-player / offline roster: two players per team (commander-capable + lower rank).
## AI players occupy slots so hierarchy works offline â€” not gated on multiplayer.
func bootstrap_default_match() -> void:
	clear()
	register_player("YOU", 3, Team.USA, false, [1, 2, 3, 4] as Array[int])
	register_player("FTD", 1, Team.USA, true, [5, 6, 7, 8] as Array[int])
	register_player("HANS", 3, Team.GERMANY, true, [1, 2, 3, 4] as Array[int])
	register_player("FRITZ", 1, Team.GERMANY, true, [5, 6, 7, 8] as Array[int])
	## First USA human is Mission Commander by default.
	set_mission_commander(1)
	## Offline defaults: USA AI Attack Center; Germany AI Defend.
	set_selected_ai_plan(2, AiPlanClass.ID_ATTACK_CENTER)
	set_selected_ai_plan(3, AiPlanClass.ID_DEFEND)
	set_selected_ai_plan(4, AiPlanClass.ID_DEFEND)


## Build hierarchy from MatchConfig player slots / owned fireteams (players + whole AI fireteams).
## Each owned fireteam becomes one hierarchy player â€” never individual soldiers as commanders.
func bootstrap_from_session(session) -> void:
	if session == null or session.owned_fireteams.is_empty():
		bootstrap_default_match()
		return
	clear()
	var config = session.match_config
	var local_id := int(session.local_player_id) if session.local_player_id > 0 else 1
	for ft in session.owned_fireteams:
		var player_id := int(ft.owner_player_id)
		if player_id <= 0:
			continue
		var team_id := int(ft.team_id)
		var slot_index := 0
		var controller := 1 ## MatchConfig.ControllerType.AI
		var display_name := "Player %d" % player_id
		var selected_from_config := ""
		if config != null:
			for slot in config.slots:
				if int(slot.get("player_id", -1)) != player_id:
					continue
				slot_index = int(slot.get("slot_index", 0))
				controller = int(slot.get("controller", controller))
				display_name = str(slot.get("display_name", display_name))
				selected_from_config = str(slot.get("selected_ai_plan", ""))
				break
		## HUMAN / OPEN = human-capable slot; AI = whole AI fireteam entry.
		var is_ai := controller == 1 ## ControllerType.AI
		if not is_ai and player_id == local_id:
			display_name = "YOU"
		elif is_ai and display_name.is_empty():
			if team_id == Team.USA:
				display_name = "USA AI Player %d" % (slot_index + 1)
			else:
				display_name = "GE Player %d" % (slot_index + 1)
		var soldier_ids: Array[int] = []
		for state in ft.soldiers:
			soldier_ids.append(int(state.soldier_id))
		## Lead slot on a side starts higher rank so they can command allied AI fireteams.
		var rank := 3 if slot_index == 0 else 1
		register_player(display_name, rank, team_id, is_ai, soldier_ids, player_id)
		if is_ai:
			var selected_plan := AiPlanClass.normalize_id(selected_from_config)
			if not AiPlanClass.is_valid_id(selected_plan):
				var human_team := Team.USA
				if config != null:
					for slot in config.slots:
						if int(slot.get("controller", -1)) == 0: ## HUMAN
							human_team = int(slot.get("team_id", Team.USA))
							break
				selected_plan = AiPlanClass.default_selected_for_slot(1, team_id, human_team)
			set_selected_ai_plan(player_id, selected_plan)
	if has_player(local_id):
		set_mission_commander(local_id)
	elif not all_player_ids().is_empty():
		set_mission_commander(all_player_ids()[0])


func is_ai_player(player_id: int) -> bool:
	if not _players.has(player_id):
		return false
	return bool((_players[player_id] as Dictionary).get("is_ai", false))


## Flip AI/human controller only. Does not change team, soldiers, rank, or command links.
func set_is_ai(player_id: int, is_ai: bool) -> void:
	if not _players.has(player_id):
		return
	var entry: Dictionary = _players[player_id]
	entry["is_ai"] = is_ai
	_players[player_id] = entry


## Preserve plans when a human claims this AI slot (resume on leave).
func stash_ai_plans_for_human(player_id: int) -> void:
	if not _players.has(player_id):
		return
	var entry: Dictionary = _players[player_id]
	var selected := AiPlanClass.normalize_id(str(entry.get("selected_ai_plan", "")))
	var active := AiPlanClass.normalize_id(str(entry.get("active_ai_plan", "")))
	if AiPlanClass.is_valid_id(selected):
		entry["stashed_selected_ai_plan"] = selected
	if AiPlanClass.is_concrete_id(active):
		entry["stashed_active_ai_plan"] = active
	## Humans do not expose live plan fields in UI/serialize paths.
	entry["selected_ai_plan"] = ""
	entry["active_ai_plan"] = ""
	_players[player_id] = entry


## After leave → AI: restore stashed plan or apply team defaults.
func restore_ai_plans_after_human(player_id: int, human_team_id: int = Team.USA) -> void:
	if not _players.has(player_id) or not is_ai_player(player_id):
		return
	var entry: Dictionary = _players[player_id]
	var stashed_selected := AiPlanClass.normalize_id(str(entry.get("stashed_selected_ai_plan", "")))
	var stashed_active := AiPlanClass.normalize_id(str(entry.get("stashed_active_ai_plan", "")))
	var selected := stashed_selected
	if not AiPlanClass.is_valid_id(selected):
		selected = AiPlanClass.default_selected_for_slot(
			1, ## ControllerType.AI
			get_team_id(player_id),
			human_team_id,
		)
	entry["selected_ai_plan"] = selected
	if AiPlanClass.is_concrete_id(stashed_active):
		entry["active_ai_plan"] = stashed_active
	elif AiPlanClass.is_concrete_id(selected):
		entry["active_ai_plan"] = selected
	else:
		## Random selected — resolve once now so gameplay can resume.
		entry["active_ai_plan"] = AiPlanClass.resolve_to_concrete(selected)
	_players[player_id] = entry


func clear_active_ai_order(player_id: int) -> void:
	set_active_ai_order(player_id, "none", Vector2i(-999, -999))


func get_commander(player_id: int) -> int:
	if not _players.has(player_id):
		return NO_COMMANDER
	return int((_players[player_id] as Dictionary).get("commander_id", NO_COMMANDER))


func get_subordinates(player_id: int) -> Array[int]:
	var out: Array[int] = []
	if not _players.has(player_id):
		return out
	var entry: Dictionary = _players[player_id]
	## Prefer subordinate_ids when present (Phase 2 name); fall back to subordinates.
	var raw: Variant = entry.get("subordinate_ids", entry.get("subordinates", []))
	if raw is Array:
		for sid in raw:
			out.append(int(sid))
	return out


## Phase 2 alias for get_subordinates.
func get_subordinate_ids(player_id: int) -> Array[int]:
	return get_subordinates(player_id)


func get_rank(player_id: int) -> int:
	if not _players.has(player_id):
		return MIN_JOIN_RANK
	return int((_players[player_id] as Dictionary).get("rank", MIN_JOIN_RANK))


func set_rank(player_id: int, rank: int) -> void:
	if not _players.has(player_id):
		return
	var entry: Dictionary = _players[player_id]
	entry["rank"] = clampi(rank, MIN_JOIN_RANK, MAX_JOIN_RANK)
	_players[player_id] = entry


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
	var name := get_display_name(player_id)
	if is_ai_player(player_id):
		name = "%s (AI Fireteam)" % name
	return "%s   %s" % [rank_label(get_rank(player_id)), name]


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
	cmd["subordinate_ids"] = subs.duplicate()
	sub["player_id"] = subordinate_id
	cmd["player_id"] = commander_id
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
	cmd["subordinate_ids"] = subs.duplicate()
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
	## Player IDs only â€” no scene/node refs. Safe for multiplayer / dedicated server.
	return {"players": _players.duplicate(true), "next_player_id": _next_player_id}


func load_from_dict(data: Dictionary) -> void:
	clear()
	var raw: Variant = data.get("players", {})
	if raw is Dictionary:
		for key in raw.keys():
			var entry: Dictionary = (raw[key] as Dictionary).duplicate(true)
			var pid := int(key)
			entry["player_id"] = int(entry.get("player_id", pid))
			## Keep subordinates / subordinate_ids in sync.
			var subs_raw: Variant = entry.get("subordinate_ids", entry.get("subordinates", []))
			var subs: Array = []
			if subs_raw is Array:
				for sid in subs_raw:
					subs.append(int(sid))
			entry["subordinates"] = subs
			entry["subordinate_ids"] = subs.duplicate()
			## Normalize AI plan fields for older saves.
			if bool(entry.get("is_ai", false)):
				var selected := AiPlanClass.normalize_id(str(entry.get("selected_ai_plan", "")))
				if not AiPlanClass.is_valid_id(selected):
					selected = AiPlanClass.ID_RANDOM
				entry["selected_ai_plan"] = selected
				var active := AiPlanClass.normalize_id(str(entry.get("active_ai_plan", "")))
				if not AiPlanClass.is_concrete_id(active):
					## Prefer concrete selected; never re-roll Random on load (keeps RNG stream stable).
					if AiPlanClass.is_concrete_id(selected):
						active = selected
					else:
						active = AiPlanClass.ID_ATTACK_CENTER
				entry["active_ai_plan"] = active
			else:
				## Preserve stashed plans for Human↔AI rejoin; clear live plan fields.
				if not entry.has("stashed_selected_ai_plan"):
					entry["stashed_selected_ai_plan"] = ""
				if not entry.has("stashed_active_ai_plan"):
					entry["stashed_active_ai_plan"] = ""
				entry["selected_ai_plan"] = ""
				entry["active_ai_plan"] = ""
			_players[pid] = entry
	_next_player_id = int(data.get("next_player_id", _players.size() + 1))


## --- Future hooks (order issuing / AI planning) â€” stubs for Phase 2 ---

## Reserved: downward order flow (attack/defend/move). Implemented for AI players via active_ai_order.
func issue_order(from_player_id: int, to_player_id: int, order: Dictionary = {}) -> Dictionary:
	if not has_player(from_player_id) or not has_player(to_player_id):
		return {"ok": false, "error": "Invalid player"}
	if not is_ai_player(to_player_id):
		return {"ok": false, "error": "Orders only apply to AI players"}
	if get_team_id(from_player_id) != get_team_id(to_player_id):
		return {"ok": false, "error": "Orders must target same-team AI"}
	var order_id := AiOrderClass.normalize_id(str(order.get("order_id", order.get("type", ""))))
	if order_id.is_empty() or not AiOrderClass.is_valid_id(order_id):
		return {"ok": false, "error": "Invalid order"}
	var cell := Vector2i(-999, -999)
	var raw_cell: Variant = order.get("target_cell", {})
	if raw_cell is Dictionary:
		cell = Vector2i(int(raw_cell.get("x", -999)), int(raw_cell.get("y", -999)))
	elif raw_cell is Vector2i:
		cell = raw_cell
	set_active_ai_order(to_player_id, order_id, cell)
	return {"ok": true, "order_id": order_id, "to_player_id": to_player_id}


func get_active_ai_order(player_id: int) -> String:
	if not _players.has(player_id):
		return "none"
	return AiOrderClass.normalize_id(str((_players[player_id] as Dictionary).get("active_ai_order", "none")))


func get_active_ai_order_cell(player_id: int) -> Vector2i:
	if not _players.has(player_id):
		return Vector2i(-999, -999)
	var raw: Variant = (_players[player_id] as Dictionary).get("active_ai_order_cell", {})
	if raw is Dictionary:
		return Vector2i(int(raw.get("x", -999)), int(raw.get("y", -999)))
	return Vector2i(-999, -999)


func set_active_ai_order(
	player_id: int,
	order_id: String,
	target_cell: Vector2i = Vector2i(-999, -999),
) -> void:
	if not _players.has(player_id) or not is_ai_player(player_id):
		return
	var normalized := AiOrderClass.normalize_id(order_id)
	if not AiOrderClass.is_valid_id(normalized):
		return
	var entry: Dictionary = _players[player_id]
	if normalized == AiOrderClass.ID_RESUME_PLAN:
		entry["active_ai_order"] = "none"
		entry["active_ai_order_cell"] = {"x": -999, "y": -999}
	else:
		entry["active_ai_order"] = normalized
		entry["active_ai_order_cell"] = {"x": target_cell.x, "y": target_cell.y}
	_players[player_id] = entry


## Players in this player's command tree (self + recursive subordinates).
func get_visible_players(player_id: int) -> Array[int]:
	var out: Array[int] = []
	if not has_player(player_id):
		return out
	out.append(player_id)
	out.append_array(collect_subordinate_tree(player_id))
	return out


## Whether this player may issue orders down the chain (has subordinates).
func can_issue_orders(player_id: int) -> bool:
	if not has_player(player_id):
		return false
	return subordinate_count(player_id) > 0


## Whether this player sits under a commander (can receive downward orders later).
func can_receive_orders(player_id: int) -> bool:
	return has_player(player_id) and get_commander(player_id) != NO_COMMANDER


## --- Phase 3 AI plans (selection + resolved active; no behavior) ---

func get_selected_ai_plan(player_id: int) -> String:
	if not _players.has(player_id):
		return ""
	return AiPlanClass.normalize_id(str((_players[player_id] as Dictionary).get("selected_ai_plan", "")))


func get_active_ai_plan(player_id: int) -> String:
	if not _players.has(player_id):
		return ""
	return AiPlanClass.normalize_id(str((_players[player_id] as Dictionary).get("active_ai_plan", "")))


func set_selected_ai_plan(player_id: int, plan_id: String) -> void:
	if not _players.has(player_id) or not is_ai_player(player_id):
		return
	var normalized := AiPlanClass.normalize_id(plan_id)
	if not AiPlanClass.is_valid_id(normalized):
		return
	var entry: Dictionary = _players[player_id]
	entry["selected_ai_plan"] = normalized
	_players[player_id] = entry


func set_active_ai_plan(player_id: int, plan_id: String) -> void:
	if not _players.has(player_id) or not is_ai_player(player_id):
		return
	var normalized := AiPlanClass.normalize_id(plan_id)
	if not AiPlanClass.is_concrete_id(normalized):
		return
	var entry: Dictionary = _players[player_id]
	entry["active_ai_plan"] = normalized
	_players[player_id] = entry


## Resolve Random â†’ concrete once per AI player. Skips players that already have a
## concrete active plan (so match-start / UI refresh never re-rolls).
func resolve_ai_plans() -> void:
	for pid in all_player_ids():
		if not is_ai_player(pid):
			continue
		var selected := get_selected_ai_plan(pid)
		if not AiPlanClass.is_valid_id(selected):
			selected = AiPlanClass.ID_RANDOM
			set_selected_ai_plan(pid, selected)
		if AiPlanClass.is_concrete_id(get_active_ai_plan(pid)):
			continue
		set_active_ai_plan(pid, AiPlanClass.resolve_to_concrete(selected))


## Apply a new selected plan and resolve active immediately (pre-game / deployment only).
func apply_selected_ai_plan(player_id: int, plan_id: String) -> void:
	set_selected_ai_plan(player_id, plan_id)
	if not is_ai_player(player_id):
		return
	var selected := get_selected_ai_plan(player_id)
	set_active_ai_plan(player_id, AiPlanClass.resolve_to_concrete(selected))
