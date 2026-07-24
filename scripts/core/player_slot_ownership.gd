class_name PlayerSlotOwnership
extends RefCounted
## Runtime Human ↔ AI controller switches for multiplayer join/leave.
##
## Does NOT change fireteams, soldier ownership, commander links, or visibility.
## Only flips MatchConfig.controller + CommandHierarchy.is_ai and syncs AiCommanderFramework.
##
## Authoritative host/server only — clients never call these when networking lands.

const MatchConfigClass := preload("res://scripts/core/match_config.gd")
const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const AiCommanderFrameworkClass := preload("res://scripts/ai/ai_commander_framework.gd")


## Find an AI-controlled slot, optionally preferring a team. Returns player_id or -1.
static func find_ai_slot(game_state, preferred_team_id: int = -1) -> int:
	if game_state == null or game_state.command_hierarchy == null:
		return -1
	var hierarchy = game_state.command_hierarchy
	var fallback := -1
	var pids: Array = hierarchy.all_player_ids()
	pids.sort()
	for pid in pids:
		if not hierarchy.is_ai_player(int(pid)):
			continue
		var team_id: int = hierarchy.get_team_id(int(pid))
		if preferred_team_id > 0 and team_id == preferred_team_id:
			return int(pid)
		if fallback < 0:
			fallback = int(pid)
	return fallback


## Human joins: claim a specific AI slot. Preserves player_id / team / fireteam / plan stash.
static func claim_slot_as_human(
	game_state,
	framework: AiCommanderFrameworkClass,
	player_id: int,
) -> bool:
	if game_state == null or game_state.command_hierarchy == null:
		return false
	if player_id <= 0 or not game_state.command_hierarchy.has_player(player_id):
		return false
	if not game_state.command_hierarchy.is_ai_player(player_id):
		return false ## Already human / not AI.

	## Stash plans before flipping (resume on leave).
	game_state.command_hierarchy.stash_ai_plans_for_human(player_id)
	game_state.command_hierarchy.clear_active_ai_order(player_id)
	game_state.command_hierarchy.set_is_ai(player_id, false)

	_sync_match_config_controller(game_state, player_id, MatchConfigClass.ControllerType.HUMAN)

	if framework != null:
		framework.disable_commander(player_id)
	return true


## Join helper: first AI slot (optional preferred team) becomes Human.
## Returns claimed player_id, or -1 on failure.
static func join_as_human(
	game_state,
	framework: AiCommanderFrameworkClass,
	preferred_team_id: int = -1,
) -> int:
	var pid := find_ai_slot(game_state, preferred_team_id)
	if pid <= 0:
		return -1
	if not claim_slot_as_human(game_state, framework, pid):
		return -1
	return pid


## Human leaves: restore AI control and resume stashed / existing plan.
static func release_slot_to_ai(
	game_state,
	framework: AiCommanderFrameworkClass,
	player_id: int,
) -> bool:
	if game_state == null or game_state.command_hierarchy == null:
		return false
	if player_id <= 0 or not game_state.command_hierarchy.has_player(player_id):
		return false
	if game_state.command_hierarchy.is_ai_player(player_id):
		return false ## Already AI.

	var human_team := _local_human_team(game_state)
	game_state.command_hierarchy.set_is_ai(player_id, true)
	game_state.command_hierarchy.restore_ai_plans_after_human(
		player_id,
		human_team,
	)
	game_state.command_hierarchy.clear_active_ai_order(player_id)

	_sync_match_config_controller(game_state, player_id, MatchConfigClass.ControllerType.AI)

	if framework != null:
		framework.enable_commander(player_id)
	return true


static func _sync_match_config_controller(game_state, player_id: int, controller: int) -> void:
	if game_state.session == null or game_state.session.match_config == null:
		return
	var cfg: MatchConfigClass = game_state.session.match_config
	## Multiplayer allows multiple humans — set without SP demotion side effects.
	var prev_mode: int = cfg.game_mode
	## Temporarily treat as MP so set_slot_controller won't demote other humans.
	if prev_mode == MatchConfigClass.GameModeKind.SINGLE_PLAYER:
		## SP runtime leave/join is unusual; still only touch this slot.
		for i in cfg.slots.size():
			var slot: Dictionary = cfg.slots[i]
			if int(slot.get("player_id", -1)) != player_id:
				continue
			slot["controller"] = controller
			cfg.slots[i] = slot
			break
		cfg._normalize_ai_plans_after_controller_change()
		return
	cfg.set_slot_controller(player_id, controller)


static func _local_human_team(game_state) -> int:
	if game_state.session != null and game_state.session.match_config != null:
		return game_state.session.match_config.local_human_team_id()
	var hierarchy = game_state.command_hierarchy
	for pid in hierarchy.all_player_ids():
		if not hierarchy.is_ai_player(int(pid)):
			return hierarchy.get_team_id(int(pid))
	return Team.USA
