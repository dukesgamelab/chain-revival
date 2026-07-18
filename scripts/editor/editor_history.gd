class_name EditorHistory
extends RefCounted
## Snapshot undo/redo for MapData.

const MAX_DEPTH := 64

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


func clear() -> void:
	_undo.clear()
	_redo.clear()


func push(map_data: MapData) -> void:
	if map_data == null:
		return
	_undo.append(map_data.snapshot())
	if _undo.size() > MAX_DEPTH:
		_undo.remove_at(0)
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo(map_data: MapData) -> MapData:
	if map_data == null or _undo.is_empty():
		return null
	_redo.append(map_data.snapshot())
	return MapData.from_dict(_undo.pop_back())


func redo(map_data: MapData) -> MapData:
	if map_data == null or _redo.is_empty():
		return null
	_undo.append(map_data.snapshot())
	return MapData.from_dict(_redo.pop_back())
