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
	_assert(
		"1v1 local cannot control GER soldier",
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
		_spawns(4, Vector2i(10, 10)),
		_spawns(4, Vector2i(40, 40)),
	)
	_assert("2v2 owned_fireteams == 4", session.owned_fireteams.size() == 4)
	_assert("2v2 blue has 4 soldiers", session.blue_team.soldiers.size() == 4)
	_assert("2v2 red has 4 soldiers", session.red_team.soldiers.size() == 4)
	var human_ft := session.get_fireteam_for_player(cfg.local_player_id)
	_assert("2v2 human FT has 2 soldiers", human_ft != null and human_ft.soldiers.size() == 2)
	_assert(
		"2v2 local owns soldier 1",
		session.can_local_control_soldier(Team.USA, 1),
	)
	_assert(
		"2v2 local does not own ally AI soldier 3",
		not session.can_local_control_soldier(Team.USA, 3),
	)
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
	var cfg: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
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
	_assert("MP 1v1 valid with Open", cfg.is_valid())
	for slot in cfg.slots:
		_assert(
			"MP default Open",
			int(slot.get("controller", -1)) == MatchConfigClass.ControllerType.OPEN,
		)
	cfg.set_match_type(MatchConfigClass.MatchType.TWO_V_TWO)
	_assert("MP 2v2 four Open slots", cfg.slots.size() == 4 and cfg.is_valid())
