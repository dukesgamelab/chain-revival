class_name CombatSystem
extends RefCounted
## Resolves shooting against GameState data (no scene nodes).
## Called by ActionResolver — not by UI directly.

const GameStateClass := preload("res://scripts/core/game_state.gd")
const ScenarioRulesClass := preload("res://scripts/core/scenario_rules.gd")
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
const PerceptionCacheClass := preload("res://scripts/combat/perception_cache.gd")
const HitChancePolicyClass := preload("res://scripts/gameplay_policies/hit_chance_policy.gd")
const GrenadePolicyClass := preload("res://scripts/gameplay_policies/grenade_policy.gd")
const SuppressionPolicyClass := preload("res://scripts/gameplay_policies/suppression_policy.gd")

## Numeric aliases kept for existing call sites; live values live in GameplayPolicies.
const CLEAR_BASE_HIT_CHANCE := HitChancePolicyClass.DEFAULT_CLEAR_BASE_HIT_CHANCE
const CLEAR_DISTANCE_PENALTY := HitChancePolicyClass.DEFAULT_CLEAR_DISTANCE_PENALTY
const MIN_HIT_CHANCE := HitChancePolicyClass.DEFAULT_MIN_HIT_CHANCE
const AUTO_FIRE_SCAN_INTERVAL := HitChancePolicyClass.DEFAULT_AUTO_FIRE_SCAN_INTERVAL
const FIRE_PREP_DELAY_SEC := HitChancePolicyClass.DEFAULT_FIRE_PREP_DELAY_SEC
const STRESS_RECOVERY_PER_TICK := SuppressionPolicyClass.DEFAULT_RECOVERY_PER_TICK
const STRESS_RECOVERY_PRONE_PER_TICK := SuppressionPolicyClass.DEFAULT_RECOVERY_PRONE_PER_TICK
const SHOOTER_PRONE_ACCURACY_MULT := HitChancePolicyClass.DEFAULT_SHOOTER_PRONE_ACCURACY_MULT
const TARGET_PRONE_HIT_MULT := HitChancePolicyClass.DEFAULT_TARGET_PRONE_HIT_MULT
const MODERATE_COVER_SUPPRESSION_MULT := SuppressionPolicyClass.DEFAULT_MODERATE_COVER_SUPPRESSION_MULT
const PRONE_SUPPRESSION_MULT := SuppressionPolicyClass.DEFAULT_PRONE_SUPPRESSION_MULT
const STRESS_PINNED_THRESHOLD := SuppressionPolicyClass.DEFAULT_PINNED_THRESHOLD
const STRESS_PANIC_THRESHOLD := SuppressionPolicyClass.DEFAULT_PANIC_THRESHOLD
const AUTO_TARGET_ENGAGED_BONUS := HitChancePolicyClass.DEFAULT_AUTO_TARGET_ENGAGED_BONUS
const GRENADE_THROW_RANGE := GrenadePolicyClass.DEFAULT_THROW_RANGE
const GRENADE_FUSE_MSEC := GrenadePolicyClass.DEFAULT_FUSE_MSEC
const GRENADE_BLAST_RADIUS := GrenadePolicyClass.DEFAULT_BLAST_RADIUS
const GRENADE_KILL_RADIUS := GrenadePolicyClass.DEFAULT_KILL_RADIUS
const GRENADE_KILL_CHANCE := GrenadePolicyClass.DEFAULT_KILL_CHANCE
const GRENADE_STUN_DURATION_SEC := GrenadePolicyClass.DEFAULT_STUN_DURATION_SEC
const RECENTLY_SEEN_SEC := HitChancePolicyClass.DEFAULT_RECENTLY_SEEN_SEC
const RECENTLY_FIRED_SPOT_SEC := HitChancePolicyClass.DEFAULT_RECENTLY_FIRED_SPOT_SEC
const LAST_KNOWN_NEAR_TILES := HitChancePolicyClass.DEFAULT_LAST_KNOWN_NEAR_TILES
const SPOTTING_RANGE_BONUS := HitChancePolicyClass.DEFAULT_SPOTTING_RANGE_BONUS

## stress = suppression/combat pressure; affects accuracy, movement, and fire cadence.
## spotting controls target eligibility; shot LOS controls whether bullets can fire.
## cover reduces both hit chance and spotting; recently fired enemies are easier to detect.
## Manual Fire At remains priority-target behavior; Fire At Will uses tactical target scoring.

static var _last_preview_debug_key: String = ""

## Int world hash — rebuilt only when stale + throttle allows (not every move step).
static var _team_visibility_cache_key: int = -1
static var _visibility_cache_by_team: Dictionary = {}
static var _visibility_log_keys: Dictionary = {}
## Per-observer direct spots built with the team map (key "team:soldier" -> { enemy_key -> Result }).
## Lets player fog reuse team LOS instead of re-spotting.
static var _observer_spot_maps: Dictionary = {}
## Presentation layer: world-derived grid cells for soldiers mid-move (key "team_id:soldier_id").
static var _spotting_cell_overrides: Dictionary = {}
## Cap O(observers×enemies) LOS rebuilds while many AI soldiers move every sim tick.
static var _last_team_vis_rebuild_msec: int = -999999
static var _force_team_vis_rebuild: bool = false
## Match combat-scan cadence so spotting stays correct without per-step rebuilds.
const TEAM_VIS_REBUILD_MIN_MSEC := 500

## --- Command-chain fog of war (visibility, NOT LOS) ---
## NOT PROVEN that sharing is upward-only + fully transitive. Flip this one switch if playtest
## shows otherwise — do not scatter direction logic elsewhere.
const COMMAND_VIS_UPWARD_ONLY := true
const COMMAND_VIS_DEPTH_GUARD := 32
## Bumped on assign/break so effective_visibility recomputes immediately (change-driven).
static var _command_link_revision: int = 0
static var _player_vis_cache_sig: int = -1
static var _player_vis_cmd_rev: int = -1
## player_id -> { enemy_key -> EnemyVisibilityResult }
static var _player_vis_cache: Dictionary = {}
## SubordOldVis mirror: player_id -> { enemy_key -> true }
static var _player_vis_prev_sets: Dictionary = {}
## Players whose effective set changed on the last recompute (VisListChangdTrigger analog).
static var _player_vis_changed_ids: Array[int] = []


static func set_spotting_cell_overrides(overrides: Dictionary) -> void:
	_spotting_cell_overrides = overrides


static func clear_spotting_cell_overrides() -> void:
	_spotting_cell_overrides.clear()


static func spotting_cell_for(soldier: SoldierStateClass) -> Vector2i:
	if soldier == null:
		return Vector2i.ZERO
	var key := ObjectId.team_soldier_key(soldier.team_id, soldier.soldier_id)
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
			_combat_range(shooter.grid_position, target.grid_position) <= float(max_range)
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
	var in_range := _combat_range(shooter.grid_position, target.grid_position) <= float(max_range)
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

	var distance := _combat_range(shooter.grid_position, target.grid_position)
	var max_range := float(_effective_weapon_range(weapon))
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

	## Automatic corner peek — no command; expose lean side for presentation.
	result.corner_peek = los.corner_peek
	result.peek_side = los.peek_side
	result.corner_cell = los.corner_cell

	if not _can_fire_yet(shooter, weapon):
		result.on_cooldown = true
		if not auto_engagement:
			result.messages.append(
				"%s %s — wait %.1fs between shots"
				% [
					Team.display_name(shooter.team_id),
					weapon.weapon_name,
					effective_fire_cycle_sec(weapon),
				],
			)
		return result

	if not auto_engagement:
		result.messages.append(
			"%s Soldier %d firing %s"
			% [Team.display_name(shooter.team_id), shooter.soldier_id, weapon.weapon_name],
		)
		if los.corner_peek:
			result.messages.append(
				"Corner peek (%s)" % CoverSystemClass.peek_side_name(los.peek_side)
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
	var now_msec := SimulationClock.get_ticks_msec()
	shooter.last_shot_msec = now_msec
	shooter.last_fired_msec = now_msec
	## Restart the single aim/fire cycle (OG Aiming state between shots).
	begin_fire_prep(shooter)
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

	var breakdown: Dictionary = {}
	var chance := _final_hit_chance(shooter, target, weapon, los, breakdown)
	result.hit_breakdown = breakdown
	result.hit_final = chance
	if not auto_engagement and los.cover_type == CoverSystemClass.CoverType.MODERATE:
		var base_chance := float(breakdown.get("base", chance))
		result.messages.append(
			"Hit chance reduced from %d%% to %d%%"
			% [int(round(base_chance * 100.0)), int(round(chance * 100.0))],
		)

	## P(death) = HitFinal × lethality. Hit curve stays untouched so WIA can split
	## this back into a second roll later (set lethality_multiplier to 1.0 then).
	var kill_chance := clampf(
		chance * GameplayPolicies.hit.lethality_multiplier,
		0.0,
		1.0,
	)
	result.kill_chance = kill_chance
	if GameConfig.combat_verbose_enabled():
		_log_combat_verbose(shooter, target, weapon, breakdown, kill_chance)

	# V1: one hit roll per burst; future version can roll once per bullet in rounds_per_attack.
	if GameRandom.chance(kill_chance):
		result.hit = true
		result.messages.append("%s hit" % weapon.weapon_name)
		target.mark_killed()
		notify_soldier_perception_dirty(game_state, target)
		result.killed = true
		ScenarioRulesClass.on_soldier_killed(game_state, shooter.team_id, target)
		result.messages.append(
			"%s Soldier %d killed" % [Team.display_name(target.team_id), target.soldier_id],
		)
		AudioManager.play_death(target.team_id)
	elif los.cover_type == CoverSystemClass.CoverType.MODERATE:
		result.messages.append("Shot missed due to cover")
	else:
		result.messages.append("%s missed" % weapon.weapon_name)

	return result


static func _log_combat_verbose(
	shooter: SoldierStateClass,
	target: SoldierStateClass,
	weapon: WeaponDataClass,
	breakdown: Dictionary,
	kill_chance: float,
) -> void:
	GameLog.log_combat(
		"[CombatVerbose] %s%d→%s%d %s range=%.1f base=%.4f cover×%.4f type×%.4f angle×%.4f stress×%.4f prone×%.2f/%.2f final=%.4f lethality×%.2f kill=%.4f"
		% [
			Team.display_name(shooter.team_id),
			shooter.soldier_id,
			Team.display_name(target.team_id),
			target.soldier_id,
			weapon.weapon_name if weapon != null else "?",
			float(breakdown.get("range", 0.0)),
			float(breakdown.get("base", 0.0)),
			float(breakdown.get("cover_mult", 1.0)),
			float(breakdown.get("move_type_mult", 1.0)),
			float(breakdown.get("move_angle_mult", 1.0)),
			float(breakdown.get("stress_mult", 1.0)),
			float(breakdown.get("shooter_prone_mult", 1.0)),
			float(breakdown.get("target_prone_mult", 1.0)),
			float(breakdown.get("final", 0.0)),
			float(breakdown.get("lethality", 0.0)),
			kill_chance,
		]
	)


## --- Spotting / visibility (map cover + range + forward arc) vs shot LOS (strict) ---
## Living/dead soldiers never block spotting. Broad forward arc, not the narrow fire cone.


static func can_spot_enemy(
	observer: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
) -> bool:
	return _spot_score_once(observer, target, game_state, true) >= 0.0


## Single LOS + facing/range pass. Returns visibility score, or -1 if not spotted.
## Uses PerceptionCache — unchanged pairs reuse prior scores.
## force_immediate: skip far-defer (fire / close threats / combat flush warm).
static func _spot_score_once(
	observer: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
	force_immediate: bool = false,
) -> float:
	if observer == null or target == null or target.is_dead or observer.is_dead:
		return -1.0
	if observer.team_id == target.team_id:
		return -1.0
	return PerceptionCacheClass.get_or_compute_spot(
		observer,
		target,
		func() -> float: return _spot_score_compute(observer, target, game_state),
		force_immediate,
	)


static func _spot_score_compute(
	observer: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
) -> float:
	var observer_cell := spotting_cell_for(observer)
	var target_cell := spotting_cell_for(target)
	var weapon := observer.get_weapon_data()
	var spotting_range := _effective_spotting_range(weapon)
	var dist := _manhattan_distance(observer_cell, target_cell)
	## Cheap rejects before LOS raycast.
	if dist > spotting_range:
		return -1.0
	if not ConeOfFireClass.is_facing_toward_target(
		observer_cell,
		observer.facing_direction,
		target_cell,
		spotting_range,
	):
		return -1.0

	var hit_p := GameplayPolicies.hit
	var score := hit_p.vis_score_base - float(dist) * hit_p.vis_score_dist_penalty
	if target.is_moving:
		if target.movement_mode == MovementModeClass.RUN:
			score += hit_p.vis_score_run_bonus
		elif target.movement_mode == MovementModeClass.WALK:
			score += hit_p.vis_score_walk_bonus
	if _target_recently_fired(target):
		score += hit_p.vis_score_recently_fired_bonus
	## Cover only hurts score — if already negative, skip the ray entirely.
	if score < 0.0:
		return -1.0

	var observer_prone := observer.position_state == PositionStateClass.DOWN
	var target_prone := target.position_state == PositionStateClass.DOWN
	## Cover can flip visible→hidden only when score < moderate penalty (then × mult).
	## Above that cutoff, block-only LOS is enough for visible/not + ranking.
	var cover_cutoff := hit_p.vis_score_moderate_cover_penalty
	if score >= cover_cutoff:
		if LOSSystemClass.is_spotting_line_blocked(
			observer_cell,
			target_cell,
			game_state.map_data,
			observer_prone,
			target_prone,
		):
			return -1.0
		return score

	var los := LOSSystemClass.evaluate_spotting(
		observer_cell,
		target_cell,
		game_state.map_data,
		null,
		observer_prone,
		target_prone,
		false,
	)
	if los.status == LOSSystemClass.Status.BLOCKED:
		return -1.0

	if los.cover_type == CoverSystemClass.CoverType.MODERATE:
		score -= hit_p.vis_score_moderate_cover_penalty
	score *= get_cover_visibility_modifier(observer, target, game_state, los)
	return score if score >= 0.0 else -1.0


## Budgeted dirty-pair warm (called every sim tick). Combat scan flushes the rest.
static func process_perception_tick(game_state: GameStateClass) -> void:
	if game_state == null:
		return
	PerceptionCacheClass.process_dirty_budget(
		game_state,
		PerceptionCacheClass.tick_budget(),
		func(obs_team: int, obs_id: int, tgt_team: int, tgt_id: int):
			var observer := game_state.get_soldier(obs_team, obs_id)
			var target := game_state.get_soldier(tgt_team, tgt_id)
			if observer == null or target == null:
				return null
			return {"observer": observer, "target": target},
		func(observer, target) -> float:
			return _spot_score_compute(observer, target, game_state),
	)


static func notify_soldier_perception_dirty(
	game_state: GameStateClass,
	soldier: SoldierStateClass,
) -> void:
	PerceptionCacheClass.mark_soldier_dirty(game_state, soldier)


static func _passes_spotting_checks(
	observer: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
) -> bool:
	return _spot_score_once(observer, target, game_state, true) >= 0.0


static func get_visibility_score(
	observer: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
) -> float:
	## Callers (AI / fire eligibility) need a definitive answer — never defer.
	return _spot_score_once(observer, target, game_state, true)


static func get_cover_visibility_modifier(
	_observer: SoldierStateClass,
	_target: SoldierStateClass,
	_game_state: GameStateClass,
	los: LOSSystemClass.LossResult = null,
) -> float:
	if los != null and los.cover_type == CoverSystemClass.CoverType.MODERATE:
		return GameplayPolicies.cover.moderate_visibility_mult
	return 1.0


static func get_target_visibility_modifier(target: SoldierStateClass) -> float:
	if target == null:
		return 1.0
	if target.position_state == PositionStateClass.DOWN:
		return GameplayPolicies.vision.prone_visibility_mult
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
	var elapsed_sec := (SimulationClock.get_ticks_msec() - seen_msec) / 1000.0
	return elapsed_sec <= GameplayPolicies.hit.recently_seen_sec


static func is_priority_target_trackable(
	observer: SoldierStateClass,
	target: SoldierStateClass,
	game_state: GameStateClass,
) -> bool:
	if not _is_valid_priority_enemy(observer, target):
		return false
	## Prefer the combat-scan observer spot map — avoid a second full LOS ray per shooter.
	var observer_key := ObjectId.team_soldier_key(observer.team_id, observer.soldier_id)
	if _observer_spot_maps.has(observer_key):
		var spots: Dictionary = _observer_spot_maps[observer_key]
		var enemy_key := SoldierStateClass.enemy_tracking_key(target.team_id, target.soldier_id)
		var vis: Variant = spots.get(enemy_key)
		if vis is EnemyVisibilityResult and (vis as EnemyVisibilityResult).visible:
			return true
	elif can_spot_enemy(observer, target, game_state):
		## Cache cold (before first combat scan) — fall back to a live LOS check.
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
		_manhattan_distance(last_pos, click_cell) <= GameplayPolicies.hit.last_known_near_tiles
		or _manhattan_distance(target.grid_position, click_cell) <= GameplayPolicies.hit.last_known_near_tiles
	)


## Read existing visibility caches for AI decisions. Never forces a LOS rebuild —
## combat scan (`update_spotting`) is the only authoritative refresh. Forcing rebuilds
## from every AI think was the main 2v2 hitch that got worse as units kept moving.
static func ensure_visibility_readable(game_state: GameStateClass) -> void:
	if game_state == null:
		return
	_get_team_visibility_cache(game_state, Team.USA)
	_get_team_visibility_cache(game_state, Team.GERMANY)
	_ensure_player_visibility_cache(game_state)


static func update_spotting(game_state: GameStateClass) -> void:
	## Flush remaining dirty pairs, then rebuild team aggregates from the pair cache.
	## last_seen stays combat-scan-only for deterministic FAW track windows.
	PerceptionCacheClass.flush_dirty(
		game_state,
		func(obs_team: int, obs_id: int, tgt_team: int, tgt_id: int):
			var observer := game_state.get_soldier(obs_team, obs_id)
			var target := game_state.get_soldier(tgt_team, tgt_id)
			if observer == null or target == null:
				return null
			return {"observer": observer, "target": target},
		func(observer, target) -> float:
			return _spot_score_compute(observer, target, game_state),
	)
	_force_team_vis_rebuild = true
	## One pass per team from the shared visibility cache (no per-observer re-query loop).
	for fireteam in game_state.session.all_fireteams():
		var team_id: int = fireteam.team_id
		var team_cache := _get_team_visibility_cache(game_state, team_id)
		for enemy_key in team_cache.keys():
			var visibility: EnemyVisibilityResult = team_cache[enemy_key]
			if visibility == null or not visibility.visible:
				continue
			var spotter := game_state.get_soldier(
				visibility.spotter_team_id,
				visibility.spotter_soldier_id,
			)
			var parts := str(enemy_key).split(":")
			if parts.size() < 2 or spotter == null:
				continue
			var enemy := game_state.get_soldier(int(parts[0]), int(parts[1]))
			if enemy != null:
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


## Player-scoped fog of war: own spotting ∪ subordinates' effective_visibility (recursive).
## Separate from LOS — never affects shot blocking. Change-driven via world sig + link revision.
static func get_enemy_visibility_for_player(
	game_state: GameStateClass,
	player_id: int,
	enemy: SoldierStateClass,
) -> EnemyVisibilityResult:
	var empty := EnemyVisibilityResult.new()
	if game_state == null or game_state.command_hierarchy == null:
		return empty
	if enemy == null or enemy.is_dead:
		return empty
	var hierarchy := game_state.command_hierarchy
	if not hierarchy.has_player(player_id):
		return empty
	if enemy.team_id == hierarchy.get_team_id(player_id):
		empty.visible = true
		empty.source = EnemyVisibilityResultClass.Source.DIRECT
		return empty

	var map := effective_visibility(game_state, player_id)
	var enemy_key := SoldierStateClass.enemy_tracking_key(enemy.team_id, enemy.soldier_id)
	if map.has(enemy_key):
		return map[enemy_key]
	return empty


static func is_enemy_visible_to_player(
	game_state: GameStateClass,
	player_id: int,
	enemy: SoldierStateClass,
) -> bool:
	return get_enemy_visibility_for_player(game_state, player_id, enemy).visible


## Cached set of visible enemies for a player (enemy_key -> EnemyVisibilityResult).
## Unions own_visibility with each direct subordinate's effective_visibility when
## COMMAND_VIS_UPWARD_ONLY (commander sees down the chain; subordinate does not see up).
static func effective_visibility(game_state: GameStateClass, player_id: int) -> Dictionary:
	_ensure_player_visibility_cache(game_state)
	if _player_vis_cache.has(player_id):
		return _player_vis_cache[player_id]
	return {}


## Enemy tracking keys currently visible to this player (fog filter for clients).
static func effective_visibility_keys(game_state: GameStateClass, player_id: int) -> Array[String]:
	var out: Array[String] = []
	var map := effective_visibility(game_state, player_id)
	for key in map.keys():
		out.append(str(key))
	out.sort()
	return out


## Players whose SubordVisList changed on the last recompute (empty if unchanged).
static func players_with_visibility_changes() -> Array[int]:
	return _player_vis_changed_ids.duplicate()


## Call when a command link is created/broken (SubordVisTrigger). Forces immediate shrink/grow.
static func notify_command_hierarchy_changed(game_state: GameStateClass = null) -> void:
	_command_link_revision += 1
	_player_vis_cache_sig = -1
	_player_vis_cmd_rev = -1
	_player_vis_cache.clear()
	if game_state != null:
		_ensure_player_visibility_cache(game_state)


static func clear_player_visibility_cache() -> void:
	_player_vis_cache_sig = -1
	_player_vis_cmd_rev = -1
	_player_vis_cache.clear()
	_player_vis_prev_sets.clear()
	_player_vis_changed_ids.clear()
	## Observer maps are tied to team cache lifetime; clear with player cache for safety.
	_observer_spot_maps.clear()
	_team_visibility_cache_key = -1
	_visibility_cache_by_team.clear()
	_last_team_vis_rebuild_msec = -999999
	_force_team_vis_rebuild = false
	PerceptionCacheClass.clear_all()


static func _ensure_player_visibility_cache(game_state: GameStateClass) -> void:
	if game_state == null or game_state.command_hierarchy == null:
		return
	## Ensure team maps exist first (may reuse throttled stale LOS between combat scans).
	_get_team_visibility_cache(game_state, Team.USA)
	_get_team_visibility_cache(game_state, Team.GERMANY)
	var world_sig := _team_visibility_cache_key
	if (
		world_sig == _player_vis_cache_sig
		and _command_link_revision == _player_vis_cmd_rev
		and not _player_vis_cache.is_empty()
	):
		return

	var hierarchy := game_state.command_hierarchy
	var new_cache: Dictionary = {}
	var changed: Array[int] = []
	## Compute leaves-first via memo inside recursive builder with per-player visited guards.
	var memo: Dictionary = {}
	for pid in hierarchy.all_player_ids():
		var visited: Dictionary = {}
		new_cache[pid] = _build_effective_visibility(game_state, pid, visited, memo, 0)
		var new_keys := _visibility_key_set(new_cache[pid])
		var old_keys: Dictionary = _player_vis_prev_sets.get(pid, {})
		if not _visibility_key_sets_equal(old_keys, new_keys):
			changed.append(pid)
		_player_vis_prev_sets[pid] = new_keys

	_player_vis_cache = new_cache
	_player_vis_cache_sig = world_sig
	_player_vis_cmd_rev = _command_link_revision
	_player_vis_changed_ids = changed


static func _build_effective_visibility(
	game_state: GameStateClass,
	player_id: int,
	visited: Dictionary,
	memo: Dictionary,
	depth: int,
) -> Dictionary:
	if memo.has(player_id):
		return memo[player_id]
	if depth >= COMMAND_VIS_DEPTH_GUARD or visited.has(player_id):
		return {}
	visited[player_id] = true

	var result := _own_visibility_map(game_state, player_id)
	var hierarchy := game_state.command_hierarchy
	if COMMAND_VIS_UPWARD_ONLY:
		## Share along the chain upward to commanders: union each direct subordinate recursively.
		for sub_id in hierarchy.get_subordinates(player_id):
			var sub_map := _build_effective_visibility(
				game_state,
				sub_id,
				visited,
				memo,
				depth + 1,
			)
			_merge_visibility_maps(result, sub_map, true)
	else:
		## Alternate (unproven): also pull from commander. Kept as a single-branch switch.
		var cmd_id := hierarchy.get_commander(player_id)
		if cmd_id > 0:
			var cmd_own := _own_visibility_map(game_state, cmd_id)
			_merge_visibility_maps(result, cmd_own, true)

	memo[player_id] = result
	visited.erase(player_id)
	return result


## Spotting from this player's own soldiers only (no command-chain share).
## Reuses per-observer maps filled while building the team visibility cache — no extra LOS.
static func _own_visibility_map(game_state: GameStateClass, player_id: int) -> Dictionary:
	var out: Dictionary = {}
	var hierarchy := game_state.command_hierarchy
	if not hierarchy.has_player(player_id):
		return out
	var team_id := hierarchy.get_team_id(player_id)
	## Ensure team (and observer) maps exist for this team.
	_get_team_visibility_cache(game_state, team_id)
	for soldier_id in hierarchy.get_soldier_ids(player_id):
		var observer_key := ObjectId.team_soldier_key(team_id, soldier_id)
		var spots: Variant = _observer_spot_maps.get(observer_key)
		if not (spots is Dictionary):
			continue
		_merge_visibility_maps(out, spots as Dictionary, false)
	return out


static func _merge_visibility_maps(
	dest: Dictionary,
	src: Dictionary,
	mark_subordinate: bool,
) -> void:
	for key in src.keys():
		var incoming: EnemyVisibilityResult = src[key]
		if incoming == null or not incoming.visible:
			continue
		var existing: EnemyVisibilityResult = dest.get(key)
		if existing != null and existing.visibility_score >= incoming.visibility_score:
			continue
		var copy := EnemyVisibilityResult.new()
		copy.visible = true
		copy.source = (
			EnemyVisibilityResultClass.Source.SUBORDINATE
			if mark_subordinate
			else incoming.source
		)
		copy.visibility_score = incoming.visibility_score
		copy.spotter_team_id = incoming.spotter_team_id
		copy.spotter_soldier_id = incoming.spotter_soldier_id
		dest[key] = copy


static func _visibility_key_set(vis_map: Dictionary) -> Dictionary:
	var keys: Dictionary = {}
	for key in vis_map.keys():
		keys[str(key)] = true
	return keys


static func _visibility_key_sets_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a.keys():
		if not b.has(key):
			return false
	return true


static func _get_team_visibility_cache(
	game_state: GameStateClass,
	observer_team_id: int,
) -> Dictionary:
	var signature := _build_visibility_cache_signature(game_state)
	## Only clear when the world signature changes — never wipe the other team mid-scan.
	## While many soldiers move, signature flips every tick; throttle LOS rebuilds and keep
	## slightly stale maps until combat scan forces a fresh pass.
	if signature != _team_visibility_cache_key:
		var now_msec := SimulationClock.get_ticks_msec()
		var allow_rebuild := (
			_force_team_vis_rebuild
			or _visibility_cache_by_team.is_empty()
			or (now_msec - _last_team_vis_rebuild_msec) >= TEAM_VIS_REBUILD_MIN_MSEC
		)
		if allow_rebuild:
			_team_visibility_cache_key = signature
			_visibility_cache_by_team.clear()
			_visibility_log_keys.clear()
			_observer_spot_maps.clear()
			_last_team_vis_rebuild_msec = now_msec
			_force_team_vis_rebuild = false
			## Player fog must rebuild against the new observer maps.
			_player_vis_cache_sig = -1
	if not _visibility_cache_by_team.has(observer_team_id):
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

	## Seed empty per-observer maps for living observers on this team.
	for observer_state in observer_fireteam.soldiers:
		var observer: SoldierStateClass = observer_state
		if observer.is_dead:
			continue
		var observer_key := ObjectId.team_soldier_key(observer.team_id, observer.soldier_id)
		if not _observer_spot_maps.has(observer_key):
			_observer_spot_maps[observer_key] = {}

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
			var dist := _manhattan_distance(observer.grid_position, enemy.grid_position)
			## Close pairs always resolve now; far misses defer into the dirty budget.
			var score := _spot_score_once(
				observer,
				enemy,
				game_state,
				dist <= PerceptionCacheClass.CLOSE_FORCE_DIST,
			)
			if score < 0.0:
				continue
			var observer_key := ObjectId.team_soldier_key(observer.team_id, observer.soldier_id)
			var spot := EnemyVisibilityResult.new()
			spot.visible = true
			spot.source = EnemyVisibilityResultClass.Source.DIRECT
			spot.visibility_score = score
			spot.spotter_team_id = observer.team_id
			spot.spotter_soldier_id = observer.soldier_id
			var obs_map: Dictionary = _observer_spot_maps[observer_key]
			obs_map[enemy_key] = spot
			_observer_spot_maps[observer_key] = obs_map
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
			## Already scored every observer once — no second LOS pass.
			result.visibility_score = -1.0

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


## Cheap int hash of soldier cells/facing/alive — no string allocs on the hot path.
static func _build_visibility_cache_signature(game_state: GameStateClass) -> int:
	var h := 17
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier: SoldierStateClass = state
			var cell := spotting_cell_for(soldier)
			h = _mix_hash(h, soldier.team_id)
			h = _mix_hash(h, soldier.soldier_id)
			h = _mix_hash(h, cell.x)
			h = _mix_hash(h, cell.y)
			h = _mix_hash(h, soldier.facing_direction.x)
			h = _mix_hash(h, soldier.facing_direction.y)
			h = _mix_hash(h, int(soldier.is_dead))
	for key in _spotting_cell_overrides.keys():
		var snap: Vector2i = _spotting_cell_overrides[key]
		h = _mix_hash(h, hash(str(key)))
		h = _mix_hash(h, snap.x)
		h = _mix_hash(h, snap.y)
	return h


static func _mix_hash(h: int, value: int) -> int:
	## Keep in signed 31-bit range for stable Dictionary keys across platforms.
	return int((h * 31 + value) & 0x7fffffff)


static func _visibility_source_name(source: int) -> String:
	match source:
		EnemyVisibilityResultClass.Source.DIRECT:
			return "direct"
		EnemyVisibilityResultClass.Source.CLUSTER:
			return "cluster"
		EnemyVisibilityResultClass.Source.SUBORDINATE:
			return "subordinate"
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
	return (SimulationClock.get_ticks_msec() - target.last_fired_msec) / 1000.0 <= GameplayPolicies.hit.recently_fired_spot_sec


static func find_closest_visible_enemy(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
) -> SoldierStateClass:
	return find_best_auto_target(game_state, shooter)


## Fire At Will: highest-scored spotted/shootable enemy in weapon range (clear LOS required).
## Facing cone is not required to acquire — shooters turn toward the pick before firing.
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
	## Prefer already-spotted enemies from the team cache — avoids O(enemies) fresh
	## spotting LOS before the shot LOS in score_auto_target (critical in 2v2 8v8).
	var team_cache := _get_team_visibility_cache(game_state, shooter.team_id)

	for state in enemy_fireteam.soldiers:
		var enemy: SoldierStateClass = state
		if enemy.is_dead:
			continue
		var enemy_key := SoldierStateClass.enemy_tracking_key(enemy.team_id, enemy.soldier_id)
		var vis: EnemyVisibilityResult = team_cache.get(enemy_key)
		if vis == null or not vis.visible:
			continue
		if _combat_range(shooter.grid_position, enemy.grid_position) > float(max_range):
			continue
		## score_auto_target does the single shot-LOS pass (no prior can_spot_enemy).
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

	var shot: Dictionary = PerceptionCacheClass.get_or_compute_shot(
		shooter,
		target,
		func() -> Dictionary:
			var los := LOSSystemClass.evaluate(
				shooter.grid_position,
				target.grid_position,
				game_state.map_data,
				game_state,
			)
			return {
				"blocked": los.status == LOSSystemClass.Status.BLOCKED,
				"status": los.status,
				"cover_type": los.cover_type,
				"target_using_wall_cover": los.target_using_wall_cover,
			},
	)
	if bool(shot.get("blocked", true)):
		return -1.0
	if bool(shot.get("target_using_wall_cover", false)):
		return -1.0

	var dist := _combat_range(shooter.grid_position, target.grid_position)
	var hit_p := GameplayPolicies.hit
	var score := hit_p.auto_score_base - dist * hit_p.auto_score_dist_penalty
	var cover_type: int = int(shot.get("cover_type", CoverSystemClass.CoverType.NONE))

	if cover_type == CoverSystemClass.CoverType.NONE:
		score += hit_p.auto_score_clear_bonus
	elif cover_type == CoverSystemClass.CoverType.MODERATE:
		score -= hit_p.auto_score_moderate_penalty
	else:
		score -= hit_p.auto_score_complete_penalty

	if target.is_moving:
		score += hit_p.auto_score_moving_bonus

	if target.position_state == PositionStateClass.DOWN:
		score -= hit_p.auto_score_prone_penalty

	var aim_dir := FacingDirection.toward_cell(shooter.grid_position, target.grid_position)
	if aim_dir == shooter.facing_direction:
		score += hit_p.auto_score_facing_bonus

	var target_weapon := target.get_weapon_data()
	if target_weapon != null:
		match target_weapon.weapon_type:
			WeaponTypeClass.SMG, WeaponTypeClass.LMG:
				score += hit_p.auto_score_smg_lmg_bonus

	if (
		shooter.engaged_target_team_id == target.team_id
		and shooter.engaged_target_soldier_id == target.soldier_id
	):
		score += GameplayPolicies.hit.auto_target_engaged_bonus

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
		var dist := _combat_range(shooter.grid_position, enemy.grid_position)
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
		var dist := _combat_range(shooter.grid_position, enemy.grid_position)
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
		var dist := _combat_range(shooter.grid_position, enemy.grid_position)
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
	shooter: SoldierStateClass,
	target: SoldierStateClass,
	weapon: WeaponDataClass,
	los: LOSSystemClass.LossResult,
) -> void:
	if target == null or target.is_dead or weapon == null or shooter == null:
		return
	if los.status == LOSSystemClass.Status.BLOCKED:
		return

	var policy := GameplayPolicies.suppression
	var range_tiles := int(round(_combat_range(shooter.grid_position, target.grid_position)))
	var gain := _suppression_stress_gain(weapon, range_tiles)
	if gain <= 0.0:
		return
	var cover_mult := 1.0
	if los.cover_type == CoverSystemClass.CoverType.MODERATE:
		cover_mult = policy.moderate_cover_suppression_mult
	var stance_mult := 1.0
	if target.position_state == PositionStateClass.DOWN:
		stance_mult = policy.prone_suppression_mult
	gain *= cover_mult * stance_mult
	if gain <= 0.0:
		return
	var cap := minf(policy.max_stress, policy.weapon_stress_cap_runtime(weapon.stress_limit))
	target.stress = clampf(target.stress + gain, 0.0, cap)
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
	var policy := GameplayPolicies.suppression
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier: SoldierStateClass = state
			if soldier.is_dead or soldier.stress <= 0.0:
				continue
			if soldier.received_suppression_this_tick:
				continue
			var prone := soldier.position_state == PositionStateClass.DOWN
			soldier.stress = policy.apply_stress_decay(soldier.stress, prone)


static func _suppression_stress_gain(weapon: WeaponDataClass, range_tiles: int) -> float:
	## RECOVERED: (stress_limit_tiles − range) × StressFactor → runtime via STRESS_SCALE.
	var policy := GameplayPolicies.suppression
	if weapon == null:
		return policy.range_suppression_gain_runtime(
			policy.suppression_default,
			SuppressionPolicyClass.DEFAULT_STRESS_LIMIT_TILES,
			range_tiles,
		)
	return policy.range_suppression_gain_runtime(
		weapon.suppression_generated,
		weapon.stress_limit_tiles,
		range_tiles,
	)


## Stress represents suppression/combat pressure and reduces firing effectiveness.
## Uses Exp-Str × Range table (normalized); optional mid-range legacy call.
static func get_stress_accuracy_modifier(stress: float, distance_tiles: int = 3) -> float:
	return GameplayPolicies.suppression.accuracy_modifier_for(stress, distance_tiles, 1.0)


static func get_stress_movement_modifier(stress: float) -> float:
	return GameplayPolicies.suppression.movement_modifier(stress)


static func get_stress_fire_delay_modifier(stress: float) -> float:
	return GameplayPolicies.suppression.fire_delay_modifier(stress)


static func get_stress_state_label(stress: float) -> String:
	return StressLabelsClass.state_label(stress)


static func is_stress_pinned(stress: float) -> bool:
	return stress >= GameplayPolicies.suppression.pinned_threshold


static func is_stress_panicked(stress: float) -> bool:
	return stress >= GameplayPolicies.suppression.panic_threshold


static func _stress_band(stress: float) -> int:
	return GameplayPolicies.suppression.stress_band(stress)


static func _final_hit_chance(
	shooter: SoldierStateClass,
	target: SoldierStateClass,
	weapon: WeaponDataClass,
	los: LOSSystemClass.LossResult,
	out_breakdown = null,
) -> float:
	var marksman := shooter.marksman if shooter != null else 0.0
	var base_chance := hit_chance(
		shooter.grid_position,
		target.grid_position,
		weapon,
		marksman,
	)
	var dist := _combat_range(shooter.grid_position, target.grid_position)
	var chance := base_chance
	var cover_mult := 1.0
	var move_type_mult := 1.0
	var move_angle_mult := 1.0
	var in_cover := (
		los.cover_type == CoverSystemClass.CoverType.MODERATE
		or los.cover_type == CoverSystemClass.CoverType.COMPLETE
	)
	## Cover curve when covered; open-ground movement/angle only when not.
	if in_cover:
		cover_mult = GameplayPolicies.cover.cover_multiplier_for_range(dist)
		chance = base_chance * cover_mult
	elif target != null and target.is_moving:
		var move_pol := GameplayPolicies.movement
		move_type_mult = move_pol.type_multiplier(target.movement_mode)
		chance *= move_type_mult
		## Sine crossing term only while running.
		if target.movement_mode == MovementModeClass.RUN:
			move_angle_mult = move_pol.angle_hit_multiplier(
				shooter.facing_direction,
				target.movement_heading(),
				target.movement_mode,
			)
			chance *= move_angle_mult
	var aim_factor := weapon.stress_aim_factor if weapon != null else 1.0
	var stress_mult := GameplayPolicies.suppression.accuracy_modifier_for(
		shooter.stress,
		int(round(dist)),
		aim_factor,
	)
	chance *= stress_mult
	var shooter_prone_mult := 1.0
	var target_prone_mult := 1.0
	if shooter.position_state == PositionStateClass.DOWN:
		shooter_prone_mult = GameplayPolicies.hit.shooter_prone_accuracy_mult
		chance *= shooter_prone_mult
	if target.position_state == PositionStateClass.DOWN:
		target_prone_mult = GameplayPolicies.hit.target_prone_hit_mult
		chance *= target_prone_mult
	var final_chance := clampf(chance, 0.0, 1.0)
	if out_breakdown is Dictionary:
		out_breakdown["base"] = base_chance
		out_breakdown["cover_mult"] = cover_mult
		out_breakdown["move_type_mult"] = move_type_mult
		out_breakdown["move_angle_mult"] = move_angle_mult
		out_breakdown["stress_mult"] = stress_mult
		out_breakdown["shooter_prone_mult"] = shooter_prone_mult
		out_breakdown["target_prone_mult"] = target_prone_mult
		out_breakdown["final"] = final_chance
		out_breakdown["range"] = dist
		out_breakdown["lethality"] = GameplayPolicies.hit.lethality_multiplier
	## Cover / prone / suppression may push below min_hit_chance — that floor
	## applies only to base hit_chance(), not after situational multipliers.
	return final_chance


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

	## Cheap weapon/cooldown rejects before target trackability (which may raycast).
	if shooter.ammo_current <= 0:
		return empty
	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return empty
	if not _is_fire_prep_complete(shooter):
		return empty
	if not _can_fire_yet(shooter, weapon):
		return empty

	var target := _resolve_engaged_target(game_state, shooter)
	if target == null:
		return empty

	if not is_facing_target(shooter, target):
		var fireteam := game_state.session.get_fireteam(shooter.team_id)
		fireteam.face_toward_tile(shooter.soldier_id, target.grid_position)
		return empty

	var max_range := _effective_weapon_range(weapon)
	if _combat_range(shooter.grid_position, target.grid_position) > float(max_range):
		return empty

	## resolve_shot evaluates LOS once — do not pre-check with is_shot_blocked (was 2× rays).
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
	## Fire At Will: acquire → aim/fire cycle → fire → restart cycle on same target.
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


## Aim/fire cycle seconds: per-weapon fire_interval_sec override, else global base.
static func effective_fire_cycle_sec(weapon: WeaponDataClass) -> float:
	if weapon != null and weapon.fire_interval_sec > 0.0:
		return weapon.fire_interval_sec
	return GameplayPolicies.hit.base_fire_cycle_sec


static func begin_fire_prep(shooter: SoldierStateClass) -> void:
	## Single aim/fire cycle (not stacked aim + interval). Stress scales the cycle.
	var weapon := shooter.get_weapon_data()
	var delay_sec := effective_fire_cycle_sec(weapon)
	delay_sec *= get_stress_fire_delay_modifier(shooter.stress)
	shooter.fire_ready_after_msec = SimulationClock.get_ticks_msec() + int(delay_sec * 1000.0)


static func get_aim_delay_sec(shooter: SoldierStateClass) -> float:
	## Alias of the fire cycle (UI "firing in Xs"); not a separate acquisition delay.
	var weapon := shooter.get_weapon_data()
	return effective_fire_cycle_sec(weapon) * get_stress_fire_delay_modifier(shooter.stress)


static func get_fire_cooldown_remaining(
	shooter: SoldierStateClass,
	weapon: WeaponDataClass,
) -> float:
	if shooter == null:
		return 0.0
	if shooter.fire_ready_after_msec > 0:
		var remaining_prep := (shooter.fire_ready_after_msec - SimulationClock.get_ticks_msec()) / 1000.0
		if remaining_prep > 0.0:
			return remaining_prep
	if weapon == null or shooter.last_shot_msec <= 0:
		return 0.0
	var interval_sec := effective_fire_cycle_sec(weapon) * get_stress_fire_delay_modifier(shooter.stress)
	var elapsed_sec := (SimulationClock.get_ticks_msec() - shooter.last_shot_msec) / 1000.0
	return maxf(0.0, interval_sec - elapsed_sec)


static func _is_fire_prep_complete(shooter: SoldierStateClass) -> bool:
	if shooter.fire_ready_after_msec <= 0:
		return false
	return SimulationClock.get_ticks_msec() >= shooter.fire_ready_after_msec


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


## Base hit chance before cover / prone / suppression.
## RECOVERED quotient: hit_scale × (aim_factor_sqr·AimTime² + …) / (cub·D³ + pent·D⁵)
## D = max(ε, EuclideanRange − MarksMan). min_hit_chance floors here only.
static func hit_chance(
	from_cell: Vector2i,
	to_cell: Vector2i,
	weapon: WeaponDataClass,
	marksman: float = 0.0,
) -> float:
	var hit_policy := GameplayPolicies.hit
	if weapon == null:
		return hit_policy.min_hit_chance
	var range_tiles := _combat_range(from_cell, to_cell)
	var d := maxf(hit_policy.range_epsilon, range_tiles - marksman)
	var denom := weapon.hit_denominator(d)
	if denom <= 0.0:
		return hit_policy.min_hit_chance
	var chance := hit_policy.hit_scale * weapon.hit_numerator(hit_policy.aim_time) / denom
	return clampf(chance, hit_policy.min_hit_chance, 1.0)


static func _can_fire_yet(
	shooter: SoldierStateClass,
	weapon: WeaponDataClass,
) -> bool:
	## Cycle gate is normally fire_ready_after_msec (begin_fire_prep after each shot).
	## last_shot fallback covers callers that skip prep (manual resolve_shot in tests).
	if weapon == null:
		return false
	if shooter.last_shot_msec <= 0:
		return true
	var interval_sec := effective_fire_cycle_sec(weapon) * get_stress_fire_delay_modifier(shooter.stress)
	var elapsed_sec := (SimulationClock.get_ticks_msec() - shooter.last_shot_msec) / 1000.0
	return elapsed_sec >= interval_sec


static func _manhattan_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	## Pathfinding / click-near helpers. Combat range uses _combat_range (Euclidean).
	return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)


## Euclidean tile distance for combat (hit chance, suppression range, engagement).
static func _combat_range(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var dx := float(to_cell.x - from_cell.x)
	var dy := float(to_cell.y - from_cell.y)
	return sqrt(dx * dx + dy * dy)


static func _effective_weapon_range(weapon: WeaponDataClass) -> int:
	## Engagement envelope only — hit falloff is the polynomial, not a hard weapon cap.
	var envelope := GameplayPolicies.hit.max_engagement_tiles
	if weapon != null:
		envelope = maxi(envelope, weapon.range_tiles)
	return ConeOfFireClass.effective_range(envelope)


static func _effective_spotting_range(weapon: WeaponDataClass) -> int:
	return _effective_weapon_range(weapon) + GameplayPolicies.hit.spotting_range_bonus


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
	if _combat_range(shooter.grid_position, target.grid_position) > float(max_range):
		return false
	return _is_target_in_cone(shooter, target.grid_position, max_range)


static func _is_auto_target_valid(
	game_state: GameStateClass,
	shooter: SoldierStateClass,
	target: SoldierStateClass,
) -> bool:
	## Keep engagement while spotted/shootable in range; shooter turns as needed.
	if not is_priority_target_trackable(shooter, target, game_state):
		return false
	var weapon := shooter.get_weapon_data()
	if weapon == null:
		return false
	var max_range := _effective_weapon_range(weapon)
	if _combat_range(shooter.grid_position, target.grid_position) > float(max_range):
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


## True when a living same-team soldier (including the thrower) is inside the blast.
static func grenade_would_hit_friendly(
	game_state: GameStateClass,
	thrower_team_id: int,
	explosion_cell: Vector2i,
) -> bool:
	if game_state == null or game_state.session == null:
		return false
	var radius := GameplayPolicies.grenade.blast_radius
	for fireteam in game_state.session.all_fireteams():
		if fireteam == null or fireteam.team_id != thrower_team_id:
			continue
		for state in fireteam.soldiers:
			var soldier: SoldierStateClass = state
			if soldier == null or soldier.is_dead:
				continue
			if _chebyshev_distance(soldier.grid_position, explosion_cell) <= radius:
				return true
	return false


## Grenade blast resolution — Chebyshev radius; cover ignored for V1.
## Same-team soldiers are never killed or stunned (friendly fire off for nades).
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
	result.blast_radius = GameplayPolicies.grenade.blast_radius

	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier: SoldierStateClass = state
			if soldier.is_dead:
				continue
			## Own / friendly team — never affected by this thrower's blast.
			if soldier.team_id == thrower.team_id:
				continue

			var distance := _chebyshev_distance(soldier.grid_position, explosion_cell)
			if distance > GameplayPolicies.grenade.blast_radius:
				continue

			if distance <= GameplayPolicies.grenade.kill_radius:
				if GameRandom.chance(GameplayPolicies.grenade.kill_chance):
					soldier.mark_killed()
					notify_soldier_perception_dirty(game_state, soldier)
					ScenarioRulesClass.on_soldier_killed(game_state, thrower.team_id, soldier)
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
	soldier.apply_grenade_stun(GameplayPolicies.grenade.stun_duration_sec)


static func _chebyshev_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return maxi(absi(from_cell.x - to_cell.x), absi(from_cell.y - to_cell.y))
