class_name CombatSystem
extends RefCounted
## Resolves shooting: facing, line of fire, cover, ammo, hit chance, death, and Fire At Will.

const GameStateClass := preload("res://scripts/game_state.gd")
const SoldierStateClass := preload("res://scripts/soldier_state.gd")
const FireControlStateClass := preload("res://scripts/fire_control_state.gd")
const LOSSystemClass := preload("res://scripts/los_system.gd")
const MapObjectRegistryClass := preload("res://scripts/map_object_registry.gd")

const BASE_HIT_CHANCE := 0.60
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
	if shooter.ammo_current <= 0:
		result.no_ammo = true
		result.messages.append("No ammo")
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

	shooter.ammo_current -= 1
	result.fired = true
	if auto_engagement:
		result.messages.append(
			"Soldier %d automatically engaged %s Soldier %d"
			% [
				shooter.soldier_id,
				Team.display_name(target.team_id),
				target.soldier_id,
			],
		)
	result.messages.append(
		"%s Soldier %d fired at %s Soldier %d"
		% [
			Team.display_name(shooter.team_id),
			shooter.soldier_id,
			Team.display_name(target.team_id),
			target.soldier_id,
		],
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

	var chance := hit_chance(shooter.grid_position, target.grid_position, los.cover_value)
	if los.cover_value > 0.0:
		result.messages.append("Cover reduced hit chance to %d%%" % int(round(chance * 100.0)))

	if randf() <= chance:
		result.hit = true
		result.messages.append("Shot hit")
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
		result.messages.append("Shot missed")

	return result


## Closest living enemy with clear line of fire (Manhattan distance).
static func find_closest_visible_enemy(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
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
		if LOSSystemClass.is_shot_blocked(shooter.grid_position, enemy.grid_position, game_state.map_data):
			continue
		var dist := _manhattan_distance(shooter.grid_position, enemy.grid_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy

	return best


static func try_auto_engagement(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> CombatShotResult:
	var empty := CombatShotResult.new()
	if shooter == null or shooter.is_dead:
		return empty
	if shooter.fire_control_state != FireControlStateClass.FIRE_AT_WILL:
		return empty
	if shooter.ammo_current <= 0:
		return empty

	var target := find_closest_visible_enemy(game_state, shooter)
	if target == null:
		return empty

	return resolve_shot(game_state, shooter, target, true)


## Base 60% minus 5% per Manhattan tile, floored at 10%.
## Cover subtracts percentage points (e.g. 0.30 cover on 60% base -> 30% chance).
## Alternative: multiply by (1.0 - cover_value) instead of subtracting points.
static func hit_chance(
	from_cell: Vector2i,
	to_cell: Vector2i,
	cover_value: float = 0.0,
) -> float:
	var dist := _manhattan_distance(from_cell, to_cell)
	var chance := maxf(MIN_HIT_CHANCE, BASE_HIT_CHANCE - float(dist) * DISTANCE_PENALTY)
	if cover_value > 0.0:
		chance = maxf(MIN_HIT_CHANCE, chance - cover_value)
	return chance


static func _manhattan_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
