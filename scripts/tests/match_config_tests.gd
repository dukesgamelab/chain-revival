extends Node
## Phase 1 Match Setup: MatchConfig + GameSession ownership smoke tests.
##
## Run:
##   Godot_v4.x_console.exe --headless --path <project> res://scripts/tests/match_config_tests.tscn

const MatchConfigClass := preload("res://scripts/core/match_config.gd")
const GameSessionClass := preload("res://scripts/core/game_session.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_default_offline_1v1()
	_test_sp_2v2_slots_and_ownership()
	_test_switch_sides()
	_test_round_trip_serialize()
	_test_mp_open_slots()
	print("")
	print("Match config tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _pass(name: String) -> void:
	_passed += 1
	print("[PASS] %s" % name)


func _fail(name: String, detail: String) -> void:
	_failed += 1
	print("[FAIL] %s — %s" % [name, detail])


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass(name)
	else:
		_fail(name, detail if not detail.is_empty() else "assertion failed")


func _spawns(n: int, base: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in n:
		out.append(base + Vector2i(i, 0))
	return out


func _test_default_offline_1v1() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	var v: Dictionary = cfg.validate()
	_assert("default 1v1 valid", bool(v.get("ok", false)), str(v.get("errors", [])))
	_assert("default 1v1 two slots", cfg.slots.size() == 2)
	_assert("default 1v1 two fireteams", cfg.fireteam_count() == 2)
	_assert("offline 1v1 has no AI slots", cfg.ai_slots().is_empty())
	_assert("offline 1v1 skips timed deployment", not cfg.timed_deployment)
	var human_slots := 0
	for slot in cfg.slots:
		if int(slot.get("controller", -1)) == MatchConfigClass.ControllerType.HUMAN:
			human_slots += 1
	_assert("offline 1v1 both slots human", human_slots == 2, "humans=%d" % human_slots)

	var session := GameSessionClass.from_match_config(
		cfg,
		_spawns(4, Vector2i(10, 10)),
		_spawns(4, Vector2i(40, 40)),
	)
	_assert("1v1 owned_fireteams == 2", session.owned_fireteams.size() == 2)
	_assert("1v1 blue has 4 soldiers", session.blue_team.soldiers.size() == 4)
	_assert("1v1 red has 4 soldiers", session.red_team.soldiers.size() == 4)
	var usa := session.get_fireteam_for_player(1)
	_assert("1v1 player 1 owns USA FT", usa != null and usa.team_id == Team.USA)
	_assert(
		"1v1 local controls soldier 1",
		session.can_local_control_soldier(Team.USA, 1),
	)
	## Hotseat: only the active local player_id is controllable until 1/2 switch.
	_assert(
		"1v1 local cannot control GER until side switch",
		not session.can_local_control_soldier(Team.GERMANY, 1),
	)


func _test_sp_2v2_slots_and_ownership() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.SINGLE_PLAYER,
		MatchConfigClass.MatchType.TWO_V_TWO,
	) as MatchConfigClass
	var v: Dictionary = cfg.validate()
	_assert("SP 2v2 valid", bool(v.get("ok", false)), str(v.get("errors", [])))
	_assert("SP 2v2 four slots", cfg.slots.size() == 4)

	var session := GameSessionClass.from_match_config(
		cfg,
		_spawns(8, Vector2i(10, 10)),
		_spawns(8, Vector2i(40, 40)),
	)
	_assert("2v2 owned_fireteams == 4", session.owned_fireteams.size() == 4)
	_assert("2v2 blue has 8 soldiers", session.blue_team.soldiers.size() == 8)
	_assert("2v2 red has 8 soldiers", session.red_team.soldiers.size() == 8)
	var human_ft := session.get_fireteam_for_player(cfg.local_player_id)
	_assert("2v2 human FT has 4 soldiers", human_ft != null and human_ft.soldiers.size() == 4)
	_assert(
		"2v2 local owns soldier 1",
		session.can_local_control_soldier(Team.USA, 1),
	)
	_assert(
		"2v2 local does not own ally AI soldier 5",
		not session.can_local_control_soldier(Team.USA, 5),
	)
	var ally_ft := session.get_fireteam_for_player(2)
	_assert("2v2 ally AI FT has 4 soldiers", ally_ft != null and ally_ft.soldiers.size() == 4)
	for ft in session.owned_fireteams:
		_assert(
			"2v2 FT has owner_player_id",
			ft.owner_player_id > 0,
			"fireteam_id=%d" % ft.fireteam_id,
		)
		_assert(
			"2v2 FT has team_id",
			ft.team_id == Team.USA or ft.team_id == Team.GERMANY,
		)


func _test_switch_sides() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.default_single_player_1v1() as MatchConfigClass
	cfg.switch_human_side()
	_assert("switch sides local on GER", cfg.local_player_id == 2)
	var humans := 0
	for slot in cfg.slots:
		if int(slot.get("controller", -1)) == MatchConfigClass.ControllerType.HUMAN:
			humans += 1
			_assert(
				"human on Germany after switch",
				int(slot.get("team_id", -1)) == Team.GERMANY,
			)
	_assert("still one human after switch", humans == 1)
	_assert("still valid after switch", cfg.is_valid())


func _test_round_trip_serialize() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.SINGLE_PLAYER,
		MatchConfigClass.MatchType.TWO_V_TWO,
	) as MatchConfigClass
	cfg.switch_human_side()
	var raw := cfg.to_dict()
	var restored: MatchConfigClass = MatchConfigClass.from_dict(raw) as MatchConfigClass
	_assert("serialize game_mode", restored.game_mode == cfg.game_mode)
	_assert("serialize match_type", restored.match_type == cfg.match_type)
	_assert("serialize map_id", restored.map_id == cfg.map_id)
	_assert("serialize local_player_id", restored.local_player_id == cfg.local_player_id)
	_assert("serialize slot count", restored.slots.size() == cfg.slots.size())
	_assert("serialize still valid", restored.is_valid())


func _test_mp_open_slots() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.MULTIPLAYER,
		MatchConfigClass.MatchType.ONE_V_ONE,
	) as MatchConfigClass
	_assert("MP 1v1 valid", cfg.is_valid())
	var humans := 0
	var ais := 0
	for slot in cfg.slots:
		var c := int(slot.get("controller", -1))
		if c == MatchConfigClass.ControllerType.HUMAN:
			humans += 1
		elif c == MatchConfigClass.ControllerType.AI:
			ais += 1
	_assert("MP 1v1 defaults one Human", humans == 1)
	_assert("MP 1v1 unused slots are AI", ais == 1)
	cfg.set_match_type(MatchConfigClass.MatchType.TWO_V_TWO)
	_assert("MP 2v2 four slots", cfg.slots.size() == 4 and cfg.is_valid())
	ais = 0
	humans = 0
	for slot in cfg.slots:
		var c2 := int(slot.get("controller", -1))
		if c2 == MatchConfigClass.ControllerType.HUMAN:
			humans += 1
		elif c2 == MatchConfigClass.ControllerType.AI:
			ais += 1
	_assert("MP 2v2 one Human three AI", humans == 1 and ais == 3, "h=%d a=%d" % [humans, ais])

	## Legacy Open seats fill to AI before match start.
	cfg.set_slot_controller(2, MatchConfigClass.ControllerType.OPEN)
	## Direct write for Open (set_slot_controller may normalize).
	for i in cfg.slots.size():
		var slot: Dictionary = cfg.slots[i]
		if int(slot.get("player_id", -1)) == 2:
			slot["controller"] = MatchConfigClass.ControllerType.OPEN
			slot["selected_ai_plan"] = ""
			cfg.slots[i] = slot
	cfg.fill_open_slots_with_ai()
	_assert(
		"fill_open converts Open→AI",
		int(cfg.slots[1].get("controller", -1)) == MatchConfigClass.ControllerType.AI
		or cfg.find_ai_slot(Team.USA) == 2,
	)
