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

enum MatchPhase { DEPLOYMENT, RUNNING }

var session: GameSession
var map_data: MapData
var objects: ObjectRegistry
var command_hierarchy: CommandHierarchyClass
## Per-player weapon/equipment pool (WeaponCashe).
var weapon_cache: WeaponCacheClass
var match_phase: int = MatchPhase.DEPLOYMENT
## Local/offline controlling player for UI + shared visibility (human USA by default).
var local_player_id: int = 1


func _init(game_session: GameSession, map: MapData) -> void:
	session = game_session
	map_data = map
	objects = ObjectRegistry.new()
	objects.rebuild_from(self)
	command_hierarchy = CommandHierarchyClass.new()
	command_hierarchy.bootstrap_default_match()
	local_player_id = 1
	if session != null and session.local_player_id > 0:
		local_player_id = session.local_player_id
	match_phase = MatchPhase.DEPLOYMENT
	weapon_cache = WeaponCacheClass.new()
	_bootstrap_weapon_caches()


func _bootstrap_weapon_caches() -> void:
	var player_ids: Array[int] = command_hierarchy.all_player_ids()
	weapon_cache.bootstrap_default_caches(
		player_ids,
		func(pid: int) -> int: return command_hierarchy.get_team_id(pid),
	)
	## AI players auto-distribute specials from their starting cache onto rifle-holders.
	for pid in player_ids:
		if not bool(command_hierarchy.get_entry(pid).get("is_ai", false)):
			continue
		weapon_cache.auto_distribute_to_soldiers(
			self,
			pid,
			command_hierarchy.get_soldier_ids(pid),
			command_hierarchy.get_team_id(pid),
		)


func rebuild_object_registry() -> void:
	objects.rebuild_from(self)


func get_soldier(team_id: int, soldier_id: int) -> SoldierState:
	var from_registry: SoldierState = objects.get_soldier_by_team_slot(team_id, soldier_id)
	if from_registry != null:
		return from_registry
	return session.get_fireteam(team_id).get_soldier(soldier_id)


func get_soldier_by_id(object_id: String) -> SoldierState:
	return objects.get_soldier(object_id)


## First living soldier standing on this tile (any team).
func find_living_soldier_at_cell(cell: Vector2i) -> SoldierState:
	for fireteam in session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.is_dead:
				continue
			if soldier_state.grid_position == cell:
				return soldier_state
	return null


## Any soldier on this tile, including dead or prone.
func find_soldier_at_cell(cell: Vector2i) -> SoldierState:
	for fireteam in session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.grid_position == cell:
				return soldier_state
	return null


func enemy_team_id(team_id: int) -> int:
	return Team.GERMANY if team_id == Team.USA else Team.USA


## --- Command hierarchy accessors (IDs only) ---

func get_commander(player_id: int) -> int:
	return command_hierarchy.get_commander(player_id)


func get_subordinates(player_id: int) -> Array[int]:
	return command_hierarchy.get_subordinates(player_id)


func commanders_with_openings() -> Array[int]:
	return command_hierarchy.commanders_with_openings()


func players_without_commanders() -> Array[int]:
	return command_hierarchy.players_without_commanders()


func all_command_links() -> Array[Dictionary]:
	return command_hierarchy.all_links()


func begin_running_phase() -> void:
	match_phase = MatchPhase.RUNNING


func is_deployment_phase() -> bool:
	return match_phase == MatchPhase.DEPLOYMENT
