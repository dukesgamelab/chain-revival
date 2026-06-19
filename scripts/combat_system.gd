class_name CombatSystem
extends RefCounted
## Resolves shooting against GameState data (no scene nodes).
## Called by ActionResolver — not by UI directly.

const GameStateClass := preload("res://scripts/game_state.gd")
const SoldierStateClass := preload("res://scripts/soldier_state.gd")
const WeaponDataClass := preload("res://scripts/weapon_data.gd")
const WeaponRegistryClass := preload("res://scripts/weapon_registry.gd")
const WeaponTypeClass := preload("res://scripts/weapon_type.gd")
const PositionStateClass := preload("res://scripts/position_state.gd")
const FireControlStateClass := preload("res://scripts/fire_control_state.gd")
const LOSSystemClass := preload("res://scripts/los_system.gd")
const CoverSystemClass := preload("res://scripts/cover_system.gd")
const MapObjectRegistryClass := preload("res://scripts/map_object_registry.gd")
const ConeOfFireClass := preload("res://scripts/cone_of_fire.gd")

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

## Manual Fire At = priority target; blocked LOS holds fire but keeps the assignment.
## Fire At Will = auto-acquire visible targets; aim delay then repeat cooldown.


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
	)
	if los.status == LOSSystemClass.Status.BLOCKED:
		result.blocked = true
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

	var ammo_cost := weapon.ammo_cost(shooter.ammo_current)
	# Authoritative ammo/death mutations (invoked only via ActionResolver → process_combat_tick).
	shooter.ammo_current -= ammo_cost
	shooter.last_shot_msec = Time.get_ticks_msec()
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

	AudioManager.play_gunshot()
	apply_suppression_from_shot(game_state, shooter, target, weapon, los)

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
	## Fire At Will: nearest shootable enemy in the facing cone (clear LOS required).
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


## Manual Fire At: pick a priority enemy from aim/click without requiring clear LOS.
static func find_manual_priority_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	from_world: Vector2,
	aim_world: Vector2,
	max_range: int,
	explicit_team_id: int = -1,
	explicit_soldier_id: int = -1,
) -> SoldierStateClass:
	if shooter == null or shooter.is_dead:
		return null

	if explicit_team_id >= 0 and explicit_soldier_id > 0:
		var explicit := game_state.get_soldier(explicit_team_id, explicit_soldier_id)
		if _is_valid_priority_enemy(shooter, explicit):
			return explicit

	return find_best_aim_cone_priority_target(
		game_state,
		shooter,
		from_world,
		aim_world,
		max_range,
	)


static func find_best_aim_cone_priority_target(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	from_world: Vector2,
	aim_world: Vector2,
	max_range: int,
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
		var enemy_world := IsometricGrid.grid_to_world(enemy.grid_position) + Vector2(0, -16)
		if not ConeOfFireClass.is_world_point_in_aim_cone(
			from_world,
			aim_world,
			enemy_world,
			shooter.grid_position,
			max_range,
		):
			continue
		var dist := _manhattan_distance(shooter.grid_position, enemy.grid_position)
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
	## UI preview: any living enemy in the aim cone (blocked targets still count).
	return find_best_aim_cone_priority_target(
		game_state,
		shooter,
		from_world,
		aim_world,
		max_range,
	) != null


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
	var target := _get_engaged_target(game_state, shooter)
	if target == null:
		target = find_faced_enemy(game_state, shooter)
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
	if los.cover_type == CoverSystemClass.CoverType.MODERATE:
		gain *= MODERATE_COVER_SUPPRESSION_MULT
	target.stress = clampf(target.stress + gain, 0.0, 100.0)


static func recover_stress_tick(
	game_state: GameStateClass,
	_delta_sec: float = AUTO_FIRE_SCAN_INTERVAL,
) -> void:
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier: SoldierStateClass = state
			if soldier.is_dead or soldier.stress <= 0.0:
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
	chance *= clampf(1.0 - shooter.stress / 100.0, 0.15, 1.0)
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
	var empty := CombatShotResult.new()
	if shooter == null or shooter.is_dead or shooter.is_moving:
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
			if _is_valid_priority_enemy(shooter, target):
				return target
			shooter.clear_engaged_target()
			return _acquire_sustained_target(game_state, shooter)
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

	var target := find_best_cone_target(game_state, shooter)
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
	## aim_delay_sec = first-shot acquisition; target changes call this again via acquisition code.
	var weapon := shooter.get_weapon_data()
	var delay_sec := FIRE_PREP_DELAY_SEC
	if weapon != null and weapon.aim_delay_sec > 0.0:
		delay_sec = weapon.aim_delay_sec
	shooter.fire_ready_after_msec = Time.get_ticks_msec() + int(delay_sec * 1000.0)


static func get_aim_delay_sec(shooter: SoldierStateClass) -> float:
	var weapon := shooter.get_weapon_data()
	if weapon != null and weapon.aim_delay_sec > 0.0:
		return weapon.aim_delay_sec
	return FIRE_PREP_DELAY_SEC


static func get_fire_cooldown_remaining(
	shooter: SoldierStateClass,
	weapon: WeaponDataClass,
) -> float:
	if weapon == null or weapon.fire_interval_sec <= 0.0:
		return 0.0
	if shooter == null or shooter.last_shot_msec <= 0:
		return 0.0
	var elapsed_sec := (Time.get_ticks_msec() - shooter.last_shot_msec) / 1000.0
	return maxf(0.0, weapon.fire_interval_sec - elapsed_sec)


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
	## Repeat cooldown: elapsed since last_shot_msec must reach weapon.fire_interval_sec.
	if weapon == null:
		return false
	if weapon.fire_interval_sec <= 0.0:
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
	game_state: GameStateClass,
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
	if not _is_valid_priority_enemy(shooter, target):
		return false
	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return false
	var max_range := _effective_weapon_range(weapon)
	if _manhattan_distance(shooter.grid_position, target.grid_position) > max_range:
		return false
	if not _is_target_in_cone(shooter, target.grid_position, max_range):
		return false
	return not LOSSystemClass.is_shot_blocked(
		shooter.grid_position,
		target.grid_position,
		game_state.map_data,
	)
