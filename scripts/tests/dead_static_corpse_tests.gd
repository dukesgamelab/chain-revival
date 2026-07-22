extends Node
## Headless tests for faction dead_static corpse families.
##
## Run:
##   Godot_v4.x_console.exe --headless --path <project> res://scripts/tests/dead_static_corpse_tests.tscn

const DIR_LETTERS: PackedStringArray = ["w", "sw", "s", "se", "e", "ne", "n", "nw"]
const DIR_DIGITS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const USA_POOL: PackedStringArray = ["ADDSS", "ADOAS", "ADFUS", "ADLYS"]
const GER_POOL: PackedStringArray = ["GDLYS", "GDFUS"]
const USA_DIR := "res://assets/sprites/us_soldier/dead_fallen"
const GER_DIR := "res://assets/sprites/german_soldier/dead_fallen"

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	GameRandom.reseed(GameRandom.DEFAULT_SEED)
	UsSoldierSpriteFrames.reload_cached_frames()
	_test_asset_files_exist()
	_test_sprite_frames_loaded()
	_test_usa_pool_selection()
	_test_germany_pool_selection()
	_test_family_stable_once()
	_test_deterministic_same_seed()
	_test_different_seeds_can_differ()
	_test_filename_resolution_eight_dirs()
	_test_camera_remap_preserves_family()
	_test_save_load_preserves_family()
	_test_legacy_save_fallback()
	_test_dead_cannot_return_to_living_anim_priority()

	print("")
	print("Dead static corpse tests: %d passed, %d failed" % [_passed, _failed])
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


func _test_asset_files_exist() -> void:
	var missing: Array[String] = []
	for fam in USA_POOL:
		for i in DIR_DIGITS.size():
			var path := "%s/%s%dA.png" % [USA_DIR, fam, DIR_DIGITS[i]]
			if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
				missing.append(path)
	for fam in GER_POOL:
		for i in DIR_DIGITS.size():
			var path := "%s/%s%dA.png" % [GER_DIR, fam, DIR_DIGITS[i]]
			if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
				missing.append(path)
	_assert("all 48 corpse assets exist", missing.is_empty(), "missing=%s" % str(missing))


func _test_sprite_frames_loaded() -> void:
	var usa := UsSoldierSpriteFrames.get_usa_sprite_frames()
	var ger := UsSoldierSpriteFrames.get_germany_sprite_frames()
	var missing: Array[String] = []
	for fam in USA_POOL:
		for d in DIR_LETTERS:
			var anim := "dead_%s_%s" % [fam, d]
			if not usa.has_animation(anim) or usa.get_frame_count(anim) < 1:
				missing.append("USA %s" % anim)
	for fam in GER_POOL:
		for d in DIR_LETTERS:
			var anim := "dead_%s_%s" % [fam, d]
			if not ger.has_animation(anim) or ger.get_frame_count(anim) < 1:
				missing.append("GER %s" % anim)
	_assert("sprite frames contain all dead_<family>_<dir>", missing.is_empty(), str(missing))


func _test_usa_pool_selection() -> void:
	GameRandom.reseed(42)
	var seen := {}
	for i in 40:
		var s := SoldierState.new(i + 1, Vector2i(i, 0), Team.USA)
		s.mark_killed()
		_assert(
			"USA death family in pool #%d" % i,
			s.death_sprite_family in USA_POOL,
			"got %s" % s.death_sprite_family,
		)
		seen[s.death_sprite_family] = true
	_assert("USA pool produces multiple variants over rolls", seen.size() >= 2, str(seen.keys()))


func _test_germany_pool_selection() -> void:
	GameRandom.reseed(42)
	var seen := {}
	for i in 40:
		var s := SoldierState.new(i + 1, Vector2i(i, 0), Team.GERMANY)
		s.mark_killed()
		_assert(
			"GER death family in pool #%d" % i,
			s.death_sprite_family in GER_POOL,
			"got %s" % s.death_sprite_family,
		)
		seen[s.death_sprite_family] = true
	_assert("GER pool produces multiple variants over rolls", seen.size() >= 2, str(seen.keys()))


func _test_family_stable_once() -> void:
	GameRandom.reseed(7)
	var s := SoldierState.new(3, Vector2i.ZERO, Team.USA)
	s.mark_killed()
	var first := s.death_sprite_family
	s._select_death_sprite_family_once()
	s._select_death_sprite_family_once()
	_assert("corpse family not re-rolled", s.death_sprite_family == first, "%s vs %s" % [first, s.death_sprite_family])


func _test_deterministic_same_seed() -> void:
	var seq_a: Array[String] = []
	var seq_b: Array[String] = []
	GameRandom.reseed(11)
	for i in 8:
		var s1 := SoldierState.new(i + 1, Vector2i(i, 0), Team.USA if i % 2 == 0 else Team.GERMANY)
		s1.mark_killed()
		seq_a.append(s1.death_sprite_family)
	GameRandom.reseed(11)
	for i in 8:
		var s2 := SoldierState.new(i + 1, Vector2i(i, 0), Team.USA if i % 2 == 0 else Team.GERMANY)
		s2.mark_killed()
		seq_b.append(s2.death_sprite_family)
	_assert("same seed + sequence → same corpse families", seq_a == seq_b, "%s vs %s" % [str(seq_a), str(seq_b)])


func _test_different_seeds_can_differ() -> void:
	GameRandom.reseed(100)
	var a: Array[String] = []
	for i in 12:
		var s := SoldierState.new(i + 1, Vector2i.ZERO, Team.USA)
		s.mark_killed()
		a.append(s.death_sprite_family)
	GameRandom.reseed(99991)
	var b: Array[String] = []
	for i in 12:
		var s2 := SoldierState.new(i + 1, Vector2i.ZERO, Team.USA)
		s2.mark_killed()
		b.append(s2.death_sprite_family)
	_assert("different seeds can yield different corpse sequences", a != b, "%s vs %s" % [str(a), str(b)])


func _test_filename_resolution_eight_dirs() -> void:
	for i in DIR_LETTERS.size():
		var letter: String = DIR_LETTERS[i]
		var digit: int = DIR_DIGITS[i]
		_assert(
			"source digit for %s" % letter,
			AnimationDatabase.source_direction_digit(letter) == digit,
		)
		for fam in USA_POOL:
			var path := "%s/%s%dA.png" % [USA_DIR, fam, digit]
			_assert("USA %s %s file" % [fam, letter], FileAccess.file_exists(path) or ResourceLoader.exists(path), path)
		for fam in GER_POOL:
			var path2 := "%s/%s%dA.png" % [GER_DIR, fam, digit]
			_assert("GER %s %s file" % [fam, letter], FileAccess.file_exists(path2) or ResourceLoader.exists(path2), path2)


func _test_camera_remap_preserves_family() -> void:
	var family := "ADFUS"
	var world := "ne"
	var cam0 := AnimationDatabase.display_direction(world, 0)
	var cam90 := AnimationDatabase.display_direction(world, 90)
	var cam180 := AnimationDatabase.display_direction(world, 180)
	var cam270 := AnimationDatabase.display_direction(world, 270)
	_assert("cam0 maps NE non-empty", not cam0.is_empty())
	var anim0 := "dead_%s_%s" % [family, cam0]
	var anim90 := "dead_%s_%s" % [family, cam90]
	var anim180 := "dead_%s_%s" % [family, cam180]
	var anim270 := "dead_%s_%s" % [family, cam270]
	_assert("family prefix stable across cams", anim0.begins_with("dead_ADFUS_"))
	_assert("family prefix stable 90", anim90.begins_with("dead_ADFUS_"))
	_assert("family prefix stable 180", anim180.begins_with("dead_ADFUS_"))
	_assert("family prefix stable 270", anim270.begins_with("dead_ADFUS_"))
	var changed := cam0 != cam90 or cam0 != cam180 or cam0 != cam270
	_assert(
		"some camera rotation remaps NE display dir",
		changed,
		"all=%s,%s,%s,%s" % [cam0, cam90, cam180, cam270],
	)


func _test_save_load_preserves_family() -> void:
	GameRandom.reseed(55)
	var s := SoldierState.new(9, Vector2i(2, 3), Team.GERMANY)
	s.facing_direction = FacingDirection.NORTHEAST
	s.mark_killed()
	var family := s.death_sprite_family
	var restored := SoldierState.from_dict(s.to_dict())
	_assert("save/load preserves death_sprite_family", restored.death_sprite_family == family, restored.death_sprite_family)
	_assert("save/load preserves is_dead", restored.is_dead)
	_assert("save/load preserves facing", restored.facing_direction == FacingDirection.NORTHEAST)


func _test_legacy_save_fallback() -> void:
	GameRandom.reseed(1)
	var data := {
		"soldier_id": 4,
		"team_id": Team.USA,
		"grid_x": 1,
		"grid_y": 1,
		"facing_x": 0,
		"facing_y": -1,
		"is_dead": true,
	}
	var restored := SoldierState.from_dict(data)
	_assert("legacy dead save gets family", restored.death_sprite_family in USA_POOL, restored.death_sprite_family)
	var again := restored.death_sprite_family
	restored.ensure_death_sprite_family()
	_assert("legacy fallback stable", restored.death_sprite_family == again)


func _pools_equal(a: PackedStringArray, b: PackedStringArray) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if str(a[i]) != str(b[i]):
			return false
	return true


func _test_dead_cannot_return_to_living_anim_priority() -> void:
	const PositionStateClass := preload("res://scripts/enums/position_state.gd")
	var s := SoldierState.new(1, Vector2i.ZERO, Team.USA)
	s.mark_killed()
	_assert("dead stays dead", s.is_dead)
	_assert("dead forced DOWN", s.position_state == PositionStateClass.DOWN)
	var usa_pool := AnimationDatabase.dead_static_variants_for_team(Team.USA)
	var ger_pool := AnimationDatabase.dead_static_variants_for_team(Team.GERMANY)
	_assert("DB USA pool matches approved", _pools_equal(usa_pool, USA_POOL), str(usa_pool))
	_assert("DB GER pool matches approved", _pools_equal(ger_pool, GER_POOL), str(ger_pool))
