class_name ObjectRegistry
extends RefCounted
## ID → object index owned by GameState.
## Does not replace Fireteam arrays or MapData; rebuild/sync from those sources.

const KIND_SOLDIER := "soldier"
const KIND_MAP := "map"
const KIND_GRENADE := "grenade"

var _soldiers_by_id: Dictionary = {}
var _soldiers_by_slot: Dictionary = {}
var _map_objects_by_id: Dictionary = {}
var _map_objects_by_cell: Dictionary = {}
var _grenades_by_id: Dictionary = {}


func clear() -> void:
	_soldiers_by_id.clear()
	_soldiers_by_slot.clear()
	_map_objects_by_id.clear()
	_map_objects_by_cell.clear()
	_grenades_by_id.clear()


func rebuild_from(game_state) -> void:
	clear()
	if game_state == null:
		return
	if game_state.session != null:
		for fireteam in game_state.session.all_fireteams():
			for state in fireteam.soldiers:
				var soldier: SoldierState = state
				register_soldier(soldier)
				if soldier.has_pending_grenade():
					register_grenade_from_soldier(soldier)
	if game_state.map_data != null:
		for cell in game_state.map_data.get_object_cells():
			var type_id: String = game_state.map_data.get_object_type(cell)
			if not type_id.is_empty():
				register_map_object(cell, type_id)


func register_soldier(soldier: SoldierState) -> void:
	if soldier == null:
		return
	var oid := ObjectId.soldier(soldier.team_id, soldier.soldier_id)
	_soldiers_by_id[oid] = soldier
	_soldiers_by_slot[ObjectId.team_soldier_key(soldier.team_id, soldier.soldier_id)] = soldier


func get_soldier(object_id: String) -> SoldierState:
	return _soldiers_by_id.get(object_id) as SoldierState


func get_soldier_by_team_slot(team_id: int, soldier_id: int) -> SoldierState:
	return _soldiers_by_slot.get(ObjectId.team_soldier_key(team_id, soldier_id)) as SoldierState


func register_map_object(cell: Vector2i, type_id: String) -> void:
	if type_id.is_empty():
		unregister_map_object(cell)
		return
	var oid := ObjectId.map_object(cell)
	var entry := {
		"object_id": oid,
		"cell": cell,
		"type_id": type_id,
	}
	_map_objects_by_id[oid] = entry
	_map_objects_by_cell[cell] = entry


func unregister_map_object(cell: Vector2i) -> void:
	var oid := ObjectId.map_object(cell)
	_map_objects_by_id.erase(oid)
	_map_objects_by_cell.erase(cell)


func get_map_object(object_id: String) -> Dictionary:
	var entry: Variant = _map_objects_by_id.get(object_id)
	return entry if entry is Dictionary else {}


func get_map_object_at(cell: Vector2i) -> Dictionary:
	var entry: Variant = _map_objects_by_cell.get(cell)
	return entry if entry is Dictionary else {}


func register_grenade_from_soldier(soldier: SoldierState) -> void:
	var grenade := GrenadeState.from_soldier(soldier)
	if grenade == null:
		return
	_grenades_by_id[grenade.object_id] = grenade


func unregister_grenade(object_id: String) -> void:
	_grenades_by_id.erase(object_id)


func get_grenade(object_id: String) -> GrenadeState:
	return _grenades_by_id.get(object_id) as GrenadeState


func all_grenade_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _grenades_by_id.keys():
		ids.append(str(key))
	return ids


## Re-index in-flight grenades from SoldierState (e.g. after mark_killed clears a fuse).
func sync_grenades_from(game_state) -> void:
	_grenades_by_id.clear()
	if game_state == null or game_state.session == null:
		return
	for fireteam in game_state.session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier: SoldierState = state
			if soldier.has_pending_grenade():
				register_grenade_from_soldier(soldier)


func has(object_id: String) -> bool:
	return (
		_soldiers_by_id.has(object_id)
		or _map_objects_by_id.has(object_id)
		or _grenades_by_id.has(object_id)
	)


func kind_of(object_id: String) -> String:
	if _soldiers_by_id.has(object_id):
		return KIND_SOLDIER
	if _map_objects_by_id.has(object_id):
		return KIND_MAP
	if _grenades_by_id.has(object_id):
		return KIND_GRENADE
	if object_id.begins_with("soldier:"):
		return KIND_SOLDIER
	if object_id.begins_with("map:"):
		return KIND_MAP
	if object_id.begins_with("grenade:"):
		return KIND_GRENADE
	return ""
