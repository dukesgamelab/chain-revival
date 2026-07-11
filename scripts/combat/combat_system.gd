class_name CombatSystem
extends RefCounted
## Resolves shooting against GameState data (no scene nodes).
## Called by ActionResolver — not by UI directly.

const GameStateClass := preload("res://scripts/core/game_state.gd")
const SoldierStateClass := preload("res://scripts/soldiers/soldier_state.gd")
const WeaponDataClass := preload("res://scripts/combat/weapon_data.gd")
const WeaponRegistryClass := preload("res://scripts/combat/weapon_registry.gd")
const WeaponTypeClass := preload("res://scripts/enums/weapon_type.gd")
const PositionStateClass := preload("res://scripts/enums/position_state.gd")
const MovementModeClass := preload("res://scripts/enums/movement_mode.gd")
const FireControlStateClass := preload("res://scripts/enums/fire_control_state.gd")
const LOSSystemClass := preload("res://scripts/combat/los_system.gd")
const CoverSystemClass := preload("res://scripts/combat/cover_system.gd")
const MapObjectRegistryClass := preload("res://scripts/map/map_object_registry.gd")
const ConeOfFireClass := preload("res://scripts/combat/cone_of_fire.gd")
const EnemyVisibilityResultClass := preload("res://scripts/combat/enemy_visibility_result.gd")
const FireAtPreviewResultClass := preload("res://scripts/combat/fire_at_preview_result.gd")
const StressLabelsClass := preload("res://scripts/combat/stress_labels.gd")
const CombatGrenadeResultClass := preload("res://scripts/combat/combat_grenade_result.gd")

const CLEAR_BASE_HIT_CHANCE := 0.78
const CLEAR_DISTANCE_PENALTY := 0.025
const MIN_HIT_CHANCE := 0.10
const AUTO_FIRE_SCAN_INTERVAL := 0.5
## Fallback first-shot aim time when weapon data is missing.
const FIRE_PREP_DELAY_SEC := 1.0
## Repeat fire cadence: last_shot_msec + weapon.fire_interval_sec (per weapon in WeaponRegistry).
const STRESS_RECOVERY_PER_TICK := 0.15
const STRESS_RECOVERY_PRONE_PER_TICK := 0.25
const SHOOTER_PRONE_ACCURACY_MULT := 1.15
const TARGET_PRONE_HIT_MULT := 0.55
const MODERATE_COVER_SUPPRESSION_MULT := 0.65
const PRONE_SUPPRESSION_MULT := 0.75
const STRESS_PINNED_THRESHOLD := 45.0
const STRESS_PANIC_THRESHOLD := 70.0
const AUTO_TARGET_ENGAGED_BONUS := 10.0
const GRENADE_THROW_RANGE := 7
const GRENADE_FUSE_MSEC := 1800
const GRENADE_BLAST_RADIUS := 3
const GRENADE_KILL_RADIUS := 1
const GRENADE_KILL_CHANCE := 0.25
const GRENADE_STUN_DURATION_SEC := 8.0
const RECENTLY_SEEN_SEC := 2.0
const RECENTLY_FIRED_SPOT_SEC := 2.0
const LAST_KNOWN_NEAR_TILES := 2
## Spotting reaches beyond max weapon range (eyes/binoculars vs effective fire distance).
const SPOTTING_RANGE_BONUS := 10

## stress = suppression/combat pressure; affects accuracy, movement, and fire cadence.
## spotting controls target eligibility; shot LOS controls whether bullets can fire.
## cover reduces both hit chance and spotting; recently fired enemies are easier to detect.
## Manual Fire At remains priority-target behavior; Fire At Will uses tactical target scoring.

static var _last_preview_debug_key: String = ""

static var _team_visibility_cache_key: String = ""
static var _visibility_cache_by_team: Dictionary = {}
static var _visibility_log_keys: Dictionary = {}
## Presentation layer: world-derived grid cells for soldiers mid-move (key "team_id:soldier_id").
static var _spotting_cell_overrides: Dictionary = {}


static func set_spotting_cell_overrides(overrides: Dictionary) -> void:
	_spotting_cell_overrides = overrides


static func clear_spotting_cell_overrides() -> void:
	_spotting_cell_overrides.clear()


static func spotting_cell_for(soldier: SoldierStateClass) -> Vector2i:
	if soldier == null:
		return Vector2i.ZERO
	var key := "%d:%d" % [soldier.team_id, soldier.soldier_id]
	var override_cell: Variant = _spotting_cell_overrides.get(key)
	if override_cell is Vector2i:
		return override_cell
	return soldier.grid_position


## Authoritative Fire At aim preview — same target and LOS rules as manual combat.
static func evaluate_fire_at_preview(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	from_world: Vector2,
	aim_world: Vector2,
	click_cell: Vector2i = Vector2i(-999, -999),
	explicit_team_id: int = -1,
	explicit_soldier_id: int = -1,
) -> FireAtPreviewResult:
	var result := FireAtPreviewResult.new()
	if game_state == null or shooter == null or shooter.is_dead:
		_log_fire_at_preview(shooter, result)
		return result

	var weapon := shooter.get_weapon_data()
	var max_range := _effective_weapon_range(weapon)
	if click_cell.x <= -900:
		click_cell = IsometricGrid.world_to_grid(aim_world)
	result.click_cell = click_cell

	result.enemy_in_cone = _has_living_enemy_in_aim_cone(
		game_state,
		shooter,
		from_world,
		aim_world,
		max_range,
	)

	var target := find_manual_priority_target(
		game_state,
		shooter,
		from_world,
		aim_world,
		max_range,
		explicit_team_id,
		explicit_soldier_id,
		click_cell,
	)
	result.target = target

	if target != null:
		result.aim_to_world = IsometricGrid.soldier_aim_point(target.grid_position)
		result.los = LOSSystemClass.evaluate(
			shooter.grid_position,
			target.grid_position,
			game_state.map_data,
			game_state,
		)
		var in_range := (
			_manhattan_distance(shooter.grid_position, target.grid_position) <= max_range
		)
		var target_in_aim_cone := ConeOfFireClass.is_world_point_in_aim_cone(
			from_world,
			aim_world,
			result.aim_to_world,
			shooter.grid_position,
			max_range,
		)
		result.targetable = (
			in_range
			and target_in_aim_cone
			and result.los.status != LOSSystemClass.Status.BLOCKED
		)
	else:
		result.aim_to_world = aim_world
		result.targetable = false

	_log_fire_at_preview(shooter, result)
	return result


## Aim preview for a soldier already engaged on a priority target (squad Fire At).
static func evaluate_engaged_target_preview(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> FireAtPreviewResult:
	var result := FireAtPreviewResult.new()
	if game_state == null or shooter == null or shooter.is_dead or not shooter.is_sustained_fire():
		_log_fire_at_preview(shooter, result)
		return result

	var target := _get_engaged_target(game_state, shooter)
	if target == null:
		_log_fire_at_preview(shooter, result)
		return result

	var weapon := shooter.get_weapon_data()
	var max_range := _effective_weapon_range(weapon)
	result.click_cell = target.grid_position
	result.target = target
	result.enemy_in_cone = true
	result.aim_to_world = IsometricGrid.soldier_aim_point(target.grid_position)
	result.los = LOSSystemClass.evaluate(
		shooter.grid_position,
		target.grid_position,
		game_state.map_data,
		game_state,
	)
	var in_range := _manhattan_distance(shooter.grid_position, target.grid_position) <= max_range
	result.targetable = (
		in_range
		and result.los.status != LOSSystemClass.Status.BLOCKED
	)

	_log_fire_at_preview(shooter, result)
	return result


static func resolve_shot(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	target: SoldierStateClass,
	auto_engagement: bool = false,
) -> CombatShotResult:
	var result := CombatShotResult.new()
	result.shooter_team_id = shooter.team_id
	result.shooter_id = shooter.soldier_id
	result.target_team_id = target.team_id
	result.target_id = target.soldier_id

	if shooter.is_dead:
		return result
	if shooter.is_moving:
		if not auto_engagement:
			result.messages.append("Cannot fire while moving")
		return result
	if not _is_fire_prep_complete(shooter):
		result.on_cooldown = true
		return result
	if target.is_dead:
		if not auto_engagement:
			result.messages.append("Target already dead")
		return result
	if shooter.team_id == target.team_id:
		if not auto_engagement:
			result.messages.append("Cannot shoot friendlies")
		return result

	var weapon := shooter.get_weapon_data()
	if weapon == null:
		if not auto_engagement:
			result.messages.append("No weapon assigned")
		return result
	result.weapon_name = weapon.weapon_name

	if shooter.ammo_current <= 0:
		result.no_ammo = true
		if not auto_engagement:
			result.messages.append("%s %s out of ammo" % [Team.display_name(shooter.team_id), weapon.weapon_name])
		return result

	var distance := _manhattan_distance(shooter.grid_position, target.grid_position)
	var max_range := _effective_weapon_range(weapon)
	if distance > max_range:
		result.out_of_range = true
		if not auto_engagement:
			result.messages.append(
				"%s %s out of range" % [Team.display_name(shooter.team_id), weapon.weapon_name],
			)
		return result

	var fireteam := game_state.session.get_fireteam(shooter.team_id)
	# Authoritative facing during combat (ActionResolver → process_combat_tick only).
	fireteam.face_toward_tile(shooter.soldier_id, target.grid_position)

	var los := LOSSystemClass.evaluate(
		shooter.grid_position,
		target.grid_position,
		game_state.map_data,
		game_state,
	)
	if los.status == LOSSystemClass.Status.BLOCKED:
		result.blocked = true
		if LOSSystemClass.is_debug_logging_enabled():
			if _is_wall_blocker_type(los.blocking_type):
				GameLog.log_system("[Combat] Shot blocked by wall")
			else:
				GameLog.log_system(
					"[Combat] Shot blocked by %s at %s"
					% [los.blocking_type, los.blocking_cell]
				)
		if not auto_engagement:
			var blocker_name := los.blocking_type
			var blocker_def := MapObjectRegistryClass.get_def(blocker_name)
			if blocker_def != null:
				blocker_name = blocker_def.display_name
			result.messages.append("Shot blocked by %s" % blocker_name)
		return result

	if not _can_fire_yet(shooter, weapon):
		result.on_cooldown = true
		if not auto_engagement:
			result.messages.append(
				"%s %s — wait %.1fs between shots"
				% [Team.display_name(shooter.team_id), weapon.weapon_name, weapon.fire_interval_sec],
			)
		return result

	if not auto_engagement:
		result.messages.append(
			"%s Soldier %d firing %s"
			% [Team.display_name(shooter.team_id), shooter.soldier_id, weapon.weapon_name],
		)
		if los.cover_type == CoverSystemClass.CoverType.MODERATE:
			result.had_cover = true
			result.cover_type = los.cover_type
			var cover_name := los.cover_source_type
			var cover_def := MapObjectRegistryClass.get_def(cover_name)
			if cover_def != null:
				cover_name = cover_def.display_name
			result.messages.append("Target in moderate cover (%s)" % cover_name)
		elif los.cover_type == CoverSystemClass.CoverType.COMPLETE:
			result.had_cover = true
			result.cover_type = los.cover_type
			var cover_name := los.cover_source_type
			var cover_def := MapObjectRegistryClass.get_def(cover_name)
			if cover_def != null:
				cover_name = cover_def.display_name
			result.messages.append("Target in complete cover (%s)" % cover_name)

	var ammo_cost := weapon.ammo_cost(shooter.ammo_current)
	# Authoritative ammo/death mutations (invoked only via ActionResolver → process_combat_tick).
	shooter.ammo_current -= ammo_cost
	var now_msec := Time.get_ticks_msec()
	shooter.last_shot_msec = now_msec
	shooter.last_fired_msec = now_msec
	result.fired = true
	result.tracer_count = weapon.tracer_count

	if weapon.is_burst():
		result.messages.append(
			"%s %s fired burst" % [Team.display_name(shooter.team_id), weapon.weapon_name],
		)
	else:
		result.messages.append(
			"%s %s fired" % [Team.display_name(shooter.team_id), weapon.weapon_name],
		)
	if not auto_engagement:
		result.messages.append("Ammo remaining: %d" % shooter.ammo_current)

	AudioManager.play_weapon_fire(weapon.weapon_id)
	apply_suppression_from_shot(game_state, shooter, target, weapon, los)

	if los.target_using_wall_cover:
		if LOSSystemClass.is_debug_logging_enabled():
			GameLog.log_system("[Combat] Target protected by complete cover")
		if not auto_engagement:
			result.messages.append("Target protected by wall")
		return result

	var chance := _final_hit_chance(shooter, target, weapon, los)
	if not auto_engagement and los.cover_type == CoverSystemClass.CoverType.MODERATE:
		var base_chance := hit_chance(
			shooter.grid_position,
			target.grid_position,
			weapon,
		)
		result.messages.append(
			"Hit chance reduced from %d%% to %d%%"
			% [int(round(base_chance * 100.0)), int(round(chance * 100.0))],
		)

	# V1: one hit roll per burst; future version can roll once per bullet in rounds_per_attack.
	if randf() <= chance:
		result.hit = true
		result.messages.append("%s hit" % weapon.weapon_name)
		target.mark_killed()
		result.killed = true
		result.messages.append(
			"%s Soldier %d killed" % [Team.display_name(target.team_id), target.soldier_id],
		)
		AudioManager.play_death(target.team_id)
	elif los.cover_type == CoverSystemClass.CoverType.MODERATE:
		result.messages.append("Shot missed due to cover")
	else:
		result.messages.append("%s missed" % weapon.weapon_name)

	return result


## --- Spotting / visibility (map cover + range + forward arc) vs shot LOS (strict) ---
## Living/dead soldiers never block spotting. Broad forward arc, not the narrow fire cone.


static func can_spot_enemy(
	observer: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
) -> bool:
	return _passes_spotting_checks(observer, target, game_state)


static func _passes_spotting_checks(
	observer: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
) -> bool:
	if observer == null or target == null or target.is_dead or observer.is_dead:
		return false
	if observer.team_id == target.team_id:
		return false

	var observer_cell := spotting_cell_for(observer)
	var target_cell := spotting_cell_for(target)

	var los := LOSSystemClass.evaluate_spotting(
		observer_cell,
		target_cell,
		game_state.map_data,
		game_state,
	)
	if los.status == LOSSystemClass.Status.BLOCKED:
		return false

	var weapon := observer.get_weapon_data()
	var spotting_range := _effective_spotting_range(weapon)
	if _manhattan_distance(observer_cell, target_cell) > spotting_range:
		return false

	return ConeOfFireClass.is_facing_toward_target(
		observer_cell,
		observer.facing_direction,
		target_cell,
		spotting_range,
	)


static func get_visibility_score(
	observer: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
) -> float:
	if not _passes_spotting_checks(observer, target, game_state):
		return -1.0

	var observer_cell := spotting_cell_for(observer)
	var target_cell := spotting_cell_for(target)
	var weapon := observer.get_weapon_data()
	var max_range := _effective_weapon_range(weapon) if weapon != null else ConeOfFireClass.RANGE_BONUS
	var dist := _manhattan_distance(observer_cell, target_cell)
	var score := 100.0 - float(dist) * 4.0

	if target.is_moving:
		if target.movement_mode == MovementModeClass.RUN:
			score += 15.0
		elif target.movement_mode == MovementModeClass.WALK:
			score += 10.0

	if _target_recently_fired(target):
		score += 25.0

	var los := LOSSystemClass.evaluate_spotting(
		observer_cell,
		target_cell,
		game_state.map_data,
		game_state,
	)
	if los.cover_type == CoverSystemClass.CoverType.MODERATE:
		score -= 20.0

	score *= get_cover_visibility_modifier(observer, target, game_state, los)
	return score


static func get_cover_visibility_modifier(
	_observer: SoldierStateClass,
	_target: SoldierStateClass,
	_game_state: GameStateClass,
	los: LOSSystemClass.LossResult = null,
) -> float:
	if los != null and los.cover_type == CoverSystemClass.CoverType.MODERATE:
		return MODERATE_COVER_SUPPRESSION_MULT
	return 1.0


static func get_target_visibility_modifier(target: SoldierStateClass) -> float:
	if target == null:
		return 1.0
	if target.position_state == PositionStateClass.DOWN:
		return 0.75
	return 1.0


static func is_enemy_recently_seen(
	observer: SoldierStateClass,
	enemy_team_id: int,
	enemy_soldier_id: int,
) -> bool:
	if observer == null:
		return false
	var seen_msec := observer.get_last_seen_enemy_msec(enemy_team_id, enemy_soldier_id)
	if seen_msec <= 0:
		return false
	var elapsed_sec := (Time.get_ticks_msec() - seen_msec) / 1000.0
	return elapsed_sec <= RECENTLY_SEEN_SEC


static func is_priority_target_trackable(
	observer: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
) -> bool:
	if not _is_valid_priority_enemy(observer, target):
		return false
	if can_spot_enemy(observer, target, game_state):
		return true
	return is_enemy_recently_seen(observer, target.team_id, target.soldier_id)


static func can_assign_manual_priority_target(
	observer: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
	click_cell: Vector2i,
) -> bool:
	if not _is_valid_priority_enemy(observer, target):
		return false
	if can_spot_enemy(observer, target, game_state):
		return true
	if not is_enemy_recently_seen(observer, target.team_id, target.soldier_id):
		return false
	var key := SoldierStateClass.enemy_tracking_key(target.team_id, target.soldier_id)
	var last_pos: Vector2i = observer.last_seen_enemy_positions.get(
		key,
		target.grid_position,
	)
	return (
		_manhattan_distance(last_pos, click_cell) <= LAST_KNOWN_NEAR_TILES
		or _manhattan_distance(target.grid_position, click_cell) <= LAST_KNOWN_NEAR_TILES
	)


static func update_spotting(game_state: GameStateClass) -> void:
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var observer: SoldierStateClass = state
			if observer.is_dead:
				continue
			var enemy_team_id: int = game_state.enemy_team_id(observer.team_id)
			var enemy_fireteam := game_state.session.get_fireteam(enemy_team_id)
			for enemy_state in enemy_fireteam.soldiers:
				var enemy: SoldierStateClass = enemy_state
				if enemy.is_dead:
					continue
				var visibility := get_enemy_visibility_for_team(
					game_state,
					observer.team_id,
					enemy,
				)
				if not visibility.visible:
					continue
				var spotter := game_state.get_soldier(
					visibility.spotter_team_id,
					visibility.spotter_soldier_id,
				)
				if spotter != null:
					spotter.record_last_seen_enemy(enemy)


static func is_enemy_visible_to_team(
	game_state: GameStateClass,
	observer_team_id: int,
	enemy: SoldierStateClass,
) -> bool:
	return get_enemy_visibility_for_team(game_state, observer_team_id, enemy).visible


static func get_enemy_visibility_for_team(
	game_state: GameStateClass,
	observer_team_id: int,
	enemy: SoldierStateClass,
) -> EnemyVisibilityResult:
	var empty := EnemyVisibilityResult.new()
	if enemy == null or enemy.is_dead:
		return empty
	if enemy.team_id == observer_team_id:
		empty.visible = true
		empty.source = EnemyVisibilityResultClass.Source.DIRECT
		return empty

	var team_cache := _get_team_visibility_cache(game_state, observer_team_id)
	var enemy_key := SoldierStateClass.enemy_tracking_key(enemy.team_id, enemy.soldier_id)
	if team_cache.has(enemy_key):
		return team_cache[enemy_key]
	return empty


static func _get_team_visibility_cache(
	game_state: GameStateClass,
	observer_team_id: int,
) -> Dictionary:
	var signature := _build_visibility_cache_signature(game_state)
	if signature != _team_visibility_cache_key or not _visibility_cache_by_team.has(observer_team_id):
		_team_visibility_cache_key = signature
		_visibility_cache_by_team.clear()
		_visibility_log_keys.clear()
		_visibility_cache_by_team[observer_team_id] = _build_team_visibility_map(
			game_state,
			observer_team_id,
		)
	return _visibility_cache_by_team[observer_team_id]


static func _build_team_visibility_map(
	game_state: GameStateClass,
	observer_team_id: int,
) -> Dictionary:
	var results: Dictionary = {}
	var enemy_team_id: int = game_state.enemy_team_id(observer_team_id)
	var observer_fireteam := game_state.session.get_fireteam(observer_team_id)
	var enemy_fireteam := game_state.session.get_fireteam(enemy_team_id)

	for enemy_state in enemy_fireteam.soldiers:
		var enemy: SoldierStateClass = enemy_state
		if enemy.is_dead:
			continue
		var enemy_key := SoldierStateClass.enemy_tracking_key(enemy.team_id, enemy.soldier_id)
		var result := EnemyVisibilityResult.new()
		var best_score := -1.0
		var best_observer: SoldierStateClass = null

		for observer_state in observer_fireteam.soldiers:
			var observer: SoldierStateClass = observer_state
			if observer.is_dead:
				continue
			if not can_spot_enemy(observer, enemy, game_state):
				continue
			var score := get_visibility_score(observer, enemy, game_state)
			if score > best_score:
				best_score = score
				best_observer = observer

		if best_observer != null:
			result.visible = true
			result.source = EnemyVisibilityResultClass.Source.DIRECT
			result.visibility_score = best_score
			result.spotter_team_id = best_observer.team_id
			result.spotter_soldier_id = best_observer.soldier_id
		else:
			result.visibility_score = _best_team_visibility_score(
				game_state,
				observer_team_id,
				enemy,
			)

		results[enemy_key] = result
		_log_enemy_visibility(observer_team_id, enemy, result)

	return results


static func _best_team_visibility_score(
	game_state: GameStateClass,
	observer_team_id: int,
	enemy: SoldierStateClass,
) -> float:
	var best_score := -1.0
	var fireteam := game_state.session.get_fireteam(observer_team_id)
	for state in fireteam.soldiers:
		var observer: SoldierStateClass = state
		if observer.is_dead:
			continue
		var score := get_visibility_score(observer, enemy, game_state)
		best_score = maxf(best_score, score)
	return best_score


static func _build_visibility_cache_signature(game_state: GameStateClass) -> String:
	var parts: PackedStringArray = []
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier: SoldierStateClass = state
			parts.append(
				"%d:%d@%s:%s:%d"
				% [
					soldier.team_id,
					soldier.soldier_id,
					spotting_cell_for(soldier),
					soldier.facing_direction,
					int(soldier.is_dead),
				]
			)
	for key in _spotting_cell_overrides.keys():
		parts.append("snap:%s=%s" % [key, _spotting_cell_overrides[key]])
	return "|".join(parts)


static func _visibility_source_name(source: int) -> String:
	match source:
		EnemyVisibilityResultClass.Source.DIRECT:
			return "direct"
		EnemyVisibilityResultClass.Source.CLUSTER:
			return "cluster"
		_:
			return "hidden"


static func _log_enemy_visibility(
	observer_team_id: int,
	enemy: SoldierStateClass,
	result: EnemyVisibilityResult,
) -> void:
	if not LOSSystemClass.is_debug_logging_enabled():
		return

	var log_key := "%d>%s>%s>%s" % [
		observer_team_id,
		SoldierStateClass.enemy_tracking_key(enemy.team_id, enemy.soldier_id),
		result.visible,
		_visibility_source_name(result.source),
	]
	if _visibility_log_keys.get(log_key, false):
		return
	_visibility_log_keys[log_key] = true

	var score_text := "-" if result.visibility_score < 0.0 else str(int(round(result.visibility_score)))
	var source_text := _visibility_source_name(result.source)
	var detail := ""
	if result.visible and result.source == EnemyVisibilityResultClass.Source.DIRECT:
		detail = " via %s S%d" % [
			Team.display_name(result.spotter_team_id),
			result.spotter_soldier_id,
		]

	GameLog.log_system(
		"[Visibility] %s -> %s S%d @ %s: %s score=%s%s"
		% [
			Team.display_name(observer_team_id),
			Team.display_name(enemy.team_id),
			enemy.soldier_id,
			enemy.grid_position,
			source_text if result.visible else "hidden",
			score_text,
			detail,
		]
	)


static func _target_recently_fired(target: SoldierStateClass) -> bool:
	if target.last_fired_msec <= 0:
		return false
	return (Time.get_ticks_msec() - target.last_fired_msec) / 1000.0 <= RECENTLY_FIRED_SPOT_SEC


static func find_closest_visible_enemy(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	return find_best_auto_target(game_state, shooter)


## Fire At Will: highest-scored shootable enemy in the facing cone (clear LOS required).
static func find_best_auto_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	if shooter == null or shooter.is_dead:
		return null

	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return null

	var max_range := _effective_weapon_range(weapon)
	var enemy_team_id: int = game_state.enemy_team_id(shooter.team_id)
	var enemy_fireteam := game_state.session.get_fireteam(enemy_team_id)
	var best: SoldierStateClass = null
	var best_score := -INF

	for state in enemy_fireteam.soldiers:
		var enemy: SoldierStateClass = state
		if enemy.is_dead:
			continue
		if not can_spot_enemy(shooter, enemy, game_state):
			continue
		if not _is_target_in_cone(shooter, enemy.grid_position, max_range):
			continue
		var score := score_auto_target(shooter, enemy, game_state)
		if score < 0.0:
			continue
		if score > best_score:
			best_score = score
			best = enemy

	return best


## Tactical scoring for Fire At Will only; manual Fire At uses priority assignment.
static func score_auto_target(
	shooter: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
) -> float:
	if shooter == null or target == null or target.is_dead:
		return -1.0

	var los := LOSSystemClass.evaluate(
		shooter.grid_position,
		target.grid_position,
		game_state.map_data,
		game_state,
	)
	if los.status == LOSSystemClass.Status.BLOCKED:
		return -1.0
	if los.target_using_wall_cover:
		return -1.0

	var dist := _manhattan_distance(shooter.grid_position, target.grid_position)
	var score := 100.0 - float(dist) * 4.0

	if los.cover_type == CoverSystemClass.CoverType.NONE:
		score += 25.0
	elif los.cover_type == CoverSystemClass.CoverType.MODERATE:
		score -= 10.0
	else:
		score -= 25.0

	if target.is_moving:
		score += 10.0

	if target.position_state == PositionStateClass.DOWN:
		score -= 20.0

	var aim_dir := FacingDirection.toward_cell(shooter.grid_position, target.grid_position)
	if aim_dir == shooter.facing_direction:
		score += 15.0

	var target_weapon := target.get_weapon_data()
	if target_weapon != null:
		match target_weapon.weapon_type:
			WeaponTypeClass.SMG, WeaponTypeClass.LMG:
				score += 20.0

	if (
		shooter.engaged_target_team_id == target.team_id
		and shooter.engaged_target_soldier_id == target.soldier_id
	):
		score += AUTO_TARGET_ENGAGED_BONUS

	return score


static func find_best_cone_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	if shooter == null or shooter.is_dead:
		return null

	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return null

	var max_range := _effective_weapon_range(weapon)
	var enemy_team_id: int = game_state.enemy_team_id(shooter.team_id)
	var enemy_fireteam := game_state.session.get_fireteam(enemy_team_id)
	var best: SoldierStateClass = null
	var best_dist := INF

	for state in enemy_fireteam.soldiers:
		var enemy: SoldierStateClass = state
		if enemy.is_dead:
			continue
		if not _is_target_in_cone(shooter, enemy.grid_position, max_range):
			continue
		var dist := _manhattan_distance(shooter.grid_position, enemy.grid_position)
		if LOSSystemClass.is_shot_blocked(
			shooter.grid_position,
			enemy.grid_position,
			game_state.map_data,
			game_state,
		):
			continue
		if dist < best_dist:
			best_dist = dist
			best = enemy

	return best


## Manual Fire At: priority enemy from aim/click when spotted or recently seen near click.
static func find_manual_priority_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	from_world: Vector2,
	aim_world: Vector2,
	max_range: int,
	explicit_team_id: int = -1,
	explicit_soldier_id: int = -1,
	click_cell: Vector2i = Vector2i(-999, -999),
) -> SoldierStateClass:
	if shooter == null or shooter.is_dead:
		return null

	if click_cell.x <= -900:
		click_cell = IsometricGrid.world_to_grid(aim_world)

	if explicit_team_id >= 0 and explicit_soldier_id > 0:
		var explicit := game_state.get_soldier(explicit_team_id, explicit_soldier_id)
		if can_assign_manual_priority_target(shooter, explicit, game_state, click_cell):
			return explicit
		return null

	return find_best_spotted_aim_cone_target(
		game_state,
		shooter,
		from_world,
		aim_world,
		max_range,
		click_cell,
	)


static func find_best_spotted_aim_cone_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	from_world: Vector2,
	aim_world: Vector2,
	max_range: int,
	click_cell: Vector2i,
) -> SoldierStateClass:
	if shooter == null or shooter.is_dead:
		return null

	var enemy_team_id: int = game_state.enemy_team_id(shooter.team_id)
	var enemy_fireteam := game_state.session.get_fireteam(enemy_team_id)
	var best: SoldierStateClass = null
	var best_dist := INF

	for state in enemy_fireteam.soldiers:
		var enemy: SoldierStateClass = state
		if enemy.is_dead:
			continue
		var enemy_world := IsometricGrid.soldier_aim_point(enemy.grid_position)
		if not ConeOfFireClass.is_world_point_in_aim_cone(
			from_world,
			aim_world,
			enemy_world,
			shooter.grid_position,
			max_range,
		):
			continue
		if not can_assign_manual_priority_target(shooter, enemy, game_state, click_cell):
			continue
		var dist := _manhattan_distance(shooter.grid_position, enemy.grid_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy

	return best


## UI / manual cone checks — spotted or recently seen near aim point.
static func find_best_aim_cone_priority_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	from_world: Vector2,
	aim_world: Vector2,
	max_range: int,
) -> SoldierStateClass:
	return find_best_spotted_aim_cone_target(
		game_state,
		shooter,
		from_world,
		aim_world,
		max_range,
		IsometricGrid.world_to_grid(aim_world),
	)


## Living enemy in the fire cone with unobstructed line of fire.
static func find_faced_enemy(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	return find_best_cone_target(game_state, shooter)


static func aim_cone_has_visible_enemy(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	from_world: Vector2,
	aim_world: Vector2,
	_max_range: int,
) -> bool:
	return evaluate_fire_at_preview(
		game_state,
		shooter,
		from_world,
		aim_world,
	).targetable


static func find_best_aim_cone_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	from_world: Vector2,
	aim_world: Vector2,
	max_range: int,
) -> SoldierStateClass:
	## Legacy alias: auto-acquisition with clear LOS.
	if shooter == null or shooter.is_dead:
		return null

	var enemy_team_id: int = game_state.enemy_team_id(shooter.team_id)
	var enemy_fireteam := game_state.session.get_fireteam(enemy_team_id)
	var best: SoldierStateClass = null
	var best_dist := INF

	for state in enemy_fireteam.soldiers:
		var enemy: SoldierStateClass = state
		if enemy.is_dead:
			continue
		var enemy_world := IsometricGrid.soldier_aim_point(enemy.grid_position)
		if not ConeOfFireClass.is_world_point_in_aim_cone(
			from_world,
			aim_world,
			enemy_world,
			shooter.grid_position,
			max_range,
		):
			continue
		if LOSSystemClass.is_shot_blocked(
			shooter.grid_position,
			enemy.grid_position,
			game_state.map_data,
			game_state,
		):
			continue
		var dist := _manhattan_distance(shooter.grid_position, enemy.grid_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy

	return best


## Hit chance (0–100) vs priority or faced enemy; 0 when fully blocked, -1 if no target.
static func hit_pct_vs_faced_enemy(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> float:
	var target := _resolve_hit_display_target(game_state, shooter)
	if target == null:
		return -1.0

	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return -1.0

	var los := LOSSystemClass.evaluate(
		shooter.grid_position,
		target.grid_position,
		game_state.map_data,
		game_state,
	)
	if los.status == LOSSystemClass.Status.BLOCKED:
		return 0.0
	if los.target_using_wall_cover:
		return 0.0

	return _final_hit_chance(shooter, target, weapon, los) * 100.0


static func apply_suppression_from_shot(
	_game_state: GameStateClass,
	_shooter: SoldierStateClass,
	target: SoldierStateClass,
	weapon: WeaponDataClass,
	los: LOSSystemClass.LossResult,
) -> void:
	if target == null or target.is_dead or weapon == null:
		return
	if los.status == LOSSystemClass.Status.BLOCKED:
		return

	var gain := _suppression_stress_gain(weapon)
	var cover_mult := 1.0
	if los.cover_type == CoverSystemClass.CoverType.MODERATE:
		cover_mult = MODERATE_COVER_SUPPRESSION_MULT
	var stance_mult := 1.0
	if target.position_state == PositionStateClass.DOWN:
		stance_mult = PRONE_SUPPRESSION_MULT
	gain *= cover_mult * stance_mult
	target.stress = clampf(target.stress + gain, 0.0, 100.0)
	target.received_suppression_this_tick = true


static func clear_suppression_tick_flags(game_state: GameStateClass) -> void:
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier: SoldierStateClass = state
			soldier.received_suppression_this_tick = false


static func recover_stress_tick(
	game_state: GameStateClass,
	_delta_sec: float = AUTO_FIRE_SCAN_INTERVAL,
) -> void:
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier: SoldierStateClass = state
			if soldier.is_dead or soldier.stress <= 0.0:
				continue
			if soldier.received_suppression_this_tick:
				continue
			var rate := (
				STRESS_RECOVERY_PRONE_PER_TICK
				if soldier.position_state == PositionStateClass.DOWN
				else STRESS_RECOVERY_PER_TICK
			)
			soldier.stress = maxf(0.0, soldier.stress - rate)


static func _suppression_stress_gain(weapon: WeaponDataClass) -> float:
	match weapon.weapon_id:
		WeaponRegistryClass.ID_MG42:
			return 2.0
		WeaponRegistryClass.ID_BAR:
			return 1.2
		_:
			match weapon.weapon_type:
				WeaponTypeClass.SMG:
					return 0.8
				_:
					return 0.4


## Stress represents suppression/combat pressure and reduces firing effectiveness.
static func get_stress_accuracy_modifier(stress: float) -> float:
	match _stress_band(stress):
		1:
			return 0.85
		2:
			return 0.65
		3:
			return 0.4
		4:
			return 0.2
		_:
			return 1.0


static func get_stress_movement_modifier(stress: float) -> float:
	match _stress_band(stress):
		1:
			return 0.9
		2:
			return 0.75
		3:
			return 0.5
		4:
			return 0.35
		_:
			return 1.0


static func get_stress_fire_delay_modifier(stress: float) -> float:
	match _stress_band(stress):
		1:
			return 1.1
		2:
			return 1.25
		3:
			return 1.5
		4:
			return 2.0
		_:
			return 1.0


static func get_stress_state_label(stress: float) -> String:
	return StressLabelsClass.state_label(stress)


static func is_stress_pinned(stress: float) -> bool:
	return stress >= STRESS_PINNED_THRESHOLD


static func is_stress_panicked(stress: float) -> bool:
	return stress >= STRESS_PANIC_THRESHOLD


static func _stress_band(stress: float) -> int:
	if stress < 10.0:
		return 0
	if stress < 25.0:
		return 1
	if stress < 45.0:
		return 2
	if stress < 70.0:
		return 3
	return 4


static func _final_hit_chance(
	shooter: SoldierStateClass,
	target: SoldierStateClass,
	weapon: WeaponDataClass,
	los: LOSSystemClass.LossResult,
) -> float:
	var base_chance := hit_chance(
		shooter.grid_position,
		target.grid_position,
		weapon,
	)
	var chance := base_chance
	if los.cover_type == CoverSystemClass.CoverType.MODERATE:
		chance = CoverSystemClass.apply_moderate_cover(base_chance)
	chance *= get_stress_accuracy_modifier(shooter.stress)
	if shooter.position_state == PositionStateClass.DOWN:
		chance *= SHOOTER_PRONE_ACCURACY_MULT
	if target.position_state == PositionStateClass.DOWN:
		chance *= TARGET_PRONE_HIT_MULT
	return clampf(chance, MIN_HIT_CHANCE, 1.0)


static func is_in_weapon_range(
	shooter: SoldierStateClass,
	target_cell: Vector2i,
) -> bool:
	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return false
	return _is_target_in_cone(shooter, target_cell, _effective_weapon_range(weapon))


static func is_facing_target(
	shooter: SoldierStateClass,
	target: SoldierStateClass,
) -> bool:
	if shooter == null or target == null:
		return false
	return is_facing_cell(shooter, target.grid_position)


static func is_facing_cell(shooter: SoldierStateClass, target_cell: Vector2i) -> bool:
	if shooter == null:
		return false
	var aim_dir := FacingDirection.toward_cell(shooter.grid_position, target_cell)
	return shooter.facing_direction == aim_dir


static func try_engaged_fire(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> CombatShotResult:
	## Sustained manual Fire At: keep priority target; blocked LOS holds fire silently.
	## Hard cover still fires (0% hit) via resolve_shot.
	var empty := CombatShotResult.new()
	if shooter == null or shooter.is_dead or shooter.is_moving:
		return empty
	if shooter.is_stunned() or shooter.has_pending_grenade():
		return empty
	if not shooter.is_sustained_fire():
		return empty

	var target := _resolve_engaged_target(game_state, shooter)
	if target == null:
		return empty

	if not is_facing_target(shooter, target):
		var fireteam := game_state.session.get_fireteam(shooter.team_id)
		fireteam.face_toward_tile(shooter.soldier_id, target.grid_position)
		return empty

	if shooter.ammo_current <= 0:
		return empty

	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return empty

	if not _is_fire_prep_complete(shooter):
		return empty

	if not _can_fire_yet(shooter, weapon):
		return empty

	var max_range := _effective_weapon_range(weapon)
	if _manhattan_distance(shooter.grid_position, target.grid_position) > max_range:
		return empty

	if LOSSystemClass.is_shot_blocked(
		shooter.grid_position,
		target.grid_position,
		game_state.map_data,
		game_state,
	):
		return empty

	return resolve_shot(game_state, shooter, target, true)


static func _resolve_engaged_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	var target := _get_engaged_target(game_state, shooter)
	if target != null:
		if shooter.is_sustained_fire():
			if is_priority_target_trackable(shooter, target, game_state):
				return target
			shooter.clear_engaged_target()
			return null
		if shooter.fire_control_state == FireControlStateClass.FIRE_AT_WILL:
			if _is_auto_target_valid(game_state, shooter, target):
				return target
			shooter.clear_engaged_target()
			return _acquire_auto_target(game_state, shooter)
		shooter.clear_engaged_target()
		return null

	if shooter.is_sustained_fire():
		return _acquire_sustained_target(game_state, shooter)
	if shooter.fire_control_state == FireControlStateClass.FIRE_AT_WILL:
		return _acquire_auto_target(game_state, shooter)
	return null


static func _acquire_sustained_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	if not shooter.is_sustained_fire():
		return null

	if shooter.fire_control_state == FireControlStateClass.HOLD_FIRE:
		shooter.end_sustained_fire()
		return null

	var target := find_best_cone_target(game_state, shooter)
	if target == null:
		return null

	shooter.set_engaged_target(target.team_id, target.soldier_id)
	begin_fire_prep(shooter)
	var fireteam := game_state.session.get_fireteam(shooter.team_id)
	fireteam.face_toward_tile(shooter.soldier_id, target.grid_position)
	return target


static func _acquire_auto_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	if shooter.fire_control_state != FireControlStateClass.FIRE_AT_WILL:
		shooter.clear_engaged_target()
		return null

	var target := find_best_auto_target(game_state, shooter)
	if target == null:
		shooter.clear_engaged_target()
		return null

	shooter.set_engaged_target(target.team_id, target.soldier_id)
	begin_fire_prep(shooter)
	var fireteam := game_state.session.get_fireteam(shooter.team_id)
	fireteam.face_toward_tile(shooter.soldier_id, target.grid_position)
	return target


static func try_auto_engagement(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	ignore_fire_control: bool = false,
) -> CombatShotResult:
	## Fire At Will: acquire → aim delay → fire → repeat cooldown on same target.
	var empty := CombatShotResult.new()
	if shooter == null or shooter.is_dead:
		return empty
	if shooter.is_moving:
		return empty
	if shooter.is_stunned() or shooter.has_pending_grenade():
		return empty
	if shooter.is_sustained_fire():
		return empty
	if not ignore_fire_control and shooter.fire_control_state != FireControlStateClass.FIRE_AT_WILL:
		return empty
	if shooter.ammo_current <= 0:
		return empty

	var target: SoldierStateClass = _resolve_engaged_target(game_state, shooter)
	if target == null:
		return empty

	if not is_facing_target(shooter, target):
		var fireteam := game_state.session.get_fireteam(shooter.team_id)
		fireteam.face_toward_tile(shooter.soldier_id, target.grid_position)
		return empty

	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return empty

	if not _is_fire_prep_complete(shooter):
		return empty

	if not _can_fire_yet(shooter, weapon):
		return empty

	return resolve_shot(game_state, shooter, target, true)


static func begin_fire_prep(shooter: SoldierStateClass) -> void:
	## aim_delay_sec = first-shot acquisition; multiplied by stress fire-delay modifier.
	var weapon := shooter.get_weapon_data()
	var delay_sec := FIRE_PREP_DELAY_SEC
	if weapon != null and weapon.aim_delay_sec > 0.0:
		delay_sec = weapon.aim_delay_sec
	delay_sec *= get_stress_fire_delay_modifier(shooter.stress)
	shooter.fire_ready_after_msec = Time.get_ticks_msec() + int(delay_sec * 1000.0)


static func get_aim_delay_sec(shooter: SoldierStateClass) -> float:
	var weapon := shooter.get_weapon_data()
	var delay_sec := FIRE_PREP_DELAY_SEC
	if weapon != null and weapon.aim_delay_sec > 0.0:
		delay_sec = weapon.aim_delay_sec
	return delay_sec * get_stress_fire_delay_modifier(shooter.stress)


static func get_fire_cooldown_remaining(
	shooter: SoldierStateClass,
	weapon: WeaponDataClass,
) -> float:
	if weapon == null or weapon.fire_interval_sec <= 0.0:
		return 0.0
	if shooter == null or shooter.last_shot_msec <= 0:
		return 0.0
	var interval_sec := weapon.fire_interval_sec * get_stress_fire_delay_modifier(shooter.stress)
	var elapsed_sec := (Time.get_ticks_msec() - shooter.last_shot_msec) / 1000.0
	return maxf(0.0, interval_sec - elapsed_sec)


static func _is_fire_prep_complete(shooter: SoldierStateClass) -> bool:
	if shooter.fire_ready_after_msec <= 0:
		return false
	return Time.get_ticks_msec() >= shooter.fire_ready_after_msec


static func _get_engaged_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	if shooter.engaged_target_team_id < 0 or shooter.engaged_target_soldier_id < 0:
		return null
	var target := game_state.get_soldier(shooter.engaged_target_team_id, shooter.engaged_target_soldier_id)
	if target == null or target.is_dead:
		return null
	return target


## Base hit chance before cover modifiers (distance + weapon bonus only).
static func hit_chance(
	from_cell: Vector2i,
	to_cell: Vector2i,
	weapon: WeaponDataClass,
) -> float:
	var dist := _manhattan_distance(from_cell, to_cell)
	var chance := maxf(MIN_HIT_CHANCE, CLEAR_BASE_HIT_CHANCE - float(dist) * CLEAR_DISTANCE_PENALTY)
	if weapon != null:
		chance += weapon.effective_hit_modifier(dist)
	return clampf(chance, MIN_HIT_CHANCE, 1.0)


static func _can_fire_yet(
	shooter: SoldierStateClass,
	weapon: WeaponDataClass,
) -> bool:
	## Repeat cooldown: fire_interval_sec scaled by stress fire-delay modifier.
	if weapon == null:
		return false
	if weapon.fire_interval_sec <= 0.0:
		return true
	if shooter.last_shot_msec <= 0:
		return true
	var interval_sec := weapon.fire_interval_sec * get_stress_fire_delay_modifier(shooter.stress)
	var elapsed_sec := (Time.get_ticks_msec() - shooter.last_shot_msec) / 1000.0
	return elapsed_sec >= interval_sec


static func _manhattan_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)


static func _effective_weapon_range(weapon: WeaponDataClass) -> int:
	if weapon == null:
		return ConeOfFireClass.RANGE_BONUS
	return ConeOfFireClass.effective_range(weapon.range_tiles)


static func _effective_spotting_range(weapon: WeaponDataClass) -> int:
	return _effective_weapon_range(weapon) + SPOTTING_RANGE_BONUS


static func _is_target_in_cone(
	shooter: SoldierStateClass,
	target_cell: Vector2i,
	max_range: int,
) -> bool:
	return ConeOfFireClass.is_cell_in_cone(
		shooter.grid_position,
		shooter.facing_direction,
		target_cell,
		max_range,
	)


static func _is_valid_priority_enemy(
	shooter: SoldierStateClass,
	enemy: SoldierStateClass,
) -> bool:
	return (
		enemy != null
		and not enemy.is_dead
		and shooter != null
		and enemy.team_id != shooter.team_id
	)


static func _is_priority_target_in_effect(
	_game_state: GameStateClass,
	shooter: SoldierStateClass,
	target: SoldierStateClass,
) -> bool:
	if target == null or target.is_dead:
		return false
	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return false
	var max_range := _effective_weapon_range(weapon)
	if _manhattan_distance(shooter.grid_position, target.grid_position) > max_range:
		return false
	return _is_target_in_cone(shooter, target.grid_position, max_range)


static func _is_auto_target_valid(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	target: SoldierStateClass,
) -> bool:
	if not is_priority_target_trackable(shooter, target, game_state):
		return false
	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return false
	var max_range := _effective_weapon_range(weapon)
	if _manhattan_distance(shooter.grid_position, target.grid_position) > max_range:
		return false
	if not _is_target_in_cone(shooter, target.grid_position, max_range):
		return false
	return _is_target_shootable(game_state, shooter, target)


static func _is_target_shootable(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	target: SoldierStateClass,
) -> bool:
	## Fire At Will auto-targeting: skip fully blocked lines and hard cover (0% hit).
	if shooter == null or target == null or target.is_dead:
		return false
	var los := LOSSystemClass.evaluate(
		shooter.grid_position,
		target.grid_position,
		game_state.map_data,
		game_state,
	)
	if los.status == LOSSystemClass.Status.BLOCKED:
		return false
	if los.target_using_wall_cover:
		return false
	return true


## Read-only target pick for hit % display (no engaged-target mutation).
static func _resolve_hit_display_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	var engaged := _get_engaged_target(game_state, shooter)
	if engaged != null:
		if shooter.fire_control_state == FireControlStateClass.FIRE_AT_WILL:
			if _is_auto_target_valid(game_state, shooter, engaged):
				return engaged
			return find_best_auto_target(game_state, shooter)
		return engaged
	if shooter.fire_control_state == FireControlStateClass.FIRE_AT_WILL:
		return find_best_auto_target(game_state, shooter)
	return find_faced_enemy(game_state, shooter)


static func _has_living_enemy_in_aim_cone(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	from_world: Vector2,
	aim_world: Vector2,
	max_range: int,
) -> bool:
	if shooter == null or shooter.is_dead:
		return false

	var enemy_team_id: int = game_state.enemy_team_id(shooter.team_id)
	var enemy_fireteam := game_state.session.get_fireteam(enemy_team_id)
	for state in enemy_fireteam.soldiers:
		var enemy: SoldierStateClass = state
		if enemy.is_dead:
			continue
		var enemy_world := IsometricGrid.soldier_aim_point(enemy.grid_position)
		if ConeOfFireClass.is_world_point_in_aim_cone(
			from_world,
			aim_world,
			enemy_world,
			shooter.grid_position,
			max_range,
		):
			return true
	return false


static func _log_fire_at_preview(
	shooter: SoldierStateClass,
	result: FireAtPreviewResult,
) -> void:
	if not LOSSystemClass.is_debug_logging_enabled():
		return

	var shooter_label := "none"
	if shooter != null:
		shooter_label = "%d:%d" % [shooter.team_id, shooter.soldier_id]

	var los_status := "BLOCKED"
	if result.los != null:
		los_status = LOSSystemClass.status_name(result.los.status)

	var debug_key := "%s>%s>%s>%s>%s" % [
		shooter_label,
		result.click_cell,
		result.enemy_in_cone,
		los_status,
		result.targetable,
	]
	if debug_key == _last_preview_debug_key:
		return
	_last_preview_debug_key = debug_key

	var lines: PackedStringArray = []
	lines.append("[LOS Preview] Enemy in cone: %s" % ("true" if result.enemy_in_cone else "false"))
	lines.append("[LOS Preview] LOS status: %s" % los_status)
	lines.append("[LOS Preview] Targetable: %s" % ("true" if result.targetable else "false"))
	if result.target != null:
		lines.append(
			"[LOS Preview] Target: %s Soldier %d at %s"
			% [Team.display_name(result.target.team_id), result.target.soldier_id, result.target.grid_position]
		)
	GameLog.log_system("\n".join(lines))


static func _is_wall_blocker_type(blocking_type: String) -> bool:
	var def := MapObjectRegistryClass.get_def(blocking_type)
	return def != null and def.cover_type == CoverSystemClass.CoverType.COMPLETE


## Grenade blast resolution — Chebyshev radius; cover ignored for V1.
static func resolve_grenade(
	game_state: GameStateClass,
	thrower: SoldierStateClass,
	explosion_cell: Vector2i,
) -> CombatGrenadeResultClass:
	var result := CombatGrenadeResultClass.new()
	if game_state == null or thrower == null:
		return result

	result.thrower_team_id = thrower.team_id
	result.thrower_id = thrower.soldier_id
	result.explosion_cell = explosion_cell
	result.blast_radius = GRENADE_BLAST_RADIUS

	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier: SoldierStateClass = state
			if soldier.is_dead:
				continue

			var distance := _chebyshev_distance(soldier.grid_position, explosion_cell)
			if distance > GRENADE_BLAST_RADIUS:
				continue

			if distance <= GRENADE_KILL_RADIUS:
				if randf() <= GRENADE_KILL_CHANCE:
					soldier.mark_killed()
					result.killed.append({
						"team_id": soldier.team_id,
						"soldier_id": soldier.soldier_id,
					})
					result.messages.append(
						"%s Soldier %d killed by grenade blast."
						% [Team.display_name(soldier.team_id), soldier.soldier_id],
					)
				else:
					_apply_grenade_stun(soldier)
					result.stunned.append({
						"team_id": soldier.team_id,
						"soldier_id": soldier.soldier_id,
					})
					result.messages.append(
						"%s Soldier %d stunned by grenade blast."
						% [Team.display_name(soldier.team_id), soldier.soldier_id],
					)
			else:
				_apply_grenade_stun(soldier)
				result.stunned.append({
					"team_id": soldier.team_id,
					"soldier_id": soldier.soldier_id,
				})
				result.messages.append(
					"%s Soldier %d stunned by grenade blast."
					% [Team.display_name(soldier.team_id), soldier.soldier_id],
				)

	return result


static func grenade_throw_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return _chebyshev_distance(from_cell, to_cell)


static func _apply_grenade_stun(soldier: SoldierStateClass) -> void:
	soldier.apply_grenade_stun(GRENADE_STUN_DURATION_SEC)


static func _chebyshev_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return maxi(absi(from_cell.x - to_cell.x), absi(from_cell.y - to_cell.y))
