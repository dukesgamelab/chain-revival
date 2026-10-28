class_name GameState
extends RefCounted
## Single source of truth for authoritative gameplay data.
##
## Owns the session (soldiers, teams), map (blockers, cover objects, walkability),
## ObjectRegistry (stable ID → object index), and CommandHierarchy (player chain of command).
## All gameplay mutations go through CommandRouter → ActionResolver — never write soldier
## or map fields from UI, Soldier views, or scene scripts.
##
## Authoritative soldier fields (via SoldierState): grid_position, facing_direction,
## is_dead, position_state, movement_mode, fire_control_state, ammo, engagement,
## grenades, stun timers, stress, and weapon assignment.
## Soldier scene nodes are presentation-only and are never stored in the registry.

const CommandHierarchyClass := preload("res://scripts/core/command_hierarchy.gd")
const WeaponCacheClass := preload("res://scripts/core/weapon_cache.gd")
const ScenarioRulesClass := preload("res://scripts/core/scenario_rules.gd")

enum MatchPhase { DEPLOYMENT, RUNNING, ENDED }

var session: GameSession
var map_data: MapData
var objects: ObjectRegistry
var command_hierarchy: CommandHierarchyClass
## Per-player weapon/equipment pool (WeaponCashe).
var weapon_cache: WeaponCacheClass
var match_phase: int = MatchPhase.DEPLOYMENT
## Local/offline controlling player for UI + shared visibility (human USA by default).
var local_player_id: int = 1
## When true, deployment has a countdown and soldiers cannot leave spawn zones.
var timed_deployment: bool = false
## Countdown seconds while timed_deployment is active (sim-tick driven).
var deployment_time_remaining_sec: float = 0.0
## O(1) cell → SoldierState for LOS. Updated on moves; rebuilt when positions change.
var _cell_occupancy: Dictionary = {}
var _occupancy_generation: int = -1

## --- Scenario clock + scoring (authoritative; sim-tick driven) ---
var scenario_time_remaining_sec: float = 0.0
var scenario_elapsed_sec: float = 0.0
var scenario_ended: bool = false
## Survival Mode: 1 v All — no time limit; GE reinforcements continue after wipes.
var survival_mode: bool = false
## Survival: German soldiers eliminated (authoritative kill count).
var survival_enemies_killed: int = 0
## ScenarioEndCause / ScenarioWinner enums (kept separate like OG ScEnd Cause / Winner).
var end_cause: int = 0
var winner: int = 0
## team_id -> int points from kills (can go negative when losing soldiers).
var team_kill_points: Dictionary = {}
## team_id -> int actual kill count (soldiers killed by this team).
var team_kill_counts: Dictionary = {}
## team_id -> int points from held VPs at mission end.
var team_terrain_points: Dictionary = {}
## VP poll accumulator (seconds of sim time). Used by ScenarioRules.
var vp_poll_accum_sec: float = 0.0
## Set by ScenarioRules when a VP holder flips — Main clears after redraw.
var vp_holders_dirty: bool = false


func _init(game_session: GameSession, map: MapData) -> void:
	session = game_session
	map_data = map
	objects = ObjectRegistry.new()
	objects.rebuild_from(self)
	command_hierarchy = CommandHierarchyClass.new()
	command_hierarchy.bootstrap_from_session(session)
	local_player_id = 1
	if session != null and session.local_player_id > 0:
		local_player_id = session.local_player_id
	match_phase = MatchPhase.DEPLOYMENT
	weapon_cache = WeaponCacheClass.new()
	_bootstrap_weapon_caches()
	rebuild_cell_occupancy()


func _bootstrap_weapon_caches() -> void:
	var player_ids: Array[int] = command_hierarchy.all_player_ids()
	weapon_cache.bootstrap_default_caches(
		player_ids,
		func(pid: int) -> int: return command_hierarchy.get_team_id(pid),
	)
	## Do not auto-equip specials at match start — human (and AI) assign via Weapons dialog.
	## AI auto-distribute still runs when a commander gives gear to an AI subordinate player.


func rebuild_object_registry() -> void:
	objects.rebuild_from(self)


func get_soldier(team_id: int, soldier_id: int) -> SoldierState:
	var from_registry: SoldierState = objects.get_soldier_by_team_slot(team_id, soldier_id)
	if from_registry != null:
		return from_registry
	return session.get_fireteam(team_id).get_soldier(soldier_id)


func get_soldier_by_id(object_id: String) -> SoldierState:
	return objects.get_soldier(object_id)


## Rebuild occupancy from current soldier positions (combat scan / load / tests).
func rebuild_cell_occupancy() -> void:
	_cell_occupancy.clear()
	if session == null:
		_occupancy_generation = SoldierState.position_generation
		return
	for fireteam in session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state == null:
				continue
			_cell_occupancy[soldier_state.grid_position] = soldier_state
	_occupancy_generation = SoldierState.position_generation


## Cheap guard used by LOS — rebuilds only after teleports / load / missed notifies.
func ensure_cell_occupancy() -> void:
	if _occupancy_generation == SoldierState.position_generation:
		return
	rebuild_cell_occupancy()


## Incremental update after an authoritative grid move.
func notify_soldier_cell_changed(
	soldier: SoldierState,
	from_cell: Vector2i,
	to_cell: Vector2i,
) -> void:
	if soldier == null:
		return
	## If positions were teleported without notify, rebuild instead of patching a stale map.
	if _occupancy_generation != SoldierState.position_generation - 1:
		rebuild_cell_occupancy()
		return
	if _cell_occupancy.get(from_cell) == soldier:
		_cell_occupancy.erase(from_cell)
	_cell_occupancy[to_cell] = soldier
	_occupancy_generation = SoldierState.position_generation


## First living soldier standing on this tile (any team). O(1) via occupancy map.
func find_living_soldier_at_cell(cell: Vector2i) -> SoldierState:
	ensure_cell_occupancy()
	var soldier_state: SoldierState = _cell_occupancy.get(cell)
	if soldier_state != null and not soldier_state.is_dead:
		return soldier_state
	return null


## Any soldier on this tile, including dead or prone. O(1) via occupancy map.
func find_soldier_at_cell(cell: Vector2i) -> SoldierState:
	ensure_cell_occupancy()
	return _cell_occupancy.get(cell)


func enemy_team_id(team_id: int) -> int:
	return Team.GERMANY if team_id == Team.USA else Team.USA


## --- Command hierarchy accessors (IDs only) ---

func get_commander(player_id: int) -> int:
	return command_hierarchy.get_commander(player_id)


func get_subordinates(player_id: int) -> Array[int]:
	return command_hierarchy.get_subordinates(player_id)


func get_subordinate_ids(player_id: int) -> Array[int]:
	return command_hierarchy.get_subordinate_ids(player_id)


func commanders_with_openings() -> Array[int]:
	return command_hierarchy.commanders_with_openings()


func players_without_commanders() -> Array[int]:
	return command_hierarchy.players_without_commanders()


func all_command_links() -> Array[Dictionary]:
	return command_hierarchy.all_links()


## --- Phase 2 future hooks (stubs / thin wrappers; no order issuing yet) ---

func issue_order(from_player_id: int, to_player_id: int, order: Dictionary = {}) -> Dictionary:
	return command_hierarchy.issue_order(from_player_id, to_player_id, order)


func get_visible_players(player_id: int) -> Array[int]:
	return command_hierarchy.get_visible_players(player_id)


## Enemy soldier keys currently visible to this player (own FT ∪ subordinate LOS).
func get_visible_enemies(player_id: int) -> Array[String]:
	return CombatSystem.effective_visibility_keys(self, player_id)


func can_issue_orders(player_id: int) -> bool:
	return command_hierarchy.can_issue_orders(player_id)


func can_receive_orders(player_id: int) -> bool:
	return command_hierarchy.can_receive_orders(player_id)


## --- Phase 3 AI plans (selection / resolution; no behavior) ---

func get_selected_ai_plan(player_id: int) -> String:
	return command_hierarchy.get_selected_ai_plan(player_id)


func get_active_ai_plan(player_id: int) -> String:
	return command_hierarchy.get_active_ai_plan(player_id)


func set_selected_ai_plan(player_id: int, plan) -> void:
	## Accepts AiPlan string id. Prefer SetAiPlanCommand from UI.
	command_hierarchy.set_selected_ai_plan(player_id, str(plan))


func resolve_ai_plans() -> void:
	## Resolve Random once; active plans stay fixed for the match.
	command_hierarchy.resolve_ai_plans()


func are_ai_plans_locked() -> bool:
	## Locked once Scenario Running (MatchPhase.RUNNING).
	return match_phase == MatchPhase.RUNNING


## --- Serialization (IDs only; no scene refs) ---

func to_dict() -> Dictionary:
	return {
		"match_phase": match_phase,
		"local_player_id": local_player_id,
		"session": session.to_dict() if session != null else {},
		"command_hierarchy": command_hierarchy.to_dict() if command_hierarchy != null else {},
	}


func load_hierarchy_from_dict(data: Dictionary) -> void:
	if command_hierarchy == null:
		command_hierarchy = CommandHierarchyClass.new()
	command_hierarchy.load_from_dict(data)
	CombatSystem.notify_command_hierarchy_changed(self)


func begin_running_phase() -> void:
	match_phase = MatchPhase.RUNNING
	deployment_time_remaining_sec = 0.0
	ScenarioRulesClass.begin_scenario(self)


## SP/MP: arm the deploy countdown. Offline Quick Start leaves timed_deployment false.
func begin_timed_deployment(duration_sec: float = ScenarioRulesClass.DEPLOYMENT_TIME_SEC) -> void:
	timed_deployment = true
	match_phase = MatchPhase.DEPLOYMENT
	deployment_time_remaining_sec = maxf(0.0, duration_sec)


func is_deployment_phase() -> bool:
	return match_phase == MatchPhase.DEPLOYMENT


## Zone lock + countdown active (not the brief Offline dialog-only deployment).
func locks_deployment_zone() -> bool:
	return is_deployment_phase() and timed_deployment


func is_ended_phase() -> bool:
	return match_phase == MatchPhase.ENDED or scenario_ended


func local_team_id() -> int:
	if command_hierarchy != null and local_player_id > 0:
		var tid := command_hierarchy.get_team_id(local_player_id)
		if tid == Team.USA or tid == Team.GERMANY:
			return tid
	if session != null and session.active_team_id > 0:
		return session.active_team_id
	return Team.USA


func time_remaining() -> float:
	return maxf(0.0, scenario_time_remaining_sec)
