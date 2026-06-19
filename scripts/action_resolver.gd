class_name ActionResolver
extends RefCounted
## Single entry point for mutating authoritative GameState.
##
## Flow (local today, server-ready tomorrow):
##   UI input → Command DTO → ActionResolver.execute(game_state, command, context)
##            → GameState updated → ActionResult → presentation refresh
##
## CombatSystem, CoverSystem, and LOSSystem are called from here; they never touch nodes.

const GameStateClass := preload("res://scripts/game_state.gd")
const MoveCommandClass := preload("res://scripts/move_command.gd")
const FaceCommandClass := preload("res://scripts/face_command.gd")
const FireCommandClass := preload("res://scripts/fire_command.gd")
const PositionCommandClass := preload("res://scripts/position_command.gd")
const FireControlCommandClass := preload("res://scripts/fire_control_command.gd")
const MovementModeClass := preload("res://scripts/movement_mode.gd")
const PositionStateClass := preload("res://scripts/position_state.gd")
const FireControlStateClass := preload("res://scripts/fire_control_state.gd")
const ConeOfFireClass := preload("res://scripts/cone_of_fire.gd")
const CombatShotResultClass := preload("res://scripts/combat_shot_result.gd")
const LOSSystemClass := preload("res://scripts/los_system.gd")


static func execute(
	game_state: GameStateClass,
	command: RefCounted,
	context: CommandContext = null,
) -> ActionResult:
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
	var result := ActionResult.new()
	result.refresh_map_data = true
	result.refresh_views = false
	if is_now_blocked:
		return result.set_status("Blocked tile %s." % cell)
	return result.set_status("Unblocked tile %s." % cell)


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


## Movement animation reached a tile — updates authoritative position and facing.
static func on_movement_step(
	game_state: GameStateClass,
	team_id: int,
	soldier_id: int,
	tile: Vector2i,
	step_delta: Vector2i,
) -> void:
	game_state.session.get_fireteam(team_id).on_soldier_reached_tile(soldier_id, tile, step_delta)


## Movement animation finished — clears path flags on authoritative state.
static func on_movement_complete(
	game_state: GameStateClass,
	team_id: int,
	soldier_id: int,
) -> void:
	game_state.session.get_fireteam(team_id).on_soldier_finished_moving(soldier_id)


## Periodic combat tick: sustained Fire At (priority) + Fire At Will (auto) + stress recovery.
static func process_combat_tick(game_state: GameStateClass) -> ActionResult:
	var result := ActionResult.new()
	result.refresh_views = false

	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var shooter: SoldierState = state
			if not shooter.is_sustained_fire():
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
			var shot: CombatShotResultClass = CombatSystem.try_auto_engagement(game_state, shooter)
			if shot.fired:
				result.combat_shots.append(shot)
				result.refresh_views = true

	CombatSystem.recover_stress_tick(game_state, CombatSystem.AUTO_FIRE_SCAN_INTERVAL)
	result.refresh_views = true

	if not result.combat_shots.is_empty():
		result.sync_fire_at_ui = true
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
	var mode_label := MovementModeClass.display_name(cmd.movement_mode).to_lower()
	var result := ActionResult.new()

	if cmd.scope == MoveCommandClass.Scope.SQUAD:
		var ordered_count := 0
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if _assign_move_path(game_state, context, fireteam, soldier_state, cmd, result):
				ordered_count += 1
		if ordered_count == 0:
			return ActionResult.fail("No soldiers could %s to that tile." % mode_label)
		result.path_overlay = {"cells": [], "target": cmd.target_cell}
		return result.set_status(
			"%s fireteam %s to %s — click another tile to redirect."
			% [Team.display_name(cmd.team_id), mode_label, cmd.target_cell],
		)

	var soldier_state: SoldierState = fireteam.get_soldier(cmd.soldier_id)
	if soldier_state == null:
		return ActionResult.fail("Soldier unavailable.")

	var validation := _validate_move(soldier_state, cmd.movement_mode)
	if not validation.is_empty():
		return ActionResult.fail(validation)

	if not _assign_move_path(game_state, context, fireteam, soldier_state, cmd, result):
		if cmd.target_cell == _start_cell_for_soldier(context, soldier_state):
			result.refresh_views = false
			return result
		return ActionResult.fail("No path to that tile.")

	result.path_overlay = {
		"cells": soldier_state.current_path,
		"target": cmd.target_cell,
	}
	return result.set_status(
		"%s Soldier %d %s to %s — click another tile to redirect."
		% [Team.display_name(cmd.team_id), cmd.soldier_id, mode_label, cmd.target_cell],
	)


static func execute_face(game_state: GameStateClass, cmd: FaceCommandClass) -> ActionResult:
	var fireteam := game_state.session.get_fireteam(cmd.team_id)
	if not fireteam.face_toward_tile(cmd.soldier_id, cmd.target_cell):
		return ActionResult.fail("Pick a different tile to face.")

	var soldier_state: SoldierState = fireteam.get_soldier(cmd.soldier_id)
	var result := ActionResult.new()

	if soldier_state != null and soldier_state.is_sustained_fire():
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
					Team.display_name(cmd.team_id),
					cmd.soldier_id,
					FacingDirection.direction_name(soldier_state.facing_direction),
				],
			)
	elif soldier_state != null and soldier_state.is_engaged():
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
					Team.display_name(cmd.team_id),
					cmd.soldier_id,
					FacingDirection.direction_name(soldier_state.facing_direction),
				],
			)

	return result.set_status(
		"%s Soldier %d facing %s."
		% [
			Team.display_name(cmd.team_id),
			cmd.soldier_id,
			FacingDirection.direction_name(soldier_state.facing_direction),
		],
	)


static func execute_fire(
	game_state: GameStateClass,
	cmd: FireCommandClass,
	context: CommandContext,
) -> ActionResult:
	## Manual Fire At = assign priority target(s); blocked cover holds fire but keeps assignment.
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
	var any_obscured := false
	var halted_any := false

	for soldier_id in shooter_ids:
		var shooter: SoldierState = fireteam.get_soldier(soldier_id)
		if shooter == null or shooter.is_dead:
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
		)
		if target == null:
			if shooter.is_sustained_fire():
				shooter.end_sustained_fire()
			continue

		shooter.begin_sustained_fire()
		shooter.set_engaged_target(target.team_id, target.soldier_id)
		CombatSystem.begin_fire_prep(shooter)
		fireteam.face_toward_tile(shooter.soldier_id, target.grid_position)
		engaged_count += 1
		if first_target == null:
			first_target = target

		var los := LOSSystemClass.evaluate(
			shooter.grid_position,
			target.grid_position,
			game_state.map_data,
		)
		if los.status == LOSSystemClass.Status.BLOCKED:
			any_obscured = true

	if engaged_count == 0:
		result.sync_fire_at_ui = true
		return result.set_status("No enemies in aim cone — ceased fire.")

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
	if engaged_count == 1 and first_target != null:
		return result.set_status(
			"Priority target %s Soldier %d — firing in %.0fs."
			% [
				Team.display_name(first_target.team_id),
				first_target.soldier_id,
				CombatSystem.FIRE_PREP_DELAY_SEC,
			],
		)
	if any_obscured:
		return result.set_status(
			"%d soldiers assigned priority targets — holding fire where obscured."
			% engaged_count,
		)
	return result.set_status(
		"%d soldiers assigned priority targets — firing in %.0fs."
		% [engaged_count, CombatSystem.FIRE_PREP_DELAY_SEC],
	)


static func execute_position(
	game_state: GameStateClass,
	cmd: PositionCommandClass,
) -> ActionResult:
	var soldier: SoldierState = game_state.get_soldier(cmd.team_id, cmd.soldier_id)
	if soldier == null or soldier.is_dead:
		return ActionResult.fail("Soldier unavailable.")

	soldier.position_state = cmd.position_state
	return ActionResult.new().set_status(
		"Soldier %d changed to %s"
		% [soldier.soldier_id, PositionStateClass.display_name(cmd.position_state)],
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

	var stand_message := _stand_up_for_run(soldier, movement_mode)
	if not MovementModeClass.is_allowed(soldier.position_state, movement_mode):
		return "Cannot use %s while DOWN." % MovementModeClass.display_name(movement_mode)

	soldier.movement_mode = movement_mode
	var mode_message := "Soldier %d movement mode = %s" % [
		soldier.soldier_id,
		MovementModeClass.display_name(movement_mode),
	]
	if stand_message.is_empty():
		return mode_message
	return "%s\n%s" % [stand_message, mode_message]


static func _assign_move_path(
	game_state: GameStateClass,
	context: CommandContext,
	fireteam: Fireteam,
	state: SoldierState,
	cmd: MoveCommandClass,
	result: ActionResult,
) -> bool:
	if state.is_dead:
		return false

	if not _validate_move(state, cmd.movement_mode).is_empty():
		return false

	var start_cell := _start_cell_for_soldier(context, state)
	var snap_key := _soldier_key(state.team_id, state.soldier_id)
	if context.soldier_snap_cells.has(snap_key) and state.is_moving:
		start_cell = context.soldier_snap_cells[snap_key]
		state.grid_position = start_cell
		state.clear_path()
		result.movement_halts.append({
			"team_id": state.team_id,
			"soldier_id": state.soldier_id,
			"snap_cell": start_cell,
		})

	if cmd.target_cell == start_cell:
		return false
	if not game_state.map_data.is_walkable(cmd.target_cell):
		return false

	var path: Array[Vector2i] = context.find_path.call(start_cell, cmd.target_cell)
	if path.is_empty():
		return false

	state.movement_mode = cmd.movement_mode
	fireteam.order_path(state.soldier_id, path)
	result.move_orders.append({
		"team_id": state.team_id,
		"soldier_id": state.soldier_id,
		"path": path,
		"speed_mult": MovementModeClass.speed_multiplier(cmd.movement_mode),
	})
	return true


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
	if soldier.position_state != PositionStateClass.DOWN:
		return ""
	soldier.position_state = PositionStateClass.UP
	return "Soldier %d changed to UP" % soldier.soldier_id


static func _start_cell_for_soldier(context: CommandContext, state: SoldierState) -> Vector2i:
	var key := _soldier_key(state.team_id, state.soldier_id)
	if context != null and context.soldier_snap_cells.has(key):
		return context.soldier_snap_cells[key]
	return state.grid_position


static func _halt_soldier_for_combat(
	context: CommandContext,
	state: SoldierState,
	result: ActionResult,
) -> bool:
	var key := _soldier_key(state.team_id, state.soldier_id)
	if context == null or not context.soldier_snap_cells.has(key):
		if not state.is_moving:
			return false
		state.clear_path()
		return true

	var snap_cell: Vector2i = context.soldier_snap_cells[key]
	var was_active := state.is_moving or snap_cell != state.grid_position
	state.grid_position = snap_cell
	state.clear_path()
	if was_active:
		result.movement_halts.append({
			"team_id": state.team_id,
			"soldier_id": state.soldier_id,
			"snap_cell": snap_cell,
		})
	return was_active


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
			if soldier_state.is_alive():
				ids.append(soldier_state.soldier_id)
	else:
		var shooter: SoldierState = fireteam.get_soldier(cmd.soldier_id)
		if shooter != null and shooter.is_alive():
			ids.append(shooter.soldier_id)
	return ids


static func _tracer_world_for_soldier(state: SoldierState) -> Vector2:
	return IsometricGrid.grid_to_world(state.grid_position) + Vector2(0, -16)


static func _soldier_key(team_id: int, soldier_id: int) -> String:
	return "%d:%d" % [team_id, soldier_id]
