class_name ActionResolver
extends RefCounted
## Single entry point for mutating authoritative GameState.
##
## Flow (OFFLINE_DEV):
##   Input/UI → CommandRouter → ActionResolver → GameState → visuals
##
## CombatSystem, CoverSystem, and LOSSystem are called from here; they never touch nodes.

const GameStateClass := preload("res://scripts/core/game_state.gd")
const MoveCommandClass := preload("res://scripts/commands/move_command.gd")
const FaceCommandClass := preload("res://scripts/commands/face_command.gd")
const FireCommandClass := preload("res://scripts/commands/fire_command.gd")
const PositionCommandClass := preload("res://scripts/commands/position_command.gd")
const FireControlCommandClass := preload("res://scripts/commands/fire_control_command.gd")
const GrenadeCommandClass := preload("res://scripts/commands/grenade_command.gd")
const AssignCommanderCommandClass := preload("res://scripts/commands/assign_commander_command.gd")
const BreakCommandLinkCommandClass := preload("res://scripts/commands/break_command_link_command.gd")
const SetMissionCommanderCommandClass := preload("res://scripts/commands/set_mission_commander_command.gd")
const AssignWeaponCommandClass := preload("res://scripts/commands/assign_weapon_command.gd")
const ReturnWeaponCommandClass := preload("res://scripts/commands/return_weapon_command.gd")
const CommandHierarchyClass := preload("res://scripts/core/command_hierarchy.gd")
const WeaponCacheClass := preload("res://scripts/core/weapon_cache.gd")
const CombatGrenadeResultClass := preload("res://scripts/combat/combat_grenade_result.gd")
const MapEditorClass := preload("res://scripts/map/map_editor.gd")
const MapDataClass := preload("res://scripts/map/map_data.gd")
const GameSaveClass := preload("res://scripts/core/game_save.gd")
const MovementModeClass := preload("res://scripts/enums/movement_mode.gd")
const PositionStateClass := preload("res://scripts/enums/position_state.gd")
const FireControlStateClass := preload("res://scripts/enums/fire_control_state.gd")
const ConeOfFireClass := preload("res://scripts/combat/cone_of_fire.gd")
const CombatShotResultClass := preload("res://scripts/combat/combat_shot_result.gd")
const LOSSystemClass := preload("res://scripts/combat/los_system.gd")


static func execute(
	game_state: GameStateClass,
	command: RefCounted,
	context: CommandContext = null,
) -> ActionResult:
	_log_action("execute %s" % _command_type_name(command))
	if command is MoveCommandClass:
		return execute_move(game_state, command as MoveCommandClass, context)
	if command is FaceCommandClass:
		return execute_face(game_state, command as FaceCommandClass)
	if command is FireCommandClass:
		return execute_fire(game_state, command as FireCommandClass, context)
	if command is PositionCommandClass:
		return execute_position(game_state, command as PositionCommandClass)
	if command is FireControlCommandClass:
		return execute_fire_control(game_state, command as FireControlCommandClass)
	if command is GrenadeCommandClass:
		return execute_grenade(game_state, command as GrenadeCommandClass, context)
	if command is AssignCommanderCommandClass:
		return execute_assign_commander(game_state, command as AssignCommanderCommandClass)
	if command is BreakCommandLinkCommandClass:
		return execute_break_command_link(game_state, command as BreakCommandLinkCommandClass)
	if command is SetMissionCommanderCommandClass:
		return execute_set_mission_commander(
			game_state,
			command as SetMissionCommanderCommandClass,
		)
	if command is AssignWeaponCommandClass:
		return execute_assign_weapon(game_state, command as AssignWeaponCommandClass)
	if command is ReturnWeaponCommandClass:
		return execute_return_weapon(game_state, command as ReturnWeaponCommandClass)
	return ActionResult.fail("Unknown command type.")


## One-time match bootstrap: face teams toward each other, Hold Fire on all soldiers.
static func apply_match_start_setup(game_state: GameStateClass) -> void:
	var usa_team: Fireteam = game_state.session.blue_team
	var germany_team: Fireteam = game_state.session.red_team
	for i in range(mini(usa_team.soldiers.size(), germany_team.soldiers.size())):
		var usa_soldier: SoldierState = usa_team.soldiers[i]
		var germany_soldier: SoldierState = germany_team.soldiers[i]
		usa_soldier.facing_direction = FacingDirection.toward_cell(
			usa_soldier.grid_position,
			germany_soldier.grid_position,
		)
		germany_soldier.facing_direction = FacingDirection.toward_cell(
			germany_soldier.grid_position,
			usa_soldier.grid_position,
		)
		usa_soldier.fire_control_state = FireControlStateClass.HOLD_FIRE
		germany_soldier.fire_control_state = FireControlStateClass.HOLD_FIRE


## Dev map editor: toggle a blocker tile on authoritative map_data.
static func toggle_map_block(game_state: GameStateClass, cell: Vector2i) -> ActionResult:
	if not game_state.map_data.is_in_bounds(cell):
		return ActionResult.fail("That tile is outside the map.")

	var is_now_blocked: bool = game_state.map_data.toggle_blocked(cell)
	if is_now_blocked:
		game_state.objects.register_map_object(
			cell,
			game_state.map_data.get_object_type(cell),
		)
	else:
		game_state.objects.unregister_map_object(cell)
	var result := ActionResult.new()
	result.refresh_map_data = true
	result.refresh_views = false
	if is_now_blocked:
		return result.set_status("Blocked tile %s." % cell)
	return result.set_status("Unblocked tile %s." % cell)


## Dev map editor: place or erase a map object on authoritative map_data.
static func apply_map_edit(
	game_state: GameStateClass,
	cell: Vector2i,
	palette: int,
	erase: bool,
) -> ActionResult:
	if not game_state.map_data.is_in_bounds(cell):
		return ActionResult.fail("That tile is outside the map.")

	var result := ActionResult.new()
	result.refresh_map_data = true
	result.refresh_views = false

	if erase or palette == MapEditorClass.Palette.ERASE:
		game_state.map_data.clear_object(cell)
		game_state.objects.unregister_map_object(cell)
		_log_action("map edit erase %s" % cell)
		return result.set_status("Erased tile %s." % cell)

	var type_id := MapEditorClass.palette_type_id(palette)
	if type_id.is_empty():
		return ActionResult.fail("Unknown map edit palette.")

	game_state.map_data.set_object(cell, type_id)
	game_state.objects.register_map_object(cell, type_id)
	_log_action("map edit place %s=%s" % [cell, type_id])
	return result.set_status("Placed %s at %s." % [type_id, cell])


## Replace authoritative map_data from the default map file (dev tool).
static func reload_map_from_file(game_state: GameStateClass) -> ActionResult:
	var map_data: MapData = MapDataClass.load_from_file()
	game_state.map_data = map_data
	game_state.rebuild_object_registry()
	_log_action("reload map from file")
	var result := ActionResult.new()
	result.refresh_map_data = true
	result.refresh_views = true
	return result.set_status("Map loaded from res://maps/test_map.json")


## Restore soldier/session snapshot from disk into the live GameState session.
static func load_saved_session(
	game_state: GameStateClass,
	file_path: String = GameSaveClass.DEFAULT_PATH,
) -> ActionResult:
	if not GameSaveClass.load_game(game_state.session, file_path):
		return ActionResult.fail("Load failed.")
	game_state.rebuild_object_registry()
	_log_action("load saved session")
	var result := ActionResult.new()
	result.refresh_views = true
	return result.set_status("Game loaded.")


## UI prep before move orders: sets movement_mode (and stands prone soldiers for Run).
static func arm_movement_mode(
	game_state: GameStateClass,
	team_id: int,
	soldier_id: int,
	movement_mode: int,
) -> ActionResult:
	var fireteam := game_state.session.get_fireteam(team_id)
	var lines: Array[String] = []

	# CommandBar.SQUAD_ID == 0
	if soldier_id == 0:
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.is_alive():
				var line := arm_movement_mode_for_soldier(soldier_state, movement_mode)
				if not line.is_empty():
					lines.append(line)
	else:
		var soldier: SoldierState = fireteam.get_soldier(soldier_id)
		var line := arm_movement_mode_for_soldier(soldier, movement_mode)
		if not line.is_empty():
			lines.append(line)

	if lines.is_empty():
		return ActionResult.fail("Soldier unavailable.")

	var result := ActionResult.new()
	result.refresh_views = false
	return result.set_status("\n".join(lines))


## Authoritative movement step — updates grid_position and facing.
## Called from process_movement_tick (sim) or tests; never from render interpolation.
static func on_movement_step(
	game_state: GameStateClass,
	team_id: int,
	soldier_id: int,
	tile: Vector2i,
	step_delta: Vector2i,
) -> void:
	game_state.session.get_fireteam(team_id).on_soldier_reached_tile(soldier_id, tile, step_delta)


## Authoritative movement finished — clears path flags on SoldierState.
static func on_movement_complete(
	game_state: GameStateClass,
	team_id: int,
	soldier_id: int,
) -> void:
	game_state.session.get_fireteam(team_id).on_soldier_finished_moving(soldier_id)


## Advance all in-progress paths by one simulation tick. Presentation-free.
static func process_movement_tick(game_state: GameStateClass) -> ActionResult:
	var result := ActionResult.new()
	result.refresh_views = false
	var tick_msec := SimulationClock.tick_msec()
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier: SoldierState = state
			if soldier == null or soldier.is_dead or not soldier.is_moving:
				continue
			_advance_soldier_movement(game_state, soldier, tick_msec, result)
	if not result.movement_steps.is_empty() or not result.movement_completions.is_empty():
		## Movers are synced in Main._present_movement_tick_result; avoid a full roster
		## refresh every step (that was a major gameplay hitch).
		result.refresh_views = false
	return result


static func _advance_soldier_movement(
	game_state: GameStateClass,
	soldier: SoldierState,
	tick_msec: int,
	result: ActionResult,
) -> void:
	if soldier.current_path.size() < 2 or soldier.path_index <= 0:
		on_movement_complete(game_state, soldier.team_id, soldier.soldier_id)
		result.movement_completions.append({
			"team_id": soldier.team_id,
			"soldier_id": soldier.soldier_id,
		})
		return

	soldier.move_accum_msec += tick_msec
	## Multiple tiles may complete in one tick if speed is high or hitch catch-up is large.
	while soldier.is_moving and soldier.move_accum_msec >= soldier.move_step_cost_msec:
		soldier.move_accum_msec -= soldier.move_step_cost_msec
		var from_cell := soldier.current_path[soldier.path_index - 1]
		var to_cell := soldier.current_path[soldier.path_index]
		## Never advance onto climb/NoPass (stale paths / bad pathfinder results).
		if game_state.map_data != null and game_state.map_data.is_blocked(to_cell):
			on_movement_complete(game_state, soldier.team_id, soldier.soldier_id)
			result.movement_completions.append({
				"team_id": soldier.team_id,
				"soldier_id": soldier.soldier_id,
			})
			return
		var step_delta := to_cell - from_cell
		on_movement_step(game_state, soldier.team_id, soldier.soldier_id, to_cell, step_delta)
		result.movement_steps.append({
			"team_id": soldier.team_id,
			"soldier_id": soldier.soldier_id,
			"tile": to_cell,
			"step_delta": step_delta,
		})
		soldier.path_index += 1
		if soldier.path_index >= soldier.current_path.size():
			on_movement_complete(game_state, soldier.team_id, soldier.soldier_id)
			result.movement_completions.append({
				"team_id": soldier.team_id,
				"soldier_id": soldier.soldier_id,
			})
			return
		soldier.move_step_cost_msec = MovementPolicy.step_cost_msec(
			soldier.current_path[soldier.path_index - 1],
			soldier.current_path[soldier.path_index],
			soldier.move_speed_mult,
		)


## Periodic combat tick: sustained Fire At (priority) + Fire At Will (auto) + stress recovery.
static func process_combat_tick(game_state: GameStateClass) -> ActionResult:
	var result := ActionResult.new()
	result.refresh_views = false

	CombatSystem.clear_suppression_tick_flags(game_state)
	CombatSystem.update_spotting(game_state)

	var now_msec := SimulationClock.get_ticks_msec()
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var thrower: SoldierState = state
			if thrower.grenade_explode_at_msec <= 0:
				continue
			if now_msec < thrower.grenade_explode_at_msec:
				continue

			var explosion_cell := thrower.pending_grenade_target
			game_state.objects.unregister_grenade(ObjectId.grenade(thrower.team_id, thrower.soldier_id))
			thrower.clear_pending_grenade()
			var grenade_result: CombatGrenadeResultClass = CombatSystem.resolve_grenade(
				game_state,
				thrower,
				explosion_cell,
			)
			result.grenade_explosions.append(grenade_result)
			result.refresh_views = true
			_append_grenade_movement_halts(game_state, grenade_result, result)

	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var shooter: SoldierState = state
			if not shooter.is_sustained_fire():
				continue
			if shooter.is_stunned() or shooter.has_pending_grenade():
				continue
			var shot: CombatShotResultClass = CombatSystem.try_engaged_fire(game_state, shooter)
			if shot.fired:
				result.combat_shots.append(shot)
				result.refresh_views = true

	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var shooter: SoldierState = state
			if shooter.is_sustained_fire():
				continue
			if shooter.is_stunned() or shooter.has_pending_grenade():
				continue
			var shot: CombatShotResultClass = CombatSystem.try_auto_engagement(game_state, shooter)
			if shot.fired:
				result.combat_shots.append(shot)
				result.refresh_views = true

	CombatSystem.recover_stress_tick(game_state, GameplayPolicies.hit.auto_fire_scan_interval)

	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier: SoldierState = state
			soldier.recover_from_stun_if_expired()

	game_state.objects.sync_grenades_from(game_state)
	## Do not force a full view refresh every combat scan — shots/explosions already
	## set refresh_views. Spotting/stress UI updates via the combat_tick path in Main.

	if not result.combat_shots.is_empty() or not result.grenade_explosions.is_empty():
		result.sync_fire_at_ui = true
		_log_action(
			"combat tick: %d shot(s), %d explosion(s)"
			% [result.combat_shots.size(), result.grenade_explosions.size()]
		)
	return result


static func execute_move(
	game_state: GameStateClass,
	cmd: MoveCommandClass,
	context: CommandContext,
) -> ActionResult:
	if context == null or not context.find_path.is_valid():
		return ActionResult.fail("Move command requires a pathfinder in CommandContext.")

	if not game_state.map_data.is_walkable(cmd.target_cell):
		if game_state.map_data.is_blocked(cmd.target_cell):
			return ActionResult.fail("That tile is blocked.")
		return ActionResult.fail("That tile is outside the map.")

	var fireteam := game_state.session.get_fireteam(cmd.team_id)
	var result := ActionResult.new()

	if cmd.scope == MoveCommandClass.Scope.SQUAD:
		var ordered_count := 0
		var notices: Array[String] = []
		var squad_mode_label := MovementModeClass.display_name(cmd.movement_mode).to_lower()
		for state in fireteam.soldiers:
			var squad_soldier: SoldierState = state
			if not _can_local_order_soldier(game_state, cmd.team_id, squad_soldier.soldier_id):
				continue
			var squad_move_result := _resolve_move_order(squad_soldier, cmd.movement_mode)
			if squad_move_result.rejected:
				if not squad_move_result.message.is_empty():
					notices.append(squad_move_result.message)
				continue
			if _assign_move_path(
				game_state, context, fireteam, squad_soldier,
				cmd, result, squad_move_result.mode, squad_move_result.message,
			):
				ordered_count += 1
				if not squad_move_result.message.is_empty():
					notices.append(squad_move_result.message)
		if ordered_count == 0:
			if not notices.is_empty():
				return ActionResult.fail(notices[0])
			return ActionResult.fail("No soldiers could %s to that tile." % squad_mode_label)
		result.path_overlay = {"cells": [] as Array[Vector2i], "target": cmd.target_cell}
		var squad_status := "%s fireteam %s to %s — click another tile to redirect." % [
			Team.display_name(cmd.team_id), squad_mode_label, cmd.target_cell,
		]
		if not notices.is_empty():
			squad_status += "\n" + "\n".join(notices)
		return result.set_status(squad_status)

	if not _can_local_order_soldier(game_state, cmd.team_id, cmd.soldier_id):
		return ActionResult.fail("That soldier is not under your control.")

	var soldier_state: SoldierState = fireteam.get_soldier(cmd.soldier_id)
	if soldier_state == null:
		return ActionResult.fail("Soldier unavailable.")

	var move_result := _resolve_move_order(soldier_state, cmd.movement_mode)
	if move_result.rejected:
		return ActionResult.fail(move_result.message)

	var mode_label := MovementModeClass.display_name(move_result.mode).to_lower()
	var validation := _validate_move(soldier_state, move_result.mode)
	if not validation.is_empty():
		return ActionResult.fail(validation)

	if not _assign_move_path(
		game_state, context, fireteam, soldier_state,
		cmd, result, move_result.mode, move_result.message,
	):
		if cmd.target_cell == _start_cell_for_soldier(context, soldier_state):
			result.refresh_views = false
			return result
		return ActionResult.fail("No path to that tile.")

	result.path_overlay = {
		"cells": soldier_state.current_path,
		"target": cmd.target_cell,
	}
	var status := "%s Soldier %d %s to %s — click another tile to redirect." % [
		Team.display_name(cmd.team_id), cmd.soldier_id, mode_label, cmd.target_cell,
	]
	if not move_result.message.is_empty():
		status = move_result.message + "\n" + status
	return result.set_status(status)


static func execute_face(game_state: GameStateClass, cmd: FaceCommandClass) -> ActionResult:
	if cmd.scope == FaceCommandClass.Scope.SQUAD:
		return _execute_face_squad(game_state, cmd)

	if not _can_local_order_soldier(game_state, cmd.team_id, cmd.soldier_id):
		return ActionResult.fail("That soldier is not under your control.")

	var fireteam := game_state.session.get_fireteam(cmd.team_id)
	var soldier_state: SoldierState = fireteam.get_soldier(cmd.soldier_id)
	if soldier_state == null or soldier_state.is_dead:
		return ActionResult.fail("Soldier unavailable.")
	if soldier_state.is_stunned():
		return ActionResult.fail("Soldier is stunned.")

	if not fireteam.face_toward_tile(cmd.soldier_id, cmd.target_cell):
		return ActionResult.fail("Pick a different tile to face.")

	return _face_result_after_reorient(game_state, cmd.team_id, soldier_state)


static func _execute_face_squad(game_state: GameStateClass, cmd: FaceCommandClass) -> ActionResult:
	var fireteam := game_state.session.get_fireteam(cmd.team_id)
	var faced := 0
	var result := ActionResult.new()
	for state in fireteam.soldiers:
		var soldier_state: SoldierState = state
		if soldier_state == null or soldier_state.is_dead or soldier_state.is_stunned():
			continue
		if not _can_local_order_soldier(game_state, cmd.team_id, soldier_state.soldier_id):
			continue
		if not fireteam.face_toward_tile(soldier_state.soldier_id, cmd.target_cell):
			continue
		faced += 1
		var one := _face_result_after_reorient(game_state, cmd.team_id, soldier_state)
		if one.sync_fire_at_ui:
			result.sync_fire_at_ui = true
	if faced <= 0:
		return ActionResult.fail("No soldiers available to face.")
	return result.set_status(
		"%s Fireteam facing — %d soldier(s) reoriented."
		% [Team.display_name(cmd.team_id), faced],
	)


## Human UI / local client may only order soldiers owned by session.local_player_id.
static func _can_local_order_soldier(
	game_state: GameStateClass,
	team_id: int,
	soldier_id: int,
) -> bool:
	if game_state == null or game_state.session == null:
		return true
	return game_state.session.can_local_control_soldier(team_id, soldier_id)


static func _face_result_after_reorient(
	game_state: GameStateClass,
	team_id: int,
	soldier_state: SoldierState,
) -> ActionResult:
	var result := ActionResult.new()

	if soldier_state.is_sustained_fire():
		var priority: SoldierState = game_state.get_soldier(
			soldier_state.engaged_target_team_id,
			soldier_state.engaged_target_soldier_id,
		)
		if priority != null and not CombatSystem.is_facing_target(soldier_state, priority):
			soldier_state.end_sustained_fire()
			result.sync_fire_at_ui = true
			return result.set_status(
				"%s Soldier %d ceased fire — facing %s."
				% [
					Team.display_name(team_id),
					soldier_state.soldier_id,
					FacingDirection.direction_name(soldier_state.facing_direction),
				],
			)
	elif soldier_state.is_engaged():
		var engaged_target: SoldierState = game_state.get_soldier(
			soldier_state.engaged_target_team_id,
			soldier_state.engaged_target_soldier_id,
		)
		if engaged_target != null and not CombatSystem.is_facing_target(soldier_state, engaged_target):
			soldier_state.clear_engagement()
			result.sync_fire_at_ui = true
			return result.set_status(
				"%s Soldier %d ceased fire — facing %s."
				% [
					Team.display_name(team_id),
					soldier_state.soldier_id,
					FacingDirection.direction_name(soldier_state.facing_direction),
				],
			)

	return result.set_status(
		"%s Soldier %d facing %s."
		% [
			Team.display_name(team_id),
			soldier_state.soldier_id,
			FacingDirection.direction_name(soldier_state.facing_direction),
		],
	)


## Orient Fire At soldiers toward the current aim cell (preview only; no target assignment).
static func preview_fire_at_facing(
	game_state: GameStateClass,
	team_id: int,
	shooter_ids: Array,
	face_cell: Vector2i,
) -> bool:
	var fireteam := game_state.session.get_fireteam(team_id)
	var changed := false
	for soldier_id in shooter_ids:
		var shooter: SoldierState = fireteam.get_soldier(soldier_id)
		if shooter == null or shooter.is_dead or shooter.is_sustained_fire():
			continue
		if fireteam.face_toward_tile(soldier_id, face_cell):
			changed = true
	return changed


## Orient one soldier toward the grenade aim cell during targeting preview.
static func preview_grenade_facing(
	game_state: GameStateClass,
	team_id: int,
	soldier_id: int,
	face_cell: Vector2i,
) -> bool:
	var shooter: SoldierState = game_state.get_soldier(team_id, soldier_id)
	if shooter == null or shooter.is_dead or shooter.is_stunned():
		return false
	var fireteam := game_state.session.get_fireteam(team_id)
	return fireteam.face_toward_tile(soldier_id, face_cell)


static func execute_fire(
	game_state: GameStateClass,
	cmd: FireCommandClass,
	context: CommandContext,
) -> ActionResult:
	## Manual Fire At = assign priority target(s); fully blocked LOS holds fire but keeps assignment.
	if context == null or cmd.aim_world == Vector2.ZERO:
		return ActionResult.fail("Fire command requires aim_world.")

	var fireteam := game_state.session.get_fireteam(cmd.team_id)
	var shooter_ids := _resolve_shooter_ids(fireteam, cmd, context)
	if shooter_ids.is_empty():
		return ActionResult.fail("No available soldiers to fire.")

	var explicit_team := cmd.target_team_id if cmd.target_soldier_id > 0 else -1
	var explicit_soldier := cmd.target_soldier_id if cmd.target_soldier_id > 0 else -1

	var result := ActionResult.new()
	var engaged_count := 0
	var first_target: SoldierState = null
	var first_shooter: SoldierState = null
	var any_obscured := false
	var halted_any := false
	var any_faced := false
	var rejected_notices: Array[String] = []
	var click_cell := IsometricGrid.world_to_grid(cmd.aim_world)
	var face_cell := _fire_at_face_cell(game_state, click_cell, explicit_team, explicit_soldier)

	for soldier_id in shooter_ids:
		var shooter: SoldierState = fireteam.get_soldier(soldier_id)
		if shooter == null or shooter.is_dead:
			continue

		if CombatSystem.is_stress_panicked(shooter.stress):
			rejected_notices.append("Soldier is panicked and ignores the order.")
			continue

		if shooter.is_stunned():
			rejected_notices.append("Soldier is stunned and cannot fire.")
			continue

		if _halt_soldier_for_combat(context, shooter, result):
			halted_any = true

		var weapon := shooter.get_weapon_data()
		var max_range := (
			ConeOfFireClass.effective_range(weapon.range_tiles)
			if weapon != null
			else ConeOfFireClass.RANGE_BONUS
		)
		var from_world := _tracer_world_for_soldier(shooter)
		var target: SoldierState = CombatSystem.find_manual_priority_target(
			game_state,
			shooter,
			from_world,
			cmd.aim_world,
			max_range,
			explicit_team,
			explicit_soldier,
			click_cell,
		)
		if target == null:
			if shooter.is_sustained_fire():
				shooter.end_sustained_fire()
			if fireteam.face_toward_tile(shooter.soldier_id, face_cell):
				any_faced = true
			continue

		if CombatSystem.can_spot_enemy(shooter, target, game_state):
			shooter.record_last_seen_enemy(target)

		shooter.begin_sustained_fire()
		shooter.fire_control_state = FireControlStateClass.FIRE_AT_WILL
		shooter.set_engaged_target(target.team_id, target.soldier_id)
		CombatSystem.begin_fire_prep(shooter)
		if fireteam.face_toward_tile(shooter.soldier_id, target.grid_position):
			any_faced = true
		engaged_count += 1
		if first_target == null:
			first_target = target
			first_shooter = shooter

		var los := LOSSystemClass.evaluate(
			shooter.grid_position,
			target.grid_position,
			game_state.map_data,
			game_state,
		)
		if los.status == LOSSystemClass.Status.BLOCKED:
			any_obscured = true

	if any_faced:
		result.refresh_views = true

	if engaged_count == 0:
		result.sync_fire_at_ui = true
		if not rejected_notices.is_empty():
			return ActionResult.fail(rejected_notices[0])
		return result.set_status("No visible target there.")

	if halted_any:
		result.clear_path_overlay = true
		result.clear_move_targeting = true

	result.sync_fire_at_ui = true
	result.begin_fire_engagement = true

	if any_obscured and engaged_count == 1 and first_target != null:
		return result.set_status(
			"Priority target %s Soldier %d — holding fire until line of sight clears."
			% [Team.display_name(first_target.team_id), first_target.soldier_id],
		)
	if engaged_count == 1 and first_target != null and first_shooter != null:
		return result.set_status(
			"Priority target %s Soldier %d — firing in %.1fs."
			% [
				Team.display_name(first_target.team_id),
				first_target.soldier_id,
				CombatSystem.get_aim_delay_sec(first_shooter),
			],
		)
	if any_obscured:
		return result.set_status(
			"%d soldiers assigned priority targets — holding fire where obscured."
			% engaged_count,
		)
	return result.set_status(
		"%d soldiers assigned priority targets — aiming before fire."
		% engaged_count,
	)


static func execute_position(
	game_state: GameStateClass,
	cmd: PositionCommandClass,
) -> ActionResult:
	var soldier: SoldierState = game_state.get_soldier(cmd.team_id, cmd.soldier_id)
	if soldier == null or soldier.is_dead:
		return ActionResult.fail("Soldier unavailable.")
	if soldier.is_stunned():
		return ActionResult.fail("Soldier is stunned.")
	if soldier.pending_position_state >= 0:
		return ActionResult.fail("Soldier is already changing stance.")
	if soldier.position_state == cmd.position_state:
		return ActionResult.new().set_status(
			"Soldier %d already %s"
			% [soldier.soldier_id, PositionStateClass.display_name(cmd.position_state)],
		)

	## German (and any family with transition anims): defer gameplay stance until anim ends.
	var family_id := _animation_family_for_soldier(soldier)
	if _has_stance_transitions(family_id):
		soldier.pending_position_state = cmd.position_state
		var deferred := ActionResult.new()
		deferred.stance_transition_orders.append({
			"team_id": cmd.team_id,
			"soldier_id": cmd.soldier_id,
			"target_position_state": cmd.position_state,
		})
		return deferred.set_status(
			"Soldier %d changing to %s..."
			% [soldier.soldier_id, PositionStateClass.display_name(cmd.position_state)],
		)

	soldier.position_state = cmd.position_state
	return ActionResult.new().set_status(
		"Soldier %d changed to %s"
		% [soldier.soldier_id, PositionStateClass.display_name(cmd.position_state)],
	)


## Called when a stance-transition animation finishes (presentation → gameplay commit).
static func commit_stance_transition(
	game_state: GameStateClass,
	team_id: int,
	soldier_id: int,
	target_position_state: int,
) -> ActionResult:
	var soldier: SoldierState = game_state.get_soldier(team_id, soldier_id)
	if soldier == null or soldier.is_dead:
		return ActionResult.fail("Soldier unavailable.")
	if soldier.pending_position_state != target_position_state:
		## Cancelled (e.g. Run forced stand) — do not apply a stale target.
		return ActionResult.new().set_status(
			"Soldier %d stance transition cancelled." % soldier_id
		)
	soldier.position_state = target_position_state
	soldier.clear_pending_position()
	return ActionResult.new().set_status(
		"Soldier %d changed to %s"
		% [soldier.soldier_id, PositionStateClass.display_name(target_position_state)],
	)


static func execute_fire_control(
	game_state: GameStateClass,
	cmd: FireControlCommandClass,
) -> ActionResult:
	var soldier: SoldierState = game_state.get_soldier(cmd.team_id, cmd.soldier_id)
	if soldier == null or soldier.is_dead:
		return ActionResult.fail("Soldier unavailable.")

	soldier.fire_control_state = cmd.fire_control_state
	var result := ActionResult.new()
	var message := "Soldier %d set to %s" % [
		soldier.soldier_id,
		FireControlStateClass.display_name(cmd.fire_control_state),
	]

	if cmd.fire_control_state == FireControlStateClass.HOLD_FIRE:
		if soldier.is_sustained_fire():
			soldier.end_sustained_fire()
			result.sync_fire_at_ui = true
			message = "Soldier %d set to Hold Fire — ceased fire." % soldier.soldier_id
		elif soldier.is_engaged():
			soldier.clear_engagement()
			result.sync_fire_at_ui = true
			message = "Soldier %d set to Hold Fire — ceased fire." % soldier.soldier_id

	return result.set_status(message)


static func execute_grenade(
	game_state: GameStateClass,
	cmd: GrenadeCommandClass,
	context: CommandContext,
) -> ActionResult:
	var soldier: SoldierState = game_state.get_soldier(cmd.team_id, cmd.soldier_id)
	if soldier == null or soldier.is_dead:
		return ActionResult.fail("Soldier unavailable.")
	if soldier.is_stunned():
		return ActionResult.fail("Soldier is stunned.")
	if soldier.is_moving:
		return ActionResult.fail("Cannot throw a grenade while moving.")
	if soldier.has_pending_grenade():
		return ActionResult.fail("Soldier already has a grenade in the air.")
	if soldier.grenade_count <= 0:
		return ActionResult.fail("No grenades remaining.")
	if not game_state.map_data.is_in_bounds(cmd.target_cell):
		return ActionResult.fail("That tile is outside the map.")

	var throw_distance := CombatSystem.grenade_throw_distance(
		soldier.grid_position,
		cmd.target_cell,
	)
	if throw_distance > GameplayPolicies.grenade.throw_range:
		return ActionResult.fail("Target is out of grenade range.")

	var result := ActionResult.new()
	if _halt_soldier_for_combat(context, soldier, result):
		result.clear_path_overlay = true
		result.clear_move_targeting = true

	var fireteam := game_state.session.get_fireteam(cmd.team_id)
	fireteam.face_toward_tile(soldier.soldier_id, cmd.target_cell)

	soldier.grenade_count -= 1
	soldier.end_sustained_fire()
	soldier.reset_fire_prep()
	soldier.pending_grenade_target = cmd.target_cell
	soldier.grenade_explode_at_msec = (
		SimulationClock.get_ticks_msec() + GameplayPolicies.grenade.fuse_msec
	)
	game_state.objects.register_grenade_from_soldier(soldier)

	result.throw_orders.append({
		"team_id": soldier.team_id,
		"soldier_id": soldier.soldier_id,
	})
	result.sync_fire_at_ui = true
	result.refresh_views = true
	_log_action("grenade thrown soldier %d:%d -> %s" % [cmd.team_id, cmd.soldier_id, cmd.target_cell])
	return result.set_status("Grenade thrown.")


## UI cancel / mode exit — ends sustained Fire At on every soldier.
static func cancel_all_sustained_fire(game_state: GameStateClass) -> void:
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			soldier_state.end_sustained_fire()


static func arm_movement_mode_for_soldier(
	soldier: SoldierState,
	movement_mode: int,
) -> String:
	if soldier == null or soldier.is_dead:
		return "Soldier unavailable."

	if CombatSystem.is_stress_panicked(soldier.stress):
		return "Soldier is panicked and ignores the order."

	if soldier.is_stunned():
		return "Soldier is stunned and cannot move."

	var move_result := _resolve_move_order(soldier, movement_mode)
	if move_result.rejected:
		return move_result.message

	var stand_message := _stand_up_for_run(soldier, move_result.mode)
	if not MovementModeClass.is_allowed(soldier.position_state, move_result.mode):
		return "Cannot use %s while DOWN." % MovementModeClass.display_name(move_result.mode)

	soldier.movement_mode = move_result.mode
	var mode_message := "Soldier %d movement mode = %s" % [
		soldier.soldier_id,
		MovementModeClass.display_name(move_result.mode),
	]
	var lines: Array[String] = []
	if not move_result.message.is_empty():
		lines.append(move_result.message)
	if not stand_message.is_empty():
		lines.append(stand_message)
	lines.append(mode_message)
	return "\n".join(lines)


static func _assign_move_path(
	game_state: GameStateClass,
	context: CommandContext,
	fireteam: Fireteam,
	state: SoldierState,
	cmd: MoveCommandClass,
	result: ActionResult,
	resolved_mode: int = -1,
	_notice: String = "",
) -> bool:
	if state.is_dead:
		return false

	var mode := resolved_mode if resolved_mode >= 0 else cmd.movement_mode
	if CombatSystem.is_stress_panicked(state.stress):
		return false
	if state.is_stunned():
		return false

	if not _validate_move(state, mode).is_empty():
		return false

	var start_cell := _start_cell_for_soldier(context, state)
	## Mid-move redirect: halt presentation at the authoritative cell, then repath.
	if state.is_moving:
		result.movement_halts.append({
			"team_id": state.team_id,
			"soldier_id": state.soldier_id,
			"snap_cell": state.grid_position,
		})
		state.clear_path()
		start_cell = state.grid_position

	if cmd.target_cell == start_cell:
		return false
	if not game_state.map_data.is_walkable(cmd.target_cell):
		return false

	var path: Array[Vector2i] = context.find_path.call(start_cell, cmd.target_cell)
	if path.is_empty():
		return false
	## Reject any path that still contains blocked climb/NoPass cells.
	for i in range(1, path.size()):
		if game_state.map_data.is_blocked(path[i]):
			return false

	state.movement_mode = mode
	var speed_mult := (
		MovementModeClass.speed_multiplier(mode)
		* CombatSystem.get_stress_movement_modifier(state.stress)
	)
	fireteam.order_path(state.soldier_id, path, speed_mult)
	result.move_orders.append({
		"team_id": state.team_id,
		"soldier_id": state.soldier_id,
		"path": path,
		"speed_mult": speed_mult,
	})
	return true


class MoveOrderResolution:
	var mode: int = MovementModeClass.RUN
	var message: String = ""
	var rejected: bool = false


static func _resolve_move_order(soldier: SoldierState, requested_mode: int) -> MoveOrderResolution:
	var resolved := MoveOrderResolution.new()
	resolved.mode = requested_mode
	if soldier == null or soldier.is_dead:
		resolved.rejected = true
		resolved.message = "Soldier unavailable."
		return resolved
	if CombatSystem.is_stress_panicked(soldier.stress):
		resolved.rejected = true
		resolved.message = "Soldier is panicked and ignores the order."
		return resolved
	if soldier.is_stunned():
		resolved.rejected = true
		resolved.message = "Soldier is stunned and cannot move."
		return resolved
	if requested_mode == MovementModeClass.RUN and CombatSystem.is_stress_pinned(soldier.stress):
		resolved.mode = MovementModeClass.WALK
		resolved.message = "Soldier is pinned and cannot run."
	return resolved


static func validate_move(soldier: SoldierState, mode: int) -> String:
	return _validate_move(soldier, mode)


static func _validate_move(soldier: SoldierState, mode: int) -> String:
	if soldier == null or soldier.is_dead:
		return "Soldier unavailable."
	_stand_up_for_run(soldier, mode)
	if not MovementModeClass.is_allowed(soldier.position_state, mode):
		return "Cannot %s while DOWN." % MovementModeClass.display_name(mode)
	return ""


static func _stand_up_for_run(soldier: SoldierState, mode: int) -> String:
	if soldier == null or mode != MovementModeClass.RUN:
		return ""
	if soldier.position_state != PositionStateClass.DOWN and soldier.pending_position_state < 0:
		return ""
	soldier.clear_pending_position()
	if soldier.position_state == PositionStateClass.UP:
		return ""
	soldier.position_state = PositionStateClass.UP
	return "Soldier %d changed to UP" % soldier.soldier_id


static func _animation_family_for_soldier(soldier: SoldierState) -> String:
	return "german_rifle" if soldier.team_id == Team.GERMANY else "us_rifle"


static func _has_stance_transitions(family_id: String) -> bool:
	AnimationDatabase.ensure_loaded()
	return (
		not AnimationDatabase.get_animation(family_id, "transition_standing_to_prone").is_empty()
		and not AnimationDatabase.get_animation(family_id, "transition_prone_to_standing").is_empty()
	)


static func _start_cell_for_soldier(_context: CommandContext, state: SoldierState) -> Vector2i:
	## Authoritative only — never use interpolated presentation positions.
	return state.grid_position


static func _halt_soldier_for_combat(
	_context: CommandContext,
	state: SoldierState,
	result: ActionResult,
) -> bool:
	if not state.is_moving:
		return false
	var halt_cell := state.grid_position
	state.clear_path()
	result.movement_halts.append({
		"team_id": state.team_id,
		"soldier_id": state.soldier_id,
		"snap_cell": halt_cell,
	})
	return true


static func _fire_at_face_cell(
	game_state: GameStateClass,
	click_cell: Vector2i,
	explicit_team_id: int,
	explicit_soldier_id: int,
) -> Vector2i:
	if explicit_team_id >= 0 and explicit_soldier_id > 0:
		var explicit_target: SoldierState = game_state.get_soldier(explicit_team_id, explicit_soldier_id)
		if explicit_target != null and not explicit_target.is_dead:
			return explicit_target.grid_position
	return click_cell


static func _resolve_shooter_ids(
	fireteam: Fireteam,
	cmd: FireCommandClass,
	context: CommandContext,
) -> Array[int]:
	if not context.shooter_ids.is_empty():
		return context.shooter_ids.duplicate()
	var ids: Array[int] = []
	if cmd.scope == FireCommandClass.Scope.SQUAD:
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if not soldier_state.is_alive():
				continue
			## Shooter list is built in UI context; when empty fallback, still respect ownership.
			ids.append(soldier_state.soldier_id)
	else:
		var shooter: SoldierState = fireteam.get_soldier(cmd.soldier_id)
		if shooter != null and shooter.is_alive():
			ids.append(shooter.soldier_id)
	return ids


static func _tracer_world_for_soldier(state: SoldierState) -> Vector2:
	return IsometricGrid.soldier_aim_point(state.grid_position)


static func _append_grenade_movement_halts(
	game_state: GameStateClass,
	grenade_result: CombatGrenadeResultClass,
	result: ActionResult,
) -> void:
	var affected: Array[Dictionary] = []
	affected.append_array(grenade_result.killed)
	affected.append_array(grenade_result.stunned)
	for entry in affected:
		var team_id := int(entry.get("team_id", -1))
		var soldier_id := int(entry.get("soldier_id", -1))
		var soldier: SoldierState = game_state.get_soldier(team_id, soldier_id)
		if soldier == null:
			continue
		result.movement_halts.append({
			"team_id": team_id,
			"soldier_id": soldier_id,
			"snap_cell": soldier.grid_position,
		})


static func _log_action(message: String) -> void:
	GameLog.log_system("[ActionResolver] %s" % message)


static func _command_type_name(command: RefCounted) -> String:
	if command is MoveCommandClass:
		return "MoveCommand"
	if command is FaceCommandClass:
		return "FaceCommand"
	if command is FireCommandClass:
		return "FireCommand"
	if command is PositionCommandClass:
		return "PositionCommand"
	if command is FireControlCommandClass:
		return "FireControlCommand"
	if command is GrenadeCommandClass:
		return "GrenadeCommand"
	if command is AssignCommanderCommandClass:
		return "AssignCommanderCommand"
	if command is BreakCommandLinkCommandClass:
		return "BreakCommandLinkCommand"
	if command is SetMissionCommanderCommandClass:
		return "SetMissionCommanderCommand"
	if command is AssignWeaponCommandClass:
		return "AssignWeaponCommand"
	if command is ReturnWeaponCommandClass:
		return "ReturnWeaponCommand"
	return command.get_class() if command != null else "null"


## --- Commander / subordinate hierarchy ---

static func execute_assign_commander(
	game_state: GameStateClass,
	cmd: AssignCommanderCommandClass,
) -> ActionResult:
	if cmd == null or game_state == null or game_state.command_hierarchy == null:
		return ActionResult.fail("Choose a commander first")
	var hierarchy := game_state.command_hierarchy
	var commander_id := int(cmd.commander_id)
	var subordinate_id := int(cmd.subordinate_id)
	if commander_id <= 0 or not hierarchy.has_player(commander_id):
		return ActionResult.fail("Choose a commander first")
	if subordinate_id <= 0 or not hierarchy.has_player(subordinate_id):
		return ActionResult.fail("Choose a subordinate first")
	if commander_id == subordinate_id:
		return ActionResult.fail("Subordinate cannot be the commander")
	var existing_cmd := hierarchy.get_commander(subordinate_id)
	if existing_cmd != CommandHierarchyClass.NO_COMMANDER and existing_cmd != commander_id:
		return ActionResult.fail("Already commanded by another player")
	if subordinate_id in hierarchy.get_subordinates(commander_id):
		return ActionResult.fail("Already in subordinate list")
	if not hierarchy.has_opening(commander_id):
		return ActionResult.fail("This commander is full")
	if hierarchy.would_create_cycle(commander_id, subordinate_id):
		return ActionResult.fail("Commander can't be subordinate of subordinate")
	if hierarchy.get_rank(subordinate_id) >= hierarchy.get_rank(commander_id):
		return ActionResult.fail("Rank order broken")

	hierarchy.assign_link(commander_id, subordinate_id)
	CombatSystem.notify_command_hierarchy_changed(game_state)
	var result := ActionResult.new()
	result.refresh_views = true
	return result.set_status(
		"%s commanded by %s"
		% [hierarchy.list_label(subordinate_id), hierarchy.list_label(commander_id)]
	)


static func execute_break_command_link(
	game_state: GameStateClass,
	cmd: BreakCommandLinkCommandClass,
) -> ActionResult:
	if cmd == null or game_state == null or game_state.command_hierarchy == null:
		return ActionResult.fail("Choose a subordinate first")
	var hierarchy := game_state.command_hierarchy
	var subordinate_id := int(cmd.subordinate_id)
	if subordinate_id <= 0 or not hierarchy.has_player(subordinate_id):
		return ActionResult.fail("Choose a subordinate first")
	if hierarchy.get_commander(subordinate_id) == CommandHierarchyClass.NO_COMMANDER:
		return ActionResult.fail("Choose a subordinate first")
	hierarchy.break_link(subordinate_id)
	CombatSystem.notify_command_hierarchy_changed(game_state)
	var result := ActionResult.new()
	result.refresh_views = true
	return result.set_status("Broke command link for %s" % hierarchy.list_label(subordinate_id))


static func execute_set_mission_commander(
	game_state: GameStateClass,
	cmd: SetMissionCommanderCommandClass,
) -> ActionResult:
	if cmd == null or game_state == null or game_state.command_hierarchy == null:
		return ActionResult.fail("Choose a commander first")
	var hierarchy := game_state.command_hierarchy
	var player_id := int(cmd.player_id)
	if player_id <= 0 or not hierarchy.has_player(player_id):
		return ActionResult.fail("Choose a commander first")
	hierarchy.set_mission_commander(player_id)
	var result := ActionResult.new()
	result.refresh_views = false
	return result.set_status(
		"%s is now the Mission Commander" % hierarchy.list_label(player_id)
	)


## --- Weapon cache assignment (WeaponAss_*) ---

static func execute_assign_weapon(
	game_state: GameStateClass,
	cmd: AssignWeaponCommandClass,
) -> ActionResult:
	if cmd == null or game_state == null or game_state.weapon_cache == null:
		return ActionResult.fail("Choose a weapon from the cache")
	var cache: WeaponCacheClass = game_state.weapon_cache
	var hierarchy: CommandHierarchyClass = game_state.command_hierarchy
	var from_player_id := int(cmd.from_player_id)
	var item_id := str(cmd.item_id).strip_edges()
	var target_kind := int(cmd.target_kind)
	var target_id := int(cmd.target_id)

	if item_id.is_empty():
		return ActionResult.fail("Choose a weapon from the cache")
	if from_player_id <= 0 or hierarchy == null or not hierarchy.has_player(from_player_id):
		return ActionResult.fail("Choose a weapon from the cache")
	if target_id <= 0:
		return ActionResult.fail("Choose a target for weapon assignment")

	var available := cache.pool_count(from_player_id, item_id)
	if available <= 0:
		return ActionResult.fail("No weapon available")

	if target_kind == WeaponCacheClass.TargetKind.PLAYER:
		return _assign_weapon_to_player(
			game_state, cache, hierarchy, from_player_id, item_id, target_id
		)

	return _assign_weapon_to_soldier(game_state, cache, hierarchy, cmd)


static func _assign_weapon_to_player(
	game_state: GameStateClass,
	cache: WeaponCacheClass,
	hierarchy: CommandHierarchyClass,
	from_player_id: int,
	item_id: String,
	target_player_id: int,
) -> ActionResult:
	if not hierarchy.has_player(target_player_id):
		return ActionResult.fail("Choose a target for weapon assignment")
	if target_player_id == from_player_id:
		return ActionResult.fail("Choose a target for weapon assignment")
	## WeaponPlus<-FromCommander: only to direct subordinates when hierarchy is present.
	if target_player_id not in hierarchy.get_subordinates(from_player_id):
		return ActionResult.fail("Choose a target for weapon assignment")
	if not cache.take_from_pool(from_player_id, item_id):
		return ActionResult.fail("That weapon was already taken")
	cache.add_to_pool(target_player_id, item_id, 1)
	var entry: Dictionary = hierarchy.get_entry(target_player_id)
	if bool(entry.get("is_ai", false)):
		cache.auto_distribute_to_soldiers(
			game_state,
			target_player_id,
			hierarchy.get_soldier_ids(target_player_id),
			hierarchy.get_team_id(target_player_id),
		)
	var result := ActionResult.new()
	result.refresh_views = true
	return result.set_status(
		"Gave %s to %s"
		% [cache.display_name(item_id), hierarchy.get_display_name(target_player_id)]
	)


static func _assign_weapon_to_soldier(
	game_state: GameStateClass,
	cache: WeaponCacheClass,
	hierarchy: CommandHierarchyClass,
	cmd: AssignWeaponCommandClass,
) -> ActionResult:
	var from_player_id := int(cmd.from_player_id)
	var item_id := str(cmd.item_id).strip_edges()
	var soldier_id := int(cmd.target_id)
	var team_id := int(cmd.target_team_id)
	if team_id < 0 and hierarchy != null:
		team_id = hierarchy.get_team_id(from_player_id)
	var owned := hierarchy.get_soldier_ids(from_player_id) if hierarchy != null else ([] as Array[int])
	if soldier_id <= 0 or soldier_id not in owned:
		return ActionResult.fail("Choose a target for weapon assignment")
	var soldier: SoldierState = game_state.get_soldier(team_id, soldier_id)
	if soldier == null or soldier.is_dead:
		return ActionResult.fail("Choose a target for weapon assignment")

	var is_equip := cache.is_equipment(item_id)
	if not is_equip and WeaponCacheClass.would_exceed_squad_limit(game_state, team_id, item_id):
		## Already holding this weapon: swap is a no-op on count, allow re-equip from cache.
		if str(soldier.weapon_id) != item_id:
			return ActionResult.fail("Weapon limit for this squad reached")

	if not cache.take_from_pool(from_player_id, item_id):
		return ActionResult.fail("That weapon was already taken")

	if is_equip:
		soldier.add_equipment(item_id)
		var equip_result := ActionResult.new()
		equip_result.refresh_views = true
		return equip_result.set_status(
			"Assigned %s to soldier%d" % [cache.display_name(item_id), soldier_id]
		)

	## WeaponGetNew + WeaponRemoveOld: previous weapon returns to the pool.
	var old_weapon_id := str(soldier.weapon_id)
	soldier.assign_weapon(item_id, true)
	if not old_weapon_id.is_empty() and old_weapon_id != item_id:
		cache.add_to_pool(from_player_id, old_weapon_id, 1, WeaponCacheClass.Kind.WEAPON)

	var result := ActionResult.new()
	result.refresh_views = true
	return result.set_status(
		"Assigned %s to soldier%d (%s, %d)"
		% [
			cache.display_name(item_id),
			soldier_id,
			cache.display_name(item_id),
			soldier.ammo_current,
		]
	)


static func execute_return_weapon(
	game_state: GameStateClass,
	cmd: ReturnWeaponCommandClass,
) -> ActionResult:
	if cmd == null or game_state == null or game_state.weapon_cache == null:
		return ActionResult.fail("Choose a target for weapon assignment")
	var cache: WeaponCacheClass = game_state.weapon_cache
	var hierarchy: CommandHierarchyClass = game_state.command_hierarchy
	var to_player_id := int(cmd.to_player_id)
	var team_id := int(cmd.team_id)
	var soldier_id := int(cmd.soldier_id)
	var item_id := str(cmd.item_id).strip_edges()

	if to_player_id <= 0 or hierarchy == null or not hierarchy.has_player(to_player_id):
		return ActionResult.fail("Choose a target for weapon assignment")
	if team_id < 0:
		team_id = hierarchy.get_team_id(to_player_id)
	if soldier_id <= 0 or soldier_id not in hierarchy.get_soldier_ids(to_player_id):
		return ActionResult.fail("Choose a target for weapon assignment")
	var soldier: SoldierState = game_state.get_soldier(team_id, soldier_id)
	if soldier == null or soldier.is_dead:
		return ActionResult.fail("Choose a target for weapon assignment")

	if item_id.is_empty():
		item_id = str(soldier.weapon_id)

	if cache.is_equipment(item_id):
		if not soldier.remove_equipment(item_id):
			return ActionResult.fail("No weapon available")
		cache.add_to_pool(to_player_id, item_id, 1, WeaponCacheClass.Kind.EQUIPMENT)
		var equip_result := ActionResult.new()
		equip_result.refresh_views = true
		return equip_result.set_status("Returned %s to cache" % cache.display_name(item_id))

	if str(soldier.weapon_id) != item_id:
		return ActionResult.fail("No weapon available")
	var default_rifle := WeaponCacheClass.default_rifle_for_team(team_id)
	soldier.assign_weapon(default_rifle, true)
	cache.add_to_pool(to_player_id, item_id, 1, WeaponCacheClass.Kind.WEAPON)
	var result := ActionResult.new()
	result.refresh_views = true
	return result.set_status("Returned %s to cache" % cache.display_name(item_id))

