class_name MatchConfig
extends RefCounted
## Serializable match setup (IDs only — no nodes). Consumed by GameSession / GameState.
## Future: commander hierarchy, AI plans, multiplayer lobby, dedicated server.

enum GameModeKind { SINGLE_PLAYER, MULTIPLAYER }
enum MatchType { ONE_V_ONE, TWO_V_TWO }
enum ControllerType { HUMAN, AI, OPEN }

const MAP_FARM_FIGHT := "ff_farm"
const MAP_FARM_FIGHT_PATH := "res://maps/ff_farm.json"

## GameModeKind
var game_mode: int = GameModeKind.SINGLE_PLAYER
## MatchType
var match_type: int = MatchType.ONE_V_ONE
var map_id: String = MAP_FARM_FIGHT
## Local controlling player (human). Slot player_id.
var local_player_id: int = 1
## [{ player_id, team_id, controller, slot_index, display_name }, ...]
var slots: Array[Dictionary] = []


func _init(
	p_game_mode: int = GameModeKind.SINGLE_PLAYER,
	p_match_type: int = MatchType.ONE_V_ONE,
) -> void:
	game_mode = p_game_mode
	match_type = p_match_type
	map_id = MAP_FARM_FIGHT
	rebuild_default_slots()


static func default_offline_1v1() -> RefCounted:
	## Dev / offline bypass: Single Player 1v1 USA Human vs Germany AI.
	## Returns MatchConfig (typed as RefCounted to avoid self class_name parse issues).
	var cfg = new(GameModeKind.SINGLE_PLAYER, MatchType.ONE_V_ONE)
	cfg.local_player_id = 1
	return cfg


func rebuild_default_slots() -> void:
	slots.clear()
	match match_type:
		MatchType.TWO_V_TWO:
			_add_slot(1, Team.USA, _default_controller(Team.USA, 0), 0, "USA-1")
			_add_slot(2, Team.USA, _default_controller(Team.USA, 1), 1, "USA-2")
			_add_slot(3, Team.GERMANY, _default_controller(Team.GERMANY, 0), 0, "GER-1")
			_add_slot(4, Team.GERMANY, _default_controller(Team.GERMANY, 1), 1, "GER-2")
		_:
			_add_slot(1, Team.USA, _default_controller(Team.USA, 0), 0, "USA")
			_add_slot(2, Team.GERMANY, _default_controller(Team.GERMANY, 0), 0, "Germany")
	_ensure_local_human()


func _default_controller(team_id: int, slot_on_team: int) -> int:
	if game_mode == GameModeKind.MULTIPLAYER:
		return ControllerType.OPEN
	## Single player: first USA slot human; everyone else AI.
	if team_id == Team.USA and slot_on_team == 0:
		return ControllerType.HUMAN
	return ControllerType.AI


func _add_slot(
	player_id: int,
	team_id: int,
	controller: int,
	slot_index: int,
	display_name: String,
) -> void:
	slots.append({
		"player_id": player_id,
		"team_id": team_id,
		"controller": controller,
		"slot_index": slot_index,
		"display_name": display_name,
	})


func set_match_type(new_type: int) -> void:
	match_type = new_type
	rebuild_default_slots()


func set_game_mode(new_mode: int) -> void:
	game_mode = new_mode
	rebuild_default_slots()


## Swap which team the local human sits on (Single Player). AI fills the rest.
func switch_human_side() -> void:
	if game_mode != GameModeKind.SINGLE_PLAYER:
		return
	var human_team := Team.USA
	for slot in slots:
		if int(slot.get("controller", -1)) == ControllerType.HUMAN:
			human_team = int(slot.get("team_id", Team.USA))
			break
	var target_team := Team.GERMANY if human_team == Team.USA else Team.USA
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var team_id := int(slot.get("team_id", Team.USA))
		var slot_index := int(slot.get("slot_index", 0))
		if team_id == target_team and slot_index == 0:
			slot["controller"] = ControllerType.HUMAN
			local_player_id = int(slot.get("player_id", 1))
		else:
			slot["controller"] = ControllerType.AI
		slots[i] = slot


func set_slot_controller(player_id: int, controller: int) -> void:
	for i in slots.size():
		var slot: Dictionary = slots[i]
		if int(slot.get("player_id", -1)) != player_id:
			continue
		slot["controller"] = controller
		slots[i] = slot
		break
	if controller == ControllerType.HUMAN:
		local_player_id = player_id
		## Single human for SP: demote other humans to AI.
		if game_mode == GameModeKind.SINGLE_PLAYER:
			for j in slots.size():
				var other: Dictionary = slots[j]
				if int(other.get("player_id", -1)) == player_id:
					continue
				if int(other.get("controller", -1)) == ControllerType.HUMAN:
					other["controller"] = ControllerType.AI
					slots[j] = other


func _ensure_local_human() -> void:
	for slot in slots:
		if int(slot.get("controller", -1)) == ControllerType.HUMAN:
			local_player_id = int(slot.get("player_id", 1))
			return
	## Multiplayer may be all OPEN — keep default local_player_id.


func slots_for_team(team_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in slots:
		if int(slot.get("team_id", -1)) == team_id:
			out.append(slot.duplicate(true))
	return out


func player_count() -> int:
	return slots.size()


func fireteam_count() -> int:
	return slots.size()


func map_path() -> String:
	if map_id == MAP_FARM_FIGHT or map_id.is_empty():
		return MAP_FARM_FIGHT_PATH
	## IDs only — no MapData / scene refs. Convention: res://maps/<id>.json
	return "res://maps/%s.json" % map_id


func to_runtime_game_mode() -> int:
	## Mirrors GameMode enum without importing it (keeps MatchConfig dependency-light).
	## GameMode.LOCAL_MULTIPLAYER = 1, GameMode.OFFLINE_DEV = 0
	if game_mode == GameModeKind.MULTIPLAYER:
		return 1
	return 0


func validate() -> Dictionary:
	## { ok: bool, errors: PackedStringArray }
	var errors: PackedStringArray = []
	if map_id.is_empty():
		errors.append("Map is required")
	if match_type != MatchType.ONE_V_ONE and match_type != MatchType.TWO_V_TWO:
		errors.append("Invalid match type")
	var expected := 2 if match_type == MatchType.ONE_V_ONE else 4
	if slots.size() != expected:
		errors.append("Expected %d player slots, got %d" % [expected, slots.size()])
	var humans := 0
	var opens := 0
	var seen_ids: Dictionary = {}
	for slot in slots:
		var pid := int(slot.get("player_id", -1))
		var team_id := int(slot.get("team_id", -1))
		var controller := int(slot.get("controller", -1))
		if pid <= 0:
			errors.append("Slot missing player_id")
		if seen_ids.has(pid):
			errors.append("Duplicate player_id %d" % pid)
		seen_ids[pid] = true
		if team_id != Team.USA and team_id != Team.GERMANY:
			errors.append("Invalid team on player %d" % pid)
		if (
			controller != ControllerType.HUMAN
			and controller != ControllerType.AI
			and controller != ControllerType.OPEN
		):
			errors.append("Invalid controller on player %d" % pid)
		if controller == ControllerType.HUMAN:
			humans += 1
		if controller == ControllerType.OPEN:
			opens += 1
	if game_mode == GameModeKind.SINGLE_PLAYER:
		if humans != 1:
			errors.append("Single Player requires exactly one Human slot")
		if opens > 0:
			errors.append("Single Player cannot use Open slots")
	return {"ok": errors.is_empty(), "errors": errors}


func is_valid() -> bool:
	return bool(validate().get("ok", false))


static func controller_label(controller: int) -> String:
	match controller:
		ControllerType.HUMAN:
			return "Human"
		ControllerType.AI:
			return "AI"
		ControllerType.OPEN:
			return "Open"
		_:
			return "Unknown"


static func match_type_label(match_type_value: int) -> String:
	match match_type_value:
		MatchType.TWO_V_TWO:
			return "2v2"
		_:
			return "1v1"


static func game_mode_label(mode_value: int) -> String:
	match mode_value:
		GameModeKind.MULTIPLAYER:
			return "Multiplayer"
		_:
			return "Single Player"


func to_dict() -> Dictionary:
	var slot_dicts: Array = []
	for slot in slots:
		slot_dicts.append((slot as Dictionary).duplicate(true))
	return {
		"game_mode": game_mode,
		"match_type": match_type,
		"map_id": map_id,
		"local_player_id": local_player_id,
		"slots": slot_dicts,
	}


static func from_dict(data: Dictionary) -> RefCounted:
	## Returns MatchConfig (typed as RefCounted to avoid self class_name parse issues).
	var cfg = new()
	cfg.game_mode = int(data.get("game_mode", GameModeKind.SINGLE_PLAYER))
	cfg.match_type = int(data.get("match_type", MatchType.ONE_V_ONE))
	cfg.map_id = str(data.get("map_id", MAP_FARM_FIGHT))
	cfg.local_player_id = int(data.get("local_player_id", 1))
	cfg.slots.clear()
	var raw_slots: Variant = data.get("slots", [])
	if raw_slots is Array and not (raw_slots as Array).is_empty():
		for entry in raw_slots:
			if entry is Dictionary:
				cfg.slots.append((entry as Dictionary).duplicate(true))
	else:
		cfg.rebuild_default_slots()
	return cfg
