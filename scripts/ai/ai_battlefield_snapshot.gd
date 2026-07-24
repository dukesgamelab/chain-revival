class_name AiBattlefieldSnapshot
extends RefCounted
## One shared read of the battlefield for all AI commanders thinking this frame.
## Built once in AiCommanderFramework — never per-commander soldier/LOS scans.

var visible_enemies: Dictionary = {} ## player_id -> Array[SoldierState]
var living_soldiers: Dictionary = {} ## player_id -> Array[SoldierState]
var fireteam_moving: Dictionary = {} ## player_id -> bool


## Read-only snapshot. Does NOT force visibility rebuild (combat scan owns that).
## skip_visibility: diagnostic rush mode — roster/moving only, no LOS cache warm.
static func build(game_state, ai_player_ids: Array, skip_visibility: bool = false):
	var snap = new()
	if game_state == null or game_state.command_hierarchy == null:
		return snap
	## Ensure caches exist from the last combat scan / movement — no forced LOS pass.
	if not skip_visibility:
		CombatSystem.ensure_visibility_readable(game_state)
	var hierarchy = game_state.command_hierarchy
	for raw_pid in ai_player_ids:
		var pid := int(raw_pid)
		var living: Array = []
		var moving := false
		var team_id: int = hierarchy.get_team_id(pid)
		for sid in hierarchy.get_soldier_ids(pid):
			var soldier = game_state.get_soldier(team_id, int(sid))
			if soldier == null or soldier.is_dead or soldier.is_stunned():
				continue
			living.append(soldier)
			if soldier.is_moving:
				moving = true
		snap.living_soldiers[pid] = living
		snap.fireteam_moving[pid] = moving

		var visible: Array = []
		if not skip_visibility:
			for key in game_state.get_visible_enemies(pid):
				var parts := str(key).split(":")
				if parts.size() < 2:
					continue
				var enemy = game_state.get_soldier(int(parts[0]), int(parts[1]))
				if enemy != null and not enemy.is_dead:
					visible.append(enemy)
		snap.visible_enemies[pid] = visible
	return snap


func visible_for(player_id: int) -> Array:
	return visible_enemies.get(player_id, [])


func living_for(player_id: int) -> Array:
	return living_soldiers.get(player_id, [])


func is_moving(player_id: int) -> bool:
	return bool(fireteam_moving.get(player_id, false))
