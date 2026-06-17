class_name MapData
extends RefCounted
## Pure map gameplay data: size, blocked tiles, and team spawn points.
## Kept separate from scene nodes so maps can be shared in multiplayer later.

const DEFAULT_FILE := "res://maps/test_map.json"
const DEFAULT_WIDTH := 60
const DEFAULT_HEIGHT := 60

var map_name: String = "test_map"
var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT
var blocked_tiles: Array[Vector2i] = []
var team_1_spawn_points: Array[Vector2i] = []
var team_2_spawn_points: Array[Vector2i] = []

var _blocked_lookup: Dictionary = {}


func _init() -> void:
	_rebuild_blocked_lookup()


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func is_blocked(cell: Vector2i) -> bool:
	return _blocked_lookup.has(cell)


func is_walkable(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and not is_blocked(cell)


## Flip a tile between walkable and blocked. Returns the new blocked state.
func toggle_blocked(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	if is_blocked(cell):
		set_blocked(cell, false)
		return false
	set_blocked(cell, true)
	return true


func set_blocked(cell: Vector2i, blocked: bool) -> void:
	if not is_in_bounds(cell):
		return
	if blocked and not is_blocked(cell):
		blocked_tiles.append(cell)
		_blocked_lookup[cell] = true
	elif not blocked and is_blocked(cell):
		blocked_tiles.erase(cell)
		_blocked_lookup.erase(cell)


func to_dict() -> Dictionary:
	return {
		"map_name": map_name,
		"width": width,
		"height": height,
		"blocked_tiles": _cells_to_json(blocked_tiles),
		"team_1_spawn_points": _cells_to_json(team_1_spawn_points),
		"team_2_spawn_points": _cells_to_json(team_2_spawn_points),
	}


static func from_dict(data: Dictionary) -> MapData:
	var map_data := MapData.new()
	map_data.map_name = str(data.get("map_name", "test_map"))
	map_data.width = int(data.get("width", DEFAULT_WIDTH))
	map_data.height = int(data.get("height", DEFAULT_HEIGHT))
	map_data.blocked_tiles = _cells_from_json(data.get("blocked_tiles", []))
	map_data.team_1_spawn_points = _cells_from_json(data.get("team_1_spawn_points", []))
	map_data.team_2_spawn_points = _cells_from_json(data.get("team_2_spawn_points", []))
	map_data._rebuild_blocked_lookup()
	return map_data


## Default map used when no JSON file exists yet.
static func create_default() -> MapData:
	var map_data := MapData.new()
	map_data.map_name = "test_map"
	map_data.width = DEFAULT_WIDTH
	map_data.height = DEFAULT_HEIGHT
	map_data.team_1_spawn_points = [
		Vector2i(28, 30),
		Vector2i(29, 30),
		Vector2i(30, 30),
		Vector2i(31, 30),
	]
	map_data.team_2_spawn_points = [
		Vector2i(33, 32),
		Vector2i(34, 32),
		Vector2i(35, 32),
		Vector2i(36, 32),
	]
	map_data.blocked_tiles = generate_tree_obstacles(
		map_data.width,
		map_data.height,
		map_data.team_1_spawn_points + map_data.team_2_spawn_points,
	)
	map_data._rebuild_blocked_lookup()
	return map_data


## Place static tree groves across the map (blocked tiles). Deterministic layout.
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
				# Skip some corners so groves look less like solid squares.
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


func _rebuild_blocked_lookup() -> void:
	_blocked_lookup.clear()
	for cell in blocked_tiles:
		_blocked_lookup[cell] = true
