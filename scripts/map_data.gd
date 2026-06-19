class_name MapData
extends RefCounted
## Pure map gameplay data: size, map objects, and team spawn points.

const DEFAULT_FILE := "res://maps/test_map.json"
const DEFAULT_WIDTH := 60
const DEFAULT_HEIGHT := 60
const MapObjectRegistryClass := preload("res://scripts/map_object_registry.gd")

## Default deployment: vertical columns facing each other, paired by row (same y).
const DEFAULT_TEAM_SEPARATION := 10
const DEFAULT_USA_ANCHOR := Vector2i(26, 28)
const DEFAULT_GERMANY_ANCHOR := Vector2i(36, 28)

var map_name: String = "test_map"
var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT
var team_1_spawn_points: Array[Vector2i] = []
var team_2_spawn_points: Array[Vector2i] = []

## Legacy list kept in sync with movement-blocking objects for older saves.
var blocked_tiles: Array[Vector2i] = []

var _object_lookup: Dictionary = {}


func _init() -> void:
	_rebuild_blocked_tiles_list()


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func get_object_type(cell: Vector2i) -> String:
	return str(_object_lookup.get(cell, ""))


func get_object_def(cell: Vector2i) -> MapObjectDef:
	var type_id := get_object_type(cell)
	if type_id.is_empty():
		return null
	return MapObjectRegistryClass.get_def(type_id)


func has_object(cell: Vector2i) -> bool:
	return _object_lookup.has(cell)


func get_object_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in _object_lookup.keys():
		cells.append(cell)
	return cells


func is_blocked(cell: Vector2i) -> bool:
	var object_def := get_object_def(cell)
	return object_def != null and object_def.blocks_movement


func is_walkable(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and not is_blocked(cell)


func set_object(cell: Vector2i, type_id: String) -> void:
	if not is_in_bounds(cell):
		return
	if type_id.is_empty():
		clear_object(cell)
		return
	_object_lookup[cell] = MapObjectRegistryClass.normalize_type_id(type_id)
	_rebuild_blocked_tiles_list()


## Place repeated 1-tile wall segments along a grid line.
func create_wall_line(start_tile: Vector2i, direction: Vector2i, length: int) -> Array[Vector2i]:
	var placed: Array[Vector2i] = []
	if length <= 0:
		return placed

	var step := Vector2i(
		clampi(direction.x, -1, 1),
		clampi(direction.y, -1, 1),
	)
	if step == Vector2i.ZERO:
		return placed

	for i in range(length):
		var cell := start_tile + step * i
		if not is_in_bounds(cell):
			continue
		set_object(cell, MapObjectRegistryClass.TYPE_WALL_STRAIGHT)
		placed.append(cell)
	return placed


func clear_object(cell: Vector2i) -> void:
	_object_lookup.erase(cell)
	_rebuild_blocked_tiles_list()


## Flip a tree (or other default blocked object) on this tile. Returns true if now blocked.
func toggle_blocked(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	if is_blocked(cell):
		clear_object(cell)
		return false
	set_object(cell, MapObjectRegistryClass.DEFAULT_BLOCKED_TYPE)
	return true


func set_blocked(cell: Vector2i, blocked: bool) -> void:
	if blocked:
		set_object(cell, MapObjectRegistryClass.DEFAULT_BLOCKED_TYPE)
	else:
		clear_object(cell)


func to_dict() -> Dictionary:
	return {
		"map_name": map_name,
		"width": width,
		"height": height,
		"map_objects": _objects_to_json(),
		"blocked_tiles": _cells_to_json(blocked_tiles),
		"team_1_spawn_points": _cells_to_json(team_1_spawn_points),
		"team_2_spawn_points": _cells_to_json(team_2_spawn_points),
	}


static func from_dict(data: Dictionary) -> MapData:
	var map_data := MapData.new()
	map_data.map_name = str(data.get("map_name", "test_map"))
	map_data.width = int(data.get("width", DEFAULT_WIDTH))
	map_data.height = int(data.get("height", DEFAULT_HEIGHT))
	map_data.team_1_spawn_points = _cells_from_json(data.get("team_1_spawn_points", []))
	map_data.team_2_spawn_points = _cells_from_json(data.get("team_2_spawn_points", []))
	map_data._object_lookup.clear()

	var raw_objects: Variant = data.get("map_objects", [])
	if raw_objects is Array and not raw_objects.is_empty():
		map_data._load_objects_from_json(raw_objects)
	else:
		for cell in _cells_from_json(data.get("blocked_tiles", [])):
			map_data.set_object(cell, MapObjectRegistryClass.DEFAULT_BLOCKED_TYPE)

	map_data._rebuild_blocked_tiles_list()
	return map_data


static func default_usa_spawn_points() -> Array[Vector2i]:
	return _default_spawn_line(DEFAULT_USA_ANCHOR)


static func default_germany_spawn_points() -> Array[Vector2i]:
	return _default_spawn_line(DEFAULT_GERMANY_ANCHOR)


static func _default_spawn_line(anchor: Vector2i) -> Array[Vector2i]:
	return [
		anchor,
		anchor + Vector2i(0, 1),
		anchor + Vector2i(0, 2),
		anchor + Vector2i(0, 3),
	]


static func create_default() -> MapData:
	var map_data := MapData.new()
	map_data.map_name = "test_map"
	map_data.width = DEFAULT_WIDTH
	map_data.height = DEFAULT_HEIGHT
	map_data.team_1_spawn_points = default_usa_spawn_points()
	map_data.team_2_spawn_points = default_germany_spawn_points()
	_place_between_teams_cover(map_data)
	return map_data


## Haybail, tree, and a 5-tile wall row (visually side-by-side in isometric view).
static func _place_between_teams_cover(map_data: MapData) -> void:
	var mid_x := DEFAULT_USA_ANCHOR.x + (DEFAULT_TEAM_SEPARATION / 2)  # x=31 between 26 and 36
	_clear_legacy_lane_walls(map_data)
	var cover_line: Array[Dictionary] = [
		{"cell": Vector2i(mid_x, DEFAULT_USA_ANCHOR.y - 1), "type": MapObjectRegistryClass.TYPE_HAYBAIL},
		{"cell": Vector2i(mid_x, DEFAULT_USA_ANCHOR.y + 2), "type": MapObjectRegistryClass.TYPE_TREE},
	]
	for entry in cover_line:
		var cell: Vector2i = entry.cell
		if map_data.is_in_bounds(cell):
			map_data.set_object(cell, entry.type)
	# Grid (1, -1): constant screen row — each segment sits directly beside the last on screen.
	map_data.create_wall_line(Vector2i(32, 34), Vector2i(1, -1), 5)


static func _clear_legacy_lane_walls(map_data: MapData) -> void:
	var legacy_cells: Array[Vector2i] = [
		Vector2i(30, 33),
		Vector2i(31, 33),
		Vector2i(mid_x_for_lane() - 1, DEFAULT_USA_ANCHOR.y + 5),
		Vector2i(mid_x_for_lane(), DEFAULT_USA_ANCHOR.y + 5),
	]
	for x in range(28, 33):
		legacy_cells.append(Vector2i(x, 32))
	for i in range(5):
		legacy_cells.append(Vector2i(28 + i, 30 + i))
		legacy_cells.append(Vector2i(32 + i, 34 - i))
	for cell in legacy_cells:
		if map_data.has_object(cell):
			map_data.clear_object(cell)


static func mid_x_for_lane() -> int:
	return DEFAULT_USA_ANCHOR.x + (DEFAULT_TEAM_SEPARATION / 2)


static func _place_default_cover_samples(map_data: MapData) -> void:
	_place_between_teams_cover(map_data)


static func generate_tree_obstacles(
	map_width: int,
	map_height: int,
	spawn_points: Array[Vector2i],
) -> Array[Vector2i]:
	var blocked: Array[Vector2i] = []
	var grove_centers: Array[Vector2i] = [
		Vector2i(8, 8),
		Vector2i(52, 8),
		Vector2i(8, 52),
		Vector2i(52, 52),
		Vector2i(30, 6),
		Vector2i(6, 30),
		Vector2i(54, 30),
		Vector2i(30, 54),
		Vector2i(16, 16),
		Vector2i(44, 16),
		Vector2i(16, 44),
		Vector2i(44, 44),
		Vector2i(22, 10),
		Vector2i(38, 10),
		Vector2i(22, 50),
		Vector2i(38, 50),
		Vector2i(10, 22),
		Vector2i(50, 22),
		Vector2i(10, 38),
		Vector2i(50, 38),
		Vector2i(20, 26),
		Vector2i(40, 26),
		Vector2i(20, 34),
		Vector2i(40, 34),
	]

	for center in grove_centers:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if absi(dx) == 1 and absi(dy) == 1 and (center.x + center.y) % 2 == 0:
					continue
				var cell: Vector2i = center + Vector2i(dx, dy)
				if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
					continue
				if _is_near_any_spawn(cell, spawn_points, 4):
					continue
				if cell not in blocked:
					blocked.append(cell)

	return blocked


static func _is_near_any_spawn(cell: Vector2i, spawn_points: Array[Vector2i], radius: int) -> bool:
	for spawn in spawn_points:
		if absi(cell.x - spawn.x) <= radius and absi(cell.y - spawn.y) <= radius:
			return true
	return false


static func save_to_file(map_data: MapData, file_path: String = DEFAULT_FILE) -> bool:
	var json_text := JSON.stringify(map_data.to_dict(), "\t")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("MapData: could not write %s (error %s)" % [file_path, FileAccess.get_open_error()])
		return false
	file.store_string(json_text)
	return true


static func load_from_file(file_path: String = DEFAULT_FILE) -> MapData:
	if not FileAccess.file_exists(file_path):
		push_warning("MapData: missing %s, creating default map." % file_path)
		var default_map := create_default()
		save_to_file(default_map, file_path)
		return default_map

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("MapData: could not read %s" % file_path)
		return create_default()

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("MapData: invalid JSON in %s" % file_path)
		return create_default()

	return from_dict(parsed)


## Guarantee the between-teams lane cover (haybail, tree, 5-tile wall line).
static func ensure_default_lane_cover(map_data: MapData) -> void:
	_place_between_teams_cover(map_data)


func _objects_to_json() -> Array:
	var result: Array = []
	for cell in _object_lookup.keys():
		var type_id: String = _object_lookup[cell]
		var object_def := MapObjectRegistryClass.get_def(type_id)
		if object_def == null:
			continue
		result.append(_object_entry_to_dict(cell, object_def))
	return result


static func _object_entry_to_dict(cell: Vector2i, object_def: MapObjectDef) -> Dictionary:
	return {
		"object_id": "%s@%d,%d" % [object_def.type_id, cell.x, cell.y],
		"object_type": object_def.type_id,
		"type": object_def.type_id,
		"x": cell.x,
		"y": cell.y,
		"grid_position": {"x": cell.x, "y": cell.y},
		"sprite_path": object_def.sprite_path,
		"blocks_movement": object_def.blocks_movement,
		"blocks_los": object_def.blocks_los,
		"provides_cover": object_def.provides_cover,
		"cover_type": object_def.cover_type,
		"cover_type_name": MapObjectRegistryClass.cover_type_name(object_def.cover_type),
	}


func _load_objects_from_json(raw: Array) -> void:
	_object_lookup.clear()
	for entry in raw:
		if not entry is Dictionary:
			continue
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var type_id := str(
			entry.get("object_type", entry.get("type", MapObjectRegistryClass.DEFAULT_BLOCKED_TYPE))
		)
		type_id = MapObjectRegistryClass.normalize_type_id(type_id)
		if is_in_bounds(cell) and MapObjectRegistryClass.get_def(type_id) != null:
			_object_lookup[cell] = type_id


func _rebuild_blocked_tiles_list() -> void:
	blocked_tiles.clear()
	for cell in _object_lookup.keys():
		if is_blocked(cell):
			blocked_tiles.append(cell)


static func _cells_to_json(cells: Array[Vector2i]) -> Array:
	var result: Array = []
	for cell in cells:
		result.append({"x": cell.x, "y": cell.y})
	return result


static func _cells_from_json(raw: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				cells.append(Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))))
	return cells
