extends Node
## Autoload entry point for gameplay commands.
##
## Flow (OFFLINE_DEV):
##   Input/UI → CommandRouter → ActionResolver → GameState → visuals
##
## LOCAL_MULTIPLAYER: MoveCommand is sent to the Node server (see NetworkClient).
## Other commands stay local until later phases. Single-player is unchanged.

const ActionResolverClass := preload("res://scripts/core/action_resolver.gd")
const ActionResultClass := preload("res://scripts/core/action_result.gd")
const GameStateClass := preload("res://scripts/core/game_state.gd")
const CommandContextClass := preload("res://scripts/core/command_context.gd")
const MoveCommandClass := preload("res://scripts/commands/move_command.gd")
const FaceCommandClass := preload("res://scripts/commands/face_command.gd")
const FireCommandClass := preload("res://scripts/commands/fire_command.gd")
const PositionCommandClass := preload("res://scripts/commands/position_command.gd")
const FireControlCommandClass := preload("res://scripts/commands/fire_control_command.gd")
const HaltCommandClass := preload("res://scripts/commands/halt_command.gd")
const GrenadeCommandClass := preload("res://scripts/commands/grenade_command.gd")
const AssignCommanderCommandClass := preload("res://scripts/commands/assign_commander_command.gd")
const BreakCommandLinkCommandClass := preload("res://scripts/commands/break_command_link_command.gd")
const SetMissionCommanderCommandClass := preload("res://scripts/commands/set_mission_commander_command.gd")
const SetAiPlanCommandClass := preload("res://scripts/commands/set_ai_plan_command.gd")
const IssueAiOrderCommandClass := preload("res://scripts/commands/issue_ai_order_command.gd")
const AssignWeaponCommandClass := preload("res://scripts/commands/assign_weapon_command.gd")
const ReturnWeaponCommandClass := preload("res://scripts/commands/return_weapon_command.gd")


func submit_command(
	game_state: GameStateClass,
	command: RefCounted,
	context: CommandContextClass = null,
) -> ActionResultClass:
	return _route(
		"command:%s" % _command_label(command),
		func() -> ActionResultClass:
			return ActionResolverClass.execute(game_state, command, context),
	)


func arm_movement_mode(
	game_state: GameStateClass,
	team_id: int,
	soldier_id: int,
	movement_mode: int,
) -> ActionResultClass:
	return _route(
		"arm_movement_mode team=%d soldier=%d mode=%d" % [team_id, soldier_id, movement_mode],
		func() -> ActionResultClass:
			return ActionResolverClass.arm_movement_mode(
				game_state, team_id, soldier_id, movement_mode,
			),
	)


func reload_map_from_file(game_state: GameStateClass) -> ActionResultClass:
	return _route(
		"reload_map_from_file",
		func() -> ActionResultClass:
			return ActionResolverClass.reload_map_from_file(game_state),
	)


func load_saved_session(
	game_state: GameStateClass,
	file_path: String = "",
) -> ActionResultClass:
	return _route(
		"load_saved_session",
		func() -> ActionResultClass:
			if file_path.is_empty():
				return ActionResolverClass.load_saved_session(game_state)
			return ActionResolverClass.load_saved_session(game_state, file_path),
	)


func cancel_sustained_fire(game_state: GameStateClass) -> ActionResultClass:
	return _route(
		"cancel_sustained_fire",
		func() -> ActionResultClass:
			ActionResolverClass.cancel_all_sustained_fire(game_state)
			return ActionResultClass.new(),
	)


func _route(action_label: String, resolver_call: Callable) -> ActionResultClass:
	var mode_name := GameMode.display_name(GameModeManager.get_mode())
	GameLog.log_system("[CommandRouter] submit: %s (mode=%s)" % [action_label, mode_name])

	if GameModeManager.is_local_multiplayer() and (
		action_label == "command:MoveCommand"
		or action_label == "command:FaceCommand"
		or action_label == "command:PositionCommand"
		or action_label == "command:FireControlCommand"
		or action_label == "command:FireCommand"
	):
		GameLog.log_system("[CommandRouter] refused local %s — server is authoritative" % action_label)
		return ActionResultClass.fail("That command must be resolved by the match server.")

	if GameModeManager.is_offline_dev() or GameModeManager.is_local_multiplayer():
		var route_note := "locally → ActionResolver"
		if GameModeManager.is_local_multiplayer():
			route_note = "locally → ActionResolver (remaining local-only commands)"
		GameLog.log_system("[CommandRouter] routed %s" % route_note)
		return resolver_call.call() as ActionResultClass

	return ActionResultClass.fail("Unknown game mode.")


func _command_label(command: RefCounted) -> String:
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
	if command is HaltCommandClass:
		return "HaltCommand"
	if command is GrenadeCommandClass:
		return "GrenadeCommand"
	if command is AssignCommanderCommandClass:
		return "AssignCommanderCommand"
	if command is BreakCommandLinkCommandClass:
		return "BreakCommandLinkCommand"
	if command is SetMissionCommanderCommandClass:
		return "SetMissionCommanderCommand"
	if command is SetAiPlanCommandClass:
		return "SetAiPlanCommand"
	if command is IssueAiOrderCommandClass:
		return "IssueAiOrderCommand"
	if command is AssignWeaponCommandClass:
		return "AssignWeaponCommand"
	if command is ReturnWeaponCommandClass:
		return "ReturnWeaponCommand"
	if command != null:
		return command.get_class()
	return "null"
