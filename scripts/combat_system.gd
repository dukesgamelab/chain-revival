class_name CombatSystem
extends RefCounted
## Resolves shooting: weapons, facing, line of fire, cover, ammo, hit chance, death, Fire At Will.

const GameStateClass := preload("res://scripts/game_state.gd")
const SoldierStateClass := preload("res://scripts/soldier_state.gd")
const WeaponDataClass := preload("res://scripts/weapon_data.gd")
const FireControlStateClass := preload("res://scripts/fire_control_state.gd")
const LOSSystemClass := preload("res://scripts/los_system.gd")
const CoverSystemClass := preload("res://scripts/cover_system.gd")
const MapObjectRegistryClass := preload("res://scripts/map_object_registry.gd")
const ConeOfFireClass := preload("res://scripts/cone_of_fire.gd")

const CLEAR_BASE_HIT_CHANCE := 0.78
const CLEAR_DISTANCE_PENALTY := 0.025
const MIN_HIT_CHANCE := 0.10
const AUTO_FIRE_SCAN_INTERVAL := 0.5
const FIRE_PREP_DELAY_SEC := 1.0


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
		result.messages.append("Target already dead")
		return result
	if shooter.team_id == target.team_id:
		result.messages.append("Cannot shoot friendlies")
		return result

	var weapon := shooter.get_weapon_data()
	if weapon == null:
		result.messages.append("No weapon assigned")
		return result
	result.weapon_name = weapon.weapon_name

	if shooter.ammo_current <= 0:
		result.no_ammo = true
		result.messages.append("%s %s out of ammo" % [Team.display_name(shooter.team_id), weapon.weapon_name])
		return result

	var distance := _manhattan_distance(shooter.grid_position, target.grid_position)
	var max_range := _effective_weapon_range(weapon)
	if distance > max_range:
		result.out_of_range = true
		result.messages.append(
			"%s %s out of range" % [Team.display_name(shooter.team_id), weapon.weapon_name],
		)
		return result

	var fireteam := game_state.session.get_fireteam(shooter.team_id)
	fireteam.face_toward_tile(shooter.soldier_id, target.grid_position)

	var los := LOSSystemClass.evaluate(
		shooter.grid_position,
		target.grid_position,
		game_state.map_data,
	)
	if los.status == LOSSystemClass.Status.BLOCKED:
		result.blocked = true
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

	var ammo_cost := weapon.ammo_cost(shooter.ammo_current)
	shooter.ammo_current -= ammo_cost
	shooter.last_shot_msec = Time.get_ticks_msec()
	result.fired = true
	result.tracer_count = weapon.tracer_count

	if auto_engagement:
		result.messages.append(
			"Soldier %d automatically engaged %s Soldier %d"
			% [
				shooter.soldier_id,
				Team.display_name(target.team_id),
				target.soldier_id,
			],
		)

	if weapon.is_burst():
		result.messages.append(
			"%s %s fired burst" % [Team.display_name(shooter.team_id), weapon.weapon_name],
		)
	else:
		result.messages.append(
			"%s %s fired" % [Team.display_name(shooter.team_id), weapon.weapon_name],
		)
	result.messages.append("Ammo remaining: %d" % shooter.ammo_current)

	AudioManager.play_gunshot()

	var base_chance := hit_chance(
		shooter.grid_position,
		target.grid_position,
		weapon,
	)
	var chance := base_chance
	if los.cover_type == CoverSystemClass.CoverType.MODERATE:
		chance = CoverSystemClass.apply_moderate_cover(base_chance)
		chance = clampf(chance, MIN_HIT_CHANCE, 1.0)
		result.messages.append(
			"Hit chance reduced from %d%% to %d%%"
			% [int(round(base_chance * 100.0)), int(round(chance * 100.0))],
		)

	if randf() <= chance:
		result.hit = true
		result.messages.append("%s hit" % weapon.weapon_name)
		target.is_dead = true
		target.clear_path()
		result.killed = true
		result.messages.append(
			"%s Soldier %d killed" % [Team.display_name(target.team_id), target.soldier_id],
		)
		AudioManager.play_death()
	elif los.cover_type == CoverSystemClass.CoverType.MODERATE:
		result.messages.append("Shot missed due to cover")
	else:
		result.messages.append("%s missed" % weapon.weapon_name)

	return result


static func find_closest_visible_enemy(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	return find_best_cone_target(game_state, shooter)


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
		if LOSSystemClass.is_shot_blocked(shooter.grid_position, enemy.grid_position, game_state.map_data):
			continue
		if dist < best_dist:
			best_dist = dist
			best = enemy

	return best


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
		var enemy_world := IsometricGrid.grid_to_world(enemy.grid_position) + Vector2(0, -16)
		if not ConeOfFireClass.is_world_point_in_aim_cone(
			from_world,
			aim_world,
			enemy_world,
			shooter.grid_position,
			max_range,
		):
			continue
		if LOSSystemClass.is_shot_blocked(shooter.grid_position, enemy.grid_position, game_state.map_data):
			continue
		return true
	return false


## Hit chance (0–100) vs the enemy the shooter is currently facing, or -1 if none.
static func hit_pct_vs_faced_enemy(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> float:
	var target := find_faced_enemy(game_state, shooter)
	if target == null:
		return -1.0

	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return -1.0

	var los := LOSSystemClass.evaluate(
		shooter.grid_position,
		target.grid_position,
		game_state.map_data,
	)
	if los.status == LOSSystemClass.Status.BLOCKED:
		return -1.0

	return hit_chance(
		shooter.grid_position,
		target.grid_position,
		weapon,
	) * _cover_hit_multiplier(los) * 100.0


static func _cover_hit_multiplier(los: LOSSystemClass.LossResult) -> float:
	if los.cover_type == CoverSystemClass.CoverType.MODERATE:
		return CoverSystemClass.MODERATE_HIT_MULTIPLIER
	return 1.0


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
	var empty := CombatShotResult.new()
	if shooter == null or shooter.is_dead or shooter.is_moving:
		return empty
	if not shooter.is_sustained_fire() and not shooter.is_engaged():
		return empty

	var target := _resolve_engaged_target(game_state, shooter)
	if target == null:
		return empty

	if not is_facing_target(shooter, target):
		if shooter.is_sustained_fire():
			var fireteam := game_state.session.get_fireteam(shooter.team_id)
			fireteam.face_toward_tile(shooter.soldier_id, target.grid_position)
		else:
			return empty

	if shooter.ammo_current <= 0:
		return empty
	if not _ensure_fire_prep_started(shooter):
		return empty
	if not _can_fire_yet(shooter, shooter.get_weapon_data()):
		return empty

	return resolve_shot(game_state, shooter, target, true)


static func _resolve_engaged_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	var target := _get_engaged_target(game_state, shooter)
	if target != null:
		return target
	if not shooter.is_sustained_fire():
		return null

	shooter.clear_engaged_target()
	target = find_best_cone_target(game_state, shooter)
	if target == null:
		return null

	shooter.set_engaged_target(target.team_id, target.soldier_id)
	var fireteam := game_state.session.get_fireteam(shooter.team_id)
	fireteam.face_toward_tile(shooter.soldier_id, target.grid_position)
	return target


static func try_auto_engagement(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	ignore_fire_control: bool = false,
) -> CombatShotResult:
	var empty := CombatShotResult.new()
	if shooter == null or shooter.is_dead:
		return empty
	if shooter.is_moving:
		return empty
	if not ignore_fire_control and shooter.fire_control_state != FireControlStateClass.FIRE_AT_WILL:
		return empty
	if shooter.ammo_current <= 0:
		return empty

	var target: SoldierStateClass = find_closest_visible_enemy(game_state, shooter)
	if target == null:
		return empty

	if not _ensure_fire_prep_started(shooter):
		return empty
	if not _can_fire_yet(shooter, shooter.get_weapon_data()):
		return empty

	return resolve_shot(game_state, shooter, target, true)


static func begin_fire_prep(shooter: SoldierStateClass) -> void:
	shooter.fire_ready_after_msec = Time.get_ticks_msec() + int(FIRE_PREP_DELAY_SEC * 1000.0)


static func _ensure_fire_prep_started(shooter: SoldierStateClass) -> bool:
	if _is_fire_prep_complete(shooter):
		return true
	if shooter.fire_ready_after_msec <= 0:
		begin_fire_prep(shooter)
	return false


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


static func _can_fire_yet(shooter: SoldierStateClass, weapon: WeaponDataClass) -> bool:
	if weapon == null or weapon.fire_interval_sec <= 0.0:
		return true
	if shooter.last_shot_msec <= 0:
		return true
	var elapsed_sec := (Time.get_ticks_msec() - shooter.last_shot_msec) / 1000.0
	return elapsed_sec >= weapon.fire_interval_sec


static func _manhattan_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)


static func _effective_weapon_range(weapon: WeaponDataClass) -> int:
	if weapon == null:
		return ConeOfFireClass.RANGE_BONUS
	return ConeOfFireClass.effective_range(weapon.range_tiles)


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
