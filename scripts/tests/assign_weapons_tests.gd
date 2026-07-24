extends Node
## Assign Weapons (weapon cache → players/soldiers) regression tests.
##
## Run:
##   Godot_v4.x_console.exe --headless --path <project> res://scripts/tests/assign_weapons_tests.tscn

const MapDataClass := preload("res://scripts/map/map_data.gd")
const GameSessionClass := preload("res://scripts/core/game_session.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")
const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")
const AssignWeaponCommandClass := preload("res://scripts/commands/assign_weapon_command.gd")
const ReturnWeaponCommandClass := preload("res://scripts/commands/return_weapon_command.gd")
const AssignCommanderCommandClass := preload("res://scripts/commands/assign_commander_command.gd")
const WeaponCacheClass := preload("res://scripts/core/weapon_cache.gd")
const WeaponPolicyClass := preload("res://scripts/gameplay_policies/weapon_policy.gd")
const ActionResultClass := preload("res://scripts/core/action_result.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_default_pool_contents()
	_test_validation_messages()
	_test_assign_decrements_and_updates_ammo_display()
	_test_bar_swap_returns_garand_to_pool()
	_test_squad_limit_refused()
	_test_ammunition_box_as_equipment()
	_test_solo_hides_subordinates()
	_test_assign_to_subordinate_player_and_ai_distribute()
	print("")
	print("Assign weapons tests: %d passed, %d failed" % [_passed, _failed])
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


func _make_game_state() -> GameStateClass:
	var map_data := MapDataClass.create_default()
	for cell in map_data.get_object_cells():
		map_data.clear_object(cell)
	var blue: Array[Vector2i] = map_data.team_1_spawn_points
	var red: Array[Vector2i] = map_data.team_2_spawn_points
	if blue.is_empty():
		blue = MapDataClass.default_usa_spawn_points()
	if red.is_empty():
		red = MapDataClass.default_germany_spawn_points()
	var session := GameSessionClass.new(blue, red)
	return session.create_game_state(map_data)


func _submit(game_state: GameStateClass, command: RefCounted) -> ActionResultClass:
	return ActionResolverClass.execute(game_state, command)


func _strip_squad_specials(game_state: GameStateClass, team_id: int) -> void:
	## Give every soldier the default rifle so pool specials can be assigned under limits.
	var rifle := WeaponCacheClass.default_rifle_for_team(team_id)
	for state in game_state.session.get_fireteam(team_id).soldiers:
		state.assign_weapon(rifle, true)


func _test_default_pool_contents() -> void:
	var gs := _make_game_state()
	var cache: WeaponCacheClass = gs.weapon_cache
	_assert("USA YOU cache has ammo boxes", cache.pool_count(1, WeaponCacheClass.ITEM_AMMUNITION_BOX) == 4)
	_assert("USA YOU cache has BAR x2", cache.pool_count(1, WeaponPolicyClass.ID_BAR) == 2)
	_assert("USA YOU cache has Thompson x3", cache.pool_count(1, WeaponPolicyClass.ID_THOMPSON) == 3)


func _test_validation_messages() -> void:
	var gs := _make_game_state()
	var empty := AssignWeaponCommandClass.new()
	empty.from_player_id = 1
	empty.item_id = ""
	empty.target_kind = WeaponCacheClass.TargetKind.SOLDIER
	empty.target_id = 1
	empty.target_team_id = Team.USA
	var r1 := _submit(gs, empty)
	_assert("empty item → choose weapon", not r1.success and r1.status_message == "Choose a weapon from the cache")

	var no_target := AssignWeaponCommandClass.new()
	no_target.from_player_id = 1
	no_target.item_id = WeaponPolicyClass.ID_THOMPSON
	no_target.target_kind = WeaponCacheClass.TargetKind.SOLDIER
	no_target.target_id = -1
	var r2 := _submit(gs, no_target)
	_assert(
		"no target → choose target",
		not r2.success and r2.status_message == "Choose a target for weapon assignment",
	)

	var gone := AssignWeaponCommandClass.new()
	gone.from_player_id = 1
	gone.item_id = "not_a_real_weapon"
	gone.target_kind = WeaponCacheClass.TargetKind.SOLDIER
	gone.target_id = 1
	gone.target_team_id = Team.USA
	var r3 := _submit(gs, gone)
	_assert("missing pool item → no weapon available", not r3.success and r3.status_message == "No weapon available")


func _test_assign_decrements_and_updates_ammo_display() -> void:
	var gs := _make_game_state()
	_strip_squad_specials(gs, Team.USA)
	var cache: WeaponCacheClass = gs.weapon_cache
	var before := cache.pool_count(1, WeaponPolicyClass.ID_THOMPSON)
	var cmd := AssignWeaponCommandClass.new()
	cmd.from_player_id = 1
	cmd.item_id = WeaponPolicyClass.ID_THOMPSON
	cmd.target_kind = WeaponCacheClass.TargetKind.SOLDIER
	cmd.target_id = 1
	cmd.target_team_id = Team.USA
	var result := _submit(gs, cmd)
	var soldier: SoldierState = gs.get_soldier(Team.USA, 1)
	_assert("assign thompson succeeds", result.success)
	_assert("pool decremented", cache.pool_count(1, WeaponPolicyClass.ID_THOMPSON) == before - 1)
	_assert("soldier weapon is thompson", soldier.weapon_id == WeaponPolicyClass.ID_THOMPSON)
	_assert("soldier ammo is AmmoMax 200", soldier.ammo_current == 200)
	_assert(
		"display line uses weapon, ammo",
		"%s, %d" % [cache.display_name(soldier.weapon_id), soldier.ammo_current] == "Thompson, 200",
	)


func _test_bar_swap_returns_garand_to_pool() -> void:
	var gs := _make_game_state()
	_strip_squad_specials(gs, Team.USA)
	var cache: WeaponCacheClass = gs.weapon_cache
	var soldier: SoldierState = gs.get_soldier(Team.USA, 1)
	soldier.assign_weapon(WeaponPolicyClass.ID_M1_GARAND, true)
	var garand_before := cache.pool_count(1, WeaponPolicyClass.ID_M1_GARAND)
	var bar_before := cache.pool_count(1, WeaponPolicyClass.ID_BAR)
	var cmd := AssignWeaponCommandClass.new()
	cmd.from_player_id = 1
	cmd.item_id = WeaponPolicyClass.ID_BAR
	cmd.target_kind = WeaponCacheClass.TargetKind.SOLDIER
	cmd.target_id = 1
	cmd.target_team_id = Team.USA
	var result := _submit(gs, cmd)
	_assert("BAR assign succeeds after strip", result.success)
	_assert("soldier now has BAR", soldier.weapon_id == WeaponPolicyClass.ID_BAR)
	_assert("BAR ammo is AmmoMax 900", soldier.ammo_current == 900)
	_assert("BAR left pool", cache.pool_count(1, WeaponPolicyClass.ID_BAR) == bar_before - 1)
	_assert(
		"Garand returned to pool",
		cache.pool_count(1, WeaponPolicyClass.ID_M1_GARAND) == garand_before + 1,
	)


func _test_squad_limit_refused() -> void:
	var gs := _make_game_state()
	## Default loadout already has 1 BAR on soldier 4 — assigning another must fail.
	var cmd := AssignWeaponCommandClass.new()
	cmd.from_player_id = 1
	cmd.item_id = WeaponPolicyClass.ID_BAR
	cmd.target_kind = WeaponCacheClass.TargetKind.SOLDIER
	cmd.target_id = 1
	cmd.target_team_id = Team.USA
	var result := _submit(gs, cmd)
	_assert(
		"BAR over squad limit refused",
		not result.success and result.status_message == "Weapon limit for this squad reached",
	)
	_assert(
		"BAR still in pool after refuse",
		gs.weapon_cache.pool_count(1, WeaponPolicyClass.ID_BAR) == 2,
	)


func _test_ammunition_box_as_equipment() -> void:
	var gs := _make_game_state()
	var soldier: SoldierState = gs.get_soldier(Team.USA, 1)
	var prior_weapon := str(soldier.weapon_id)
	var prior_ammo := int(soldier.ammo_current)
	var before := gs.weapon_cache.pool_count(1, WeaponCacheClass.ITEM_AMMUNITION_BOX)
	var cmd := AssignWeaponCommandClass.new()
	cmd.from_player_id = 1
	cmd.item_id = WeaponCacheClass.ITEM_AMMUNITION_BOX
	cmd.target_kind = WeaponCacheClass.TargetKind.SOLDIER
	cmd.target_id = 1
	cmd.target_team_id = Team.USA
	var result := _submit(gs, cmd)
	_assert("ammo box assign succeeds", result.success)
	_assert("weapon unchanged", soldier.weapon_id == prior_weapon)
	_assert("ammo unchanged", soldier.ammo_current == prior_ammo)
	_assert("equipment has ammo box", soldier.equipment_count(WeaponCacheClass.ITEM_AMMUNITION_BOX) == 1)
	_assert(
		"ammo box left pool",
		gs.weapon_cache.pool_count(1, WeaponCacheClass.ITEM_AMMUNITION_BOX) == before - 1,
	)


func _test_solo_hides_subordinates() -> void:
	var gs := _make_game_state()
	## No links by default — local player has zero subordinates (solo UI path).
	_assert("solo has no subordinates", gs.get_subordinates(1).is_empty())
	_assert("local player still has own soldiers", gs.command_hierarchy.get_soldier_ids(1).size() == 2)


func _test_assign_to_subordinate_player_and_ai_distribute() -> void:
	var gs := _make_game_state()
	_strip_squad_specials(gs, Team.USA)
	## Link YOU → FTD so commander can push into FTD's cache.
	var link := AssignCommanderCommandClass.new()
	link.commander_id = 1
	link.subordinate_id = 2
	_assert("link YOU→FTD", _submit(gs, link).success)
	_assert("subordinates present", gs.get_subordinates(1).size() == 1)

	## Clear FTD cache specials then give one Thompson so AI can distribute to rifle-holders.
	for entry in gs.weapon_cache.get_cache(2):
		var item_id := str(entry.get("item_id", ""))
		var count := int(entry.get("count", 0))
		for _i in count:
			gs.weapon_cache.take_from_pool(2, item_id)
	var before_you := gs.weapon_cache.pool_count(1, WeaponPolicyClass.ID_THOMPSON)
	var cmd := AssignWeaponCommandClass.new()
	cmd.from_player_id = 1
	cmd.item_id = WeaponPolicyClass.ID_THOMPSON
	cmd.target_kind = WeaponCacheClass.TargetKind.PLAYER
	cmd.target_id = 2
	var result := _submit(gs, cmd)
	_assert("assign to subordinate player succeeds", result.success)
	_assert(
		"took from commander cache",
		gs.weapon_cache.pool_count(1, WeaponPolicyClass.ID_THOMPSON) == before_you - 1,
	)
	## AI auto-distribute should put Thompson on a default-rifle soldier (3 or 4).
	var s3: SoldierState = gs.get_soldier(Team.USA, 3)
	var s4: SoldierState = gs.get_soldier(Team.USA, 4)
	var got_thompson := (
		s3.weapon_id == WeaponPolicyClass.ID_THOMPSON
		or s4.weapon_id == WeaponPolicyClass.ID_THOMPSON
	)
	_assert("AI auto-distributed thompson to rifle-holder", got_thompson)
	_assert(
		"FTD cache emptied by distribute",
		gs.weapon_cache.pool_count(2, WeaponPolicyClass.ID_THOMPSON) == 0,
	)

	## Return path: put a BAR on soldier 1 then return it.
	var bar_cmd := AssignWeaponCommandClass.new()
	bar_cmd.from_player_id = 1
	bar_cmd.item_id = WeaponPolicyClass.ID_BAR
	bar_cmd.target_kind = WeaponCacheClass.TargetKind.SOLDIER
	bar_cmd.target_id = 1
	bar_cmd.target_team_id = Team.USA
	_assert("assign BAR for return test", _submit(gs, bar_cmd).success)
	var ret := ReturnWeaponCommandClass.new()
	ret.to_player_id = 1
	ret.team_id = Team.USA
	ret.soldier_id = 1
	ret.item_id = WeaponPolicyClass.ID_BAR
	var ret_result := _submit(gs, ret)
	_assert("return weapon succeeds", ret_result.success)
	_assert(
		"soldier back on default rifle",
		gs.get_soldier(Team.USA, 1).weapon_id == WeaponPolicyClass.ID_M1_GARAND,
	)
