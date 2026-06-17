class_name SoldierActions
extends RefCounted
## Applies soldier commands to gameplay state (keeps rules out of UI).

const GameStateClass := preload("res://scripts/game_state.gd")
const MovementModeClass := preload("res://scripts/movement_mode.gd")
const PositionStateClass := preload("res://scripts/position_state.gd")
const PositionCommandClass := preload("res://scripts/position_command.gd")
const SoldierStateClass := preload("res://scripts/soldier_state.gd")
const FireControlStateClass := preload("res://scripts/fire_control_state.gd")
const FireControlCommandClass := preload("res://scripts/fire_control_command.gd")


static func apply_position(state: GameStateClass, cmd: PositionCommandClass) -> String:
	var soldier: SoldierStateClass = state.get_soldier(cmd.team_id, cmd.soldier_id)
	if soldier == null or soldier.is_dead:
		return "Soldier unavailable."

	soldier.position_state = cmd.position_state
	return "Soldier %d changed to %s" % [soldier.soldier_id, PositionStateClass.display_name(cmd.position_state)]


## Run To stands a prone soldier up automatically before moving.
static func stand_up_for_run(soldier: SoldierStateClass, mode: int) -> String:
	if soldier == null or mode != MovementModeClass.RUN:
		return ""
	if soldier.position_state != PositionStateClass.DOWN:
		return ""
	soldier.position_state = PositionStateClass.UP
	return "Soldier %d changed to UP" % soldier.soldier_id


static func arm_movement_mode(soldier: SoldierStateClass, mode: int) -> String:
	if soldier == null or soldier.is_dead:
		return "Soldier unavailable."

	var stand_message := stand_up_for_run(soldier, mode)
	if not MovementModeClass.is_allowed(soldier.position_state, mode):
		return "Cannot use %s while DOWN." % MovementModeClass.display_name(mode)

	soldier.movement_mode = mode
	var mode_message := "Soldier %d movement mode = %s" % [
		soldier.soldier_id,
		MovementModeClass.display_name(mode),
	]
	if stand_message.is_empty():
		return mode_message
	return "%s\n%s" % [stand_message, mode_message]


static func validate_move(soldier: SoldierStateClass, mode: int) -> String:
	if soldier == null or soldier.is_dead:
		return "Soldier unavailable."
	stand_up_for_run(soldier, mode)
	if not MovementModeClass.is_allowed(soldier.position_state, mode):
		return "Cannot %s while DOWN." % MovementModeClass.display_name(mode)
	return ""


static func apply_fire_control(state: GameStateClass, cmd: FireControlCommandClass) -> String:
	var soldier: SoldierStateClass = state.get_soldier(cmd.team_id, cmd.soldier_id)
	if soldier == null or soldier.is_dead:
		return "Soldier unavailable."

	soldier.fire_control_state = cmd.fire_control_state
	return "Soldier %d set to %s" % [
		soldier.soldier_id,
		FireControlStateClass.display_name(cmd.fire_control_state),
	]
