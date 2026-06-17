class_name CombatSystem
extends RefCounted
## Resolves shooting: weapons, facing, line of fire, cover, ammo, hit chance, death, Fire At Will.

const GameStateClass := preload("res://scripts/game_state.gd")
const SoldierStateClass := preload("res://scripts/soldier_state.gd")
const WeaponDataClass := preload("res://scripts/weapon_data.gd")
const FireControlStateClass := preload("res://scripts/fire_control_state.gd")
const LOSSystemClass := preload("res://scripts/los_system.gd")
const MapObjectRegistryClass := preload("res://scripts/map_object_registry.gd")

const CLEAR_BASE_HIT_CHANCE := 0.78
const CLEAR_DISTANCE_PENALTY := 0.025
const COVER_BASE_HIT_CHANCE := 0.50
const MIN_HIT_CHANCE := 0.10
const DISTANCE_PENALTY := 0.05
const AUTO_FIRE_SCAN_INTERVAL := 0.5


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
	if distance > weapon.range_tiles:
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

	if los.cover_value > 0.0:
		result.had_cover = true
		result.cover_value = los.cover_value
		result.messages.append(
			"%s Soldier %d is in cover"
			% [Team.display_name(target.team_id), target.soldier_id],
		)

	AudioManager.play_gunshot()

	var chance := hit_chance(
		shooter.grid_position,
		target.grid_position,
		weapon,
		los.cover_value,
	)
	if los.cover_value > 0.0:
		result.messages.append("Cover reduced hit chance to %d%%" % int(round(chance * 100.0)))

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
	elif los.cover_value > 0.0:
		result.messages.append("Shot missed due to cover")
	else:
		result.messages.append("%s missed" % weapon.weapon_name)

	return result


static func find_closest_visible_enemy(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	if shooter == null or shooter.is_dead:
		return null

	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return null

	var enemy_team_id: int = game_state.enemy_team_id(shooter.team_id)
	var enemy_fireteam := game_state.session.get_fireteam(enemy_team_id)
	var best: SoldierStateClass = null
	var best_dist := INF

	for state in enemy_fireteam.soldiers:
		var enemy: SoldierStateClass = state
		if enemy.is_dead:
			continue
		var dist := _manhattan_distance(shooter.grid_position, enemy.grid_position)
		if dist > weapon.range_tiles:
			continue
		if LOSSystemClass.is_shot_blocked(shooter.grid_position, enemy.grid_position, game_state.map_data):
			continue
		if dist < best_dist:
			best_dist = dist
			best = enemy

	return best


## Living enemy this shooter is facing, in weapon range with unobstructed fire.
static func find_faced_enemy(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	if shooter == null or shooter.is_dead:
		return null

	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return null

	var enemy_team_id: int = game_state.enemy_team_id(shooter.team_id)
	var enemy_fireteam := game_state.session.get_fireteam(enemy_team_id)
	var facing := shooter.facing_direction
	var best: SoldierStateClass = null
	var best_dist := INF

	for state in enemy_fireteam.soldiers:
		var enemy: SoldierStateClass = state
		if enemy.is_dead:
			continue
		var dist := _manhattan_distance(shooter.grid_position, enemy.grid_position)
		if dist > weapon.range_tiles:
			continue
		if LOSSystemClass.is_shot_blocked(shooter.grid_position, enemy.grid_position, game_state.map_data):
			continue
		var aim_dir := FacingDirection.toward_cell(shooter.grid_position, enemy.grid_position)
		if aim_dir != facing:
			continue
		if dist < best_dist:
			best_dist = dist
			best = enemy

	return best


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
		los.cover_value,
	) * 100.0


static func is_in_weapon_range(
	shooter: SoldierStateClass,
	target_cell: Vector2i,
) -> bool:
	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return false
	return _manhattan_distance(shooter.grid_position, target_cell) <= weapon.range_tiles


static func try_auto_engagement(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	ignore_fire_control: bool = false,
) -> CombatShotResult:
	var empty := CombatShotResult.new()
	if shooter == null or shooter.is_dead:
		return empty
	if not ignore_fire_control and shooter.fire_control_state != FireControlStateClass.FIRE_AT_WILL:
		return empty
	if shooter.ammo_current <= 0:
		return empty
	if not _can_fire_yet(shooter, shooter.get_weapon_data()):
		return empty

	var target := find_closest_visible_enemy(game_state, shooter)
	if target == null:
		return empty

	return resolve_shot(game_state, shooter, target, true)


## Open LOS uses a high base chance; cover and distance reduce it more aggressively.
static func hit_chance(
	from_cell: Vector2i,
	to_cell: Vector2i,
	weapon: WeaponDataClass,
	cover_value: float = 0.0,
) -> float:
	var dist := _manhattan_distance(from_cell, to_cell)
	var chance: float
	if cover_value <= 0.0:
		chance = maxf(MIN_HIT_CHANCE, CLEAR_BASE_HIT_CHANCE - float(dist) * CLEAR_DISTANCE_PENALTY)
	else:
		chance = maxf(MIN_HIT_CHANCE, COVER_BASE_HIT_CHANCE - float(dist) * DISTANCE_PENALTY)
		chance = maxf(MIN_HIT_CHANCE, chance - cover_value)
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
