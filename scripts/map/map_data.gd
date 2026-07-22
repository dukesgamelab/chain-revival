class_name MapData
extends RefCounted
## Pure map gameplay data: size, map objects, and team spawn points.

const DEFAULT_FILE := "res://maps/test_map.json"
## Single switch for the development startup map.
const USE_ORIGINAL_MAP_FOR_DEV := true
## Default original map launched in offline/dev (Farm Fight).
const DEV_MAP_FILE := "res://maps/ff_farm.json"
## Kept loadable via registry / --the-fortress (do not remove).
const FORTRESS_MAP_FILE := "res://maps/TheFortress.json"
## Stable map ids → res:// paths for game + editor.
const AVAILABLE_MAPS := {
	"ff_farm": DEV_MAP_FILE,
	"the_fortress": FORTRESS_MAP_FILE,
	"test_map": DEFAULT_FILE,
}
const DEFAULT_WIDTH := 60
const DEFAULT_HEIGHT := 60
const MapObjectRegistryClass := preload("res://scripts/map/map_object_registry.gd")

## Default deployment: vertical columns facing each other, paired by row (same y).
const DEFAULT_TEAM_SEPARATION := 10
const DEFAULT_USA_ANCHOR := Vector2i(26, 28)
const DEFAULT_GERMANY_ANCHOR := Vector2i(36, 28)

var map_name: String = "test_map"
var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT
var team_1_spawn_points: Array[Vector2i] = []
var team_2_spawn_points: Array[Vector2i] = []
var sprite_directory: String = ""
var source_format: String = ""
var uses_original_projection: bool = false
var apply_terrain_gameplay: bool = true

var floors: Array[Dictionary] = []
var decoration: Array[Dictionary] = []
var victory_points: Array[Dictionary] = []
var labels: Array[Dictionary] = []
var starting_points: Dictionary = {}
var unresolved: Array = []
## Render list for original maps (objects + decoration). Gameplay uses _object_lookup.
var visual_placements: Array[Dictionary] = []
## Unknown top-level JSON keys preserved round-trip by the editor/serializer.
var extra_fields: Dictionary = {}

## Legacy list kept in sync with movement-blocking objects for older saves.
var blocked_tiles: Array[Vector2i] = []

var _object_lookup: Dictionary = {}
var _object_meta: Dictionary = {}


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
	var base_def := MapObjectRegistryClass.get_def(type_id)
	if base_def == null:
		return null
	var meta: Dictionary = _object_meta.get(cell, {})
	if meta.is_empty():
		return base_def
	return MapObjectDef.new(
		base_def.type_id,
		base_def.display_name,
		bool(meta.get("blocks_movement", base_def.blocks_movement)),
		bool(meta.get("blocks_los", base_def.blocks_los)),
		bool(meta.get("provides_cover", base_def.provides_cover)),
		int(meta.get("cover_type", base_def.cover_type)),
		str(meta.get("sprite_path", base_def.sprite_path)),
	)


func get_object_source(cell: Vector2i) -> Dictionary:
	var meta: Dictionary = _object_meta.get(cell, {})
	var source: Variant = meta.get("source", {})
	return source if source is Dictionary else {}


func is_original_visual_map() -> bool:
	return uses_original_projection or not floors.is_empty() or not visual_placements.is_empty()


func has_object(cell: Vector2i) -> bool:
	return _object_lookup.has(cell)


func get_object_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in _object_lookup.keys():
		cells.append(cell)
	return cells


func is_blocked(cell: Vector2i) -> bool:
	if not apply_terrain_gameplay:
		return false
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
	_object_meta.erase(cell)
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
	_object_meta.erase(cell)
	_remove_visual_at(cell, "object")
	_rebuild_blocked_tiles_list()


## --- Editor / shared mutation API (keeps visual_placements in sync) ---

func place_family_object(
	cell: Vector2i,
	family: String,
	direction: int = 0,
	image1: String = "",
	z: int = 0,
	gameplay: Dictionary = {},
) -> void:
	if not is_in_bounds(cell):
		return
	var fam := family.to_upper()
	if fam.is_empty():
		return
	## CoC family placement always uses the shared original visual pipeline.
	uses_original_projection = true
	## Editor replace semantics: new object owns the cell (clears floor/objects/decoration).
	erase_all_at(cell, true)
	var type_id := str(gameplay.get("object_type", MapObjectDefinition.type_id_for_family(fam)))
	## Persist identity only — never a camera-specific sprite letter/path.
	var source := {
		"image": fam,
		"direction": direction,
		"z": z,
		"terrain": str(gameplay.get("terrain", "_HG_EVEN")),
		"terrain_height": int(gameplay.get("terrain_height", 0)),
	}
	if not image1.is_empty():
		source["image1"] = image1.to_upper()
	for key in gameplay.keys():
		if key in ["object_type", "terrain", "terrain_height", "sprite_path", "sprite"]:
			continue
		source[key] = gameplay[key]
	## Drop any legacy baked sprite keys so saves stay camera-agnostic.
	source.erase("sprite")
	_object_lookup[cell] = MapObjectRegistryClass.normalize_type_id(type_id)
	_object_meta[cell] = {
		"source": source,
		"blocks_movement": bool(gameplay.get("blocks_movement", true)),
		"blocks_los": bool(gameplay.get("blocks_los", true)),
		"provides_cover": bool(gameplay.get("provides_cover", true)),
		"cover_type": int(gameplay.get("cover_type", 2)),
		"sprite_path": "",
	}
	_upsert_visual_placement(
		{
			"x": cell.x,
			"y": cell.y,
			"object_type": type_id,
			"family": fam,
			"direction": direction,
			"image1": image1.to_upper(),
			"source": source,
			"layer": "object",
			"z": z,
			"blocks_movement": bool(gameplay.get("blocks_movement", true)),
			"blocks_los": bool(gameplay.get("blocks_los", true)),
			"provides_cover": bool(gameplay.get("provides_cover", true)),
			"cover_type": int(gameplay.get("cover_type", 2)),
		}
	)
	_rebuild_blocked_tiles_list()


func place_floor_tile(cell: Vector2i, family: String, direction: int = 0) -> void:
	if not is_in_bounds(cell):
		return
	var fam := family.to_upper()
	uses_original_projection = true
	## Editor replace semantics: floor replaces walls/objects on the cell.
	erase_all_at(cell, true)
	floors.append({"x": cell.x, "y": cell.y, "image": fam, "direction": direction})


## Clear authored content so only the GRS ground layer remains.
func place_ground_clear(cell: Vector2i) -> void:
	if not is_in_bounds(cell):
		return
	erase_all_at(cell, true)


func erase_floor_tile(cell: Vector2i) -> void:
	_remove_floor_at(cell)


func erase_all_at(cell: Vector2i, include_floors: bool = true) -> void:
	## Clear gameplay object, visuals, floors, and marker overlays at this cell.
	_object_lookup.erase(cell)
	_object_meta.erase(cell)
	_remove_visual_at(cell, "")
	if include_floors:
		_remove_floor_at(cell)
	_remove_spawn_at(cell)
	_remove_victory_at(cell)
	_remove_label_at(cell)
	_rebuild_blocked_tiles_list()


func _remove_spawn_at(cell: Vector2i) -> void:
	## Bright green/gray Grid overlays come from these spawn lists.
	var t1: Array[Vector2i] = []
	for spawn in team_1_spawn_points:
		if spawn != cell:
			t1.append(spawn)
	team_1_spawn_points = t1
	var t2: Array[Vector2i] = []
	for spawn in team_2_spawn_points:
		if spawn != cell:
			t2.append(spawn)
	team_2_spawn_points = t2


func _remove_victory_at(cell: Vector2i) -> void:
	var kept: Array[Dictionary] = []
	for entry in victory_points:
		if int(entry.get("x", -1)) == cell.x and int(entry.get("y", -1)) == cell.y:
			continue
		kept.append(entry)
	victory_points = kept


func _remove_label_at(cell: Vector2i) -> void:
	var kept: Array[Dictionary] = []
	for entry in labels:
		if int(entry.get("x", -1)) == cell.x and int(entry.get("y", -1)) == cell.y:
			continue
		kept.append(entry)
	labels = kept


func get_visual_at(cell: Vector2i) -> Dictionary:
	for entry in visual_placements:
		if int(entry.get("x", -1)) == cell.x and int(entry.get("y", -1)) == cell.y:
			return entry
	return {}


func get_floor_at(cell: Vector2i) -> Dictionary:
	for entry in floors:
		if int(entry.get("x", -1)) == cell.x and int(entry.get("y", -1)) == cell.y:
			return entry
	return {}


func snapshot() -> Dictionary:
	return to_dict().duplicate(true)


func restore_snapshot(data: Dictionary) -> void:
	var restored := from_dict(data)
	map_name = restored.map_name
	width = restored.width
	height = restored.height
	team_1_spawn_points = restored.team_1_spawn_points
	team_2_spawn_points = restored.team_2_spawn_points
	sprite_directory = restored.sprite_directory
	source_format = restored.source_format
	uses_original_projection = restored.uses_original_projection
	apply_terrain_gameplay = restored.apply_terrain_gameplay
	floors = restored.floors
	decoration = restored.decoration
	victory_points = restored.victory_points
	labels = restored.labels
	starting_points = restored.starting_points
	unresolved = restored.unresolved
	extra_fields = restored.extra_fields
	visual_placements = restored.visual_placements
	_object_lookup = restored._object_lookup
	_object_meta = restored._object_meta
	_rebuild_blocked_tiles_list()


func _upsert_visual_placement(entry: Dictionary) -> void:
	var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
	_remove_visual_at(cell, str(entry.get("layer", "object")))
	visual_placements.append(entry)


func _remove_visual_at(cell: Vector2i, layer: String) -> void:
	var kept: Array[Dictionary] = []
	for entry in visual_placements:
		if int(entry.get("x", -1)) == cell.x and int(entry.get("y", -1)) == cell.y:
			if str(entry.get("layer", "object")) == layer or layer.is_empty():
				continue
		kept.append(entry)
	visual_placements = kept


func _remove_floor_at(cell: Vector2i) -> void:
	var kept: Array[Dictionary] = []
	for entry in floors:
		if int(entry.get("x", -1)) == cell.x and int(entry.get("y", -1)) == cell.y:
			continue
		kept.append(entry)
	floors = kept


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
	var data := {
		"map_name": map_name,
		"width": width,
		"height": height,
		"map_objects": _objects_to_json(),
		"blocked_tiles": _cells_to_json(blocked_tiles),
		"team_1_spawn_points": _cells_to_json(team_1_spawn_points),
		"team_2_spawn_points": _cells_to_json(team_2_spawn_points),
	}
	if not sprite_directory.is_empty():
		data["sprite_directory"] = sprite_directory
	if not source_format.is_empty():
		data["source_format"] = source_format
	if uses_original_projection:
		data["uses_original_projection"] = true
	data["apply_terrain_gameplay"] = apply_terrain_gameplay
	if not floors.is_empty():
		data["floors"] = floors.duplicate(true)
	if not decoration.is_empty():
		data["decoration"] = decoration.duplicate(true)
	if not victory_points.is_empty():
		data["victory_points"] = victory_points.duplicate(true)
	if not labels.is_empty():
		data["labels"] = labels.duplicate(true)
	if not starting_points.is_empty():
		data["starting_points"] = starting_points.duplicate(true)
	if not unresolved.is_empty():
		data["unresolved"] = unresolved.duplicate(true)
	for key in extra_fields.keys():
		if not data.has(key):
			data[key] = extra_fields[key]
	return data


static func from_dict(data: Dictionary) -> MapData:
	var map_data := MapData.new()
	map_data.map_name = str(data.get("map_name", "test_map"))
	map_data.width = int(data.get("width", DEFAULT_WIDTH))
	map_data.height = int(data.get("height", DEFAULT_HEIGHT))
	map_data.team_1_spawn_points = _cells_from_json(data.get("team_1_spawn_points", []))
	map_data.team_2_spawn_points = _cells_from_json(data.get("team_2_spawn_points", []))
	map_data.sprite_directory = str(data.get("sprite_directory", ""))
	map_data.source_format = str(data.get("source_format", ""))
	map_data.uses_original_projection = bool(data.get("uses_original_projection", false))
	map_data.apply_terrain_gameplay = bool(data.get("apply_terrain_gameplay", true))
	map_data.floors = _dict_array_from_json(data.get("floors", []))
	map_data.decoration = _dict_array_from_json(data.get("decoration", []))
	map_data.victory_points = _dict_array_from_json(data.get("victory_points", []))
	map_data.labels = _dict_array_from_json(data.get("labels", []))
	map_data.starting_points = (
		data.get("starting_points", {}) if data.get("starting_points", {}) is Dictionary else {}
	)
	map_data.unresolved = data.get("unresolved", []) if data.get("unresolved", []) is Array else []
	map_data._object_lookup.clear()
	map_data._object_meta.clear()
	map_data.visual_placements.clear()

	var known := {
		"map_name": true,
		"width": true,
		"height": true,
		"map_objects": true,
		"blocked_tiles": true,
		"team_1_spawn_points": true,
		"team_2_spawn_points": true,
		"sprite_directory": true,
		"source_format": true,
		"uses_original_projection": true,
		"apply_terrain_gameplay": true,
		"floors": true,
		"decoration": true,
		"victory_points": true,
		"labels": true,
		"starting_points": true,
		"unresolved": true,
	}
	for key in data.keys():
		if not known.has(key):
			map_data.extra_fields[key] = data[key]

	var raw_objects: Variant = data.get("map_objects", [])
	if raw_objects is Array and not raw_objects.is_empty():
		map_data._load_objects_from_json(raw_objects)
	elif map_data.apply_terrain_gameplay:
		for cell in _cells_from_json(data.get("blocked_tiles", [])):
			map_data.set_object(cell, MapObjectRegistryClass.DEFAULT_BLOCKED_TYPE)

	map_data._append_decoration_visuals()
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
	var mid_x := DEFAULT_USA_ANCHOR.x + (DEFAULT_TEAM_SEPARATION >> 1)  # x=31 between 26 and 36
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
	return DEFAULT_USA_ANCHOR.x + (DEFAULT_TEAM_SEPARATION >> 1)


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


## Resolve a registered map id (or common alias) to a res:// path.
static func path_for_map(id: String) -> String:
	var key := id.strip_edges().to_lower()
	if key.is_empty():
		return DEV_MAP_FILE
	if AVAILABLE_MAPS.has(key):
		return str(AVAILABLE_MAPS[key])
	match key:
		"farm", "farm_fight", "farmfight", "ff", "fffarm":
			return str(AVAILABLE_MAPS["ff_farm"])
		"fortress", "thefortress", "the-fortress":
			return str(AVAILABLE_MAPS["the_fortress"])
		"test", "testmap":
			return str(AVAILABLE_MAPS["test_map"])
		_:
			push_warning("MapData.path_for_map: unknown map id '%s', using default" % id)
			return DEV_MAP_FILE


static func resolve_startup_map_path(file_path: String = "") -> String:
	if not file_path.is_empty():
		return file_path
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			var map_arg := arg.substr("--map=".length()).strip_edges()
			## Accept registry ids or explicit res:// paths.
			if map_arg.begins_with("res://") or map_arg.ends_with(".json"):
				return map_arg
			return path_for_map(map_arg)
		if arg == "--the-fortress" or arg == "--fortress":
			return path_for_map("the_fortress")
		if arg == "--ff-farm" or arg == "--farm-fight":
			return path_for_map("ff_farm")
		if arg == "--test-map":
			return path_for_map("test_map")
	if USE_ORIGINAL_MAP_FOR_DEV and FileAccess.file_exists(DEV_MAP_FILE):
		return DEV_MAP_FILE
	## Graceful fallbacks if the default original map is missing.
	var fortress_path := path_for_map("the_fortress")
	if FileAccess.file_exists(fortress_path):
		return fortress_path
	return DEFAULT_FILE


static func load_from_file(file_path: String = "") -> MapData:
	var path := resolve_startup_map_path(file_path)
	if not FileAccess.file_exists(path):
		push_warning("MapData: missing %s, creating default map." % path)
		var default_map := create_default()
		if path == DEFAULT_FILE:
			save_to_file(default_map, path)
		return default_map

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MapData: could not read %s" % path)
		return create_default()

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("MapData: invalid JSON in %s" % path)
		return create_default()

	var map_data := from_dict(parsed)
	_log_load_summary(map_data, path)
	return map_data


static func _log_load_summary(map_data: MapData, path: String) -> void:
	print(
		"MapData loaded %s (%s): %dx%d visual=%d floors=%d blocked=%d spawns=%d/%d unresolved=%d"
		% [
			map_data.map_name,
			path,
			map_data.width,
			map_data.height,
			map_data.visual_placements.size(),
			map_data.floors.size(),
			map_data.blocked_tiles.size(),
			map_data.team_1_spawn_points.size(),
			map_data.team_2_spawn_points.size(),
			map_data.unresolved.size(),
		]
	)


## Guarantee the between-teams lane cover (haybail, tree, 5-tile wall line).
static func ensure_default_lane_cover(map_data: MapData) -> void:
	_place_between_teams_cover(map_data)


func _objects_to_json() -> Array:
	var result: Array = []
	for cell in _object_lookup.keys():
		var object_def := get_object_def(cell)
		if object_def == null:
			continue
		var entry := _object_entry_to_dict(cell, object_def)
		var meta: Dictionary = _object_meta.get(cell, {})
		if meta.has("source"):
			entry["source"] = meta["source"]
		result.append(entry)
	return result


static func _object_entry_to_dict(cell: Vector2i, object_def: MapObjectDef) -> Dictionary:
	return {
		"object_id": "%s@%d,%d" % [object_def.type_id, cell.x, cell.y],
		"object_type": object_def.type_id,
		"type": object_def.type_id,
		"x": cell.x,
		"y": cell.y,
		"grid_position": {"x": cell.x, "y": cell.y},
		## Empty for CoC families — facets resolve at draw time from source.image + direction.
		"sprite_path": "",
		"blocks_movement": object_def.blocks_movement,
		"blocks_los": object_def.blocks_los,
		"provides_cover": object_def.provides_cover,
		"cover_type": object_def.cover_type,
		"cover_type_name": MapObjectRegistryClass.cover_type_name(object_def.cover_type),
	}


func _load_objects_from_json(raw: Array) -> void:
	_object_lookup.clear()
	_object_meta.clear()
	visual_placements.clear()
	for entry in raw:
		if not entry is Dictionary:
			continue
		var cell := _cell_from_object_entry(entry)
		if not is_in_bounds(cell):
			continue
		var type_id := str(
			entry.get("object_type", entry.get("type", MapObjectRegistryClass.DEFAULT_BLOCKED_TYPE))
		)
		type_id = MapObjectRegistryClass.normalize_type_id(type_id)
		var source: Dictionary = {}
		if entry.get("source", {}) is Dictionary:
			source = (entry.get("source") as Dictionary).duplicate(true)
		var family := str(source.get("image", "")).to_upper()
		var direction := int(source.get("direction", 0))
		var image1 := str(
			source.get("image1", source.get("Image1", entry.get("image1", entry.get("Image1", ""))))
		).to_upper()
		if not image1.is_empty():
			source["image1"] = image1
		var placement := {
			"x": cell.x,
			"y": cell.y,
			"object_type": type_id,
			"family": family,
			"direction": direction,
			"image1": image1,
			"source": source,
			"layer": "object",
			"z": int(source.get("z", 0)),
		}
		visual_placements.append(placement)

		if MapObjectRegistryClass.get_def(type_id) == null:
			continue
		_object_lookup[cell] = type_id
		## Ignore baked sprite_path/sprite — presentation always re-resolves via CocSpriteResolver.
		source.erase("sprite")
		_object_meta[cell] = {
			"source": source,
			"blocks_movement": bool(entry.get("blocks_movement", false)),
			"blocks_los": bool(entry.get("blocks_los", false)),
			"provides_cover": bool(entry.get("provides_cover", false)),
			"cover_type": int(entry.get("cover_type", 0)),
			"sprite_path": "",
		}


func _append_decoration_visuals() -> void:
	for entry in decoration:
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		if not is_in_bounds(cell):
			continue
		visual_placements.append(
			{
				"x": cell.x,
				"y": cell.y,
				"object_type": "decoration",
				"family": str(entry.get("image", "")).to_upper(),
				"direction": int(entry.get("direction", 0)),
				"source": {
					"image": str(entry.get("image", "")).to_upper(),
					"direction": int(entry.get("direction", 0)),
					"z": 0,
					"terrain": "_HG_EVEN",
				},
				"layer": "decoration",
				"z": 0,
			}
		)


static func _cell_from_object_entry(entry: Dictionary) -> Vector2i:
	if entry.has("x") or entry.has("y"):
		return Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
	var grid: Variant = entry.get("grid_position", {})
	if grid is Dictionary:
		return Vector2i(int(grid.get("x", 0)), int(grid.get("y", 0)))
	return Vector2i.ZERO


func _rebuild_blocked_tiles_list() -> void:
	blocked_tiles.clear()
	if not apply_terrain_gameplay:
		return
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


static func _dict_array_from_json(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				result.append((entry as Dictionary).duplicate(true))
	return result
