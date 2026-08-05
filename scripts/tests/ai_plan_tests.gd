extends Node
## Phase 3 Pre-Game AI Planning acceptance tests.
##
## Run:
##   Godot_v4.x_console.exe --headless --path <project> res://scripts/tests/ai_plan_tests.tscn

const MatchConfigClass := preload("res://scripts/core/match_config.gd")
const MapDataClass := preload("res://scripts/map/map_data.gd")
const GameSessionClass := preload("res://scripts/core/game_session.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")
const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")
const SetAiPlanCommandClass := preload("res://scripts/commands/set_ai_plan_command.gd")
const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const ActionResultClass := preload("res://scripts/core/action_result.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_default_selected_for_slot_by_side()
	_test_match_config_1v1_ai_selector_shape()
	_test_match_config_2v2_ai_selector_shape()
	_test_human_open_have_no_ai_plan()
	_test_ai_slots_receive_valid_selected_plans()
	_test_random_resolves_once_to_concrete()
	_test_random_deterministic_with_seed()
	_test_random_never_resolves_to_random()
	_test_match_config_serialization()
	_test_set_ai_plan_command_validation()
	_test_plans_lock_after_running()
	_test_runtime_active_plans_for_hud()
	_test_explicit_user_selection_wins_over_default()
	print("")
	print("AI plan tests: %d passed, %d failed" % [_passed, _failed])
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


func _make_game_state(cfg: MatchConfigClass) -> GameStateClass:
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var session := GameSessionClass.from_match_config(
		cfg,
		_spawns(4, Vector2i(10, 10)),
		_spawns(4, Vector2i(40, 40)),
	)
	var game_state := session.create_game_state(map_data)
	ActionResolverClass.apply_match_start_setup(game_state)
	return game_state


func _submit(game_state: GameStateClass, command: RefCounted) -> ActionResultClass:
	return ActionResolverClass.execute(game_state, command)


func _test_default_selected_for_slot_by_side() -> void:
	const CONTROLLER_AI := 1
	_assert(
		"Germany AI default Defend",
		AiPlanClass.default_selected_for_slot(CONTROLLER_AI, Team.GERMANY, Team.USA)
		== AiPlanClass.ID_DEFEND,
	)
	_assert(
		"USA AI default Attack Center",
		AiPlanClass.default_selected_for_slot(CONTROLLER_AI, Team.USA, Team.GERMANY)
		== AiPlanClass.ID_ATTACK_CENTER,
	)
	_assert(
		"Germany default ignores human team arg",
		AiPlanClass.default_selected_for_slot(CONTROLLER_AI, Team.GERMANY, Team.GERMANY)
		== AiPlanClass.ID_DEFEND,
	)
	_assert(
		"Human controller gets empty plan",
		AiPlanClass.default_selected_for_slot(0, Team.GERMANY, Team.USA).is_empty(),
	)


func _test_match_config_1v1_ai_selector_shape() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	var ai := cfg.ai_slots()
	_assert("SP 1v1 has exactly one AI slot", ai.size() == 1, "count=%d" % ai.size())
	if ai.is_empty():
		return
	_assert(
		"SP 1v1 AI is enemy team",
		int(ai[0].get("team_id", -1)) != cfg.local_human_team_id(),
	)
	_assert(
		"SP 1v1 Germany AI defaults to Defend",
		AiPlanClass.normalize_id(str(ai[0].get("selected_ai_plan", ""))) == AiPlanClass.ID_DEFEND,
	)


func _test_match_config_2v2_ai_selector_shape() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.SINGLE_PLAYER,
		MatchConfigClass.MatchType.TWO_V_TWO,
	) as MatchConfigClass
	var ai := cfg.ai_slots()
	_assert("SP 2v2 has three AI slots", ai.size() == 3, "count=%d" % ai.size())
	var usa_ai := 0
	var ger_ai := 0
	for slot in ai:
		var plan := AiPlanClass.normalize_id(str(slot.get("selected_ai_plan", "")))
		if int(slot.get("team_id", -1)) == Team.USA:
			usa_ai += 1
			_assert(
				"USA AI defaults to Attack Center",
				plan == AiPlanClass.ID_ATTACK_CENTER,
			)
		elif int(slot.get("team_id", -1)) == Team.GERMANY:
			ger_ai += 1
			_assert(
				"Germany AI defaults to Defend",
				plan == AiPlanClass.ID_DEFEND,
			)
	_assert("SP 2v2 one USA AI", usa_ai == 1, "usa_ai=%d" % usa_ai)
	_assert("SP 2v2 two Germany AI", ger_ai == 2, "ger_ai=%d" % ger_ai)


func _test_human_open_have_no_ai_plan() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.MULTIPLAYER,
		MatchConfigClass.MatchType.ONE_V_ONE,
	) as MatchConfigClass
	_assert("MP 1v1 has one AI slot by default", cfg.ai_slots().size() == 1)
	for slot in cfg.slots:
		if int(slot.get("controller", -1)) == MatchConfigClass.ControllerType.HUMAN:
			_assert(
				"Human slot has empty AI plan",
				str(slot.get("selected_ai_plan", "")).is_empty(),
				"pid=%s plan=%s" % [slot.get("player_id"), slot.get("selected_ai_plan")],
			)
		elif int(slot.get("controller", -1)) == MatchConfigClass.ControllerType.OPEN:
			_assert(
				"Open slot has empty AI plan",
				str(slot.get("selected_ai_plan", "")).is_empty(),
				"pid=%s plan=%s" % [slot.get("player_id"), slot.get("selected_ai_plan")],
			)
	var sp: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	for slot in sp.slots:
		if int(slot.get("controller", -1)) == MatchConfigClass.ControllerType.HUMAN:
			_assert(
				"Human slot has empty AI plan",
				str(slot.get("selected_ai_plan", "")).is_empty(),
			)


func _test_ai_slots_receive_valid_selected_plans() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.SINGLE_PLAYER,
		MatchConfigClass.MatchType.TWO_V_TWO,
	) as MatchConfigClass
	for slot in cfg.ai_slots():
		var plan := AiPlanClass.normalize_id(str(slot.get("selected_ai_plan", "")))
		_assert(
			"AI slot has valid selected plan",
			AiPlanClass.is_valid_id(plan),
			"pid=%s plan=%s" % [slot.get("player_id"), plan],
		)


func _test_random_resolves_once_to_concrete() -> void:
	GameRandom.begin_match(GameRandom.DEFAULT_SEED)
	var cfg: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	## Explicit Random — defaults are side-based now (Germany → Defend).
	_assert("set Germany AI to Random", cfg.set_slot_ai_plan(2, AiPlanClass.ID_RANDOM))
	var game_state := _make_game_state(cfg)
	var enemy_id := -1
	for pid in game_state.command_hierarchy.all_player_ids():
		if game_state.command_hierarchy.is_ai_player(pid):
			enemy_id = pid
			break
	_assert("1v1 has AI player", enemy_id > 0)
	var selected := game_state.get_selected_ai_plan(enemy_id)
	var active := game_state.get_active_ai_plan(enemy_id)
	_assert("selected remains Random", selected == AiPlanClass.ID_RANDOM)
	_assert("active is concrete", AiPlanClass.is_concrete_id(active), "active=%s" % active)
	var first_active := active
	game_state.resolve_ai_plans()
	_assert(
		"second resolve does not re-roll",
		game_state.get_active_ai_plan(enemy_id) == first_active,
	)


func _test_random_deterministic_with_seed() -> void:
	GameRandom.begin_match(42)
	var cfg_a: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	cfg_a.set_slot_ai_plan(2, AiPlanClass.ID_RANDOM)
	var gs_a := _make_game_state(cfg_a)
	var active_a := ""
	for pid in gs_a.command_hierarchy.all_player_ids():
		if gs_a.command_hierarchy.is_ai_player(pid):
			active_a = gs_a.get_active_ai_plan(pid)
			break

	GameRandom.begin_match(42)
	var cfg_b: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	cfg_b.set_slot_ai_plan(2, AiPlanClass.ID_RANDOM)
	var gs_b := _make_game_state(cfg_b)
	var active_b := ""
	for pid in gs_b.command_hierarchy.all_player_ids():
		if gs_b.command_hierarchy.is_ai_player(pid):
			active_b = gs_b.get_active_ai_plan(pid)
			break

	_assert("same seed → same resolved plan", active_a == active_b, "%s vs %s" % [active_a, active_b])
	_assert("resolved plan is concrete", AiPlanClass.is_concrete_id(active_a))


func _test_random_never_resolves_to_random() -> void:
	GameRandom.begin_match(7)
	for _i in 40:
		var resolved := AiPlanClass.resolve_to_concrete(AiPlanClass.ID_RANDOM)
		if resolved == AiPlanClass.ID_RANDOM or not AiPlanClass.is_concrete_id(resolved):
			_assert("Random never resolves to Random", false, "got=%s" % resolved)
			return
	_assert("Random never resolves to Random", true)


func _test_match_config_serialization() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.SINGLE_PLAYER,
		MatchConfigClass.MatchType.TWO_V_TWO,
	) as MatchConfigClass
	_assert(
		"set flank on friendly AI",
		cfg.set_slot_ai_plan(2, AiPlanClass.ID_FLANK),
	)
	var data := cfg.to_dict()
	var restored: MatchConfigClass = MatchConfigClass.from_dict(data) as MatchConfigClass
	_assert(
		"serialized flank survives",
		restored.get_slot_ai_plan(2) == AiPlanClass.ID_FLANK,
	)
	_assert(
		"Germany defend default survives",
		restored.get_slot_ai_plan(3) == AiPlanClass.ID_DEFEND,
	)


func _test_set_ai_plan_command_validation() -> void:
	GameRandom.begin_match(GameRandom.DEFAULT_SEED)
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.SINGLE_PLAYER,
		MatchConfigClass.MatchType.TWO_V_TWO,
	) as MatchConfigClass
	var game_state := _make_game_state(cfg)

	var missing := SetAiPlanCommandClass.new()
	missing.player_id = 999
	missing.plan_id = AiPlanClass.ID_DEFEND
	_assert("missing player rejected", not _submit(game_state, missing).success)

	var human := SetAiPlanCommandClass.new()
	human.player_id = cfg.local_player_id
	human.plan_id = AiPlanClass.ID_DEFEND
	_assert("human player rejected", not _submit(game_state, human).success)

	var bad_plan := SetAiPlanCommandClass.new()
	bad_plan.player_id = 2
	bad_plan.plan_id = "not_a_plan"
	_assert("invalid plan rejected", not _submit(game_state, bad_plan).success)

	var ok := SetAiPlanCommandClass.new()
	ok.player_id = 2
	ok.plan_id = AiPlanClass.ID_FLANK
	var result := _submit(game_state, ok)
	_assert("AI plan assign succeeds in deployment", result.success, result.status_message)
	_assert("selected is flank", game_state.get_selected_ai_plan(2) == AiPlanClass.ID_FLANK)
	_assert("active is flank", game_state.get_active_ai_plan(2) == AiPlanClass.ID_FLANK)


func _test_plans_lock_after_running() -> void:
	GameRandom.begin_match(GameRandom.DEFAULT_SEED)
	var cfg: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	var game_state := _make_game_state(cfg)
	game_state.begin_running_phase()
	var enemy_id := -1
	for pid in game_state.command_hierarchy.all_player_ids():
		if game_state.command_hierarchy.is_ai_player(pid):
			enemy_id = pid
			break
	var cmd := SetAiPlanCommandClass.new()
	cmd.player_id = enemy_id
	cmd.plan_id = AiPlanClass.ID_DEFEND
	var result := _submit(game_state, cmd)
	_assert("locked after running", not result.success, result.status_message)
	_assert(
		"lock message mentions locked/running",
		"locked" in result.status_message.to_lower()
		or "running" in result.status_message.to_lower(),
		result.status_message,
	)


func _test_runtime_active_plans_for_hud() -> void:
	GameRandom.begin_match(GameRandom.DEFAULT_SEED)
	var cfg: MatchConfigClass = MatchConfigClass.new(
		MatchConfigClass.GameModeKind.SINGLE_PLAYER,
		MatchConfigClass.MatchType.TWO_V_TWO,
	) as MatchConfigClass
	var game_state := _make_game_state(cfg)
	var lines := 0
	for pid in game_state.command_hierarchy.all_player_ids():
		if not game_state.command_hierarchy.is_ai_player(pid):
			continue
		var active := game_state.get_active_ai_plan(pid)
		_assert(
			"HUD source active plan concrete",
			AiPlanClass.is_concrete_id(active),
			"pid=%d active=%s" % [pid, active],
		)
		var label := AiPlanClass.format_runtime_label(
			game_state.get_selected_ai_plan(pid),
			active,
		)
		_assert("HUD label non-empty", not label.is_empty(), "pid=%d" % pid)
		lines += 1
	_assert("HUD would show three AI lines", lines == 3, "lines=%d" % lines)


func _test_explicit_user_selection_wins_over_default() -> void:
	var cfg: MatchConfigClass = MatchConfigClass.default_offline_1v1() as MatchConfigClass
	_assert(
		"default Germany Defend before override",
		cfg.get_slot_ai_plan(2) == AiPlanClass.ID_DEFEND,
	)
	_assert("user picks Flank", cfg.set_slot_ai_plan(2, AiPlanClass.ID_FLANK))
	_assert("explicit Flank wins over default", cfg.get_slot_ai_plan(2) == AiPlanClass.ID_FLANK)
	_assert("user can still pick Random", cfg.set_slot_ai_plan(2, AiPlanClass.ID_RANDOM))
	_assert("explicit Random retained", cfg.get_slot_ai_plan(2) == AiPlanClass.ID_RANDOM)
	## Rebuilding defaults must not clobber an already-valid explicit selection via set_slot.
	## Switching controller away and back re-applies defaults only when plan invalid.
	cfg.set_slot_controller(2, MatchConfigClass.ControllerType.HUMAN)
	cfg.set_slot_controller(2, MatchConfigClass.ControllerType.AI)
	_assert(
		"re-AI after human gets side default Defend",
		cfg.get_slot_ai_plan(2) == AiPlanClass.ID_DEFEND,
	)
