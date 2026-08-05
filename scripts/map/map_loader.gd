class_name MapLoader
extends RefCounted
## Shared map load entry-point for gameplay and the Chain Revival Editor.


## validate=true runs full sprite/placement checks (editor). Playtime skips — ff_farm
## placement×camera validation was a multi-second hitch before the first frame.
static func load_path(path: String, validate: bool = false) -> MapData:
	CocTileCatalog.ensure_loaded()
	var map_data := MapData.load_from_file(path)
	if validate and map_data != null and map_data.is_original_visual_map():
		MapValidator.validate_and_log(map_data)
	return map_data


static func load_default() -> MapData:
	return load_path(MapData.DEV_MAP_FILE)


static func load_fortress() -> MapData:
	return load_path(MapData.path_for_map("the_fortress"))


static func load_ff_farm() -> MapData:
	return load_path(MapData.path_for_map("ff_farm"))


static func load_test_map() -> MapData:
	return load_path(MapData.path_for_map("test_map"))


static func create_blank(width: int = 60, height: int = 60, map_name: String = "untitled") -> MapData:
	var map_data := MapData.new()
	map_data.map_name = map_name
	map_data.width = width
	map_data.height = height
	map_data.uses_original_projection = true
	map_data.apply_terrain_gameplay = true
	map_data.sprite_directory = "res://assets/sprites/coc_tiles"
	map_data.source_format = "Chain Revival Editor"
	map_data.team_1_spawn_points = []
	map_data.team_2_spawn_points = []
	return map_data
