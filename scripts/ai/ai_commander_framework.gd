class_name AiCommanderFramework
extends RefCounted
## Match-level AI orchestration. Authoritative host/server only — clients never tick AI.
##
## Discovers AI players from CommandHierarchy, ticks AiCommanders, coordinates objectives,
## and submits gameplay commands through CommandRouter (never direct GameState mutation).

const AiCommanderClass := preload("res://scripts/ai/ai_commander.gd")
const AiTeamCoordinatorClass := preload("res://scripts/ai/ai_team_coordinator.gd")
const AiBattlefieldSnapshotClass := preload("res://scripts/ai/ai_battlefield_snapshot.gd")
const AiOrderClass := preload("res://scripts/ai/ai_order.gd")
const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const AiCommanderStateClass := preload("res://scripts/ai/ai_commander_state.gd")
const CommandContextClass := preload("res://scripts/core/command_context.gd")

## TUNED — think every N simulation ticks (movement still runs every tick).
## 8 @ 20 Hz ≈ 2.5 Hz per commander; commanders are staggered across slots.
const THINK_EVERY_N_TICKS := 8
## Cap A* calls from all AI MoveCommands in one sim tick.
## One staggered thinker ≈ one squad order: lead A* + a couple formation fallbacks.
const MAX_AI_PATHFINDS_PER_TICK := 4

var _commanders: Dictionary = {} ## player_id -> AiCommander
var _coordinator: AiTeamCoordinatorClass = AiTeamCoordinatorClass.new()
var _find_path: Callable = Callable()
var _tick_counter: int = 0
var _enabled: bool = true
## Host/server authority gate. Clients must leave this false (no local AI execution).
var _authority: bool = true
## Optional override for tests: Callable(command, context) -> ActionResult
var submit_override: Callable = Callable()
var _pathfinds_remaining: int = 0
var _logged_simple_rush: bool = false
## ActionResults from the last tick() — Main presents these so movement_halts reach views.
var _last_tick_results: Array = []


func setup(game_state, find_path: Callable) -> void:
	_find_path = find_path
	_commanders.clear()
	_coordinator.clear()
	_tick_counter = 0
	if game_state == null or game_state.command_hierarchy == null:
		return
	for pid in game_state.command_hierarchy.all_player_ids():
		if not game_state.command_hierarchy.is_ai_player(pid):
			continue
		_commanders[pid] = AiCommanderClass.new(pid)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


## Only the authoritative host/server may tick AI. Thin clients call set_authority(false).
func set_authority(is_authority: bool) -> void:
	_authority = is_authority


func has_authority() -> bool:
	return _authority


func has_commanders() -> bool:
	return not _commanders.is_empty()


func get_commander(player_id: int) -> AiCommanderClass:
	return _commanders.get(player_id, null)


func all_commanders() -> Array:
	var out: Array = []
	for pid in _commanders.keys():
		out.append(_commanders[pid])
	return out


## Disable AI for a player that became Human. Fireteam / hierarchy links stay intact.
func disable_commander(player_id: int) -> void:
	if _commanders.has(player_id):
		_commanders.erase(player_id)
	_coordinator.set_claim(player_id, Vector2i(-999, -999))


## Enable AI for a player that became AI (leave / unused slot). Resumes plan via hierarchy.
func enable_commander(player_id: int) -> void:
	if player_id <= 0:
		return
	if _commanders.has(player_id):
		var existing: AiCommanderClass = _commanders[player_id]
		existing.request_replan("controller_ai")
		return
	var commander := AiCommanderClass.new(player_id)
	commander.request_replan("controller_ai")
	_commanders[player_id] = commander


## Rebuild commander set from hierarchy is_ai flags (after bulk join/leave).
func sync_from_hierarchy(game_state) -> void:
	if game_state == null or game_state.command_hierarchy == null:
		return
	var hierarchy = game_state.command_hierarchy
	var keep: Dictionary = {}
	for pid in hierarchy.all_player_ids():
		if not hierarchy.is_ai_player(int(pid)):
			continue
		keep[int(pid)] = true
		if not _commanders.has(int(pid)):
			enable_commander(int(pid))
	var remove_ids: Array = []
	for pid in _commanders.keys():
		if not keep.has(int(pid)):
			remove_ids.append(int(pid))
	for pid in remove_ids:
		disable_commander(int(pid))


## Apply a validated human order onto the live commander (called after ActionResolver).
func apply_order_to_commander(
	to_player_id: int,
	order_id: String,
	target_cell: Vector2i = Vector2i(-999, -999),
) -> bool:
	var commander: AiCommanderClass = _commanders.get(to_player_id, null)
	if commander == null:
		return false
	commander.apply_human_order(order_id, target_cell)
	return true


func notify_visibility_changed() -> void:
	for commander in all_commanders():
		commander.request_replan("visibility")


## Returns ActionResults produced this tick (move/fire/face/grenade) for presentation.
func tick(game_state) -> Array:
	_last_tick_results.clear()
	## Clients never execute AI — authority gate for dedicated-server readiness.
	if not _authority or not _enabled or game_state == null:
		return _last_tick_results
	if game_state.is_deployment_phase():
		return _last_tick_results
	_tick_counter += 1

	var now_msec: int = SimulationClock.get_ticks_msec()
	var commanders: Array = all_commanders()
	if commanders.is_empty():
		return _last_tick_results

	## Who thinks this sim tick?
	var thinkers: Array = []
	var slot := 0
	for commander in commanders:
		if (_tick_counter + slot) % THINK_EVERY_N_TICKS == 0:
			thinkers.append(commander)
		slot += 1
	if thinkers.is_empty():
		return _last_tick_results

	if AiCommanderClass.DIAGNOSTIC_SIMPLE_RUSH and not _logged_simple_rush:
		_logged_simple_rush = true
		GameLog.log_system(
			"[AI] DIAGNOSTIC_SIMPLE_RUSH on — AIs only march to enemy deployment (no fight/cover/fire)."
		)

	## ONE shared battlefield read for every thinker — not N× soldier/LOS scans.
	var thinker_ids: Array = []
	for commander in thinkers:
		thinker_ids.append(commander.player_id)
	## Simple rush skips visibility/LOS cache warm — movement roster only.
	var snapshot: AiBattlefieldSnapshotClass = AiBattlefieldSnapshotClass.build(
		game_state, thinker_ids, AiCommanderClass.DIAGNOSTIC_SIMPLE_RUSH
	)

	## Shared A* budget for this tick (all MoveCommands from these thinkers).
	_pathfinds_remaining = MAX_AI_PATHFINDS_PER_TICK
	var budgeted_find := func(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
		return _budgeted_find_path(from_cell, to_cell)

	for commander in thinkers:
		var claimed: Array[Vector2i] = []
		if not AiCommanderClass.DIAGNOSTIC_SIMPLE_RUSH:
			claimed = _coordinator.claimed_cells_for(commander.player_id)
		var cell: Vector2i = commander.tick(
			game_state,
			budgeted_find,
			func(command: RefCounted, context: CommandContextClass):
				return _submit(game_state, command, context),
			claimed,
			now_msec,
			snapshot,
		)
		if not AiCommanderClass.DIAGNOSTIC_SIMPLE_RUSH:
			_coordinator.set_claim(commander.player_id, cell)
	if not AiCommanderClass.DIAGNOSTIC_SIMPLE_RUSH:
		_coordinator.resolve_duplicate_claims(commanders)
	return _last_tick_results


func take_last_tick_results() -> Array:
	var out: Array = _last_tick_results.duplicate()
	_last_tick_results.clear()
	return out


func _budgeted_find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not _find_path.is_valid():
		return empty
	if _pathfinds_remaining <= 0:
		return empty
	_pathfinds_remaining -= 1
	var path: Variant = _find_path.call(from_cell, to_cell)
	if path is Array:
		var typed: Array[Vector2i] = []
		for cell in path:
			typed.append(Vector2i(cell))
		return typed
	return empty


## Advance one full stagger cycle so every commander gets exactly one think slot.
## Used by tests (and rare debug); runtime prefers per-tick `tick()`.
func tick_full_cycle(game_state) -> void:
	for _i in THINK_EVERY_N_TICKS:
		tick(game_state)


func debug_lines(game_state) -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("[DEBUG] AI Commanders")
	if AiCommanderClass.DIAGNOSTIC_SIMPLE_RUSH:
		lines.append("(DIAGNOSTIC_SIMPLE_RUSH — march to enemy deployment only)")
	if not _authority:
		lines.append("(client — AI runs on host only)")
	if _commanders.is_empty():
		lines.append("(none)")
		return lines
	var pids: Array = _commanders.keys()
	pids.sort()
	for pid in pids:
		var commander: AiCommanderClass = _commanders[pid]
		var snap: Dictionary = commander.debug_snapshot(game_state)
		var hierarchy = game_state.command_hierarchy if game_state != null else null
		var team_name := ""
		var player_name := "Player %d" % int(pid)
		if hierarchy != null:
			team_name = Team.display_name(hierarchy.get_team_id(int(pid)))
			player_name = hierarchy.get_display_name(int(pid))
			if player_name.is_empty():
				player_name = "Player %d" % int(pid)
		var plan_label := AiPlanClass.display_name(str(snap.get("plan", "")))
		var state_label := AiCommanderStateClass.display_name(str(snap.get("state", "")))
		var order_id := str(snap.get("order", AiOrderClass.ID_RESUME_PLAN))
		var order_label := AiOrderClass.display_name(order_id)
		var objective := str(snap.get("objective", "—"))
		var target := str(snap.get("target", ""))
		lines.append("%s %s" % [team_name, player_name])
		lines.append("  Plan: %s" % plan_label)
		lines.append("  State: %s" % state_label)
		lines.append("  Objective: %s" % objective)
		lines.append("  Order: %s" % order_label)
		if not target.is_empty():
			lines.append("  Target: %s" % target)
	return lines


func _submit(game_state, command: RefCounted, context: CommandContextClass):
	var result = null
	if submit_override.is_valid():
		result = submit_override.call(command, context)
	else:
		## Runtime: go through CommandRouter so MP can later intercept.
		result = CommandRouter.submit_command(game_state, command, context)
	if result != null:
		_last_tick_results.append(result)
	return result
