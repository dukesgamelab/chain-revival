class_name CombatSystem
extends RefCounted
## Resolves shooting: facing, line of fire, ammo, hit chance, death.

const BASE_HIT_CHANCE := 0.60
const MIN_HIT_CHANCE := 0.10
const DISTANCE_PENALTY := 0.05


static func resolve_shot(
	game_state: GameState,
	shooter: SoldierState,
	target: SoldierState,
) -> CombatShotResult:
	var result := CombatShotResult.new()

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

	if LineOfFire.is_blocked(shooter.grid_position, target.grid_position, game_state.map_data):
		result.blocked = true
		result.messages.append("Line of fire blocked by cover")
		return result

	shooter.ammo_current -= 1
	result.fired = true
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

	AudioManager.play_gunshot()

	var chance := hit_chance(shooter.grid_position, target.grid_position)
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
	else:
		result.messages.append("Shot missed")

	return result


static func hit_chance(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var dist := absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
	return maxf(MIN_HIT_CHANCE, BASE_HIT_CHANCE - float(dist) * DISTANCE_PENALTY)
