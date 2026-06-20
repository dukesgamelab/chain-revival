class_name SoldierActions
extends RefCounted
## Deprecated entry points — delegate to CommandRouter when game_state is available.
##
## Kept so existing call sites stay stable during the architecture migration.

const GameStateClass := preload("res://scripts/core/game_state.gd")
const PositionCommandClass := preload("res://scripts/commands/position_command.gd")
const FireControlCommandClass := preload("res://scripts/commands/fire_control_command.gd")
const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")


static func apply_position(state: GameStateClass, cmd: PositionCommandClass) -> String:
	var result := ActionResolverClass.execute_position(state, cmd)
	return result.status_message if result.success else ""


static func apply_fire_control(state: GameStateClass, cmd: FireControlCommandClass) -> String:
	var result := ActionResolverClass.execute_fire_control(state, cmd)
	return result.status_message if result.success else ""


static func arm_movement_mode(soldier: SoldierState, mode: int) -> String:
	return ActionResolverClass.arm_movement_mode_for_soldier(soldier, mode)


static func validate_move(soldier: SoldierState, mode: int) -> String:
	return ActionResolverClass.validate_move(soldier, mode)
