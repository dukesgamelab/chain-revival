class_name GameSession
extends RefCounted
## Root gameplay container for a match (local dev: both teams on one machine).
##
## Architecture (server-ready):
##   GameSession → fireteams and active team
##   GameState   → session + map_data (authoritative snapshot)
##   ActionResolver → validates/applies Command DTOs against GameState
##
## Presentation (main.gd, Soldier scenes) reads GameState and never mutates it directly.
##
## Ownership: `owned_fireteams` are MatchConfig player slots (2 for 1v1, 4 for 2v2).
## `blue_team` / `red_team` are side aggregates sharing the same SoldierState refs so
## existing combat / UI that calls get_fireteam(team) still sees every soldier on that side.

const MatchConfigClass := preload("res://scripts/core/match_config.gd")

var blue_team: Fireteam
var red_team: Fireteam
var active_team_id: int = Team.USA
## Player-owned fireteams from MatchConfig (IDs only on each Fireteam).
var owned_fireteams: Array[Fireteam] = []
var local_player_id: int = 1
var match_config: MatchConfigClass = null


func _init(blue_spawns: Array[Vector2i] = [], red_spawns: Array[Vector2i] = []) -> void:
	if blue_spawns.is_empty() and red_spawns.is_empty():
		## Empty placeholder; call setup_from_match_config / legacy two-team init.
		return
	_setup_legacy_1v1(blue_spawns, red_spawns)


static func from_match_config(
	config: MatchConfigClass,
	blue_spawns: Array[Vector2i],
	red_spawns: Array[Vector2i],
) -> GameSession:
	var session := GameSession.new()
	session.setup_from_match_config(config, blue_spawns, red_spawns)
	return session


func _setup_legacy_1v1(blue_spawns: Array[Vector2i], red_spawns: Array[Vector2i]) -> void:
	var cfg: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	setup_from_match_config(cfg, blue_spawns, red_spawns)


func setup_from_match_config(
	config: MatchConfigClass,
	blue_spawns: Array[Vector2i],
	red_spawns: Array[Vector2i],
) -> void:
	match_config = config
	local_player_id = config.local_player_id if config != null else 1
	owned_fireteams.clear()
	if config == null:
		config = MatchConfigClass.default_offline_1v1() as MatchConfigClass
		match_config = config
	## Unused Open lobby seats become AI before fireteam / hierarchy bootstrap.
	config.fill_open_slots_with_ai()
	local_player_id = config.local_player_id

	var usa_parts: Array[Fireteam] = []
	var ger_parts: Array[Fireteam] = []
	var next_ft_id := 1

	if config.match_type == MatchConfigClass.MatchType.TWO_V_TWO:
		## Two fireteams per side × 2 soldiers (soldier ids 1–2 and 3–4).
		for slot in config.slots:
			var team_id := int(slot.get("team_id", Team.USA))
			var slot_index := int(slot.get("slot_index", 0))
			var player_id := int(slot.get("player_id", next_ft_id))
			var soldier_ids: Array[int] = []
			if slot_index == 0:
				soldier_ids.assign([1, 2])
			else:
				soldier_ids.assign([3, 4])
			var spawns := blue_spawns if team_id == Team.USA else red_spawns
			var slice := _spawn_slice(spawns, slot_index, 2)
			var ft := Fireteam.create_owned(next_ft_id, player_id, team_id, soldier_ids, slice)
			owned_fireteams.append(ft)
			if team_id == Team.USA:
				usa_parts.append(ft)
			else:
				ger_parts.append(ft)
			next_ft_id += 1
	else:
		## 1v1: one fireteam per side × 4 soldiers.
		for slot in config.slots:
			var team_id := int(slot.get("team_id", Team.USA))
			var player_id := int(slot.get("player_id", next_ft_id))
			var soldier_ids: Array[int] = []
			soldier_ids.assign([1, 2, 3, 4])
			var spawns := blue_spawns if team_id == Team.USA else red_spawns
			var ft := Fireteam.create_owned(next_ft_id, player_id, team_id, soldier_ids, spawns)
			owned_fireteams.append(ft)
			if team_id == Team.USA:
				usa_parts.append(ft)
			else:
				ger_parts.append(ft)
			next_ft_id += 1

	blue_team = Fireteam.create_aggregate(Team.USA, usa_parts)
	red_team = Fireteam.create_aggregate(Team.GERMANY, ger_parts)
	active_team_id = Team.USA
	## Prefer starting on the local human's team.
	var local_ft := get_fireteam_for_player(local_player_id)
	if local_ft != null:
		active_team_id = local_ft.team_id


static func _spawn_slice(
	spawns: Array[Vector2i],
	slot_index: int,
	count: int,
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start := slot_index * count
	for i in count:
		var idx := start + i
		if idx < spawns.size():
			out.append(spawns[idx])
		elif not spawns.is_empty():
			out.append(spawns[mini(idx, spawns.size() - 1)])
		else:
			out.append(Vector2i(10 + i, 10))
	return out


func create_game_state(map_data: MapData) -> GameState:
	return GameState.new(self, map_data)


func get_active_fireteam() -> Fireteam:
	## UI "active side" aggregate (all soldiers on active_team_id).
	return get_fireteam(active_team_id)


func get_fireteam(team_id: int) -> Fireteam:
	if team_id == Team.GERMANY:
		return red_team
	return blue_team


func get_fireteam_by_id(fireteam_id: int) -> Fireteam:
	for ft in owned_fireteams:
		if ft.fireteam_id == fireteam_id:
			return ft
	return null


func get_fireteam_for_player(player_id: int) -> Fireteam:
	for ft in owned_fireteams:
		if ft.owner_player_id == player_id:
			return ft
	return null


func owned_fireteams_for_team(team_id: int) -> Array[Fireteam]:
	var out: Array[Fireteam] = []
	for ft in owned_fireteams:
		if ft.team_id == team_id:
			out.append(ft)
	return out


func local_owned_fireteams() -> Array[Fireteam]:
	var out: Array[Fireteam] = []
	for ft in owned_fireteams:
		if ft.owner_player_id == local_player_id:
			out.append(ft)
	return out


func is_soldier_owned_by_local(team_id: int, soldier_id: int) -> bool:
	for ft in local_owned_fireteams():
		if ft.team_id == team_id and ft.owns_soldier(soldier_id):
			return true
	## Offline legacy: if no ownership data, allow.
	if owned_fireteams.is_empty():
		return true
	return false


func is_soldier_owned_by_player(player_id: int, team_id: int, soldier_id: int) -> bool:
	if player_id <= 0:
		return false
	var ft := get_fireteam_for_player(player_id)
	if ft == null:
		return false
	return ft.team_id == team_id and ft.owns_soldier(soldier_id)


func can_local_control_soldier(team_id: int, soldier_id: int) -> bool:
	if not PlayerSides.can_control_team(team_id):
		return false
	return is_soldier_owned_by_local(team_id, soldier_id)


func set_active_team(team_id: int) -> void:
	if team_id == Team.USA or team_id == Team.GERMANY:
		active_team_id = team_id


## Side aggregates — one entry per team (combat, views, registry).
func all_fireteams() -> Array[Fireteam]:
	return [blue_team, red_team]


func to_dict() -> Dictionary:
	var owned: Array = []
	for ft in owned_fireteams:
		owned.append(ft.to_dict())
	return {
		"active_team_id": active_team_id,
		"local_player_id": local_player_id,
		"match_config": match_config.to_dict() if match_config != null else {},
		"owned_fireteams": owned,
		"blue_team": blue_team.to_dict(),
		"red_team": red_team.to_dict(),
	}


func load_from_dict(data: Dictionary) -> void:
	active_team_id = int(data.get("active_team_id", Team.USA))
	local_player_id = int(data.get("local_player_id", 1))
	var raw_cfg: Variant = data.get("match_config", {})
	if raw_cfg is Dictionary and not (raw_cfg as Dictionary).is_empty():
		match_config = MatchConfigClass.from_dict(raw_cfg as Dictionary) as MatchConfigClass
	owned_fireteams.clear()
	var raw_owned: Variant = data.get("owned_fireteams", [])
	if raw_owned is Array and not (raw_owned as Array).is_empty():
		for entry in raw_owned:
			if entry is Dictionary:
				var ft := Fireteam.new()
				ft.soldiers.clear()
				ft.load_from_dict(entry as Dictionary)
				owned_fireteams.append(ft)
		var usa_parts: Array[Fireteam] = []
		var ger_parts: Array[Fireteam] = []
		for ft in owned_fireteams:
			if ft.team_id == Team.USA:
				usa_parts.append(ft)
			else:
				ger_parts.append(ft)
		blue_team = Fireteam.create_aggregate(Team.USA, usa_parts)
		red_team = Fireteam.create_aggregate(Team.GERMANY, ger_parts)
	else:
		blue_team = Fireteam.new(Team.USA, [])
		red_team = Fireteam.new(Team.GERMANY, [])
		blue_team.load_from_dict(data.get("blue_team", {}))
		red_team.load_from_dict(data.get("red_team", {}))
